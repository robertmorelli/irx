//! One lane: a thread plus one engine process per active mode. It samples a
//! batch from the current table, sends identical cases to every mode, compares
//! each mode's decoded bits against the model oracle, and persists findings.
const std = @import("std");
const alpha = @import("alphabet.zig");
const ast = @import("ast.zig");
const sys = @import("sys.zig");
const harness = @import("harness.zig");
const finding = @import("finding.zig");
const sample = @import("sample.zig");
const tablemod = @import("table.zig");
const spanmod = @import("span.zig");
const rngmod = @import("rng.zig");
const runmod = @import("run.zig");

const Allocator = std.mem.Allocator;
const Run = runmod.Run;

pub const Lane = struct {
    run: *Run,
    id: u32,
    gpa: Allocator,
    children: []*harness.Child,
    mode_index: []usize, // index into run.mode_stats
    sanity_children: []*harness.Child,
    scratch: sample.Scratch = .{},
    cases: []finding.Case,
    req: std.ArrayList(u8) = .empty,
    batches: []harness.Batch,
    bits: [][]u8,
    case_counter: u64 = 0,
    batch_seq: u64 = 0,
    sanity_counter: u64 = 0,

    pub fn init(run: *Run, id: u32) !*Lane {
        const gpa = run.gpa;
        const l = try gpa.create(Lane);
        const nm = run.modes.len;
        l.* = .{
            .run = run,
            .id = id,
            .gpa = gpa,
            .children = try gpa.alloc(*harness.Child, nm),
            .mode_index = try gpa.alloc(usize, nm),
            .sanity_children = try gpa.alloc(*harness.Child, run.sanity_modes.len),
            .cases = try gpa.alloc(finding.Case, run.cfg.batch_size),
            .batches = try gpa.alloc(harness.Batch, nm + run.sanity_modes.len),
            .bits = try gpa.alloc([]u8, nm + run.sanity_modes.len),
        };
        for (l.cases) |*c| c.* = .{};
        for (l.bits) |*b| b.* = try gpa.alloc(u8, run.cfg.batch_size * spanmod.width);
        for (run.modes, 0..) |m, i| {
            l.mode_index[i] = i;
            l.children[i] = try l.makeChild(m, i);
        }
        for (run.sanity_modes, 0..) |m, i| l.sanity_children[i] = try l.makeChild(m, run.modes.len + i);
        return l;
    }

    fn exeFor(run: *Run, m: *const harness.ModeSpec) []const u8 {
        return switch (m.engine) {
            .d8, .shell, .perl => run.d8_exe,
            .sm => run.sm_exe orelse "",
            .jsc => run.jsc_exe orelse "",
        };
    }

    fn makeChild(self: *Lane, m: *const harness.ModeSpec, slot: usize) !*harness.Child {
        const jp = try std.fmt.allocPrint(self.gpa, "{s}/journals/lane{d}-{s}", .{ self.run.out_dir, self.id, m.name });
        _ = slot;
        const c = try harness.Child.create(self.gpa, m, .{ .exe = exeFor(self.run, m), .driver_path = self.run.driver_path, .journal_path = jp, .cfg = &self.run.cfg });
        try c.start();
        return c;
    }

    pub fn deinit(self: *Lane) void {
        for (self.children) |c| {
            c.shutdown(1000);
            c.discardJournalIfUnreferenced();
            c.destroy();
        }
        for (self.sanity_children) |c| {
            c.shutdown(1000);
            c.discardJournalIfUnreferenced();
            c.destroy();
        }
        self.scratch.deinit(self.gpa);
    }

    fn restart(self: *Lane, c: *harness.Child, stat_idx: usize) bool {
        c.kill();
        c.discardJournalIfUnreferenced();
        if (stat_idx < runmod.max_modes) _ = self.run.mode_stats[stat_idx].restarts.fetchAdd(1, .monotonic);
        var tries: usize = 0;
        while (tries < 3) : (tries += 1) {
            c.start() catch continue;
            return true;
        }
        self.run.setStop("mode {s}: could not restart engine process: {s}", .{ c.spec.name, c.message() });
        return false;
    }

    /// Sample up to `n` cases from `tab` into self.cases, encoding the request.
    fn fillBatch(self: *Lane, tab: *tablemod.Table, n: u64) !usize {
        const run = self.run;
        self.req.clearRetainingCapacity();
        self.batch_seq += 1;
        try self.req.print(self.gpa, "[{d},[", .{self.batch_seq});
        var count: usize = 0;
        try self.scratch.ensure(self.gpa, tab.max_prods_per_pair, tab.max_size);
        var t_sample: u64 = 0;
        var t_print: u64 = 0;
        var t_enc: u64 = 0;
        while (count < n) {
            const c = &self.cases[count];
            const idx = self.case_counter;
            var rng = rngmod.caseRng(run.global_seed, self.id, idx);
            const t0 = sys.nowNs();
            var smp: sample.Sampler = .{ .tab = tab, .scratch = &self.scratch, .rng = &rng, .out = &c.tree };
            const k = smp.sample() catch |e| {
                run.setStop("sampling failed ({s}) on table {d}: model failure", .{ @errorName(e), tab.id.seq });
                return error.ModelFailure;
            };
            const t1 = sys.nowNs();
            c.pattern.clearRetainingCapacity();
            c.spell = rng.next() | 1;
            var pr: sample.Printer = .{ .flags = tab.id.flags, .out = &c.pattern, .gpa = self.gpa, .limit = run.cfg.max_pattern_bytes, .spell = c.spell };
            pr.print(&c.tree) catch |e| {
                run.setStop("printer failed ({s}); printed-length bound violated", .{@errorName(e)});
                return error.ModelFailure;
            };
            const t2 = sys.nowNs();
            c.flags = tab.id.flags;
            c.a.set(tab.a16);
            c.r.set(tab.r16);
            c.exp_a = true;
            c.exp_r = false;
            c.size = @intCast(k);
            c.table = .{ .seq = tab.id.seq, .attempt = tab.id.attempt, .seed = tab.id.seed, .digest = tab.digest };
            c.global_seed = run.global_seed;
            c.lane = self.id;
            c.index = idx;
            c.selfcheck = false;
            const before = self.req.items.len;
            if (count > 0) try self.req.append(self.gpa, ',');
            try harness.encodeCase(&self.req, self.gpa, .{ .flags = finding.flagStr(c.flags), .a = c.a.slice(), .r = c.r.slice(), .pattern = c.pattern.items });
            t_enc += sys.nowNs() - t2;
            t_sample += t1 - t0;
            t_print += t2 - t1;
            if (self.req.items.len + 4 > run.cfg.max_request_bytes) {
                // Split by encoded length: this case goes to the next batch.
                self.req.shrinkRetainingCapacity(before);
                break;
            }
            self.case_counter += 1;
            count += 1;
        }
        try self.req.appendSlice(self.gpa, "]]\n");
        _ = run.sample_ns.fetchAdd(t_sample, .monotonic);
        _ = run.print_ns.fetchAdd(t_print, .monotonic);
        _ = run.encode_ns.fetchAdd(t_enc, .monotonic);
        return count;
    }

    pub fn loop(self: *Lane) void {
        _ = sys.setThreadQos();
        const run = self.run;
        while (!run.stopped()) {
            if (run.cases.load(.monotonic) >= run.max_cases or sys.nowNs() >= run.deadline_ns) break;
            // No blocking on a full triage queue: findings are persisted before
            // enqueueing and overflow spills to triage_pending.txt, so the queue
            // bounds memory without stalling lanes.
            const got = run.acquire(run.cfg.batch_size) orelse break;
            defer run.releaseTable(got.tab);
            self.step(got.tab, got.n) catch |e| {
                run.setStop("lane {d} failed: {s}", .{ self.id, @errorName(e) });
                break;
            };
        }
    }

    fn step(self: *Lane, tab: *tablemod.Table, n: u64) !void {
        const run = self.run;
        // Recycle at batch boundaries (after draining), or replace dead children.
        for (self.children, 0..) |c, i| {
            if (!c.alive or c.needsRecycle()) {
                if (c.alive) {
                    c.shutdown(1000);
                    c.discardJournalIfUnreferenced();
                    c.start() catch {
                        if (!self.restart(c, i)) return;
                    };
                } else if (!self.restart(c, i)) return;
            }
        }
        const count = try self.fillBatch(tab, n);
        if (count == 0) return;
        // Every child must accept the request within its journal cap.
        for (self.children, 0..) |c, i| {
            if (!c.canAdmit(self.req.items.len)) {
                c.shutdown(1000);
                c.discardJournalIfUnreferenced();
                if (!self.restart(c, i)) return;
            }
        }
        const do_sanity = self.sanity_children.len > 0 and run.cfg.sanity_fraction > 0 and blk: {
            self.sanity_counter += 1;
            const every: u64 = @intFromFloat(@max(1.0, 1.0 / run.cfg.sanity_fraction));
            break :blk self.sanity_counter % every == 0;
        };

        const now = sys.nowNs();
        const deadline = now + harness.batchDeadlineNs(&run.cfg, count);
        var active: [runmod.max_modes + 4]*harness.Child = undefined;
        var na: usize = 0;
        for (self.children, 0..) |c, i| {
            self.batches[i] = .{ .seq = self.batch_seq, .ncases = @intCast(count), .req = self.req.items, .bits = self.bits[i][0 .. count * harness.resultWidth(c.spec.expect)] };
            c.admit(&self.batches[i], deadline) catch {
                run.setStop("journal write failed for mode {s}", .{c.spec.name});
                return;
            };
            active[na] = c;
            na += 1;
            for (self.cases[0..count]) |*cs| {
                if (c.novelty.note(self.gpa, cs.flags.bits(), cs.pattern.items) catch false) {
                    _ = run.mode_stats[i].first_seen.fetchAdd(1, .monotonic);
                } else _ = run.mode_stats[i].repeated.fetchAdd(1, .monotonic);
            }
        }
        if (do_sanity) {
            for (self.sanity_children, 0..) |c, j| {
                const bi = self.children.len + j;
                if (!c.alive and !self.restart(c, runmod.max_modes)) continue;
                self.batches[bi] = .{ .seq = self.batch_seq, .ncases = @intCast(count), .req = self.req.items, .bits = self.bits[bi][0..count] };
                c.admit(&self.batches[bi], deadline) catch continue;
                active[na] = c;
                na += 1;
            }
        }
        const t_wait = sys.nowNs();
        while (true) {
            var pending = false;
            for (active[0..na]) |c| pending = pending or (c.busy() and c.alive);
            if (!pending) break;
            harness.pump(active[0..na], 1000);
        }
        _ = run.wait_ns.fetchAdd(sys.nowNs() - t_wait, .monotonic);
        _ = run.cases.fetchAdd(count, .monotonic);
        _ = run.batches.fetchAdd(1, .monotonic);

        for (self.children, 0..) |c, i| {
            const b = &self.batches[i];
            const ms = &run.mode_stats[i];
            if (b.state != .answered) {
                try self.batchFailure(c, b, i);
                continue;
            }
            const is_span = c.spec.expect == .span;
            for (self.cases[0..count], 0..) |*cs, ci| {
                var ck: spanmod.Check = .{ .bits = 0 };
                if (is_span) ck = spanmod.check(cs, b.bits[ci * spanmod.width ..][0..spanmod.width], run.cfg.span_units);
                const bits = if (is_span) ck.bits else b.bits[ci];
                if (bits & harness.Bits.skipped != 0) {
                    if (cs.flags.m) _ = ms.skipped_multiline.fetchAdd(1, .monotonic) else _ = ms.skipped_unsupported.fetchAdd(1, .monotonic);
                    continue;
                }
                _ = ms.executed.fetchAdd(1, .monotonic);
                if (finding.classify(c.spec.expect, c.spec.name, bits, cs.exp_a, cs.exp_r)) |pred| {
                    _ = ms.mismatches.fetchAdd(1, .monotonic);
                    if (pred.kind == .wrong_span) {
                        var extra: std.ArrayList(u8) = .empty;
                        defer extra.deinit(self.gpa);
                        try spanmod.extraJson(&extra, self.gpa, ck, b.bits[ci * spanmod.width ..][0..spanmod.width]);
                        try self.reportExtra(cs, pred, c, extra.items);
                    } else try self.report(cs, pred, c);
                }
            }
        }
        if (do_sanity) {
            for (self.sanity_children, 0..) |c, j| {
                const b = &self.batches[self.children.len + j];
                if (b.state != .answered) {
                    if (c.alive) c.kill();
                    continue;
                }
                for (self.cases[0..count], 0..) |*cs, ci| {
                    const bits = b.bits[ci];
                    if (finding.classify(.normal, c.spec.name, bits, cs.exp_a, cs.exp_r)) |pred| {
                        var p = pred;
                        p.kind = .sanity_disagreement;
                        // Did V8 (first mode) agree with the independent engine?
                        const v8bits = if (self.batches[0].state == .answered) self.batches[0].bits[ci] & 0x0f else 0xff;
                        var extra_buf: [128]u8 = undefined;
                        const extra = std.fmt.bufPrint(&extra_buf, "\"sanity\": {{\"engine_bits\": \"{x:0>2}\", \"v8_bits\": \"{x:0>2}\", \"classification\": \"{s}\"}}", .{ bits, v8bits, if (v8bits == bits) "model-suspect: V8 and independent engine agree against the oracle" else "engines disagree" }) catch null;
                        try self.reportExtra(cs, p, c, extra);
                    }
                }
            }
        }
    }

    fn report(self: *Lane, cs: *finding.Case, pred: finding.Predicate, c: *harness.Child) !void {
        return self.reportExtra(cs, pred, c, null);
    }

    fn reportExtra(self: *Lane, cs: *finding.Case, pred: finding.Predicate, c: *harness.Child, extra: ?[]const u8) !void {
        const run = self.run;
        c.journal_referenced = true;
        const exe = exeFor(run, c.spec);
        const res = run.store.persist(cs, pred, run.build_id, "single-case", c.spec, exe, c.journal_path, extra) catch |e| {
            run.setStop("failed to persist finding: {s}", .{@errorName(e)});
            return e;
        };
        _ = run.findings.fetchAdd(1, .monotonic);
        if (res.new) {
            _ = run.findings_new.fetchAdd(1, .monotonic);
            run.enqueueFinding(res.id, cs.pattern.items.len + 512);
        }
    }

    /// A batch failed on a child (timeout, crash, protocol). Persist the
    /// failure with its exact request and journal for triage replay, then
    /// replace the process.
    fn batchFailure(self: *Lane, c: *harness.Child, b: *harness.Batch, mode_i: usize) !void {
        const run = self.run;
        c.drainErr();
        const kind: finding.Kind = switch (c.failure) {
            .timeout => .timeout,
            .protocol => .protocol,
            else => .crash,
        };
        if (kind == .timeout) _ = run.slow_cases.fetchAdd(1, .monotonic);
        c.journal_referenced = true;
        // Represent the failure by the batch's first case; the exact request is saved alongside.
        const cs = &self.cases[0];
        const pred: finding.Predicate = .{ .kind = kind, .mode = c.spec.name, .signal = c.exit.signal, .exit_code = c.exit.code };
        var extra: std.ArrayList(u8) = .empty;
        defer extra.deinit(self.gpa);
        try extra.appendSlice(self.gpa, "\"batch_failure\": {\"message\": ");
        try harness.jsonAscii(&extra, self.gpa, c.message());
        var eb: [64]u8 = undefined;
        try extra.print(self.gpa, ", \"exit\": \"{s}\", \"stderr_truncated\": {d}, \"batch_seq\": {d}, \"cases\": {d}}}", .{ c.exit.describe(&eb), c.err.truncated, b.seq, b.ncases });
        const res = try run.store.persist(cs, pred, run.build_id, "batch", c.spec, exeFor(run, c.spec), c.journal_path, extra.items);
        _ = run.findings.fetchAdd(1, .monotonic);
        if (res.new) {
            var b1: [4096]u8 = undefined;
            const dir = try run.store.findingDir(&b1, res.id);
            var pb: [4096]u8 = undefined;
            try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/batch.req", .{dir}), b.req);
            const tail = try c.err.copyOut(self.gpa);
            defer self.gpa.free(tail);
            try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/stderr.txt", .{dir}), tail);
            if (kind == .timeout) {
                // Index in slow/, separate from semantic findings.
                const sp = try std.fmt.bufPrint(&pb, "{s}/slow/index.txt", .{run.out_dir});
                const fd = try sys.openAppend(sp);
                defer _ = sys.close(fd);
                var line: [64]u8 = undefined;
                try sys.appendFile(fd, try std.fmt.bufPrint(&line, "{d:0>6} mode={s}\n", .{ res.id, c.spec.name }));
            }
            _ = run.findings_new.fetchAdd(1, .monotonic);
            run.enqueueFinding(res.id, b.req.len + 4096);
        }
        _ = self.restart(c, mode_i);
    }
};
