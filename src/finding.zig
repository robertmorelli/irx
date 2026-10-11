//! Owned cases, failure predicates, and persisted findings: one directory per
//! finding (case.irx machine-readable, case.json, repro.js, manifest.json),
//! group indexes for navigation, and lossless content-hash dedup that only
//! coalesces byte-identical canonical reproducers.
const std = @import("std");
const alpha = @import("alphabet.zig");
const ast = @import("ast.zig");
const sys = @import("sys.zig");
const harness = @import("harness.zig");
const sample = @import("sample.zig");

const Flags = alpha.Flags;
const Allocator = std.mem.Allocator;

pub const max_units = 64;

pub const Subject = struct {
    units: [max_units]u16 = undefined,
    len: u8 = 0,
    pub fn slice(self: *const Subject) []const u16 {
        return self.units[0..self.len];
    }
    pub fn set(self: *Subject, s: []const u16) void {
        @memcpy(self.units[0..s.len], s);
        self.len = @intCast(s.len);
    }
};

pub const TableRef = struct {
    seq: u64 = 0,
    attempt: u32 = 0,
    seed: u64 = 0,
    digest: [32]u8 = [_]u8{0} ** 32,
};

/// Owned case: no PairIds or table pointers.
pub const Case = struct {
    id: u64 = 0,
    flags: Flags = .{},
    a: Subject = .{},
    r: Subject = .{},
    tree: ast.Ast = .{},
    pattern: std.ArrayList(u8) = .empty,
    /// Printer spelling seed for empty atoms (sample.Printer.spell); 0 = canonical.
    spell: u64 = 0,
    /// Long-input pair (long mode): pumped from A, checked by the long-string reference
    /// (long.zig); expected (true, false) like A/R. Empty when the case has none. Memory is
    /// owned by whoever filled the case (a lane buffer or the triage arena).
    la: []const u16 = &.{},
    lr: []const u16 = &.{},
    /// Expected (test(A), test(R)) from the model. Fuzz cases are (true, false).
    exp_a: bool = true,
    exp_r: bool = false,
    size: u16 = 0,
    table: TableRef = .{},
    global_seed: u64 = 0,
    lane: u32 = 0,
    index: u64 = 0,
    selfcheck: bool = false,
};

pub const Kind = enum { wrong_result, syntax_error, exception, tier_mismatch, crash, timeout, protocol, sanity_disagreement, selfcheck_mismatch, wrong_span, wrong_capture, long_result };

/// The recorded failure predicate that shrinking must preserve.
pub const Predicate = struct {
    kind: Kind,
    mode: []const u8,
    observed: u8 = 0,
    expected: u8 = 0,
    /// Which result bits differ (wrong_result / tier_mismatch).
    diff: u8 = 0,
    signal: u8 = 0,
    exit_code: u8 = 0,

    pub fn eqlShape(self: Predicate, other: Predicate) bool {
        if (self.kind != other.kind or !std.mem.eql(u8, self.mode, other.mode)) return false;
        return switch (self.kind) {
            .wrong_result, .tier_mismatch, .selfcheck_mismatch, .sanity_disagreement, .wrong_span, .wrong_capture, .long_result => self.diff == other.diff,
            .crash => self.signal == other.signal,
            else => true,
        };
    }
};

pub fn expectedBits(expect: harness.Expect, exp_a: bool, exp_r: bool) u8 {
    var b: u8 = 0;
    if (exp_a) b |= harness.Bits.test_a;
    if (exp_r) b |= harness.Bits.test_r;
    if (expect == .tierup) b |= b << 4;
    // Span mode (span.check): test_a = A's span agrees, test_r = R's span disagrees.
    if (expect.isSpan() or expect.isCapture()) b = harness.Bits.test_a;
    return b;
}

/// Classify one mode's result for a case. Null = agreement (or a legal skip).
pub fn classify(expect: harness.Expect, mode: []const u8, bits: u8, exp_a: bool, exp_r: bool) ?Predicate {
    const want = expectedBits(expect, exp_a, exp_r);
    if (bits & harness.Bits.skipped != 0) return null;
    if (bits & harness.Bits.syntax != 0) return .{ .kind = .syntax_error, .mode = mode, .observed = bits, .expected = want };
    if (bits & harness.Bits.exception != 0) return .{ .kind = .exception, .mode = mode, .observed = bits, .expected = want };
    if (bits == want) return null;
    if (expect.isSpan()) return .{ .kind = .wrong_span, .mode = mode, .observed = bits, .expected = want, .diff = bits ^ want };
    if (expect.isCapture()) return .{ .kind = .wrong_capture, .mode = mode, .observed = bits, .expected = want, .diff = bits ^ want };
    if (expect == .long) return .{ .kind = .long_result, .mode = mode, .observed = bits, .expected = want, .diff = bits ^ want };
    const first = (bits ^ want) & 0x03;
    if (first != 0) return .{ .kind = .wrong_result, .mode = mode, .observed = bits, .expected = want, .diff = bits ^ want };
    return .{ .kind = .tier_mismatch, .mode = mode, .observed = bits, .expected = want, .diff = bits ^ want };
}

// ---------------------------------------------------------------------------
// Serialization helpers

pub fn hexUnits(out: *std.ArrayList(u8), gpa: Allocator, s: []const u16) !void {
    for (s, 0..) |u, i| {
        if (i > 0) try out.append(gpa, ' ');
        try out.print(gpa, "{x:0>4}", .{u});
    }
}

pub fn parseUnits(text: []const u8, out: *Subject) !void {
    out.len = 0;
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    while (it.next()) |t| {
        if (out.len >= max_units) return error.SubjectTooLong;
        out.units[out.len] = try std.fmt.parseInt(u16, t, 16);
        out.len += 1;
    }
}

/// Hex units of any length (long-mode subjects). Caller owns the result.
pub fn parseLong(gpa: Allocator, text: []const u8) ![]const u16 {
    var out: std.ArrayList(u16) = .empty;
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    while (it.next()) |t| try out.append(gpa, try std.fmt.parseInt(u16, t, 16));
    return out.toOwnedSlice(gpa);
}

const flag_strs: [32][]const u8 = blk: {
    var t: [32][]const u8 = undefined;
    for (0..32) |b| t[b] = fsStr(Flags.fromBits(b));
    break :blk t;
};

pub fn flagStr(f: Flags) []const u8 {
    return flag_strs[f.bits()];
}

fn fsStr(comptime f: Flags) []const u8 {
    comptime {
        var s: []const u8 = "";
        if (f.i) s = s ++ "i";
        if (f.m) s = s ++ "m";
        if (f.s) s = s ++ "s";
        if (f.u) s = s ++ "u";
        if (f.v) s = s ++ "v";
        return s;
    }
}

/// Machine-readable case record (key=value lines).
pub fn writeCaseRecord(out: *std.ArrayList(u8), gpa: Allocator, c: *const Case, pred: Predicate) !void {
    try out.print(gpa, "id={d}\nkind={s}\nmode={s}\nobserved={x:0>2}\nexpected={x:0>2}\ndiff={x:0>2}\nsignal={d}\nexit={d}\n", .{ c.id, @tagName(pred.kind), pred.mode, pred.observed, pred.expected, pred.diff, pred.signal, pred.exit_code });
    try out.print(gpa, "flags={s}\n", .{flagStr(c.flags)});
    try out.appendSlice(gpa, "a=");
    try hexUnits(out, gpa, c.a.slice());
    try out.appendSlice(gpa, "\nr=");
    try hexUnits(out, gpa, c.r.slice());
    if (c.la.len > 0 or c.lr.len > 0) {
        try out.appendSlice(gpa, "\nla=");
        try hexUnits(out, gpa, c.la);
        try out.appendSlice(gpa, "\nlr=");
        try hexUnits(out, gpa, c.lr);
    }
    try out.print(gpa, "\nexp_a={d}\nexp_r={d}\n", .{ @intFromBool(c.exp_a), @intFromBool(c.exp_r) });
    try out.appendSlice(gpa, "pattern=");
    try out.appendSlice(gpa, c.pattern.items);
    try out.print(gpa, "\nspell={d}", .{c.spell});
    try out.appendSlice(gpa, "\nast=");
    try ast.serialize(&c.tree, out, gpa);
    try out.print(gpa, "\nsize={d}\ntable_seq={d}\ntable_attempt={d}\ntable_seed={d}\ntable_digest={s}\nglobal_seed={d}\nlane={d}\nindex={d}\nselfcheck={d}\n", .{
        c.size, c.table.seq, c.table.attempt, c.table.seed, std.fmt.bytesToHex(c.table.digest, .lower), c.global_seed, c.lane, c.index, @intFromBool(c.selfcheck),
    });
}

pub const LoadedCase = struct {
    case: Case,
    pred: Predicate,
    mode_buf: [32]u8,
};

pub fn readCaseRecord(gpa: Allocator, text: []const u8, out: *LoadedCase) !void {
    out.case = .{};
    out.pred = .{ .kind = .wrong_result, .mode = "" };
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const k = line[0..eq];
        const v = line[eq + 1 ..];
        const e = std.mem.eql;
        if (e(u8, k, "id")) out.case.id = try std.fmt.parseInt(u64, v, 10) else if (e(u8, k, "kind")) out.pred.kind = std.meta.stringToEnum(Kind, v) orelse return error.BadRecord else if (e(u8, k, "mode")) {
            const n = @min(v.len, out.mode_buf.len);
            @memcpy(out.mode_buf[0..n], v[0..n]);
            out.pred.mode = out.mode_buf[0..n];
        } else if (e(u8, k, "observed")) out.pred.observed = try std.fmt.parseInt(u8, v, 16) else if (e(u8, k, "expected")) out.pred.expected = try std.fmt.parseInt(u8, v, 16) else if (e(u8, k, "diff")) out.pred.diff = try std.fmt.parseInt(u8, v, 16) else if (e(u8, k, "signal")) out.pred.signal = try std.fmt.parseInt(u8, v, 10) else if (e(u8, k, "exit")) out.pred.exit_code = try std.fmt.parseInt(u8, v, 10) else if (e(u8, k, "flags")) out.case.flags = try Flags.parse(v) else if (e(u8, k, "a")) try parseUnits(v, &out.case.a) else if (e(u8, k, "r")) try parseUnits(v, &out.case.r) else if (e(u8, k, "la")) out.case.la = try parseLong(gpa, v) else if (e(u8, k, "lr")) out.case.lr = try parseLong(gpa, v) else if (e(u8, k, "exp_a")) out.case.exp_a = v.len > 0 and v[0] == '1' else if (e(u8, k, "exp_r")) out.case.exp_r = v.len > 0 and v[0] == '1' else if (e(u8, k, "pattern")) {
            out.case.pattern = .empty;
            try out.case.pattern.appendSlice(gpa, v);
        } else if (e(u8, k, "spell")) out.case.spell = try std.fmt.parseInt(u64, v, 10) else if (e(u8, k, "ast")) out.case.tree = try ast.parse(v) else if (e(u8, k, "size")) out.case.size = try std.fmt.parseInt(u16, v, 10) else if (e(u8, k, "table_seq")) out.case.table.seq = try std.fmt.parseInt(u64, v, 10) else if (e(u8, k, "table_attempt")) out.case.table.attempt = try std.fmt.parseInt(u32, v, 10) else if (e(u8, k, "table_seed")) out.case.table.seed = try std.fmt.parseInt(u64, v, 10) else if (e(u8, k, "table_digest")) {
            if (v.len == 64) _ = std.fmt.hexToBytes(&out.case.table.digest, v) catch {};
        } else if (e(u8, k, "global_seed")) out.case.global_seed = try std.fmt.parseInt(u64, v, 10) else if (e(u8, k, "lane")) out.case.lane = try std.fmt.parseInt(u32, v, 10) else if (e(u8, k, "index")) out.case.index = try std.fmt.parseInt(u64, v, 10) else if (e(u8, k, "selfcheck")) out.case.selfcheck = v.len > 0 and v[0] == '1';
    }
}

fn jsString(out: *std.ArrayList(u8), gpa: Allocator, units: []const u16) !void {
    try harness.jsonString(out, gpa, units);
}

pub fn wrapPattern(out: *std.ArrayList(u8), gpa: Allocator, pattern: []const u8, flags: Flags) !void {
    if (flags.m) {
        try out.appendSlice(gpa, "(?<![\\s\\S])(?:");
        try out.appendSlice(gpa, pattern);
        try out.appendSlice(gpa, ")(?![\\s\\S])");
    } else {
        try out.appendSlice(gpa, "^(?:");
        try out.appendSlice(gpa, pattern);
        try out.appendSlice(gpa, ")$");
    }
}

/// repro.js with JSON-escaped construction, the actual wrapper and call order.
pub fn writeRepro(out: *std.ArrayList(u8), gpa: Allocator, c: *const Case, pred: Predicate, spec: ?*const harness.ModeSpec, exe: []const u8, prefix_journal: ?[]const u8) !void {
    try out.print(gpa, "// irx reproducer for finding {d} ({s}, mode {s})\n", .{ c.id, @tagName(pred.kind), pred.mode });
    if (spec) |s| {
        try out.print(gpa, "// run: {s}", .{exe});
        for (s.flags) |f| try out.print(gpa, " {s}", .{f});
        try out.appendSlice(gpa, " repro.js\n");
    }
    if (prefix_journal) |j| try out.print(gpa, "// sequence-dependent: replay the journal prefix first: {s}\n", .{j});
    try out.print(gpa, "// expected (relation model): test(A)={} test(R)={}\n", .{ c.exp_a, c.exp_r });
    try out.appendSlice(gpa, "var src = ");
    var w: std.ArrayList(u8) = .empty;
    defer w.deinit(gpa);
    try wrapPattern(&w, gpa, c.pattern.items, c.flags);
    try harness.jsonAscii(out, gpa, w.items);
    try out.appendSlice(gpa, ";\nvar flags = ");
    try harness.jsonAscii(out, gpa, flagStr(c.flags));
    if (spec != null and spec.?.expect == .linear) try out.appendSlice(gpa, " + \"l\"");
    const long = spec != null and spec.?.expect.isLong();
    try out.appendSlice(gpa, if (long) ";\n// long mode: A and R are the long pair\nvar A = " else ";\nvar A = ");
    try jsString(out, gpa, if (long) c.la else c.a.slice());
    try out.appendSlice(gpa, ";\nvar R = ");
    try jsString(out, gpa, if (long) c.lr else c.r.slice());
    try out.appendSlice(gpa, ";\nvar re = new RegExp(src, flags);\nvar got = [re.test(A), re.test(R)");
    if (spec != null and spec.?.expect == .tierup) try out.appendSlice(gpa, ", re.test(A), re.test(R)");
    try out.print(gpa, "];\nprint(JSON.stringify(got), \"expected\", JSON.stringify([{}, {}]));\n", .{ c.exp_a, c.exp_r });
}

/// Index of the first UTF-16 unit where a and b differ (the reject's edit position).
pub fn firstDifference(a: []const u16, b: []const u16) usize {
    const n = @min(a.len, b.len);
    for (0..n) |i| if (a[i] != b[i]) return i;
    return n;
}

pub fn writeCaseJson(out: *std.ArrayList(u8), gpa: Allocator, c: *const Case, pred: Predicate, status: []const u8) !void {
    try out.print(gpa, "{{\n  \"id\": {d},\n  \"kind\": \"{s}\",\n  \"mode\": \"{s}\",\n  \"status\": \"{s}\",\n  \"flags\": \"{s}\",\n  \"A\": ", .{ c.id, @tagName(pred.kind), pred.mode, status, flagStr(c.flags) });
    try jsString(out, gpa, c.a.slice());
    try out.appendSlice(gpa, ",\n  \"R\": ");
    try jsString(out, gpa, c.r.slice());
    if (c.la.len > 0 or c.lr.len > 0) {
        try out.print(gpa, ",\n  \"long\": {{\"la_len\": {d}, \"lr_len\": {d}, \"first_difference\": {d}}}", .{ c.la.len, c.lr.len, firstDifference(c.la, c.lr) });
        try out.appendSlice(gpa, ",\n  \"LA\": ");
        try jsString(out, gpa, c.la);
        try out.appendSlice(gpa, ",\n  \"LR\": ");
        try jsString(out, gpa, c.lr);
    }
    try out.appendSlice(gpa, ",\n  \"pattern\": ");
    try harness.jsonAscii(out, gpa, c.pattern.items);
    try out.appendSlice(gpa, ",\n  \"ast\": ");
    var a: std.ArrayList(u8) = .empty;
    defer a.deinit(gpa);
    try ast.serialize(&c.tree, &a, gpa);
    try harness.jsonAscii(out, gpa, a.items);
    try out.print(gpa, ",\n  \"expected\": {{\"testA\": {}, \"testR\": {}, \"bits\": \"{x:0>2}\"}},\n  \"observed_bits\": \"{x:0>2}\",\n  \"signal\": {d},\n  \"table\": {{\"seq\": {d}, \"attempt\": {d}, \"seed\": {d}, \"digest\": \"{s}\"}},\n  \"seeds\": {{\"global\": {d}, \"lane\": {d}, \"case_index\": {d}}},\n  \"size\": {d}\n}}\n", .{
        c.exp_a, c.exp_r, pred.expected, pred.observed, pred.signal, c.table.seq, c.table.attempt, c.table.seed, std.fmt.bytesToHex(c.table.digest, .lower), c.global_seed, c.lane, c.index, c.size,
    });
}

// ---------------------------------------------------------------------------
// Store

pub const Store = struct {
    gpa: Allocator,
    root: []const u8,
    mutex: sys.Mutex = .{},
    next_id: u64 = 1,
    /// content hash -> finding id; canonical bytes kept for collision checks
    seen: std.AutoHashMapUnmanaged([32]u8, Seen) = .empty,
    count: u64 = 0,
    coalesced: u64 = 0,
    manifest_ref: []const u8 = "../../manifest.json",
    const Seen = struct { id: u64, canon: []u8 };

    pub fn init(gpa: Allocator, root: []const u8) !Store {
        var b: [4096]u8 = undefined;
        for ([_][]const u8{ "findings", "groups", "slow", "journals", "selfcheck" }) |d| {
            const p = try std.fmt.bufPrint(&b, "{s}/{s}", .{ root, d });
            try sys.mkdirp(p);
        }
        return .{ .gpa = gpa, .root = root };
    }

    pub fn findingDir(self: *const Store, buf: []u8, id: u64) ![]const u8 {
        return std.fmt.bufPrint(buf, "{s}/findings/{d:0>6}", .{ self.root, id });
    }

    fn canonical(gpa: Allocator, c: *const Case, pred: Predicate, build_id: []const u8, history: []const u8) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        try out.print(gpa, "{s}\x00{s}\x00{s}\x00{x}\x00{d}\x00{s}\x00{s}\x00", .{ flagStr(c.flags), pred.mode, @tagName(pred.kind), pred.diff, pred.signal, build_id, history });
        try out.appendSlice(gpa, std.mem.sliceAsBytes(c.a.slice()));
        try out.append(gpa, 0);
        try out.appendSlice(gpa, std.mem.sliceAsBytes(c.r.slice()));
        try out.append(gpa, 0);
        try out.appendSlice(gpa, std.mem.sliceAsBytes(c.la));
        try out.append(gpa, 0);
        try out.appendSlice(gpa, std.mem.sliceAsBytes(c.lr));
        try out.append(gpa, 0);
        try out.appendSlice(gpa, c.pattern.items);
        return out.toOwnedSlice(gpa);
    }

    pub const Persisted = struct { id: u64, new: bool };

    /// Persist a finding (or coalesce a byte-identical reproducer). Returns its id.
    pub fn persist(self: *Store, c: *Case, pred: Predicate, build_id: []const u8, history: []const u8, spec: ?*const harness.ModeSpec, exe: []const u8, journal: ?[]const u8, extra: ?[]const u8) !Persisted {
        const gpa = self.gpa;
        const canon = try canonical(gpa, c, pred, build_id, history);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(canon, &digest, .{});
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.seen.get(digest)) |s| {
            if (std.mem.eql(u8, s.canon, canon)) {
                gpa.free(canon);
                self.coalesced += 1;
                var b: [4096]u8 = undefined;
                const dir = try self.findingDir(&b, s.id);
                var pb: [4096]u8 = undefined;
                const p = try std.fmt.bufPrint(&pb, "{s}/occurrences", .{dir});
                const fd = try sys.openAppend(p);
                defer _ = sys.close(fd);
                var line: [128]u8 = undefined;
                try sys.appendFile(fd, try std.fmt.bufPrint(&line, "case lane={d} index={d} table={d}\n", .{ c.lane, c.index, c.table.seq }));
                return .{ .id = s.id, .new = false };
            }
            // Hash collision with different content: never coalesce.
        }
        const id = self.next_id;
        self.next_id += 1;
        c.id = id;
        if (self.seen.get(digest) == null) try self.seen.put(gpa, digest, .{ .id = id, .canon = canon }) else gpa.free(canon);
        self.count += 1;

        var b: [4096]u8 = undefined;
        const dir = try self.findingDir(&b, id);
        try sys.mkdirp(dir);
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(gpa);
        var pb: [4096]u8 = undefined;

        try writeCaseRecord(&buf, gpa, c, pred);
        if (journal) |j| try buf.print(gpa, "journal={s}\n", .{j});
        try buf.print(gpa, "content_hash={s}\nbuild={s}\nhistory={s}\n", .{ std.fmt.bytesToHex(digest, .lower), build_id, history });
        try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/case.irx", .{dir}), buf.items);

        buf.clearRetainingCapacity();
        try writeCaseJson(&buf, gpa, c, pred, "unconfirmed");
        try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/case.json", .{dir}), buf.items);

        buf.clearRetainingCapacity();
        try writeRepro(&buf, gpa, c, pred, spec, exe, journal);
        try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/repro.js", .{dir}), buf.items);

        buf.clearRetainingCapacity();
        try buf.print(gpa, "{{\"run_manifest\": \"{s}\", \"table\": {{\"seq\": {d}, \"attempt\": {d}, \"seed\": {d}, \"digest\": \"{s}\"}}, \"seeds\": {{\"global\": {d}, \"lane\": {d}, \"case_index\": {d}}}, \"mode\": \"{s}\", \"build\": \"{s}\"", .{
            self.manifest_ref, c.table.seq, c.table.attempt, c.table.seed, std.fmt.bytesToHex(c.table.digest, .lower), c.global_seed, c.lane, c.index, pred.mode, build_id,
        });
        if (spec) |s| {
            try buf.appendSlice(gpa, ", \"mode_flags\": [");
            for (s.flags, 0..) |f, i| {
                if (i > 0) try buf.append(gpa, ',');
                try harness.jsonAscii(&buf, gpa, f);
            }
            try buf.append(gpa, ']');
        }
        if (journal) |j| {
            try buf.appendSlice(gpa, ", \"journal\": ");
            try harness.jsonAscii(&buf, gpa, j);
        }
        if (extra) |x| {
            try buf.appendSlice(gpa, ", ");
            try buf.appendSlice(gpa, x);
        }
        try buf.appendSlice(gpa, ", \"confirmation\": \"unconfirmed: model and engine disagree; triage pending\"}\n");
        try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/manifest.json", .{dir}), buf.items);

        // Group index (navigation only; members are never deleted).
        var counts: [ast.n_constructs]u16 = undefined;
        ast.constructCounts(&c.tree, &counts);
        var ch = std.hash.Wyhash.init(0);
        ch.update(std.mem.sliceAsBytes(&counts));
        const gp = try std.fmt.bufPrint(&pb, "{s}/groups/{s}__{s}__{x:0>16}.txt", .{ self.root, @tagName(pred.kind), pred.mode, ch.final() });
        const gfd = try sys.openAppend(gp);
        defer _ = sys.close(gfd);
        var line: [64]u8 = undefined;
        try sys.appendFile(gfd, try std.fmt.bufPrint(&line, "{d:0>6}\n", .{id}));
        return .{ .id = id, .new = true };
    }
};

test "classification" {
    try std.testing.expect(classify(.normal, "interp", 0x01, true, false) == null);
    try std.testing.expectEqual(Kind.wrong_result, classify(.normal, "interp", 0x03, true, false).?.kind);
    try std.testing.expectEqual(Kind.syntax_error, classify(.normal, "native", 0x04, true, false).?.kind);
    try std.testing.expectEqual(Kind.tier_mismatch, classify(.tierup, "tierup", 0x01, true, false).?.kind);
    try std.testing.expect(classify(.tierup, "tierup", 0x11, true, false) == null);
    try std.testing.expect(classify(.linear, "linear", 0x40, true, false) == null);
}

test "case record round trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var c: Case = .{ .id = 7, .flags = .{ .i = true, .u = true } };
    c.a.set(&.{ 'a', 0xD83D, 0xDE00 });
    c.r.set(&.{'b'});
    c.tree.root = try c.tree.add(.{ .op = .atom, .atom = .{ .kind = .lit, .syms = .{ 'a', 0, 0, 0 } } });
    try c.pattern.appendSlice(gpa, "a");
    var out: std.ArrayList(u8) = .empty;
    try writeCaseRecord(&out, gpa, &c, .{ .kind = .wrong_result, .mode = "interp", .observed = 3, .expected = 1, .diff = 2 });
    var lc: LoadedCase = undefined;
    try readCaseRecord(gpa, out.items, &lc);
    try std.testing.expectEqual(@as(u64, 7), lc.case.id);
    try std.testing.expectEqualSlices(u16, c.a.slice(), lc.case.a.slice());
    try std.testing.expectEqualStrings("interp", lc.pred.mode);
    try std.testing.expectEqual(@as(u8, 2), lc.pred.diff);
    try std.testing.expect(lc.case.flags.i and lc.case.flags.u);
}
