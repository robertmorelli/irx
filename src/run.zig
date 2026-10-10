//! Shared campaign state: table publication (mutex-protected exchange of
//! strong references), the background table builder with bounded retries,
//! grammar cache, adaptive weights, the bounded triage queue with on-disk
//! overflow, and run-wide counters.
const std = @import("std");
const alpha = @import("alphabet.zig");
const config = @import("config.zig");
const tablemod = @import("table.zig");
const sample = @import("sample.zig");
const rngmod = @import("rng.zig");
const sys = @import("sys.zig");
const harness = @import("harness.zig");
const finding = @import("finding.zig");
const ast = @import("ast.zig");
const Budget = @import("budget.zig").Budget;

const Allocator = std.mem.Allocator;
const Table = tablemod.Table;
const Grammar = tablemod.Grammar;

pub const ModeStats = struct {
    executed: std.atomic.Value(u64) = .init(0),
    skipped_multiline: std.atomic.Value(u64) = .init(0),
    skipped_unsupported: std.atomic.Value(u64) = .init(0),
    mismatches: std.atomic.Value(u64) = .init(0),
    restarts: std.atomic.Value(u64) = .init(0),
    first_seen: std.atomic.Value(u64) = .init(0),
    repeated: std.atomic.Value(u64) = .init(0),
    engine_ns: std.atomic.Value(u64) = .init(0),
};

pub const max_modes = 12;

pub const Run = struct {
    gpa: Allocator,
    cfg: config.Config,
    host: Budget,
    global_seed: u64,
    out_dir: []const u8,
    d8_exe: []const u8,
    sm_exe: ?[]const u8 = null,
    jsc_exe: ?[]const u8 = null,
    driver_path: []const u8,
    driver_hash: []const u8,
    d8_hash: []const u8,
    d8_version: []const u8 = "",
    build_id: []const u8,
    modes: []const *const harness.ModeSpec,
    sanity_modes: []const *const harness.ModeSpec = &.{},
    store: finding.Store,
    lanes: u32 = 1,
    max_cases: u64 = std.math.maxInt(u64),
    deadline_ns: u64 = std.math.maxInt(u64),

    // --- table publication ---
    tmutex: sys.Mutex = .{},
    tcond: sys.Cond = .{},
    current: ?*Table = null,
    served: u64 = 0,
    replacement: ?*Table = null,
    live_tables: std.atomic.Value(u32) = .init(0),
    next_seq: u64 = 0,
    stop: std.atomic.Value(bool) = .init(false),
    stop_reason: [256]u8 = undefined,
    stop_reason_len: usize = 0,
    grammar_mutex: sys.Mutex = .{},
    grammars: std.ArrayList(*Grammar) = .empty,
    weights_epoch: u32 = 0,
    weight_log_fd: c_int = -1,

    // --- triage queue ---
    qmutex: sys.Mutex = .{},
    qcond: sys.Cond = .{},
    queue: std.ArrayList(u64) = .empty,
    queue_bytes: u64 = 0,
    overflowed: std.atomic.Value(u64) = .init(0),
    pending_fd: c_int = -1,
    pending_read_off: usize = 0,
    triage_done: std.atomic.Value(bool) = .init(false),

    // --- counters ---
    cases: std.atomic.Value(u64) = .init(0),
    batches: std.atomic.Value(u64) = .init(0),
    findings: std.atomic.Value(u64) = .init(0),
    findings_new: std.atomic.Value(u64) = .init(0),
    tables_built: std.atomic.Value(u64) = .init(0),
    zero_mass: std.atomic.Value(u64) = .init(0),
    resource_rejects: std.atomic.Value(u64) = .init(0),
    invalid_draws: std.atomic.Value(u64) = .init(0),
    build_ns: std.atomic.Value(u64) = .init(0),
    sample_ns: std.atomic.Value(u64) = .init(0),
    print_ns: std.atomic.Value(u64) = .init(0),
    encode_ns: std.atomic.Value(u64) = .init(0),
    wait_ns: std.atomic.Value(u64) = .init(0),
    idle_ns: std.atomic.Value(u64) = .init(0),
    slow_cases: std.atomic.Value(u64) = .init(0),
    triaged: std.atomic.Value(u64) = .init(0),
    confirmed: std.atomic.Value(u64) = .init(0),
    mode_stats: [max_modes]ModeStats = [_]ModeStats{.{}} ** max_modes,
    last_pairs: std.atomic.Value(u64) = .init(0),
    last_prods: std.atomic.Value(u64) = .init(0),
    last_stats: tablemod.BuildStats = .{},
    log_tables: bool = true,

    pub fn setStop(self: *Run, comptime f: []const u8, args: anytype) void {
        self.tmutex.lock();
        if (!self.stop.load(.monotonic)) {
            const s = std.fmt.bufPrint(&self.stop_reason, f, args) catch self.stop_reason[0..];
            self.stop_reason_len = s.len;
            self.stop.store(true, .release);
        }
        self.tcond.broadcast();
        self.tmutex.unlock();
        self.qmutex.lock();
        self.qcond.broadcast();
        self.qmutex.unlock();
    }

    pub fn stopReason(self: *const Run) []const u8 {
        return self.stop_reason[0..self.stop_reason_len];
    }

    pub fn stopped(self: *const Run) bool {
        return self.stop.load(.acquire);
    }

    // ------------------------------------------------------------------
    // Grammar cache

    pub fn grammarFor(self: *Run, flags: alpha.Flags) !*Grammar {
        self.grammar_mutex.lock();
        defer self.grammar_mutex.unlock();
        // newest epoch first
        var i = self.grammars.items.len;
        while (i > 0) {
            i -= 1;
            const g = self.grammars.items[i];
            if (g.flags.bits() == flags.bits()) return g;
        }
        const g = try self.gpa.create(Grammar);
        g.* = try Grammar.init(self.gpa, &self.cfg, flags);
        const bound = try sample.printedLengthBound(self.gpa, g, self.cfg.max_size);
        if (bound > self.cfg.max_pattern_bytes) return error.PatternBoundExceedsMax;
        try self.grammars.append(self.gpa, g);
        return g;
    }

    /// Adaptive mode: bump the weights of constructs present in a confirmed
    /// finding, capped at cap × base. Takes effect for tables built afterwards.
    pub fn adaptiveBump(self: *Run, counts: *const [ast.n_constructs]u16, base: *const config.Weights) void {
        if (!self.cfg.adaptive) return;
        self.grammar_mutex.lock();
        defer self.grammar_mutex.unlock();
        var changed = false;
        for (counts, 0..) |c, i| {
            if (c == 0) continue;
            const cap = base.w[i] * self.cfg.adaptive_cap;
            const nw = @min(self.cfg.weights.w[i] * self.cfg.adaptive_factor, cap);
            if (nw != self.cfg.weights.w[i]) {
                self.cfg.weights.w[i] = nw;
                changed = true;
            }
        }
        if (!changed) return;
        self.weights_epoch += 1;
        // Invalidate cached grammars for future tables (old ones stay alive for live tables).
        for (self.grammars.items) |g| g.flags._pad = 1; // mark stale: never matches lookups
        if (self.weight_log_fd >= 0) {
            var buf: std.ArrayList(u8) = .empty;
            defer buf.deinit(self.gpa);
            buf.print(self.gpa, "epoch={d} weights=", .{self.weights_epoch}) catch return;
            for (self.cfg.weights.w, 0..) |w, i| buf.print(self.gpa, "{s}{s}:{e}", .{ if (i > 0) "," else "", @tagName(@as(ast.Construct, @enumFromInt(i))), w }) catch return;
            buf.append(self.gpa, '\n') catch return;
            sys.appendFile(self.weight_log_fd, buf.items) catch {};
        }
    }

    // ------------------------------------------------------------------
    // Table building

    fn drawCodePoints(self: *Run, rng: *rngmod.Rng, out: *[64]u21) usize {
        const c = &self.cfg;
        const long = c.long_fraction > 0 and rng.float() < c.long_fraction;
        const lo: u8 = if (long) c.long_min else c.min_len;
        const hi: u8 = if (long) c.long_max else c.max_len;
        const len = lo + @as(u8, @intCast(rng.below(@as(u64, hi - lo) + 1)));
        for (0..len) |i| out[i] = alpha.active_pool[rng.below(alpha.active_pool.len)];
        return len;
    }

    /// Encode code points, enforcing the decoded-length cap for `flags`.
    fn encodeSubject(self: *Run, cps: []const u21, flags: alpha.Flags, out: *finding.Subject) bool {
        if (cps.len == 0 and self.cfg.min_len > 0) return false;
        var units: [128]u16 = undefined;
        const n = alpha.toUtf16(cps, &units);
        var syms: [128]u21 = undefined;
        const ns = alpha.decode(units[0..n], flags, &syms) orelse return false;
        if (ns > self.cfg.max_symbols or n > finding.max_units) return false;
        out.set(units[0..n]);
        return true;
    }

    pub const Attempt = union(enum) { table: *Table, zero_mass, resource, invalid };

    pub fn buildOne(self: *Run, seq: u64, attempt: u32) Attempt {
        const seed = rngmod.tableSeed(self.global_seed, seq, attempt);
        var rng = rngmod.Rng.fromParts(rngmod.Tag.strings, &.{seed});
        const fsets = self.cfg.flagSets();
        const flags = fsets[rng.below(fsets.len)];
        var a: finding.Subject = .{};
        var r: finding.Subject = .{};
        var draws: usize = 0;
        while (true) : (draws += 1) {
            if (draws > 1000) return .invalid;
            var ca: [64]u21 = undefined;
            var cr: [64]u21 = undefined;
            const na = self.drawCodePoints(&rng, &ca);
            const nr = if (self.cfg.max_edit_distance == 0)
                self.drawCodePoints(&rng, &cr)
            else
                editPair(&rng, ca[0..na], &cr, self.cfg.max_edit_distance);
            if (!self.encodeSubject(ca[0..na], flags, &a) or !self.encodeSubject(cr[0..nr], flags, &r)) {
                _ = self.invalid_draws.fetchAdd(1, .monotonic);
                continue;
            }
            if (!std.mem.eql(u16, a.slice(), r.slice())) break;
        }
        const g = self.grammarFor(flags) catch return .invalid;
        const t0 = sys.nowNs();
        const tab = tablemod.build(.{
            .grammar = g,
            .cfg = &self.cfg,
            .a16 = a.slice(),
            .r16 = r.slice(),
            .id = .{ .seq = seq, .attempt = attempt, .seed = seed, .flags = flags },
            .host = &self.host,
            .host_alloc = self.gpa,
        }) catch |e| return switch (e) {
            error.ZeroMass => .zero_mass,
            error.Resource => .resource,
            else => .invalid,
        };
        _ = self.build_ns.fetchAdd(sys.nowNs() - t0, .monotonic);
        return .{ .table = tab };
    }

    /// Background builder: keeps one replacement ready, waiting while two
    /// tables (active + replacement or batch-held retired) are alive.
    pub fn builderLoop(self: *Run) void {
        _ = sys.setThreadQos();
        while (!self.stopped()) {
            self.tmutex.lock();
            while (!self.stopped() and (self.replacement != null or self.live_tables.load(.acquire) >= 2)) self.tcond.wait(&self.tmutex);
            const seq = self.next_seq;
            self.next_seq += 1;
            self.tmutex.unlock();
            if (self.stopped()) break;

            var attempt: u32 = 0;
            var zm: u32 = 0;
            var res: u32 = 0;
            var inv: u32 = 0;
            const tab: *Table = while (attempt < self.cfg.max_table_attempts) : (attempt += 1) {
                if (self.stopped()) return;
                switch (self.buildOne(seq, attempt)) {
                    .table => |t| break t,
                    .zero_mass => {
                        zm += 1;
                        _ = self.zero_mass.fetchAdd(1, .monotonic);
                    },
                    .resource => {
                        res += 1;
                        _ = self.resource_rejects.fetchAdd(1, .monotonic);
                    },
                    .invalid => inv += 1,
                }
            } else {
                self.setStop("table retry exhaustion: {d} consecutive failed attempts for table {d} (zero-mass={d}, resource={d}, invalid={d})", .{ self.cfg.max_table_attempts, seq, zm, res, inv });
                return;
            };
            _ = self.live_tables.fetchAdd(1, .acq_rel);
            tab.live_counter = &self.live_tables;
            _ = self.tables_built.fetchAdd(1, .monotonic);
            self.last_pairs.store(tab.stats.pairs, .monotonic);
            self.last_prods.store(tab.stats.prods, .monotonic);
            if (self.log_tables) self.logTable(tab);

            self.tmutex.lock();
            self.last_stats = tab.stats;
            if (self.current == null) {
                self.current = tab;
                self.served = 0;
            } else self.replacement = tab;
            self.tcond.broadcast();
            self.tmutex.unlock();
        }
    }

    fn logTable(self: *Run, tab: *Table) void {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.gpa);
        var fb: [8]u8 = undefined;
        buf.print(self.gpa, "table seq={d} attempt={d} flags=\"{s}\" A=", .{ tab.id.seq, tab.id.attempt, tab.id.flags.str(&fb) }) catch return;
        harness.jsonString(&buf, self.gpa, tab.a16) catch return;
        buf.appendSlice(self.gpa, " R=") catch return;
        harness.jsonString(&buf, self.gpa, tab.r16) catch return;
        buf.print(self.gpa, " digest={s}\n", .{tablemod.digestHex(tab)}) catch return;
        tab.stats.write(&buf, self.gpa) catch return;
        var pb: [4096]u8 = undefined;
        const p = std.fmt.bufPrint(&pb, "{s}/tables.log", .{self.out_dir}) catch return;
        const fd = sys.openAppend(p) catch return;
        defer _ = sys.close(fd);
        sys.appendFile(fd, buf.items) catch {};
    }

    /// Acquire a strong table reference and up to `want` cases of its quota.
    pub fn acquire(self: *Run, want: u64) ?struct { tab: *Table, n: u64 } {
        self.tmutex.lock();
        defer self.tmutex.unlock();
        const t_wait = sys.nowNs();
        defer _ = self.idle_ns.fetchAdd(sys.nowNs() - t_wait, .monotonic);
        while (true) {
            if (self.stopped()) return null;
            if (self.current) |cur| {
                if (self.served < self.cfg.samples_per_table) {
                    const n = @min(want, self.cfg.samples_per_table - self.served);
                    self.served += n;
                    cur.acquire();
                    return .{ .tab = cur, .n = n };
                }
                if (self.replacement) |rep| {
                    self.current = rep;
                    self.replacement = null;
                    self.served = 0;
                    cur.release(); // the run's reference; batches may still hold theirs
                    self.tcond.broadcast();
                    continue;
                }
            }
            self.tcond.wait(&self.tmutex);
        }
    }

    pub fn releaseTable(self: *Run, tab: *Table) void {
        tab.release();
        self.tmutex.lock();
        self.tcond.broadcast();
        self.tmutex.unlock();
    }

    pub fn shutdownTables(self: *Run) void {
        self.tmutex.lock();
        defer self.tmutex.unlock();
        if (self.current) |c| c.release();
        if (self.replacement) |r| r.release();
        self.current = null;
        self.replacement = null;
    }

    // ------------------------------------------------------------------
    // Triage queue (bounded by count and bytes; overflow persisted to disk)

    pub fn enqueueFinding(self: *Run, id: u64, bytes: u64) void {
        self.qmutex.lock();
        defer self.qmutex.unlock();
        if (self.queue.items.len < self.cfg.max_pending_findings and self.queue_bytes + bytes <= self.cfg.max_pending_finding_bytes) {
            self.queue.append(self.gpa, id) catch {
                self.spill(id);
                return;
            };
            self.queue_bytes += bytes;
            self.qcond.signal();
            return;
        }
        self.spill(id);
    }

    fn spill(self: *Run, id: u64) void {
        // Findings are already persisted; record the id for later triage.
        _ = self.overflowed.fetchAdd(1, .monotonic);
        if (self.pending_fd < 0) return;
        var line: [32]u8 = undefined;
        sys.appendFile(self.pending_fd, std.fmt.bufPrint(&line, "{d}\n", .{id}) catch return) catch {
            self.setStop("failed to persist triage overflow list", .{});
        };
        self.qcond.signal();
    }

    pub fn queueFull(self: *Run) bool {
        self.qmutex.lock();
        defer self.qmutex.unlock();
        return self.queue.items.len >= self.cfg.max_pending_findings;
    }

    /// Next finding id for triage: queue first, then the on-disk overflow
    /// list in bounded groups. Null when stopping and nothing remains.
    pub fn nextFinding(self: *Run, est_bytes: u64) ?u64 {
        self.qmutex.lock();
        defer self.qmutex.unlock();
        while (true) {
            if (self.queue.items.len > 0) {
                const id = self.queue.orderedRemove(0);
                self.queue_bytes -|= est_bytes;
                return id;
            }
            if (self.triage_done.load(.acquire)) return null;
            if (self.readOverflow()) |id| return id;
            self.qcond.wait(&self.qmutex);
        }
    }

    fn readOverflow(self: *Run) ?u64 {
        if (self.overflowed.load(.monotonic) == 0) return null;
        var pb: [4096]u8 = undefined;
        const p = std.fmt.bufPrint(&pb, "{s}/triage_pending.txt", .{self.out_dir}) catch return null;
        const data = sys.readFileAlloc(self.gpa, p, 64 << 20) catch return null;
        defer self.gpa.free(data);
        if (self.pending_read_off >= data.len) return null;
        const rest = data[self.pending_read_off..];
        const nl = std.mem.indexOfScalar(u8, rest, '\n') orelse return null;
        self.pending_read_off += nl + 1;
        return std.fmt.parseInt(u64, rest[0..nl], 10) catch null;
    }

    /// Stop triage after its current item. Unprocessed queued findings are
    /// spilled to triage_pending.txt for `irx triage` to resume later.
    pub fn finishTriage(self: *Run) void {
        self.qmutex.lock();
        self.triage_done.store(true, .release);
        for (self.queue.items) |id| self.spill(id);
        self.queue.clearRetainingCapacity();
        self.qcond.broadcast();
        self.qmutex.unlock();
    }
};

/// R = A after 1..k random code-point edits (insert, delete, substitute from
/// the pool), so Levenshtein(A, R) <= k. Returns R's length.
pub fn editPair(rng: *rngmod.Rng, a: []const u21, out: *[64]u21, k: u8) usize {
    var n = a.len;
    @memcpy(out[0..n], a);
    const edits = 1 + rng.below(k);
    for (0..edits) |_| {
        const pool = alpha.active_pool;
        const op = rng.below(3);
        if (op == 0 and n < out.len) { // insert
            const at = rng.below(n + 1);
            std.mem.copyBackwards(u21, out[at + 1 .. n + 1], out[at..n]);
            out[at] = pool[rng.below(pool.len)];
            n += 1;
        } else if (op == 1 and n > 0) { // delete
            const at = rng.below(n);
            std.mem.copyForwards(u21, out[at .. n - 1], out[at + 1 .. n]);
            n -= 1;
        } else if (n > 0) { // substitute
            out[rng.below(n)] = pool[rng.below(pool.len)];
        }
    }
    return n;
}

fn levenshtein(a: []const u21, b: []const u21) usize {
    var prev: [65]usize = undefined;
    var cur: [65]usize = undefined;
    for (0..b.len + 1) |j| prev[j] = j;
    for (a, 0..) |x, i| {
        cur[0] = i + 1;
        for (b, 0..) |y, j| cur[j + 1] = @min(@min(prev[j + 1] + 1, cur[j] + 1), prev[j] + @intFromBool(x != y));
        @memcpy(prev[0 .. b.len + 1], cur[0 .. b.len + 1]);
    }
    return prev[b.len];
}

test "editPair keeps edit distance within k" {
    var rng = rngmod.Rng.fromParts(3, &.{});
    for (0..2000) |i| {
        var a: [64]u21 = undefined;
        const na = 1 + rng.below(8);
        for (0..na) |j| a[j] = alpha.default_pool[rng.below(alpha.default_pool.len)];
        var r: [64]u21 = undefined;
        const k: u8 = @intCast(1 + i % 3);
        const nr = editPair(&rng, a[0..na], &r, k);
        try std.testing.expect(levenshtein(a[0..na], r[0..nr]) <= k);
    }
}
