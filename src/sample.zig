//! Weighted sampling of trees from a finalized table, and the mode-aware
//! regex printer.
const std = @import("std");
const alpha = @import("alphabet.zig");
const atoms = @import("atoms.zig");
const ast = @import("ast.zig");
const tablemod = @import("table.zig");
const rngmod = @import("rng.zig");

const Flags = alpha.Flags;
const Table = tablemod.Table;
const Op = ast.Op;
const AtomSpec = atoms.AtomSpec;
const Allocator = std.mem.Allocator;

// ---------------------------------------------------------------------------
// Sampler

/// Per-lane scratch, sized for the largest production list of a table.
pub const Scratch = struct {
    cap: usize = 0,
    w: []f64 = &.{},
    prob: []f32 = &.{},
    alias: []u32 = &.{},
    items: []u32 = &.{},
    small: []u32 = &.{},
    large: []u32 = &.{},
    split: []f64 = &.{},

    pub fn ensure(self: *Scratch, gpa: Allocator, n: usize, max_size: usize) !void {
        if (n <= self.cap and self.split.len >= max_size + 1) return;
        self.deinit(gpa);
        const c = @max(n, 1);
        self.w = try gpa.alloc(f64, c);
        self.prob = try gpa.alloc(f32, c);
        self.alias = try gpa.alloc(u32, c);
        self.items = try gpa.alloc(u32, c);
        self.small = try gpa.alloc(u32, c);
        self.large = try gpa.alloc(u32, c);
        self.split = try gpa.alloc(f64, max_size + 1);
        self.cap = c;
    }

    pub fn bytesFor(n: usize, max_size: usize) u64 {
        return @as(u64, @max(n, 1)) * (8 + 4 + 4 + 4 + 4 + 4) + (max_size + 1) * 8 + 7 * 16;
    }

    pub fn deinit(self: *Scratch, gpa: Allocator) void {
        if (self.cap == 0) return;
        gpa.free(self.w);
        gpa.free(self.prob);
        gpa.free(self.alias);
        gpa.free(self.items);
        gpa.free(self.small);
        gpa.free(self.large);
        gpa.free(self.split);
        self.* = .{};
    }
};

pub const SampleError = error{ TooManyNodes, ModelFailure };

pub const Sampler = struct {
    tab: *Table,
    scratch: *Scratch,
    rng: *rngmod.Rng,
    out: *ast.Ast,

    pub fn sample(self: *Sampler) SampleError!usize {
        const k = self.tab.size_alias.draw(self.rng);
        const sa = &self.tab.start_alias[k];
        if (sa.items.len == 0) return error.ModelFailure;
        const x = sa.draw(self.rng);
        self.out.len = 0;
        self.out.root = try self.expand(x, k);
        return k;
    }

    fn drawProd(self: *Sampler, x: u32, k: usize) SampleError!u32 {
        const tab = self.tab;
        const ci = tab.countIndex(x, k) orelse return error.ModelFailure;
        if (tab.cache_enabled) {
            const v = tab.slots[ci].load(.acquire);
            if (v != 0) {
                _ = tab.cache_hits.fetchAdd(1, .monotonic);
                const base = v - 1;
                const n = tab.arena[base];
                const items = tab.arena[base + 1 .. base + 1 + n];
                const prob: []const f32 = @ptrCast(tab.arena[base + 1 + n .. base + 1 + 2 * n]);
                const al = tab.arena[base + 1 + 2 * n .. base + 1 + 3 * n];
                return items[tablemod.drawAlias(self.rng, prob, al)];
            }
        }
        // Build the alias table for (x, k) in scratch.
        const s = self.scratch;
        var n: usize = 0;
        var mx = -std.math.inf(f64);
        for (tab.pstart[x]..tab.pstart[x + 1]) |pi| {
            const t = tab.prodTerm(tab.prods[pi], k, tab.plw[pi]);
            if (t == -std.math.inf(f64)) continue;
            s.items[n] = @intCast(pi);
            s.w[n] = t;
            mx = @max(mx, t);
            n += 1;
        }
        if (n == 0) return error.ModelFailure;
        for (s.w[0..n]) |*w| w.* = @exp(w.* - mx);
        tablemod.buildAlias(s.w[0..n], s.prob[0..n], s.alias[0..n], s.small[0..n], s.large[0..n]);
        _ = tab.cache_builds.fetchAdd(1, .monotonic);
        if (tab.cache_enabled) self.publish(ci, n) else _ = tab.uncached.fetchAdd(1, .monotonic);
        return s.items[tablemod.drawAlias(self.rng, s.prob[0..n], s.alias[0..n])];
    }

    /// Copy the scratch alias table into the shared arena and publish its slot.
    fn publish(self: *Sampler, ci: u32, n: usize) void {
        const tab = self.tab;
        const need: u64 = 1 + 3 * @as(u64, n);
        var cur = tab.arena_top.load(.monotonic);
        while (true) {
            if (cur + need > tab.arena.len) {
                _ = tab.uncached.fetchAdd(1, .monotonic);
                return;
            }
            cur = tab.arena_top.cmpxchgWeak(cur, cur + need, .monotonic, .monotonic) orelse break;
        }
        const base: usize = @intCast(cur);
        const s = self.scratch;
        tab.arena[base] = @intCast(n);
        @memcpy(tab.arena[base + 1 .. base + 1 + n], s.items[0..n]);
        @memcpy(tab.arena[base + 1 + n .. base + 1 + 2 * n], @as([]const u32, @ptrCast(s.prob[0..n])));
        @memcpy(tab.arena[base + 1 + 2 * n .. base + 1 + 3 * n], s.alias[0..n]);
        if (tab.slots[ci].cmpxchgStrong(0, @intCast(base + 1), .release, .monotonic) != null) {
            _ = tab.wasted.fetchAdd(need, .monotonic);
        }
    }

    fn expand(self: *Sampler, x: u32, k: usize) SampleError!u8 {
        const tab = self.tab;
        const pi = try self.drawProd(x, k);
        const p = tab.prods[pi];
        const op: Op = @enumFromInt(p.op);
        const g = tab.grammar;
        switch (op) {
            .atom => return self.out.add(.{ .op = .atom, .atom = g.atoms[p.arg] }),
            .concat, .alt => {
                const k1 = try self.drawSplit(p.a, p.b, k);
                const a = try self.expand(p.a, k1);
                const b = try self.expand(p.b, k - 1 - k1);
                return self.out.add(.{ .op = op, .a = a, .b = b });
            },
            .quant => {
                const a = try self.expand(p.a, k - 1);
                return self.out.add(.{ .op = .quant, .quant = g.quants[p.arg], .a = a });
            },
            else => {
                const a = try self.expand(p.a, k - 1);
                return self.out.add(.{ .op = op, .a = a });
            },
        }
    }

    /// Inversion over split terms W(Y, k1)·W(Z, k−1−k1), computed in log space.
    fn drawSplit(self: *Sampler, y: u32, z: u32, k: usize) SampleError!usize {
        const tab = self.tab;
        const my = tab.ms[y];
        const mz = tab.ms[z];
        const sp = self.scratch.split;
        var mx = -std.math.inf(f64);
        var k1: usize = my;
        while (k1 + mz + 1 <= k) : (k1 += 1) {
            sp[k1] = tab.logW(y, k1) + tab.logW(z, k - 1 - k1);
            mx = @max(mx, sp[k1]);
        }
        if (mx == -std.math.inf(f64)) return error.ModelFailure;
        var total: f64 = 0;
        k1 = my;
        while (k1 + mz + 1 <= k) : (k1 += 1) {
            sp[k1] = @exp(sp[k1] - mx);
            total += sp[k1];
        }
        var u = self.rng.float() * total;
        k1 = my;
        var last: usize = my;
        while (k1 + mz + 1 <= k) : (k1 += 1) {
            if (sp[k1] > 0) last = k1;
            if (u < sp[k1]) return k1;
            u -= sp[k1];
        }
        return last;
    }
};

// ---------------------------------------------------------------------------
// Printer

pub const PrintError = error{ OutOfMemory, PatternTooLong };

const Prec = enum(u8) { alt = 0, concat = 1, quant_body = 2 };

pub const Printer = struct {
    flags: Flags,
    out: *std.ArrayList(u8),
    gpa: Allocator,
    group_counter: u32 = 0,
    limit: usize = std.math.maxInt(usize),

    fn put(self: *Printer, s: []const u8) PrintError!void {
        if (self.out.items.len + s.len > self.limit) return error.PatternTooLong;
        try self.out.appendSlice(self.gpa, s);
    }
    fn putc(self: *Printer, c: u8) PrintError!void {
        if (self.out.items.len + 1 > self.limit) return error.PatternTooLong;
        try self.out.append(self.gpa, c);
    }
    fn fmt(self: *Printer, comptime f: []const u8, args: anytype) PrintError!void {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, f, args) catch unreachable;
        try self.put(s);
    }

    pub fn print(self: *Printer, t: *const ast.Ast) PrintError!void {
        try self.node(t, t.root, .alt);
    }

    fn isQuantAtom(t: *const ast.Ast, idx: u8) bool {
        const n = t.nodes[idx];
        return switch (n.op) {
            .atom => n.atom.isConsuming() or n.atom.kind == .empty,
            .group_cap, .group_nc, .group_named => true,
            else => false,
        };
    }

    fn node(self: *Printer, t: *const ast.Ast, idx: u8, prec: Prec) PrintError!void {
        const n = t.nodes[idx];
        switch (n.op) {
            .atom => {
                // Assertions as quantifier bodies are wrapped by the caller.
                try self.atom(&n.atom);
            },
            .alt => {
                const wrap = @intFromEnum(prec) > @intFromEnum(Prec.alt);
                if (wrap) try self.put("(?:");
                try self.node(t, n.a, .alt);
                try self.putc('|');
                try self.node(t, n.b, .alt);
                if (wrap) try self.putc(')');
            },
            .concat => {
                const wrap = @intFromEnum(prec) > @intFromEnum(Prec.concat);
                if (wrap) try self.put("(?:");
                try self.node(t, n.a, .concat);
                try self.node(t, n.b, .concat);
                if (wrap) try self.putc(')');
            },
            .quant => {
                const wrap = prec == .quant_body;
                if (wrap) try self.put("(?:");
                if (isQuantAtom(t, n.a)) {
                    try self.node(t, n.a, .quant_body);
                } else {
                    try self.put("(?:");
                    try self.node(t, n.a, .alt);
                    try self.putc(')');
                }
                const q = n.quant;
                switch (q.form) {
                    .star => try self.putc('*'),
                    .plus => try self.putc('+'),
                    .opt => try self.putc('?'),
                    .range => try self.fmt("{{{d},{d}}}", .{ q.min, q.max }),
                    .open => try self.fmt("{{{d},}}", .{q.min}),
                    .exact => try self.fmt("{{{d}}}", .{q.min}),
                }
                if (q.lazy) try self.putc('?');
                if (wrap) try self.putc(')');
            },
            .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind => {
                const wrap = prec == .quant_body;
                if (wrap) try self.put("(?:");
                try self.put(switch (n.op) {
                    .look_ahead => "(?=",
                    .neg_look_ahead => "(?!",
                    .look_behind => "(?<=",
                    else => "(?<!",
                });
                try self.node(t, n.a, .alt);
                try self.putc(')');
                if (wrap) try self.putc(')');
            },
            .group_cap => {
                try self.putc('(');
                try self.node(t, n.a, .alt);
                try self.putc(')');
            },
            .group_nc => {
                try self.put("(?:");
                try self.node(t, n.a, .alt);
                try self.putc(')');
            },
            .group_named => {
                try self.fmt("(?<g{d}>", .{self.group_counter});
                self.group_counter += 1;
                try self.node(t, n.a, .alt);
                try self.putc(')');
            },
        }
    }

    fn escapedCodePoint(self: *Printer, c: u21) PrintError!void {
        if (self.flags.unicode()) {
            try self.fmt("\\u{{{X}}}", .{c});
        } else {
            std.debug.assert(c <= 0xFFFF);
            try self.fmt("\\u{X:0>4}", .{c});
        }
    }

    fn isPrintableAscii(c: u21) bool {
        return c >= 0x20 and c <= 0x7E;
    }

    /// Literal outside classes.
    pub fn literal(self: *Printer, c: u21) PrintError!void {
        if (!isPrintableAscii(c)) return self.escapedCodePoint(c);
        const b: u8 = @intCast(c);
        if (std.mem.indexOfScalar(u8, "^$\\.*+?()[]{}|/", b) != null) try self.putc('\\');
        try self.putc(b);
    }

    /// Literal inside a class, per mode.
    pub fn classLiteral(self: *Printer, c: u21) PrintError!void {
        if (!isPrintableAscii(c)) return self.escapedCodePoint(c);
        const b: u8 = @intCast(c);
        const needs = if (self.flags.v)
            // ClassSetSyntaxCharacter, ClassSetReservedPunctuator, and the remaining
            // SyntaxCharacters: escaping all of them is valid and avoids doubled punctuators.
            std.mem.indexOfScalar(u8, "()[]{}/-\\|&!#%,:;<=>@`~^$.*+?", b) != null
        else
            std.mem.indexOfScalar(u8, "\\]-^", b) != null;
        if (needs) try self.putc('\\');
        try self.putc(b);
    }

    fn escName(e: atoms.Esc) []const u8 {
        return switch (e) {
            .d => "\\d",
            .D => "\\D",
            .w => "\\w",
            .W => "\\W",
            .s => "\\s",
            .S => "\\S",
        };
    }

    fn operand(self: *Printer, o: *const atoms.Operand) PrintError!void {
        switch (o.kind) {
            .esc => try self.put(escName(o.esc)),
            .range => {
                try self.putc('[');
                try self.classLiteral(o.syms[0]);
                try self.putc('-');
                try self.classLiteral(o.syms[1]);
                try self.putc(']');
            },
            .char => try self.classLiteral(o.syms[0]),
            .list, .neglist => {
                try self.putc('[');
                if (o.kind == .neglist) try self.putc('^');
                for (o.syms[0..o.n]) |c| try self.classLiteral(c);
                try self.putc(']');
            },
        }
    }

    pub fn atom(self: *Printer, a: *const AtomSpec) PrintError!void {
        switch (a.kind) {
            .lit => try self.literal(a.syms[0]),
            .dot => try self.putc('.'),
            .esc => try self.put(escName(@enumFromInt(a.sub))),
            .range => {
                try self.putc('[');
                if (a.neg) try self.putc('^');
                try self.classLiteral(a.syms[0]);
                try self.putc('-');
                try self.classLiteral(a.syms[1]);
                try self.putc(']');
            },
            .cls => {
                try self.putc('[');
                if (a.neg) try self.putc('^');
                for (a.syms[0..a.n]) |c| try self.classLiteral(c);
                try self.putc(']');
            },
            .vset => {
                try self.putc('[');
                if (a.neg) try self.putc('^');
                try self.operand(&atoms.v_operands[a.syms[0]]);
                switch (@as(atoms.VOp, @enumFromInt(a.sub))) {
                    .sub => try self.put("--"),
                    .inter => try self.put("&&"),
                    .uni => {},
                }
                try self.operand(&atoms.v_operands[a.syms[1]]);
                try self.putc(']');
            },
            .caret => try self.putc('^'),
            .dollar => try self.putc('$'),
            .wordb => try self.put("\\b"),
            .nwordb => try self.put("\\B"),
            .empty => try self.put("(?:)"),
        }
    }
};

pub fn printAlloc(gpa: Allocator, t: *const ast.Ast, flags: Flags, out: *std.ArrayList(u8)) PrintError!void {
    var p: Printer = .{ .flags = flags, .out = out, .gpa = gpa };
    try p.print(t);
}

/// Conservative printed-length bound for any tree of `max_size` nodes in a
/// grammar: every node is charged the longest atom plus the longest wrapper.
pub fn printedLengthBound(gpa: Allocator, g: *const tablemod.Grammar, max_size: usize) !u64 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    var max_atom: usize = 0;
    for (g.atoms) |*a| {
        buf.clearRetainingCapacity();
        var p: Printer = .{ .flags = g.flags, .out = &buf, .gpa = gpa };
        try p.atom(a);
        max_atom = @max(max_atom, buf.items.len);
    }
    // Wrappers: quant "(?:(?:" + ")" + "{255,255}?" + ")" ; named group "(?<g4294967295>" + ")";
    // lookaround "(?:(?<!" + "))"; alternation "(?:" + "|" + ")".
    const per_node: u64 = @max(@as(u64, 6 + 1 + 10 + 1), @max(@as(u64, 15 + 1), @as(u64, 7 + 2)));
    return @as(u64, max_size) * (@as(u64, max_atom) + per_node + 4);
}

// ---------------------------------------------------------------------------
// Tests

const testing = std.testing;
const ucd = @import("ucd.zig");
const config = @import("config.zig");
const Budget = @import("budget.zig").Budget;

fn lit(c: u21) ast.Node {
    return .{ .op = .atom, .atom = .{ .kind = .lit, .syms = .{ c, 0, 0, 0 } } };
}

test "printer precedence and wrapping" {
    ucd.init();
    const gpa = testing.allocator;
    var t: ast.Ast = .{};
    const a = try t.add(lit('a'));
    const b = try t.add(lit('b'));
    const alt = try t.add(.{ .op = .alt, .a = a, .b = b });
    const q = try t.add(.{ .op = .quant, .quant = .{ .form = .plus, .min = 1, .max = ast.inf }, .a = alt });
    const q2 = try t.add(.{ .op = .quant, .quant = .{ .form = .opt, .min = 0, .max = 1, .lazy = true }, .a = q });
    const caret = try t.add(.{ .op = .atom, .atom = .{ .kind = .caret } });
    const q3 = try t.add(.{ .op = .quant, .quant = .{ .form = .range, .min = 0, .max = 2 }, .a = caret });
    const la = try t.add(.{ .op = .look_ahead, .a = a });
    const q4 = try t.add(.{ .op = .quant, .quant = .{ .form = .star, .min = 0, .max = ast.inf }, .a = la });
    const c1 = try t.add(.{ .op = .concat, .a = q2, .b = q3 });
    const c2 = try t.add(.{ .op = .concat, .a = c1, .b = q4 });
    const alt2 = try t.add(.{ .op = .alt, .a = c2, .b = b });
    t.root = try t.add(.{ .op = .concat, .a = alt2, .b = a });
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try printAlloc(gpa, &t, .{}, &out);
    try testing.expectEqualStrings("(?:(?:(?:a|b)+)??(?:^){0,2}(?:(?=a))*|b)a", out.items);
}

test "literal escaping per mode" {
    ucd.init();
    const gpa = testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    var p: Printer = .{ .flags = .{}, .out = &out, .gpa = gpa };
    for ([_]u21{ '.', '\n', 0x212A, 0xD83D, 0xDE00, ' ', '/' }) |c| try p.literal(c);
    try testing.expectEqualStrings("\\.\\u000A\\u212A\\uD83D\\uDE00 \\/", out.items);
    out.clearRetainingCapacity();
    p.flags = .{ .u = true };
    for ([_]u21{ alpha.astral_char, 0xD83D, '\n' }) |c| try p.literal(c);
    try testing.expectEqualStrings("\\u{1F600}\\u{D83D}\\u{A}", out.items);
    out.clearRetainingCapacity();
    p.flags = .{ .v = true };
    const vs: AtomSpec = .{ .kind = .vset, .sub = @intFromEnum(atoms.VOp.sub), .neg = true, .syms = .{ 0, 15, 0, 0 } };
    try p.atom(&vs);
    try testing.expectEqualStrings("[^\\w--[\\u{1F600}a]]", out.items);
}

const TreeEnum = struct {
    const Entry = struct { text: []const u8, w: f64, start: bool };

    fn enumerate(gpa: Allocator, g: *const tablemod.Grammar, k: usize, a: []const u21, r: []const u21, out: *std.ArrayList(Entry)) !void {
        // enumerate all ASTs of size k and print them
        var trees: std.ArrayList(ast.Ast) = .empty;
        defer trees.deinit(gpa);
        var weights: std.ArrayList(f64) = .empty;
        defer weights.deinit(gpa);
        try gen(gpa, g, k, &trees, &weights);
        for (trees.items, weights.items) |*t, w| {
            var buf: std.ArrayList(u8) = .empty;
            try printAlloc(gpa, t, g.flags, &buf);
            const ra = ast.evalRel(@import("rel.zig").Rel16, t, t.root, g.flags, a);
            const rr = ast.evalRel(@import("rel.zig").Rel16, t, t.root, g.flags, r);
            try out.append(gpa, .{ .text = buf.items, .w = w, .start = ra.get(0, a.len) and !rr.get(0, r.len) });
        }
    }

    fn gen(gpa: Allocator, g: *const tablemod.Grammar, k: usize, trees: *std.ArrayList(ast.Ast), weights: *std.ArrayList(f64)) !void {
        if (k == 1) {
            for (g.atoms, 0..) |a, i| {
                if (g.atom_w[i] <= 0) continue;
                var t: ast.Ast = .{};
                t.root = try t.add(.{ .op = .atom, .atom = a });
                try trees.append(gpa, t);
                try weights.append(gpa, g.atom_w[i]);
            }
            return;
        }
        var sub: std.ArrayList(ast.Ast) = .empty;
        defer sub.deinit(gpa);
        var subw: std.ArrayList(f64) = .empty;
        defer subw.deinit(gpa);
        try gen(gpa, g, k - 1, &sub, &subw);
        for (sub.items, subw.items) |*s, w| for (g.unary) |u| {
            var t = s.*;
            if (u.op == .quant) {
                t.root = try t.add(.{ .op = .quant, .quant = g.quants[u.arg], .a = s.root });
            } else t.root = try t.add(.{ .op = u.op, .a = s.root });
            try trees.append(gpa, t);
            try weights.append(gpa, w * u.w);
        };
        for (1..k - 1) |k1| {
            var ys: std.ArrayList(ast.Ast) = .empty;
            defer ys.deinit(gpa);
            var yw: std.ArrayList(f64) = .empty;
            defer yw.deinit(gpa);
            var zs: std.ArrayList(ast.Ast) = .empty;
            defer zs.deinit(gpa);
            var zw: std.ArrayList(f64) = .empty;
            defer zw.deinit(gpa);
            try gen(gpa, g, k1, &ys, &yw);
            try gen(gpa, g, k - 1 - k1, &zs, &zw);
            for (ys.items, yw.items) |*y, wy| for (zs.items, zw.items) |*z, wz| for (g.binary) |b| {
                var t: ast.Ast = .{};
                const ya = try copySub(&t, y, y.root);
                const za = try copySub(&t, z, z.root);
                t.root = try t.add(.{ .op = b.op, .a = ya, .b = za });
                try trees.append(gpa, t);
                try weights.append(gpa, wy * wz * b.w);
            };
        }
    }

    fn copySub(dst: *ast.Ast, src: *const ast.Ast, idx: u8) !u8 {
        var n = src.nodes[idx];
        switch (n.op) {
            .atom => {},
            .concat, .alt => {
                n.a = try copySub(dst, src, n.a);
                n.b = try copySub(dst, src, n.b);
            },
            else => n.a = try copySub(dst, src, n.a),
        }
        return dst.add(n);
    }
};

test "sampling frequencies match exact tree probabilities" {
    ucd.init();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var cfg: config.Config = .{};
    cfg.max_size = 4;
    @memset(&cfg.size_weights, 0);
    cfg.size_weights[4] = 1;
    cfg.allow_diagonal_lookarounds = true;
    for ([_]bool{ false, true }) |cache| {
        cfg.alias_cache = cache;
        // small explicit grammar with skewed weights
        var atomsl = [_]AtomSpec{
            .{ .kind = .lit, .syms = .{ 'a', 0, 0, 0 } },
            .{ .kind = .lit, .syms = .{ 'b', 0, 0, 0 } },
            .{ .kind = .dot },
            .{ .kind = .wordb },
        };
        var aw = [_]f64{ 1.0, 0.3, 2.0, 0.5 };
        var qs = [_]ast.QuantSpec{.{ .form = .star, .min = 0, .max = ast.inf }};
        var un = [_]tablemod.UnaryEntry{ .{ .op = .quant, .arg = 0, .w = 2.0 }, .{ .op = .neg_look_ahead, .arg = 0, .w = 0.7 } };
        var bin = [_]tablemod.BinaryEntry{ .{ .op = .concat, .w = 1.0 }, .{ .op = .alt, .w = 0.25 } };
        var g: tablemod.Grammar = .{ .flags = .{}, .atoms = &atomsl, .atom_w = &aw, .quants = &qs, .unary = &un, .binary = &bin, .allow_diagonal_lookarounds = true, .quant_w = &.{}, .op_w = undefined };
        try g.indexWeights(gpa);
        var host = Budget.init("host", 1 << 30, null);
        const a16 = [_]u16{ 'a', 'b' };
        const r16 = [_]u16{'b'};
        const tab = try tablemod.build(.{ .grammar = &g, .cfg = &cfg, .a16 = &a16, .r16 = &r16, .id = .{ .seq = 0, .attempt = 0, .seed = 5, .flags = .{} }, .host = &host, .host_alloc = testing.allocator });
        defer tab.release();

        var exact: std.ArrayList(TreeEnum.Entry) = .empty;
        try TreeEnum.enumerate(gpa, &g, 4, &.{ 'a', 'b' }, &.{'b'}, &exact);
        var Z: f64 = 0;
        var map = std.StringHashMap(f64).init(gpa);
        for (exact.items) |e| if (e.start) {
            Z += e.w;
            const gop = try map.getOrPut(e.text);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += e.w;
        };
        try testing.expect(Z > 0);

        var scratch: Scratch = .{};
        try scratch.ensure(gpa, tab.max_prods_per_pair, tab.max_size);
        var counts = std.StringHashMap(u32).init(gpa);
        const N: usize = 60_000;
        var rng = rngmod.Rng.fromParts(11, &.{});
        for (0..N) |_| {
            var t: ast.Ast = .{};
            var s: Sampler = .{ .tab = tab, .scratch = &scratch, .rng = &rng, .out = &t };
            const k = try s.sample();
            try testing.expectEqual(@as(usize, 4), k);
            try testing.expect(ast.oracle(&t, .{}, &a16).? and !ast.oracle(&t, .{}, &r16).?);
            var buf: std.ArrayList(u8) = .empty;
            try printAlloc(gpa, &t, .{}, &buf);
            const gop = try counts.getOrPut(buf.items);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += 1;
        }
        // every sampled tree must be a valid start tree; frequencies within 5 sigma
        var it = counts.iterator();
        while (it.next()) |e| try testing.expect(map.contains(e.key_ptr.*));
        var mit = map.iterator();
        var max_z: f64 = 0;
        while (mit.next()) |e| {
            const p = e.value_ptr.* / Z;
            const expected = p * @as(f64, @floatFromInt(N));
            const got: f64 = @floatFromInt(counts.get(e.key_ptr.*) orelse 0);
            const sd = @sqrt(@as(f64, @floatFromInt(N)) * p * (1 - p)) + 1e-9;
            max_z = @max(max_z, @abs(got - expected) / sd);
        }
        try testing.expect(max_z < 5.5);
        if (cache) try testing.expect(tab.cache_hits.load(.monotonic) > 0);
    }
}
