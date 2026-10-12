//! Startup atom self-check: for every configured flag set, compare model
//! membership of every consuming atom against every test subject, and every
//! assertion at every position of whole-string contexts, against an engine
//! (d8 interp, plus any available independent engines). Expectations come
//! from the relation model; discrepancies are reported, never adopted.
const std = @import("std");
const alpha = @import("alphabet.zig");
const dialect = @import("dialect.zig");
const ast = @import("ast.zig");
const atoms = @import("atoms.zig");
const sys = @import("sys.zig");
const harness = @import("harness.zig");
const finding = @import("finding.zig");
const sample = @import("sample.zig");
const tablemod = @import("table.zig");
const runmod = @import("run.zig");

const Allocator = std.mem.Allocator;
const Flags = alpha.Flags;

/// Out-of-pool case variants and other fragile characters.
const extra_subjects = [_]u21{ 'B', 'z', 'Z', 0xDF, 0x1E9E, 0x130, 0x131, 0x2126, 0x3C9, 0x3A9, 0x3C2, 0x3C3, 0x3A3, '\r', 0x2029, 0x00A0, 0xFEFF, '\t', 0x10400, 0x10428 };

pub const Result = struct {
    cases: u64 = 0,
    mismatches: u64 = 0,
    engine_failures: u64 = 0,
    persisted: u64 = 0,
};

const Probe = struct {
    flags: Flags,
    atom: atoms.AtomSpec,
    /// -1: the atom alone; otherwise the assertion probe [^]{pos}(?:X)[^]*
    pos: i16,
    a: finding.Subject,
    r: finding.Subject,
    exp_a: bool,
    exp_r: bool,
    what: []const u8,
};

fn subjectFrom(cps: []const u21, out: *finding.Subject) void {
    var u: [64]u16 = undefined;
    const n = alpha.toUtf16(cps, &u);
    out.set(u[0..n]);
}

fn subjectUnits(units: []const u16, out: *finding.Subject) void {
    out.set(units);
}

pub const Checker = struct {
    run: *runmod.Run,
    gpa: Allocator,
    probes: std.ArrayList(Probe) = .empty,
    result: Result = .{},
    report: std.ArrayList(u8) = .empty,
    max_persist: u64 = 200,
    /// selfcheck/mismatches.tsv: every mismatch (flags, kind, pattern, A, model, engine).
    tsv: ?c_int = null,

    fn isAscii(s: []const u16) bool {
        for (s) |u| if (u >= 0x80) return false;
        return true;
    }

    fn hasLoneSurrogate(s: []const u16) bool {
        var i: usize = 0;
        while (i < s.len) : (i += 1) {
            const u = s[i];
            if (u >= 0xD800 and u <= 0xDBFF and i + 1 < s.len and s[i + 1] >= 0xDC00 and s[i + 1] <= 0xDFFF) {
                i += 1;
                continue;
            }
            if (u >= 0xD800 and u <= 0xDFFF) return true;
        }
        return false;
    }

    fn addProbe(self: *Checker, flags: Flags, at: atoms.AtomSpec, pos: i16, a: finding.Subject, r: finding.Subject, what: []const u8) !void {
        if (dialect.noLoneSurrogates() and (hasLoneSurrogate(a.slice()) or hasLoneSurrogate(r.slice()))) return;
        if (dialect.active.ascii_only and (!isAscii(a.slice()) or !isAscii(r.slice()))) return;
        var tree: ast.Ast = .{};
        try makeTree(&tree, at, pos);
        const ea = ast.oracle(&tree, flags, a.slice()) orelse return;
        const er = ast.oracle(&tree, flags, r.slice()) orelse return;
        try self.probes.append(self.gpa, .{ .flags = flags, .atom = at, .pos = pos, .a = a, .r = r, .exp_a = ea, .exp_r = er, .what = what });
    }

    /// "Any character": [^] in JS; (?:\s|\S) in Perl, where [^] is not empty-class syntax.
    fn anyNode(t: *ast.Ast) !u8 {
        if (dialect.active.any_char == .empty_negated_class) return t.add(.{ .op = .atom, .atom = .{ .kind = .cls, .neg = true, .n = 0 } });
        const s = try t.add(.{ .op = .atom, .atom = .{ .kind = .esc, .sub = @intFromEnum(atoms.Esc.s) } });
        const S = try t.add(.{ .op = .atom, .atom = .{ .kind = .esc, .sub = @intFromEnum(atoms.Esc.S) } });
        const alt = try t.add(.{ .op = .alt, .a = s, .b = S });
        return t.add(.{ .op = .group_nc, .a = alt });
    }

    fn makeTree(t: *ast.Ast, at: atoms.AtomSpec, pos: i16) !void {
        t.len = 0;
        if (pos < 0) {
            t.root = try t.add(.{ .op = .atom, .atom = at });
            return;
        }
        const i: u8 = @intCast(pos);
        const x = try t.add(.{ .op = .atom, .atom = at });
        // No `{0}` prefix at position 0 (nim-regex NIM-6 treats {0} as {1}).
        const c1 = if (i == 0) x else blk: {
            const lead_atom = try anyNode(t);
            const lead = try t.add(.{ .op = .quant, .quant = .{ .form = .exact, .min = i, .max = i }, .a = lead_atom });
            break :blk try t.add(.{ .op = .concat, .a = lead, .b = x });
        };
        const tail_atom = try anyNode(t);
        const tail = try t.add(.{ .op = .quant, .quant = .{ .form = .star, .min = 0, .max = ast.inf }, .a = tail_atom });
        t.root = try t.add(.{ .op = .concat, .a = c1, .b = tail });
    }

    pub fn buildProbes(self: *Checker, flags: Flags) !void {
        // Every pool (pool rotation): its atoms and its characters.
        for (0..@max(1, self.run.n_pools)) |pi| try self.buildProbesPool(flags, @intCast(pi));
    }

    fn buildProbesPool(self: *Checker, flags: Flags, pool_idx: u8) !void {
        const g = try self.run.grammarVariant(flags, pool_idx, @import("ast.zig").fmod_i);
        var symbuf: [alpha.max_symbols * 2]u21 = undefined;
        const pool = alpha.poolSymbols(self.run.poolAt(pool_idx), flags, &symbuf);
        var subjects: std.ArrayList(finding.Subject) = .empty;
        defer subjects.deinit(self.gpa);
        for (pool) |s| {
            var x: finding.Subject = .{};
            if (alpha.isSurrogate(s)) subjectUnits(&.{@intCast(s)}, &x) else subjectFrom(&.{s}, &x);
            try subjects.append(self.gpa, x);
        }
        for (extra_subjects) |s| {
            if (s > 0xFFFF and !flags.unicode()) continue; // two positions; covered by halves
            var x: finding.Subject = .{};
            subjectFrom(&.{s}, &x);
            try subjects.append(self.gpa, x);
        }
        // Lone surrogates as their own symbols (u/v); halves of the astral char.
        // (Not representable in Perl strings decoded from JSON.)
        if (!dialect.noLoneSurrogates()) for ([_]u16{ 0xD83D, 0xDE00 }) |h| {
            var x: finding.Subject = .{};
            subjectUnits(&.{h}, &x);
            try subjects.append(self.gpa, x);
        };
        const empty: finding.Subject = .{};

        // Consuming atoms against every subject; R is the empty string.
        for (g.atoms) |at| {
            if (!at.isConsuming()) continue;
            for (subjects.items) |s| try self.addProbe(flags, at, -1, s, empty, "atom");
            if (at.kind == .lit) {
                // Wrapper checks: multi-symbol and multiline subjects must not fully match one literal.
                var two: finding.Subject = .{};
                var u: [8]u16 = undefined;
                var cps = [_]u21{ at.syms[0], at.syms[0] };
                var n: usize = 0;
                if (alpha.isSurrogate(at.syms[0])) {
                    u[0] = @intCast(at.syms[0]);
                    u[1] = @intCast(at.syms[0]);
                    n = 2;
                } else n = alpha.toUtf16(&cps, &u);
                two.set(u[0..n]);
                var ml: finding.Subject = .{};
                subjectFrom(&.{ '\n', 'a' }, &ml);
                try self.addProbe(flags, at, -1, two, ml, "literal-wrapper");
            }
        }

        // Assertions at each position: [^]{i}(?:X)[^]* on whole strings.
        var strings: std.ArrayList(finding.Subject) = .empty;
        defer strings.deinit(self.gpa);
        try strings.append(self.gpa, empty);
        for (pool) |x| {
            for (pool) |y| {
                var s: finding.Subject = .{};
                var u: [8]u16 = undefined;
                var n: usize = 0;
                for ([_]u21{ x, y }) |c| {
                    if (c > 0xFFFF) {
                        n += alpha.toUtf16(&.{c}, u[n..]);
                    } else {
                        u[n] = @intCast(c);
                        n += 1;
                    }
                }
                s.set(u[0..n]);
                try strings.append(self.gpa, s);
            }
            var s1: finding.Subject = .{};
            if (x > 0xFFFF) subjectFrom(&.{x}, &s1) else subjectUnits(&.{@intCast(x)}, &s1);
            try strings.append(self.gpa, s1);
        }
        for ([_][]const u21{ &.{ 'a', '\n', 'b' }, &.{ '\n', '\n' }, &.{ 'a', ' ', 'b' }, &.{ 0x17F, 'K', 0x212A }, &.{ '_', 0x2028, '_' }, &.{ '\r', '\n' }, &.{ 'k', 0x2029, 's', 0x17F } }) |cps| {
            var s: finding.Subject = .{};
            subjectFrom(cps, &s);
            try strings.append(self.gpa, s);
        }
        for ([_]atoms.Kind{ .caret, .dollar, .wordb, .nwordb }) |kd| {
            if (!dialect.active.assertions.allows(kd)) continue;
            for (strings.items) |s| {
                var syms: [64]u21 = undefined;
                const n = alpha.decode(s.slice(), flags, &syms) orelse continue;
                for (0..n + 1) |i| try self.addProbe(flags, .{ .kind = kd }, @intCast(i), s, empty, "assertion");
            }
        }
    }

    fn runOn(self: *Checker, spec: *const harness.ModeSpec, exe: []const u8) !void {
        const run = self.run;
        const c = try harness.Child.create(self.gpa, spec, .{ .exe = exe, .driver_path = run.driver_path, .journal_path = null, .cfg = &run.cfg });
        defer c.destroy();
        try c.start();
        var req: std.ArrayList(u8) = .empty;
        defer req.deinit(self.gpa);
        var pats: std.ArrayList(u8) = .empty;
        defer pats.deinit(self.gpa);
        const bits = try self.gpa.alloc(u8, run.cfg.batch_size);
        defer self.gpa.free(bits);
        var mism: u64 = 0;
        var i: usize = 0;
        var seq: u64 = 0;
        while (i < self.probes.items.len) {
            const end = @min(self.probes.items.len, i + run.cfg.batch_size);
            req.clearRetainingCapacity();
            seq += 1;
            try req.print(self.gpa, "[{d},[", .{seq});
            var tree: ast.Ast = .{};
            for (self.probes.items[i..end], 0..) |*p, j| {
                pats.clearRetainingCapacity();
                try makeTree(&tree, p.atom, p.pos);
                try sample.printAlloc(self.gpa, &tree, p.flags, &pats);
                if (j > 0) try req.append(self.gpa, ',');
                try harness.encodeCase(&req, self.gpa, .{ .flags = finding.flagStr(p.flags), .a = p.a.slice(), .r = p.r.slice(), .pattern = pats.items });
            }
            try req.appendSlice(self.gpa, "]]\n");
            if (!c.alive) try c.start();
            var b: harness.Batch = .{ .seq = seq, .ncases = @intCast(end - i), .req = req.items, .bits = bits[0 .. end - i] };
            if (harness.runSync(c, &b) != .answered) {
                self.result.engine_failures += 1;
                try self.report.print(self.gpa, "engine {s}: batch {d} failed: {s}\n", .{ spec.name, seq, c.message() });
                if (self.result.engine_failures <= 3) {
                    const tail = try c.err.copyOut(self.gpa);
                    defer self.gpa.free(tail);
                    try self.report.print(self.gpa, "  stderr tail: {s}\n", .{tail[tail.len -| 600..]});
                }
                i = end;
                continue;
            }
            for (self.probes.items[i..end], 0..) |*p, j| {
                self.result.cases += 1;
                const want = finding.expectedBits(.normal, p.exp_a, p.exp_r);
                const got = b.bits[j];
                if (got == want) continue;
                mism += 1;
                self.result.mismatches += 1;
                pats.clearRetainingCapacity();
                try makeTree(&tree, p.atom, p.pos);
                try sample.printAlloc(self.gpa, &tree, p.flags, &pats);
                if (self.tsv) |tf| {
                    var row: std.ArrayList(u8) = .empty;
                    defer row.deinit(self.gpa);
                    try row.print(self.gpa, "{s}\t{s}\t", .{ finding.flagStr(p.flags), p.what });
                    try harness.jsonAscii(&row, self.gpa, pats.items);
                    try row.append(self.gpa, '\t');
                    try harness.jsonString(&row, self.gpa, p.a.slice());
                    try row.print(self.gpa, "\t{x:0>2}\t{x:0>2}\n", .{ want, got });
                    sys.appendFile(tf, row.items) catch {};
                }
                if (mism <= 50) {
                    try self.report.print(self.gpa, "MISMATCH engine={s} flags=\"{s}\" kind={s} pattern=", .{ spec.name, finding.flagStr(p.flags), p.what });
                    try harness.jsonAscii(&self.report, self.gpa, pats.items);
                    try self.report.appendSlice(self.gpa, " A=");
                    try harness.jsonString(&self.report, self.gpa, p.a.slice());
                    try self.report.appendSlice(self.gpa, " R=");
                    try harness.jsonString(&self.report, self.gpa, p.r.slice());
                    try self.report.print(self.gpa, " model={x:0>2} engine={x:0>2}\n", .{ want, got });
                }
                if (self.result.persisted < self.max_persist) {
                    var cs: finding.Case = .{ .flags = p.flags, .a = p.a, .r = p.r, .tree = tree, .exp_a = p.exp_a, .exp_r = p.exp_r, .selfcheck = true };
                    try cs.pattern.appendSlice(self.gpa, pats.items);
                    defer cs.pattern.deinit(self.gpa);
                    const kind: finding.Kind = if (got & harness.Bits.syntax != 0) .syntax_error else .selfcheck_mismatch;
                    _ = try run.store.persist(&cs, .{ .kind = kind, .mode = spec.name, .observed = got, .expected = want, .diff = got ^ want }, run.build_id, "selfcheck", spec, exe, null, null);
                    self.result.persisted += 1;
                }
            }
            i = end;
        }
        c.shutdown(1000);
        try self.report.print(self.gpa, "engine {s}: {d} probes, {d} mismatches\n", .{ spec.name, self.probes.items.len, mism });
    }

    /// Build probes for every configured flag set and run them on interp and
    /// any independent engines.
    pub fn runAll(self: *Checker, engines: []const struct { spec: *const harness.ModeSpec, exe: []const u8 }) !Result {
        var tp: [4096]u8 = undefined;
        self.tsv = sys.openAppend(try std.fmt.bufPrint(&tp, "{s}/selfcheck/mismatches.tsv", .{self.run.out_dir})) catch null;
        defer if (self.tsv) |tf| {
            _ = sys.close(tf);
        };
        for (self.run.cfg.flagSets()) |f| try self.buildProbes(f);
        try self.report.print(self.gpa, "selfcheck: {d} probes over {d} flag sets\n", .{ self.probes.items.len, self.run.cfg.n_flag_sets });
        for (engines) |e| try self.runOn(e.spec, e.exe);
        var pb: [4096]u8 = undefined;
        try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/selfcheck/report.txt", .{self.run.out_dir}), self.report.items);
        return self.result;
    }

    pub fn deinit(self: *Checker) void {
        self.probes.deinit(self.gpa);
        self.report.deinit(self.gpa);
    }
};
