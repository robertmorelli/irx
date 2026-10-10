//! Triage: reproduction in a dedicated child, tree/string/flag shrinking under
//! the recorded failure predicate (every candidate is first revalidated by the
//! relation model), batch isolation/bisection for crashes and timeouts, journal
//! prefix replay for sequence-dependent failures, and sanity classification.
const std = @import("std");
const alpha = @import("alphabet.zig");
const ast = @import("ast.zig");
const atoms = @import("atoms.zig");
const sys = @import("sys.zig");
const harness = @import("harness.zig");
const finding = @import("finding.zig");
const sample = @import("sample.zig");
const runmod = @import("run.zig");

const Allocator = std.mem.Allocator;
const Flags = alpha.Flags;
const Run = runmod.Run;

pub const Outcome = union(enum) {
    bits: u8,
    failed: struct { kind: finding.Kind, signal: u8 },
};

pub const Triage = struct {
    run: *Run,
    gpa: Allocator,
    child: ?*harness.Child = null,
    engine_runs: u64 = 0,
    max_engine_runs: u64 = 400,
    /// During a campaign, leave crash/timeout batch replay for `irx triage`.
    defer_batches: bool = false,

    fn exeFor(self: *Triage, m: *const harness.ModeSpec) []const u8 {
        return switch (m.engine) {
            .d8, .shell, .perl => self.run.d8_exe,
            .sm => self.run.sm_exe orelse "",
            .jsc => self.run.jsc_exe orelse "",
        };
    }

    /// The single triage child; modes run sequentially by swapping it.
    fn childFor(self: *Triage, spec: *const harness.ModeSpec, fresh: bool) ?*harness.Child {
        if (self.child) |c| {
            if (c.spec == spec and c.alive and !fresh) return c;
            c.shutdown(500);
            c.discardJournalIfUnreferenced();
            c.destroy();
            self.child = null;
        }
        const jp = std.fmt.allocPrint(self.gpa, "{s}/journals/triage-{s}", .{ self.run.out_dir, spec.name }) catch return null;
        const c = harness.Child.create(self.gpa, spec, .{ .exe = self.exeFor(spec), .driver_path = self.run.driver_path, .journal_path = jp, .cfg = &self.run.cfg }) catch return null;
        c.start() catch {
            c.destroy();
            return null;
        };
        self.child = c;
        return c;
    }

    pub fn deinit(self: *Triage) void {
        if (self.child) |c| {
            c.shutdown(500);
            c.discardJournalIfUnreferenced();
            c.destroy();
        }
    }

    fn runRequest(self: *Triage, spec: *const harness.ModeSpec, req: []u8, ncases: u32, bits: []u8, fresh: bool) Outcome {
        self.engine_runs += 1;
        const c = self.childFor(spec, fresh) orelse return .{ .failed = .{ .kind = .crash, .signal = 0 } };
        var b: harness.Batch = .{ .seq = 1, .ncases = ncases, .req = req, .bits = bits };
        // Rewrite the sequence number to 1 is unnecessary: the child echoes what we send,
        // so parse the request's own sequence.
        b.seq = parseSeq(req) orelse 1;
        if (harness.runSync(c, &b) == .answered) return .{ .bits = if (ncases > 0) bits[0] else 0 };
        const kind: finding.Kind = switch (c.failure) {
            .timeout => .timeout,
            .protocol => .protocol,
            else => .crash,
        };
        const sig = c.exit.signal;
        c.kill();
        return .{ .failed = .{ .kind = kind, .signal = sig } };
    }

    fn runCase(self: *Triage, spec: *const harness.ModeSpec, c: *const finding.Case, fresh: bool) Outcome {
        var req: std.ArrayList(u8) = .empty;
        defer req.deinit(self.gpa);
        req.appendSlice(self.gpa, "[1,[") catch return .{ .failed = .{ .kind = .crash, .signal = 0 } };
        harness.encodeCase(&req, self.gpa, .{ .flags = finding.flagStr(c.flags), .a = c.a.slice(), .r = c.r.slice(), .pattern = c.pattern.items }) catch return .{ .failed = .{ .kind = .crash, .signal = 0 } };
        req.appendSlice(self.gpa, "]]\n") catch return .{ .failed = .{ .kind = .crash, .signal = 0 } };
        var bits: [1]u8 = undefined;
        return self.runRequest(spec, req.items, 1, &bits, fresh);
    }

    fn predicateHolds(self: *Triage, spec: *const harness.ModeSpec, c: *const finding.Case, pred: finding.Predicate, fresh: bool) bool {
        const o = self.runCase(spec, c, fresh);
        switch (o) {
            .bits => |b| {
                const p = finding.classify(spec.expect, spec.name, b, c.exp_a, c.exp_r) orelse return false;
                var pp = pred;
                if (pp.kind == .sanity_disagreement) pp.kind = p.kind;
                return p.eqlShape(pp);
            },
            .failed => |f| return f.kind == pred.kind and (pred.kind != .crash or f.signal == pred.signal),
        }
    }

    // ------------------------------------------------------------------

    pub fn loop(self: *Triage) void {
        while (self.run.nextFinding(1024)) |id| {
            self.handle(id) catch |e| {
                sys.stderrPrint("triage: finding {d}: {s}\n", .{ id, @errorName(e) });
            };
            _ = self.run.triaged.fetchAdd(1, .monotonic);
        }
    }

    pub fn handle(self: *Triage, id: u64) !void {
        var arena = std.heap.ArenaAllocator.init(self.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var db: [4096]u8 = undefined;
        const dir = try self.run.store.findingDir(&db, id);
        var pb: [4096]u8 = undefined;
        const text = try sys.readFileAlloc(a, try std.fmt.bufPrint(&pb, "{s}/case.irx", .{dir}), 1 << 20);
        var lc: finding.LoadedCase = undefined;
        try finding.readCaseRecord(a, text, &lc);
        const history = recordField(text, "history") orelse "single-case";
        const spec = harness.findMode(lc.pred.mode) orelse return error.UnknownMode;
        if (self.defer_batches and std.mem.eql(u8, history, "batch")) return; // no triage.json: picked up later
        self.engine_runs = 0;
        var report: std.ArrayList(u8) = .empty;
        try report.print(a, "{{\n  \"finding\": {d},\n  \"kind\": \"{s}\",\n  \"mode\": \"{s}\"", .{ id, @tagName(lc.pred.kind), spec.name });
        if (std.mem.eql(u8, history, "batch")) {
            try self.handleBatch(a, dir, spec, lc.pred, recordField(text, "journal"), &report);
        } else {
            try self.handleCase(a, dir, spec, &lc, &report);
        }
        try report.print(a, ",\n  \"engine_runs\": {d}\n}}\n", .{self.engine_runs});
        try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/triage.json", .{dir}), report.items);
    }

    fn handleCase(self: *Triage, a: Allocator, dir: []const u8, spec: *const harness.ModeSpec, lc: *finding.LoadedCase, report: *std.ArrayList(u8)) !void {
        const pred = lc.pred;
        var c = lc.case;
        // Model check of the saved case itself (guards against corrupted records).
        const ma = ast.oracle(&c.tree, c.flags, c.a.slice());
        const mr = ast.oracle(&c.tree, c.flags, c.r.slice());
        try report.print(a, ",\n  \"model_recheck\": {}", .{ma != null and ma.? == c.exp_a and mr != null and mr.? == c.exp_r});

        const reproduced = self.predicateHolds(spec, &c, pred, true);
        try report.print(a, ",\n  \"reproduced_fresh_process\": {}", .{reproduced});
        if (!reproduced) {
            try report.appendSlice(a, ",\n  \"status\": \"not reproduced in an isolated fresh process; possibly sequence-dependent (see journal)\"");
            return;
        }
        _ = self.run.confirmed.fetchAdd(1, .monotonic);

        // Independent engines.
        var model_suspect = false;
        if (self.run.sanity_modes.len > 0) {
            try report.appendSlice(a, ",\n  \"sanity\": [");
            for (self.run.sanity_modes, 0..) |sm, i| {
                const o = self.runCase(sm, &c, false);
                if (i > 0) try report.appendSlice(a, ", ");
                switch (o) {
                    .bits => |b| {
                        const agrees_with_oracle = finding.classify(.normal, sm.name, b, c.exp_a, c.exp_r) == null;
                        if (!agrees_with_oracle and pred.kind == .wrong_result and (b & 3) == (pred.observed & 3)) model_suspect = true;
                        try report.print(a, "{{\"engine\": \"{s}\", \"bits\": \"{x:0>2}\", \"agrees_with_oracle\": {}}}", .{ sm.name, b, agrees_with_oracle });
                    },
                    .failed => |f| try report.print(a, "{{\"engine\": \"{s}\", \"failed\": \"{s}\"}}", .{ sm.name, @tagName(f.kind) }),
                }
            }
            try report.append(a, ']');
            const shares_irregexp = blk: {
                for (self.run.sanity_modes) |sm| if (sm.engine == .sm) break :blk true;
                break :blk false;
            };
            try report.print(a, ",\n  \"classification\": \"{s}\"", .{if (model_suspect)
                (if (shares_irregexp) "model-suspect: an engine agrees with V8 against the oracle (note: SpiderMonkey vendors V8's irregexp, so its agreement is weak evidence; check the model and an older V8/JSC)" else "model-suspect (V8 agrees with an independent engine against the oracle)")
            else
                "candidate engine bug (unconfirmed)"});
        }

        const orig_size = c.tree.size(c.tree.root);
        const orig_pattern = try a.dupe(u8, c.pattern.items);
        var steps: u32 = 0;
        var limit_note: []const u8 = "structural AST reductions and direct relation evaluation (original grammar reconstruction not used)";
        var improved = true;
        while (improved and self.engine_runs < self.max_engine_runs) {
            improved = false;
            if (try self.shrinkTree(a, spec, &c, pred)) {
                improved = true;
                steps += 1;
            }
            if (self.engine_runs >= self.max_engine_runs) break;
            if (try self.shrinkStrings(a, spec, &c, pred)) {
                improved = true;
                steps += 1;
            }
            if (self.engine_runs >= self.max_engine_runs) break;
            if (try self.shrinkFlags(a, spec, &c, pred)) {
                improved = true;
                steps += 1;
            }
        }
        if (self.engine_runs >= self.max_engine_runs) limit_note = "work budget exhausted; partially minimized";

        // Which other sampling modes also fail on the minimized case (mode shrink: one suffices).
        try report.appendSlice(a, ",\n  \"other_modes_failing\": [");
        var first = true;
        for (self.run.modes) |m| {
            if (m == spec) continue;
            const o = self.runCase(m, &c, false);
            const fails = switch (o) {
                .bits => |b| finding.classify(m.expect, m.name, b, c.exp_a, c.exp_r) != null,
                .failed => true,
            };
            if (fails) {
                if (!first) try report.appendSlice(a, ", ");
                first = false;
                try report.print(a, "\"{s}\"", .{m.name});
            }
        }
        try report.append(a, ']');

        try report.print(a, ",\n  \"minimization\": {{\"steps\": {d}, \"original_size\": {d}, \"minimized_size\": {d}, \"note\": \"{s}\"}}", .{ steps, orig_size, c.tree.size(c.tree.root), limit_note });
        try report.appendSlice(a, ",\n  \"original_pattern\": ");
        try harness.jsonAscii(report, a, orig_pattern);
        try report.appendSlice(a, ",\n  \"minimized\": ");
        var mj: std.ArrayList(u8) = .empty;
        try finding.writeCaseJson(&mj, a, &c, pred, "reproduced; minimized");
        try report.appendSlice(a, std.mem.trimEnd(u8, mj.items, "\n"));
        try report.appendSlice(a, ",\n  \"status\": \"reproduced under the recorded build (not a confirmed V8 bug until reviewed)\"");

        var pb: [4096]u8 = undefined;
        var rj: std.ArrayList(u8) = .empty;
        try finding.writeRepro(&rj, a, &c, pred, spec, self.exeFor(spec), null);
        try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/repro.min.js", .{dir}), rj.items);
        var rec: std.ArrayList(u8) = .empty;
        try finding.writeCaseRecord(&rec, a, &c, pred);
        try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/minimized.irx", .{dir}), rec.items);

        if (!model_suspect and self.run.cfg.adaptive) {
            var counts: [ast.n_constructs]u16 = undefined;
            ast.constructCounts(&lc.case.tree, &counts);
            const base = @import("config.zig").Weights.defaults();
            self.run.adaptiveBump(&counts, &base);
        }
    }

    // ---- candidate validation ----

    fn validFor(t: *const ast.Ast, flags: Flags) bool {
        for (t.nodes[0..t.len]) |n| {
            if (n.op != .atom) continue;
            const at = n.atom;
            if (at.kind == .vset and !flags.v) return false;
            if (!flags.unicode()) {
                switch (at.kind) {
                    .lit => if (at.syms[0] > 0xFFFF) return false,
                    .cls => for (at.syms[0..at.n]) |s| if (s > 0xFFFF) return false,
                    .range => if (at.syms[1] > 0xFFFF) return false,
                    else => {},
                }
            }
        }
        return true;
    }

    /// Model revalidation then engine check. On success the candidate replaces `c`.
    fn tryCandidate(self: *Triage, spec: *const harness.ModeSpec, c: *finding.Case, cand: *finding.Case, pred: finding.Predicate) !bool {
        if (!validFor(&cand.tree, cand.flags)) return false;
        const ma = ast.oracle(&cand.tree, cand.flags, cand.a.slice()) orelse return false;
        const mr = ast.oracle(&cand.tree, cand.flags, cand.r.slice()) orelse return false;
        if (ma != c.exp_a or mr != c.exp_r) return false;
        cand.pattern.clearRetainingCapacity();
        var pr: sample.Printer = .{ .flags = cand.flags, .out = &cand.pattern, .gpa = self.gpa, .limit = self.run.cfg.max_pattern_bytes };
        pr.print(&cand.tree) catch return false;
        if (self.engine_runs >= self.max_engine_runs) return false;
        if (!self.predicateHolds(spec, cand, pred, pred.kind == .crash)) return false;
        c.tree = cand.tree;
        c.flags = cand.flags;
        c.a = cand.a;
        c.r = cand.r;
        c.pattern.clearRetainingCapacity();
        try c.pattern.appendSlice(self.gpa, cand.pattern.items);
        return true;
    }

    fn smaller(new: *const finding.Case, old: *const finding.Case) bool {
        const ns = new.tree.size(new.tree.root);
        const os = old.tree.size(old.tree.root);
        if (ns != os) return ns < os;
        return false;
    }

    fn shrinkTree(self: *Triage, a: Allocator, spec: *const harness.ModeSpec, c: *finding.Case, pred: finding.Predicate) !bool {
        _ = a;
        var cand: finding.Case = c.*;
        cand.pattern = .empty;
        defer cand.pattern.deinit(self.gpa);
        const base = c.tree.compact();
        var idx: u8 = 0;
        while (idx < base.len) : (idx += 1) {
            const n = base.nodes[idx];
            var variants: [8]Variant = undefined;
            var nv: usize = 0;
            switch (n.op) {
                .atom => {
                    if (n.atom.kind != .empty) {
                        variants[nv] = .{ .replace_atom = .{ .kind = .empty } };
                        nv += 1;
                    }
                    if (!(n.atom.kind == .lit and n.atom.syms[0] == 'a')) {
                        variants[nv] = .{ .replace_atom = .{ .kind = .lit, .syms = .{ 'a', 0, 0, 0 } } };
                        nv += 1;
                    }
                },
                .concat, .alt => {
                    variants[nv] = .{ .child = n.a };
                    variants[nv + 1] = .{ .child = n.b };
                    nv += 2;
                },
                .quant => {
                    variants[nv] = .{ .child = n.a };
                    nv += 1;
                    if (n.quant.lazy) {
                        var q = n.quant;
                        q.lazy = false;
                        variants[nv] = .{ .quant = q };
                        nv += 1;
                    }
                    if (n.quant.max != ast.inf and n.quant.max > n.quant.min and n.quant.max > 1) {
                        var q = n.quant;
                        q.max -= 1;
                        if (q.form == .opt) q.form = .range;
                        variants[nv] = .{ .quant = q };
                        nv += 1;
                    }
                    if (n.quant.min > 0 and n.quant.form != .plus) {
                        var q = n.quant;
                        q.min -= 1;
                        if (q.form == .exact) q.form = .range;
                        variants[nv] = .{ .quant = q };
                        nv += 1;
                    }
                },
                else => {
                    variants[nv] = .{ .child = n.a };
                    nv += 1;
                },
            }
            for (variants[0..nv]) |v| {
                cand.tree = rebuild(&base, idx, v);
                cand.flags = c.flags;
                cand.a = c.a;
                cand.r = c.r;
                const size_ok = smaller(&cand, c) or (v == .quant or (v == .replace_atom and n.atom.kind != .empty));
                if (!size_ok) continue;
                if (try self.tryCandidate(spec, c, &cand, pred)) return true;
                if (self.engine_runs >= self.max_engine_runs) return false;
            }
        }
        return false;
    }

    fn shrinkStrings(self: *Triage, a: Allocator, spec: *const harness.ModeSpec, c: *finding.Case, pred: finding.Predicate) !bool {
        _ = a;
        var cand: finding.Case = c.*;
        cand.pattern = .empty;
        defer cand.pattern.deinit(self.gpa);
        for ([_]bool{ true, false }) |which_a| {
            const subj = if (which_a) &c.a else &c.r;
            var syms: [64]u21 = undefined;
            const n = alpha.decode(subj.slice(), c.flags, &syms) orelse continue;
            var i: usize = 0;
            while (i < n) : (i += 1) {
                // drop symbol i, then replace it with 'a'
                for ([_]bool{ true, false }) |drop| {
                    var tmp: [64]u21 = undefined;
                    var m: usize = 0;
                    for (syms[0..n], 0..) |s, j| {
                        if (j == i) {
                            if (drop) continue;
                            if (s == 'a') break;
                            tmp[m] = 'a';
                        } else tmp[m] = s;
                        m += 1;
                    }
                    if (!drop and m != n) continue;
                    var units: [64]u16 = undefined;
                    const un = alpha.toUtf16(tmp[0..m], &units);
                    if (un > finding.max_units) continue;
                    cand.tree = c.tree;
                    cand.flags = c.flags;
                    cand.a = c.a;
                    cand.r = c.r;
                    if (which_a) cand.a.set(units[0..un]) else cand.r.set(units[0..un]);
                    if (std.mem.eql(u16, cand.a.slice(), cand.r.slice())) continue;
                    if (try self.tryCandidate(spec, c, &cand, pred)) return true;
                    if (self.engine_runs >= self.max_engine_runs) return false;
                }
            }
        }
        return false;
    }

    fn shrinkFlags(self: *Triage, a: Allocator, spec: *const harness.ModeSpec, c: *finding.Case, pred: finding.Predicate) !bool {
        _ = a;
        var cand: finding.Case = c.*;
        cand.pattern = .empty;
        defer cand.pattern.deinit(self.gpa);
        const f = c.flags;
        var options: [6]Flags = undefined;
        var no: usize = 0;
        inline for (.{ "i", "m", "s", "u", "v" }) |name| {
            // Perl strings are code points and the driver always applies /u:
            // dropping u would switch the model to UTF-16 positions.
            const keep = @import("dialect.zig").codePointsOnly() and comptime std.mem.eql(u8, name, "u");
            if (!keep and @field(f, name)) {
                var g = f;
                @field(g, name) = false;
                options[no] = g;
                no += 1;
            }
        }
        if (f.v) {
            var g = f;
            g.v = false;
            g.u = true;
            options[no] = g;
            no += 1;
        }
        for (options[0..no]) |g| {
            cand.tree = c.tree;
            cand.flags = g;
            cand.a = c.a;
            cand.r = c.r;
            // Semantics, positions and wrappers are all recomputed for g by the oracle and printer.
            if (try self.tryCandidate(spec, c, &cand, pred)) return true;
            if (self.engine_runs >= self.max_engine_runs) return false;
        }
        return false;
    }

    // ------------------------------------------------------------------
    // Batch failures: isolation, bisection, journal prefix replay

    fn handleBatch(self: *Triage, a: Allocator, dir: []const u8, spec: *const harness.ModeSpec, pred: finding.Predicate, journal: ?[]const u8, report: *std.ArrayList(u8)) !void {
        var pb: [4096]u8 = undefined;
        const req = sys.readFileAlloc(a, try std.fmt.bufPrint(&pb, "{s}/batch.req", .{dir}), 64 << 20) catch {
            try report.appendSlice(a, ",\n  \"status\": \"batch request missing\"");
            return;
        };
        if (pred.kind == .protocol) {
            try report.appendSlice(a, ",\n  \"status\": \"harness/protocol finding: recorded, not replayed\"");
            return;
        }
        const cases = try splitCases(a, req);
        try report.print(a, ",\n  \"batch_cases\": {d}", .{cases.len});
        // 1. isolated reproduction of the whole batch in a fresh process
        const whole = try self.failsSubset(a, spec, cases, pred, req);
        try report.print(a, ",\n  \"isolated_batch_reproduces\": {}", .{whole});
        if (whole) {
            // 2. bisect to a minimal failing subset (only after confirming reproduction)
            var cur = try a.dupe([]const u8, cases);
            var progress = true;
            while (progress and cur.len > 1 and self.engine_runs < self.max_engine_runs) {
                progress = false;
                var chunks: usize = 2;
                while (chunks <= cur.len and !progress) : (chunks *= 2) {
                    const sz = (cur.len + chunks - 1) / chunks;
                    var start: usize = 0;
                    while (start < cur.len) : (start += sz) {
                        const end = @min(cur.len, start + sz);
                        if (try self.failsSubset(a, spec, cur[start..end], pred, null)) {
                            cur = cur[start..end];
                            progress = true;
                            break;
                        }
                        if (self.engine_runs >= self.max_engine_runs) break;
                    }
                }
            }
            try report.print(a, ",\n  \"minimal_failing_subset\": {d}", .{cur.len});
            if (cur.len > 1 and pred.kind == .timeout) try report.appendSlice(a, ",\n  \"timeout_class\": \"aggregate: no smaller subset times out on its own\"");
            var out: std.ArrayList(u8) = .empty;
            try out.appendSlice(a, "[1,[");
            for (cur, 0..) |cs, i| {
                if (i > 0) try out.append(a, ',');
                try out.appendSlice(a, cs);
            }
            try out.appendSlice(a, "]]\n");
            try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/isolated.req", .{dir}), out.items);
            try report.appendSlice(a, ",\n  \"status\": \"reproduced in isolation; minimized request in isolated.req\"");
            if (pred.kind == .timeout) _ = self.run.slow_cases.fetchAdd(0, .monotonic);
            _ = self.run.confirmed.fetchAdd(1, .monotonic);
            return;
        }
        // 3. replay the ordered process history (journal prefix)
        const jpath = journal orelse {
            try report.appendSlice(a, ",\n  \"status\": \"not reproduced in isolation and no journal recorded\"");
            return;
        };
        const jtext = sys.readFileAlloc(a, jpath, 1 << 30) catch {
            try report.appendSlice(a, ",\n  \"status\": \"not reproduced in isolation; journal unreadable\"");
            return;
        };
        var lines: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, jtext, '\n');
        while (it.next()) |l| {
            if (l.len == 0 or l[0] == '#') continue;
            try lines.append(a, l);
            if (std.mem.eql(u8, l, std.mem.trimEnd(u8, req, "\n"))) break;
        }
        try report.print(a, ",\n  \"journal_prefix_requests\": {d}", .{lines.items.len});
        if (!try self.failsSequence(a, spec, lines.items, pred)) {
            try report.appendSlice(a, ",\n  \"status\": \"unresolved: not reproduced in isolation or by prefix replay (kept as recorded)\"");
            return;
        }
        // Greedy removal of earlier requests while the failure persists.
        var seq = try a.dupe([]const u8, lines.items);
        var i: usize = 0;
        while (i + 1 < seq.len and self.engine_runs < self.max_engine_runs) {
            var trial: std.ArrayList([]const u8) = .empty;
            for (seq, 0..) |l, j| if (j != i) try trial.append(a, l);
            if (try self.failsSequence(a, spec, trial.items, pred)) {
                seq = trial.items;
            } else i += 1;
        }
        var out: std.ArrayList(u8) = .empty;
        for (seq) |l| {
            try out.appendSlice(a, l);
            try out.append(a, '\n');
        }
        try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/sequence.jsonl", .{dir}), out.items);
        try report.print(a, ",\n  \"minimized_sequence_requests\": {d},\n  \"status\": \"sequence-dependent: reproduced by ordered replay; see sequence.jsonl (irreducible below this length within budget)\"", .{seq.len});
        _ = self.run.confirmed.fetchAdd(1, .monotonic);
    }

    fn failsSubset(self: *Triage, a: Allocator, spec: *const harness.ModeSpec, cases: []const []const u8, pred: finding.Predicate, raw: ?[]const u8) !bool {
        var req: std.ArrayList(u8) = .empty;
        if (raw) |r| {
            try req.appendSlice(a, r);
            if (r.len == 0 or r[r.len - 1] != '\n') try req.append(a, '\n');
        } else {
            try req.appendSlice(a, "[1,[");
            for (cases, 0..) |cs, i| {
                if (i > 0) try req.append(a, ',');
                try req.appendSlice(a, cs);
            }
            try req.appendSlice(a, "]]\n");
        }
        const bits = try a.alloc(u8, cases.len);
        const o = self.runRequest(spec, req.items, @intCast(cases.len), bits, true);
        return switch (o) {
            .failed => |f| f.kind == pred.kind and (pred.kind != .crash or f.signal == pred.signal),
            .bits => false,
        };
    }

    fn failsSequence(self: *Triage, a: Allocator, spec: *const harness.ModeSpec, lines: []const []const u8, pred: finding.Predicate) !bool {
        // Fresh process, then each request in order; the failure must occur.
        _ = self.childFor(spec, true) orelse return false;
        for (lines) |l| {
            const n = countCases(l);
            const req = try a.alloc(u8, l.len + 1);
            @memcpy(req[0..l.len], l);
            req[l.len] = '\n';
            const bits = try a.alloc(u8, n);
            const o = self.runRequest(spec, req, @intCast(n), bits, false);
            switch (o) {
                .failed => |f| return f.kind == pred.kind and (pred.kind != .crash or f.signal == pred.signal),
                .bits => {},
            }
        }
        return false;
    }
};

const Variant = union(enum) {
    child: u8,
    replace_atom: atoms.AtomSpec,
    quant: ast.QuantSpec,
};

fn rebuild(src: *const ast.Ast, target: u8, v: Variant) ast.Ast {
    var out: ast.Ast = .{};
    out.root = copyWith(src, src.root, target, v, &out) catch unreachable;
    return out;
}

fn copyWith(src: *const ast.Ast, idx: u8, target: u8, v: Variant, dst: *ast.Ast) !u8 {
    if (idx == target) {
        switch (v) {
            .child => |c| return copyWith(src, c, 255, v, dst),
            .replace_atom => |at| return dst.add(.{ .op = .atom, .atom = at }),
            .quant => |q| {
                var n = src.nodes[idx];
                n.quant = q;
                n.a = try copyWith(src, n.a, target, v, dst);
                return dst.add(n);
            },
        }
    }
    var n = src.nodes[idx];
    switch (n.op) {
        .atom => {},
        .concat, .alt => {
            n.a = try copyWith(src, n.a, target, v, dst);
            n.b = try copyWith(src, n.b, target, v, dst);
        },
        else => n.a = try copyWith(src, n.a, target, v, dst),
    }
    return dst.add(n);
}

fn recordField(text: []const u8, key: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |l| {
        if (l.len > key.len and std.mem.startsWith(u8, l, key) and l[key.len] == '=') return l[key.len + 1 ..];
    }
    return null;
}

fn parseSeq(req: []const u8) ?u64 {
    if (req.len < 2 or req[0] != '[') return null;
    const comma = std.mem.indexOfScalar(u8, req, ',') orelse return null;
    return std.fmt.parseInt(u64, req[1..comma], 10) catch null;
}

/// Split "[seq,[c1,c2,...]]" into the raw JSON text of each case.
pub fn splitCases(a: Allocator, req: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    const open = std.mem.indexOf(u8, req, ",[") orelse return out.toOwnedSlice(a);
    var i = open + 2;
    var depth: usize = 0;
    var start: usize = i;
    var in_str = false;
    while (i < req.len) : (i += 1) {
        const ch = req[i];
        if (in_str) {
            if (ch == '\\') i += 1 else if (ch == '"') in_str = false;
            continue;
        }
        switch (ch) {
            '"' => in_str = true,
            '[' => {
                if (depth == 0) start = i;
                depth += 1;
            },
            ']' => {
                if (depth == 0) break;
                depth -= 1;
                if (depth == 0) try out.append(a, req[start .. i + 1]);
            },
            else => {},
        }
    }
    return out.toOwnedSlice(a);
}

fn countCases(line: []const u8) usize {
    var arena_buf: [1 << 16]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arena_buf);
    const cs = splitCases(fba.allocator(), line) catch return 0;
    return cs.len;
}

test "split cases respects strings" {
    const req = "[3,[[\"\",\"a]\",\"b\",\"[a]\"],[\"i\",\"\\\"\",\"x\",\"y\"]]]";
    const cs = try splitCases(std.testing.allocator, req);
    defer std.testing.allocator.free(cs);
    try std.testing.expectEqual(@as(usize, 2), cs.len);
    try std.testing.expectEqualStrings("[\"\",\"a]\",\"b\",\"[a]\"]", cs[0]);
    try std.testing.expectEqual(@as(?u64, 3), parseSeq(req));
}

test "rebuild substitutes a subtree" {
    var t: ast.Ast = .{};
    const a = try t.add(.{ .op = .atom, .atom = .{ .kind = .lit, .syms = .{ 'a', 0, 0, 0 } } });
    const b = try t.add(.{ .op = .atom, .atom = .{ .kind = .lit, .syms = .{ 'b', 0, 0, 0 } } });
    t.root = try t.add(.{ .op = .concat, .a = a, .b = b });
    const r = rebuild(&t, t.root, .{ .child = b });
    try std.testing.expectEqual(@as(usize, 1), r.size(r.root));
    try std.testing.expectEqual(@as(u21, 'b'), r.nodes[r.root].atom.syms[0]);
}
