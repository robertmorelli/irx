//! Grammar leaves: literals, classes, escapes, v-mode set expressions and
//! assertions, with their exact ECMAScript (ES2024) semantics per flag set.
//!
//! Consuming atoms follow CharacterSetMatcher: each atom compiles to
//! (CharSet S, invert) by the syntax's own compilation rule, and a symbol c
//! matches iff (∃ s ∈ S: Canonicalize(s) = Canonicalize(c)) XOR invert. Sets
//! are never pre-complemented or pre-folded beyond what the spec does.
const std = @import("std");
const alpha = @import("alphabet.zig");
const relmod = @import("rel.zig");
const Flags = alpha.Flags;
const ucd = @import("ucd.zig");

pub const Kind = enum(u8) { lit, dot, esc, range, cls, vset, caret, dollar, wordb, nwordb, empty };
pub const Esc = enum(u8) { d, D, w, W, s, S };
pub const VOp = enum(u8) { sub, inter, uni };

/// Value-typed atom description. Owned ASTs embed these, so a finding never
/// refers back to a table's inventory.
pub const AtomSpec = struct {
    kind: Kind,
    /// Esc for .esc, VOp for .vset.
    sub: u8 = 0,
    /// Negated class spelling `[^…]`.
    neg: bool = false,
    /// Number of used syms for .cls.
    n: u8 = 0,
    /// lit: syms[0]; range: syms[0..2]; cls: syms[0..n]; vset: operand ids syms[0], syms[1].
    syms: [4]u21 = .{ 0, 0, 0, 0 },

    pub fn isAssertion(a: AtomSpec) bool {
        return switch (a.kind) {
            .caret, .dollar, .wordb, .nwordb => true,
            else => false,
        };
    }
    pub fn isConsuming(a: AtomSpec) bool {
        return switch (a.kind) {
            .lit, .dot, .esc, .range, .cls, .vset => true,
            else => false,
        };
    }
    pub fn eql(a: AtomSpec, b: AtomSpec) bool {
        return a.kind == b.kind and a.sub == b.sub and a.neg == b.neg and a.n == b.n and std.mem.eql(u21, &a.syms, &b.syms);
    }
};

/// Construct categories for weights.
pub const Category = enum(u8) { literal, dot, class, range, escape, vset, caret, dollar, backslash_b, backslash_B, empty };

pub fn category(a: AtomSpec) Category {
    return switch (a.kind) {
        .lit => .literal,
        .dot => .dot,
        .esc => .escape,
        .range => .range,
        .cls => .class,
        .vset => .vset,
        .caret => .caret,
        .dollar => .dollar,
        .wordb => .backslash_b,
        .nwordb => .backslash_B,
        .empty => .empty,
    };
}

// ---------------------------------------------------------------------------
// v-mode set operands (static, so specs that reference them stay owned values)

pub const OperandKind = enum(u8) { esc, range, char, list, neglist };
pub const Operand = struct {
    kind: OperandKind,
    esc: Esc = .d,
    syms: [2]u21 = .{ 0, 0 },
    n: u8 = 0,
};

pub const v_operands = [_]Operand{
    .{ .kind = .esc, .esc = .w },
    .{ .kind = .esc, .esc = .d },
    .{ .kind = .esc, .esc = .s },
    .{ .kind = .esc, .esc = .W },
    .{ .kind = .range, .syms = .{ 'a', 'z' } },
    .{ .kind = .range, .syms = .{ 'A', 'Z' } },
    .{ .kind = .range, .syms = .{ 'a', 'c' } },
    .{ .kind = .char, .syms = .{ 'k', 0 } },
    .{ .kind = .char, .syms = .{ 's', 0 } },
    .{ .kind = .char, .syms = .{ 'K', 0 } },
    .{ .kind = .char, .syms = .{ 'a', 0 } },
    .{ .kind = .char, .syms = .{ 'A', 0 } },
    .{ .kind = .neglist, .syms = .{ 'a', 0 }, .n = 1 },
    .{ .kind = .char, .syms = .{ 0x017F, 0 } },
    .{ .kind = .char, .syms = .{ 0x212A, 0 } },
    .{ .kind = .list, .syms = .{ alpha.astral_char, 'a' }, .n = 2 },
};

pub const explicit_ranges = [_][2]u21{ .{ 'a', 'c' }, .{ 'a', 'z' }, .{ 'A', 'Z' }, .{ '0', '9' }, .{ 'k', 's' } };

// ---------------------------------------------------------------------------
// CharSet expressions

const SetKind = enum { list, range, digit, space, word, dotset, all, comp, fold, uni, inter, diff };
const SetNode = struct {
    kind: SetKind,
    lo: u21 = 0,
    hi: u21 = 0,
    syms: []const u21 = &.{},
    a: ?*const SetNode = null,
    b: ?*const SetNode = null,
};

const SetArena = struct {
    nodes: [32]SetNode = undefined,
    len: usize = 0,
    fn add(self: *SetArena, n: SetNode) *const SetNode {
        self.nodes[self.len] = n;
        self.len += 1;
        return &self.nodes[self.len - 1];
    }
};

fn has(n: *const SetNode, flags: Flags, x: u21) bool {
    return switch (n.kind) {
        .list => std.mem.indexOfScalar(u21, n.syms, x) != null,
        .range => x >= n.lo and x <= n.hi,
        .digit => if (alpha.perl) alpha.perlDigit(x) else alpha.isDigit(x),
        .space => alpha.isSpace(x),
        .word => alpha.isWordChar(x, flags),
        .dotset => alpha.inAllCharacters(x, flags) and (flags.s or !alpha.isLineTerminator(x)),
        .all => alpha.inAllCharacters(x, flags),
        // CharacterComplement(rer, S): AllCharacters(rer) minus S.
        .comp => alpha.inAllCharacters(x, flags) and !has(n.a.?, flags, x),
        // MaybeSimpleCaseFolding: {scf(s) : s ∈ S} under v+i, else S.
        .fold => if (flags.v and flags.i) foldHas(n.a.?, flags, x) else has(n.a.?, flags, x),
        .uni => has(n.a.?, flags, x) or has(n.b.?, flags, x),
        .inter => has(n.a.?, flags, x) and has(n.b.?, flags, x),
        .diff => has(n.a.?, flags, x) and !has(n.b.?, flags, x),
    };
}

const HasCtx = struct { n: *const SetNode, flags: Flags };
fn hasCtx(ctx: HasCtx, s: u21) bool {
    return has(ctx.n, ctx.flags, s);
}

fn foldHas(base: *const SetNode, flags: Flags, x: u21) bool {
    // Folding targets are fixed points of scf; preimage of x is its scf class.
    if (ucd.simpleFold(x) != x) return false;
    return ucd.forEachEquivalent(x, true, HasCtx{ .n = base, .flags = flags }, hasCtx);
}

const Compiled = struct { root: *const SetNode, invert: bool };

fn escSet(ar: *SetArena, e: Esc, flags: Flags) *const SetNode {
    _ = flags;
    return switch (e) {
        .d => ar.add(.{ .kind = .digit }),
        .D => ar.add(.{ .kind = .comp, .a = ar.add(.{ .kind = .digit }) }),
        .s => ar.add(.{ .kind = .space }),
        .S => ar.add(.{ .kind = .comp, .a = ar.add(.{ .kind = .space }) }),
        .w => ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .word }) }),
        .W => ar.add(.{ .kind = .comp, .a = ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .word }) }) }),
    };
}

fn operandSet(ar: *SetArena, op: *const Operand, flags: Flags) *const SetNode {
    return switch (op.kind) {
        .esc => escSet(ar, op.esc, flags),
        .range => ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .range, .lo = op.syms[0], .hi = op.syms[1] }) }),
        .char => ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .list, .syms = op.syms[0..1] }) }),
        .list => ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .list, .syms = op.syms[0..op.n] }) }),
        .neglist => ar.add(.{ .kind = .comp, .a = ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .list, .syms = op.syms[0..op.n] }) }) }),
    };
}

fn compile(spec: *const AtomSpec, flags: Flags, ar: *SetArena) Compiled {
    switch (spec.kind) {
        // Atom :: PatternCharacter / escaped char: singleton, no folding at compile time.
        .lit => return .{ .root = ar.add(.{ .kind = .list, .syms = spec.syms[0..1] }), .invert = false },
        .dot => return .{ .root = ar.add(.{ .kind = .dotset }), .invert = false },
        .esc => return .{ .root = escSet(ar, @enumFromInt(spec.sub), flags), .invert = false },
        .range, .cls => {
            var contents: *const SetNode = if (spec.kind == .range)
                ar.add(.{ .kind = .range, .lo = spec.syms[0], .hi = spec.syms[1] })
            else
                ar.add(.{ .kind = .list, .syms = spec.syms[0..spec.n] });
            if (flags.v) {
                contents = ar.add(.{ .kind = .fold, .a = contents });
                if (spec.neg) return .{ .root = ar.add(.{ .kind = .comp, .a = contents }), .invert = false };
                return .{ .root = contents, .invert = false };
            }
            return .{ .root = contents, .invert = spec.neg };
        },
        .vset => {
            std.debug.assert(flags.v);
            const l = operandSet(ar, &v_operands[spec.syms[0]], flags);
            const r = operandSet(ar, &v_operands[spec.syms[1]], flags);
            const k: SetKind = switch (@as(VOp, @enumFromInt(spec.sub))) {
                .sub => .diff,
                .inter => .inter,
                .uni => .uni,
            };
            var root = ar.add(.{ .kind = k, .a = l, .b = r });
            if (spec.neg) root = ar.add(.{ .kind = .comp, .a = root });
            return .{ .root = root, .invert = false };
        },
        else => unreachable,
    }
}

/// CharacterSetMatcher for one symbol.
pub fn matches(spec: *const AtomSpec, flags: Flags, c: u21) bool {
    var ar: SetArena = .{};
    const cs = compile(spec, flags, &ar);
    const found = alpha.existsEquivalent(c, flags, HasCtx{ .n = cs.root, .flags = flags }, hasCtx);
    return found != cs.invert;
}

fn isWordAt(w: []const u21, i: isize, flags: Flags) bool {
    if (i < 0 or i >= @as(isize, @intCast(w.len))) return false;
    return alpha.isWordChar(w[@intCast(i)], flags);
}

/// Bitmask over positions 0..n where the assertion holds.
pub fn assertionMask(spec: *const AtomSpec, flags: Flags, w: []const u21) u32 {
    var mask: u32 = 0;
    const n = w.len;
    for (0..n + 1) |i| {
        const ok = switch (spec.kind) {
            // Perl: /m ^ never matches after a trailing newline; $ without /m
            // also matches before a final newline.
            .caret => i == 0 or (flags.m and alpha.isLineTerminator(w[i - 1]) and !(alpha.perl and i == n)),
            .dollar => i == n or (flags.m and alpha.isLineTerminator(w[i])) or
                (alpha.perl and !flags.m and i + 1 == n and w[i] == '\n'),
            .wordb, .nwordb => blk: {
                const ii: isize = @intCast(i);
                const b = isWordAt(w, ii - 1, flags) != isWordAt(w, ii, flags);
                break :blk if (spec.kind == .wordb) b else !b;
            },
            else => unreachable,
        };
        if (ok) mask |= @as(u32, 1) << @intCast(i);
    }
    return mask;
}

/// Relation of one atom on string w.
pub fn relation(comptime R: type, spec: *const AtomSpec, flags: Flags, w: []const u21) R {
    const dim = w.len + 1;
    switch (spec.kind) {
        .empty => return R.identity(dim),
        .caret, .dollar, .wordb, .nwordb => return R.diagFromMask(assertionMask(spec, flags, w)),
        else => {
            var r: R = .{};
            for (w, 0..) |c, i| {
                if (matches(spec, flags, c)) r.set(i, i + 1);
            }
            return r;
        },
    }
}

// ---------------------------------------------------------------------------
// Inventory

pub const InventoryConfig = struct {
    pool: []const u21 = &alpha.default_pool,
    class_max_members: u8 = 2,
};

/// Ordered atom inventory for a flag set. Deterministic in (config, flags).
pub fn buildInventory(gpa: std.mem.Allocator, cfg: InventoryConfig, flags: Flags) ![]AtomSpec {
    var out: std.ArrayList(AtomSpec) = .empty;
    errdefer out.deinit(gpa);
    var symbuf: [alpha.max_symbols * 2]u21 = undefined;
    const syms = alpha.poolSymbols(cfg.pool, flags, &symbuf);

    for (syms) |c| try out.append(gpa, .{ .kind = .lit, .syms = .{ c, 0, 0, 0 } });
    try out.append(gpa, .{ .kind = .dot });
    for (std.enums.values(Esc)) |e| try out.append(gpa, .{ .kind = .esc, .sub = @intFromEnum(e) });
    for (explicit_ranges) |rg| try out.append(gpa, .{ .kind = .range, .syms = .{ rg[0], rg[1], 0, 0 } });

    // Enumerated class templates: up to k listed pool members, positive or negated.
    const k = @min(cfg.class_max_members, 4);
    if (k > 32) return error.TooManyMembers;
    for ([_]bool{ false, true }) |neg| {
        var size: u8 = 1;
        while (size <= k) : (size += 1) {
            var idx: [4]usize = undefined;
            for (0..size) |j| idx[j] = j;
            if (size > syms.len) break;
            while (true) {
                var a: AtomSpec = .{ .kind = .cls, .neg = neg, .n = size };
                for (0..size) |j| a.syms[j] = syms[idx[j]];
                try out.append(gpa, a);
                // next combination
                var j: isize = @as(isize, size) - 1;
                while (j >= 0 and idx[@intCast(j)] == syms.len - size + @as(usize, @intCast(j))) j -= 1;
                if (j < 0) break;
                idx[@intCast(j)] += 1;
                var t: usize = @intCast(j + 1);
                while (t < size) : (t += 1) idx[t] = idx[t - 1] + 1;
            }
        }
    }

    if (flags.v) {
        for (std.enums.values(VOp)) |op| {
            for (0..v_operands.len) |l| for (0..v_operands.len) |r| {
                if (l == r) continue;
                for ([_]bool{ false, true }) |neg| {
                    try out.append(gpa, .{ .kind = .vset, .sub = @intFromEnum(op), .neg = neg, .syms = .{ @intCast(l), @intCast(r), 0, 0 } });
                }
            };
        }
    }

    for ([_]Kind{ .caret, .dollar, .wordb, .nwordb, .empty }) |kd| try out.append(gpa, .{ .kind = kd });
    if (out.items.len > 65536) return error.InventoryTooLarge;
    return out.toOwnedSlice(gpa);
}

// ---------------------------------------------------------------------------
// Tests: the flag-semantics checklist from the spec.

const testing = std.testing;

fn cls(neg: bool, members: []const u21) AtomSpec {
    var a: AtomSpec = .{ .kind = .cls, .neg = neg, .n = @intCast(members.len) };
    for (members, 0..) |m, i| a.syms[i] = m;
    return a;
}
fn esc(e: Esc) AtomSpec {
    return .{ .kind = .esc, .sub = @intFromEnum(e) };
}
fn vset(op: VOp, l: usize, r: usize) AtomSpec {
    return .{ .kind = .vset, .sub = @intFromEnum(op), .syms = .{ @intCast(l), @intCast(r), 0, 0 } };
}
fn F(s: []const u8) Flags {
    return Flags.parse(s) catch unreachable;
}

test "negated class under i must not complement before folding" {
    ucd.init();
    const nk = cls(true, &.{'k'});
    try testing.expect(!matches(&nk, F("i"), 'K'));
    try testing.expect(!matches(&nk, F("i"), 'k'));
    try testing.expect(matches(&nk, F("i"), 0x212A)); // non-unicode: Kelvin is unrelated
    try testing.expect(matches(&nk, F(""), 'K'));
    for ([_][]const u8{ "iu", "iv" }) |fs| {
        try testing.expect(!matches(&nk, F(fs), 'k'));
        try testing.expect(!matches(&nk, F(fs), 'K'));
        try testing.expect(!matches(&nk, F(fs), 0x212A));
        try testing.expect(matches(&nk, F(fs), 's'));
    }
}

test "\\W under iu and iv rejects case variants of word chars" {
    ucd.init();
    const W = esc(.W);
    for ([_][]const u8{ "iu", "iv" }) |fs| {
        for ([_]u21{ 'k', 'K', 0x212A, 's', 'S', 0x017F }) |c| try testing.expect(!matches(&W, F(fs), c));
        try testing.expect(matches(&W, F(fs), ' '));
    }
    // plain i: ſ is a non-word char and nothing folds it to ASCII
    try testing.expect(matches(&W, F("i"), 0x017F));
    try testing.expect(!matches(&W, F("i"), 'k'));
    const w = esc(.w);
    try testing.expect(matches(&w, F("iu"), 0x017F) and matches(&w, F("iv"), 0x212A));
    try testing.expect(!matches(&w, F("u"), 0x017F));
}

test "v-mode set operations under iv" {
    ucd.init();
    // [a--A] is empty under iv; [a&&A] matches a and A.
    const a_minus_A = vset(.sub, 10, 11);
    const a_and_A = vset(.inter, 10, 11);
    for ([_]u21{ 'a', 'A', 'b' }) |c| try testing.expect(!matches(&a_minus_A, F("iv"), c));
    try testing.expect(matches(&a_and_A, F("iv"), 'a') and matches(&a_and_A, F("iv"), 'A'));
    try testing.expect(matches(&a_minus_A, F("v"), 'a'));
    try testing.expect(!matches(&a_and_A, F("v"), 'a'));
    // [\w--k] under iv excludes K and Kelvin as well
    const w_minus_k = vset(.sub, 0, 7);
    try testing.expect(!matches(&w_minus_k, F("iv"), 0x212A));
    try testing.expect(!matches(&w_minus_k, F("iv"), 'K'));
    try testing.expect(matches(&w_minus_k, F("v"), 'K'));
}

test "dot and line terminators" {
    ucd.init();
    const dot: AtomSpec = .{ .kind = .dot };
    for ([_]u21{ '\n', '\r', 0x2028, 0x2029 }) |c| {
        try testing.expect(!matches(&dot, F(""), c));
        try testing.expect(matches(&dot, F("s"), c));
    }
    try testing.expect(matches(&dot, F("u"), alpha.astral_char));
    try testing.expect(matches(&dot, F("iv"), 0x212A));
}

test "assertions" {
    ucd.init();
    const w = [_]u21{ 'a', '\n', 'b', ' ' };
    const caret: AtomSpec = .{ .kind = .caret };
    const dollar: AtomSpec = .{ .kind = .dollar };
    const wb: AtomSpec = .{ .kind = .wordb };
    try testing.expectEqual(@as(u32, 0b00001), assertionMask(&caret, F(""), &w));
    try testing.expectEqual(@as(u32, 0b00101), assertionMask(&caret, F("m"), &w));
    try testing.expectEqual(@as(u32, 0b10000), assertionMask(&dollar, F(""), &w));
    try testing.expectEqual(@as(u32, 0b10010), assertionMask(&dollar, F("m"), &w));
    try testing.expectEqual(@as(u32, 0b01111), assertionMask(&wb, F(""), &w));
    // \b around ſ differs between i and iu
    const s2 = [_]u21{0x017F};
    try testing.expectEqual(@as(u32, 0b00), assertionMask(&wb, F("i"), &s2));
    try testing.expectEqual(@as(u32, 0b11), assertionMask(&wb, F("iu"), &s2));
    try testing.expectEqual(@as(u32, 0b1), assertionMask(&wb, F(""), &.{}) ^ 1);
}

test "case-insensitive literals" {
    ucd.init();
    const k: AtomSpec = .{ .kind = .lit, .syms = .{ 'k', 0, 0, 0 } };
    try testing.expect(matches(&k, F("i"), 'K') and !matches(&k, F("i"), 0x212A));
    try testing.expect(matches(&k, F("iu"), 0x212A) and matches(&k, F("iv"), 0x212A));
    const s: AtomSpec = .{ .kind = .lit, .syms = .{ 's', 0, 0, 0 } };
    try testing.expect(!matches(&s, F("i"), 0x017F) and matches(&s, F("iu"), 0x017F));
    const hs: AtomSpec = .{ .kind = .lit, .syms = .{ 0xD83D, 0, 0, 0 } };
    try testing.expect(matches(&hs, F(""), 0xD83D) and !matches(&hs, F("u"), alpha.astral_char));
}

test "inventory sizes are deterministic and bounded" {
    ucd.init();
    const gpa = testing.allocator;
    const inv1 = try buildInventory(gpa, .{}, F(""));
    defer gpa.free(inv1);
    const inv2 = try buildInventory(gpa, .{}, F("v"));
    defer gpa.free(inv2);
    try testing.expect(inv2.len > inv1.len);
    try testing.expect(inv1[0].kind == .lit and inv1[0].syms[0] == 'a');
}
