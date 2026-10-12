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
const grapheme = @import("grapheme.zig");
const dialect = @import("dialect.zig");

pub const Kind = enum(u8) { lit, dot, esc, range, cls, vset, caret, dollar, wordb, nwordb, empty, prop, strs, grapheme };

/// Unicode general categories for `\p{…}` / `\P{…}` (a selection that the character pool
/// exercises: letters and their cases, digits, the pool's punctuation, symbols, separators,
/// controls).
pub const Prop = enum(u8) {
    L, Lu, Ll, N, Nd, P, Pc, Pd, Po, S, So, Z, Zs, Zl, C, Cc,

    /// Does code point x have this general category (one letter: the major class)?
    pub fn has(p: Prop, x: u21) bool {
        const cat = ucd.category(x);
        const name = @tagName(p);
        if (cat[0] != name[0]) return false;
        return name.len == 1 or cat[1] == name[1];
    }
};
pub const Esc = enum(u8) { d, D, w, W, s, S, h, H, v, V };
pub const VOp = enum(u8) { sub, inter, uni };

/// Value-typed atom description. Owned ASTs embed these, so a finding never
/// refers back to a table's inventory.
pub const AtomSpec = struct {
    kind: Kind,
    /// Esc for .esc, VOp for .vset, Prop for .prop.
    sub: u8 = 0,
    /// Negated class spelling `[^…]`.
    neg: bool = false,
    /// Number of used syms for .cls.
    n: u8 = 0,
    /// lit: syms[0]; range: syms[0..2]; cls: syms[0..n]; vset: operand ids syms[0], syms[1];
    /// strs: two strings back to back, lengths in n (low nibble, high nibble; the second may be 0).
    syms: [4]u21 = .{ 0, 0, 0, 0 },

    /// strs ([\q{ab|c}], ES v mode): the string alternatives, longest first (the order ES tries
    /// them in).
    pub fn strings(a: *const AtomSpec, out: *[2][]const u21) usize {
        const l1: usize = a.n & 0xF;
        const l2: usize = a.n >> 4;
        const s1 = a.syms[0..l1];
        const s2 = a.syms[l1 .. l1 + l2];
        if (l2 == 0) {
            out[0] = s1;
            return 1;
        }
        if (l2 > l1) {
            out[0] = s2;
            out[1] = s1;
        } else {
            out[0] = s1;
            out[1] = s2;
        }
        return 2;
    }
    /// Match length bounds: 1 for single-character atoms, 0 for assertions and empty.
    pub fn minLen(a: AtomSpec) u8 {
        if (a.kind == .strs) return @min(a.n & 0xF, if (a.n >> 4 == 0) a.n & 0xF else a.n >> 4);
        return if (a.isConsuming()) 1 else 0;
    }
    pub fn maxLen(a: AtomSpec) u8 {
        if (a.kind == .strs) return @max(a.n & 0xF, a.n >> 4);
        if (a.kind == .grapheme) return 255;
        return if (a.isConsuming()) 1 else 0;
    }

    pub fn isAssertion(a: AtomSpec) bool {
        return switch (a.kind) {
            .caret, .dollar, .wordb, .nwordb => true,
            else => false,
        };
    }
    /// Under i, the atom may match a character whose full case fold is several characters, so
    /// its match length can vary (Onigmo rejects such atoms inside lookbehind): properties,
    /// ranges reaching past ASCII, and literals or listed members with multi-character folds.
    pub fn mayFoldMulti(a: AtomSpec) bool {
        const multi = [_]u21{ 0xDF, 0x1E9E, 0x130, 0x149, 0x1F0, 0x390, 0x3B0, 0x587, 0x1FD3, 0x1FE3, 0xFB00, 0xFB01, 0xFB02, 0xFB03, 0xFB04, 0xFB05, 0xFB06 };
        return switch (a.kind) {
            .prop => true,
            .range => a.syms[1] > 0x7F,
            .lit => std.mem.indexOfScalar(u21, &multi, a.syms[0]) != null,
            .cls => for (a.syms[0..a.n]) |c| {
                if (std.mem.indexOfScalar(u21, &multi, c) != null) break true;
            } else false,
            else => false,
        };
    }

    pub fn isConsuming(a: AtomSpec) bool {
        return switch (a.kind) {
            .lit, .dot, .esc, .range, .cls, .vset, .prop, .strs, .grapheme => true,
            else => false,
        };
    }
    pub fn eql(a: AtomSpec, b: AtomSpec) bool {
        return a.kind == b.kind and a.sub == b.sub and a.neg == b.neg and a.n == b.n and std.mem.eql(u21, &a.syms, &b.syms);
    }
};

/// Construct categories for weights.
pub const Category = enum(u8) { literal, dot, class, range, escape, vset, caret, dollar, backslash_b, backslash_B, empty, property };

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
        .prop => .property,
        .strs => .vset,
        .grapheme => .escape,
    };
}

// ---------------------------------------------------------------------------
// v-mode set operands (static, so specs that reference them stay owned values)

pub const OperandKind = enum(u8) { esc, range, char, list, neglist, prop, qstr };
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
    // Unicode properties as set operands ([\p{L}--\p{Lu}]); syms[0] = Prop.
    .{ .kind = .prop, .syms = .{ @intFromEnum(Prop.L), 0 } },
    .{ .kind = .prop, .syms = .{ @intFromEnum(Prop.Lu), 0 } },
    .{ .kind = .prop, .syms = .{ @intFromEnum(Prop.Ll), 0 } },
    // ClassStringDisjunction with one-character strings (\q{a|s}): a list, spelled differently.
    .{ .kind = .qstr, .syms = .{ 'a', 's' }, .n = 2 },
    .{ .kind = .qstr, .syms = .{ 'k', 0x17F }, .n = 2 },
};

pub const explicit_ranges = [_][2]u21{
    .{ 'a', 'c' }, .{ 'a', 'z' }, .{ 'A', 'Z' }, .{ '0', '9' }, .{ 'k', 's' },
    // Non-ASCII endpoints, and ranges whose case partners fall outside them (folding bugs).
    .{ 0xE0, 0xFF }, // à-ÿ (ß below, ÿ's uppercase Ÿ is U+0178)
    .{ 0xC0, 0xDE }, // À-Þ
    .{ 0x3B1, 0x3C9 }, // α-ω (contains ς)
    .{ 0x391, 0x3A9 }, // Α-Ω
    .{ 0x430, 0x44F }, // а-я
    .{ 'k', 0x17F }, // k-ſ (crosses into Latin Extended-A; K and Kelvin fold into it)
};

// ---------------------------------------------------------------------------
// CharSet expressions

const SetKind = enum { list, range, digit, space, word, dotset, all, comp, fold, uni, inter, diff, prop, hspace, vspace };
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
        .digit => dialect.active.isDigit(x),
        .space => alpha.isSpace(x),
        .word => alpha.isWordChar(x, flags),
        .hspace => dialect.active.isHSpace(x),
        .vspace => dialect.active.isVSpace(x),
        .dotset => alpha.inAllCharacters(x, flags) and
            (if (dialect.active.dot_all_unless_m) !flags.m or x != '\n' else flags.s or !alpha.isLineTerminator(x)),
        .all => alpha.inAllCharacters(x, flags),
        // CharacterComplement(rer, S): AllCharacters(rer) minus S.
        .comp => alpha.inAllCharacters(x, flags) and !has(n.a.?, flags, x),
        // MaybeSimpleCaseFolding: {scf(s) : s ∈ S} under v+i, else S.
        .fold => if (flags.v and flags.i) foldHas(n.a.?, flags, x) else has(n.a.?, flags, x),
        .uni => has(n.a.?, flags, x) or has(n.b.?, flags, x),
        .inter => has(n.a.?, flags, x) and has(n.b.?, flags, x),
        .diff => has(n.a.?, flags, x) and !has(n.b.?, flags, x),
        // General category (lo = Prop). Perl-style /i: Lu and Ll stand for any cased letter.
        .prop => blk: {
            const p: Prop = @enumFromInt(n.lo);
            if (flags.i and dialect.active.prop_case == .cased and (p == .Lu or p == .Ll))
                break :blk Prop.Lu.has(x) or Prop.Ll.has(x) or std.mem.eql(u8, &ucd.category(x), "Lt");
            break :blk p.has(x);
        },
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
        .h => ar.add(.{ .kind = .hspace }),
        .H => ar.add(.{ .kind = .comp, .a = ar.add(.{ .kind = .hspace }) }),
        .v => ar.add(.{ .kind = .vspace }),
        .V => ar.add(.{ .kind = .comp, .a = ar.add(.{ .kind = .vspace }) }),
    };
}

fn operandSet(ar: *SetArena, op: *const Operand, flags: Flags) *const SetNode {
    return switch (op.kind) {
        .esc => escSet(ar, op.esc, flags),
        .range => ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .range, .lo = op.syms[0], .hi = op.syms[1] }) }),
        .char => ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .list, .syms = op.syms[0..1] }) }),
        .list => ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .list, .syms = op.syms[0..op.n] }) }),
        .neglist => ar.add(.{ .kind = .comp, .a = ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .list, .syms = op.syms[0..op.n] }) }) }),
        .prop => ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .prop, .lo = @intCast(op.syms[0]) }) }),
        .qstr => ar.add(.{ .kind = .fold, .a = ar.add(.{ .kind = .list, .syms = op.syms[0..op.n] }) }),
    };
}

fn compile(spec: *const AtomSpec, flags: Flags, ar: *SetArena) Compiled {
    switch (spec.kind) {
        // Atom :: PatternCharacter / escaped char: singleton, no folding at compile time.
        .lit => return .{ .root = ar.add(.{ .kind = .list, .syms = spec.syms[0..1] }), .invert = false },
        .dot => return .{ .root = ar.add(.{ .kind = .dotset }), .invert = false },
        .esc => {
            const e: Esc = @enumFromInt(spec.sub);
            if (dialect.active.negated_escapes_invert) {
                // \W, \D, \S as (positive set, invert): negation after case folding.
                const pos: Esc = switch (e) {
                    .W => .w,
                    .D => .d,
                    .S => .s,
                    .H => .h,
                    .V => .v,
                    else => e,
                };
                return .{ .root = escSet(ar, pos, flags), .invert = pos != e };
            }
            return .{ .root = escSet(ar, e, flags), .invert = false };
        },
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
        .prop => {
            // \p{X}: the property's set. \P{X} is its complement taken before any case
            // folding (ES u-mode CharacterClassEscape), unlike an inverted class [^\p{X}]; under
            // v the set is simple-case-folded first (MaybeSimpleCaseFolding).
            var set = ar.add(.{ .kind = .prop, .lo = spec.sub });
            if (flags.v) set = ar.add(.{ .kind = .fold, .a = set });
            // equivalence_invert: \P as the inverse after case equivalence, like [^\p{X}].
            if (dialect.active.prop_case == .equivalence_invert and !flags.v) return .{ .root = set, .invert = spec.neg };
            if (spec.neg) set = ar.add(.{ .kind = .comp, .a = set });
            return .{ .root = set, .invert = false };
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

/// Set membership without case-insensitive equivalence (for dialects whose
/// escapes and '.' are plain property tests).
pub fn matchesCaseless(spec: *const AtomSpec, flags: Flags, c: u21) bool {
    var ar: SetArena = .{};
    const cs = compile(spec, flags, &ar);
    return has(cs.root, flags, c) != cs.invert;
}

/// CharacterSetMatcher for one symbol (dialect override first).
pub fn matches(spec: *const AtomSpec, flags: Flags, c: u21) bool {
    // Multi-character atoms have no per-character test (callers handle them first).
    if (spec.kind == .strs or spec.kind == .grapheme) return false;
    if (dialect.active.matchAtom) |m| return m(spec, flags, c);
    return matchesGeneric(spec, flags, c);
}

/// The generic CharacterSetMatcher (with the dialect's fold), for overrides to fall back on.
pub fn matchesGeneric(spec: *const AtomSpec, flags: Flags, c: u21) bool {
    if (spec.kind == .esc and dialect.active.escapes_ignore_case) return matchesCaseless(spec, flags, c);
    // Properties as plain membership tests in dialects where /i does not reach them (or only
    // through the cased-letter rule in `has`).
    if (spec.kind == .prop) switch (dialect.active.prop_case) {
        .equivalence, .equivalence_invert => {},
        .cased, .plain => return matchesCaseless(spec, flags, c),
        .upper_lower => {
            // .NET: c, its simple upper/lower forms, or a case-folding equivalent (ß ~ ẞ).
            const p: Prop = @enumFromInt(spec.sub);
            const Ctx = struct { p: Prop };
            const hit = p.has(c) or (flags.i and (p.has(ucd.simpleUpper(c)) or p.has(ucd.simpleLower(c)) or
                ucd.forEachEquivalent(c, true, Ctx{ .p = p }, struct {
                fn f(ctx: Ctx, x: u21) bool {
                    return ctx.p.has(x);
                }
            }.f)));
            return hit != spec.neg;
        },
    };
    var ar: SetArena = .{};
    const cs = compile(spec, flags, &ar);
    const found = alpha.existsEquivalent(c, flags, HasCtx{ .n = cs.root, .flags = flags }, hasCtx);
    return found != cs.invert;
}

fn isWordAt(w: []const u21, i: isize, flags: Flags) bool {
    if (i < 0 or i >= @as(isize, @intCast(w.len))) return false;
    if (dialect.active.isBoundaryWord) |bw| return bw(w[@intCast(i)], flags);
    return alpha.isWordChar(w[@intCast(i)], flags);
}

/// Bitmask over positions 0..n where the assertion holds.
pub fn assertionMask(spec: *const AtomSpec, flags: Flags, w: []const u21) u32 {
    var mask: u32 = 0;
    for (0..w.len + 1) |i| {
        if (assertionAt(spec, flags, w, i)) mask |= @as(u32, 1) << @intCast(i);
    }
    return mask;
}

/// Does assertion `spec` (^ $ \b \B) hold at position i of w (0 <= i <= w.len)?
pub fn assertionAt(spec: *const AtomSpec, flags0: Flags, w: []const u21, i: usize) bool {
    const dl = dialect.active;
    var flags = flags0;
    if (dl.anchors_always_multiline) flags.m = true;
    const n = w.len;
    return switch (spec.kind) {
        // Perl: /m ^ never matches after a trailing newline; $ without /m
        // also matches before a final newline.
        .caret => if (flags.m and dl.caret_m_never_at_end and i == n) false else i == 0 or (flags.m and alpha.isLineTerminator(w[i - 1]) and (dl.caret_after_trailing_newline or i != n) and
            !(dl.crlf_atomic and !dl.caret_splits_crlf and w[i - 1] == '\r' and i < n and w[i] == '\n')),
        .dollar => i == n or
            (flags.m and alpha.isLineTerminator(w[i]) and !(dl.crlf_atomic and w[i] == '\n' and i > 0 and w[i - 1] == '\r')) or
            (dl.dollar_before_final_terminator and !flags.m and
                ((i + 1 == n and alpha.isLineTerminator(w[i]) and !(dl.crlf_atomic and w[i] == '\n' and i > 0 and w[i - 1] == '\r')) or
                (dl.crlf_atomic and i + 2 == n and w[i] == '\r' and w[i + 1] == '\n'))),
        .wordb, .nwordb => blk: {
            const ii: isize = @intCast(i);
            const b = if (dl.boundaryAt) |f| f(w, i, flags) else isWordAt(w, ii - 1, flags) != isWordAt(w, ii, flags);
            break :blk if (spec.kind == .wordb) b else !b;
        },
        else => unreachable,
    };
}

/// Relation of one atom on string w.
/// Full case folds of more than one character for the characters the pools use (CaseFolding.txt
/// status F). Subjects never contain these (dialect.pattern_only), so a subject string matches
/// when its characters' simple folds spell the fold.
pub fn multiFold(c: u21) ?[]const u21 {
    return switch (c) {
        0xDF, 0x1E9E => &.{ 's', 's' },
        0xFB00 => &.{ 'f', 'f' },
        0xFB01 => &.{ 'f', 'i' },
        0xFB02 => &.{ 'f', 'l' },
        0xFB03 => &.{ 'f', 'f', 'i' },
        0xFB04 => &.{ 'f', 'f', 'l' },
        0xFB05, 0xFB06 => &.{ 's', 't' },
        0x130 => &.{ 'i', 0x307 },
        else => null,
    };
}

/// Multi-character folds the atom can match at w[i..] under i (full_fold dialects): calls
/// `f(ctx, end)` for each, stopping when it returns true.
pub fn forEachFoldMatch(a: *const AtomSpec, flags: Flags, w: []const u21, i: usize, ctx: anytype, comptime f: fn (@TypeOf(ctx), usize) bool) bool {
    if (!foldsMulti(a, flags)) return false;
    const members: []const u21 = if (a.kind == .lit) a.syms[0..1] else a.syms[0..a.n];
    for (members) |c| {
        const fold = multiFold(c) orelse continue;
        if (i + fold.len > w.len) continue;
        for (fold, 0..) |x, k| {
            if (ucd.simpleFold(w[i + k]) != x) break;
        } else if (f(ctx, i + fold.len)) return true;
    }
    return false;
}

/// Could the atom match more than one character under these flags (full folding)?
pub fn foldsMulti(a: *const AtomSpec, flags: Flags) bool {
    if (!flags.i or dialect.active.full_fold == .none) return false;
    return switch (a.kind) {
        .lit => multiFold(a.syms[0]) != null,
        .cls => dialect.active.full_fold == .classes and !a.neg and for (a.syms[0..a.n]) |c| {
            if (multiFold(c) != null) break true;
        } else false,
        else => false,
    };
}

/// Does string `s` (a \q{…} alternative) occur at w[i..]? Case-insensitive under i (v mode:
/// simple case folding).
pub fn stringAt(s: []const u21, w: []const u21, i: usize, flags: Flags) bool {
    if (i + s.len > w.len) return false;
    for (s, 0..) |c, j| {
        const x = w[i + j];
        if (c != x and !(flags.i and alpha.canonicalize(c, flags) == alpha.canonicalize(x, flags))) return false;
    }
    return true;
}

pub fn relation(comptime R: type, spec: *const AtomSpec, flags: Flags, w: []const u21) R {
    const dim = w.len + 1;
    switch (spec.kind) {
        .empty => return R.identity(dim),
        .caret, .dollar, .wordb, .nwordb => return R.diagFromMask(assertionMask(spec, flags, w)),
        .grapheme => {
            var r: R = .{};
            for (0..w.len) |i| r.set(i, grapheme.clusterEndActive(w, i));
            return r;
        },
        .strs => {
            var r: R = .{};
            var ss: [2][]const u21 = undefined;
            const k = spec.strings(&ss);
            for (0..w.len + 1) |i| for (ss[0..k]) |s| {
                if (stringAt(s, w, i, flags)) r.set(i, i + s.len);
            };
            return r;
        },
        else => {
            var r: R = .{};
            for (w, 0..) |c, i| {
                if (matches(spec, flags, c)) r.set(i, i + 1);
            }
            if (foldsMulti(spec, flags)) {
                const Ctx = struct {
                    r: *R,
                    i: usize,
                    fn add(x: @This(), e: usize) bool {
                        x.r.set(x.i, e);
                        return false;
                    }
                };
                for (0..w.len) |i| _ = forEachFoldMatch(spec, flags, w, i, Ctx{ .r = &r, .i = i }, Ctx.add);
            }
            return r;
        },
    }
}

// ---------------------------------------------------------------------------
// Inventory

pub const InventoryConfig = struct {
    pool: []const u21 = &alpha.base_pool,
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
    for (std.enums.values(Esc)) |e| {
        if ((e == .h or e == .H or e == .v or e == .V) and !dialect.active.hv_escapes) continue;
        try out.append(gpa, .{ .kind = .esc, .sub = @intFromEnum(e) });
    }
    for (explicit_ranges) |rg| {
        if (rg[1] > 0x7F and dialect.active.ascii_only) continue;
        try out.append(gpa, .{ .kind = .range, .syms = .{ rg[0], rg[1], 0, 0 } });
    }
    // Unicode properties where the dialect has them (ES: only with u or v).
    if (dialect.active.unicode_props and (flags.unicode() or !dialect.active.props_need_u) and !(flags.i and dialect.active.props_multi_fold)) {
        for (std.enums.values(Prop)) |p| for ([_]bool{ false, true }) |neg| {
            try out.append(gpa, .{ .kind = .prop, .sub = @intFromEnum(p), .neg = neg });
        };
    }

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
                if (!dialect.active.unicode_props and (v_operands[l].kind == .prop or v_operands[r].kind == .prop)) continue;
                if (flags.i and !dialect.active.qstr_ignore_case and (v_operands[l].kind == .qstr or v_operands[r].kind == .qstr)) continue;
                for ([_]bool{ false, true }) |neg| {
                    try out.append(gpa, .{ .kind = .vset, .sub = @intFromEnum(op), .neg = neg, .syms = .{ @intCast(l), @intCast(r), 0, 0 } });
                }
            };
        }
    }
    if (flags.v and (!flags.i or dialect.active.qstr_ignore_case)) {
        // Multi-character class strings [\q{xy|x}] over the first pool symbols: one string, or a
        // longer and a shorter one sharing a prefix or not (ES tries the longest first).
        const nq = @min(syms.len, 4);
        for (syms[0..nq]) |x| for (syms[0..nq]) |y| {
            try out.append(gpa, .{ .kind = .strs, .n = 2, .syms = .{ x, y, 0, 0 } });
            try out.append(gpa, .{ .kind = .strs, .n = 2 | (1 << 4), .syms = .{ x, y, x, 0 } });
            try out.append(gpa, .{ .kind = .strs, .n = 2 | (1 << 4), .syms = .{ x, y, y, 0 } });
            try out.append(gpa, .{ .kind = .strs, .n = 3 | (1 << 4), .syms = .{ x, x, y, y } });
        };
    }

    if (dialect.active.grapheme_escape != .none) try out.append(gpa, .{ .kind = .grapheme });
    for ([_]Kind{ .caret, .dollar, .wordb, .nwordb, .empty }) |kd| {
        if (!dialect.active.assertions.allows(kd)) continue;
        try out.append(gpa, .{ .kind = kd });
    }
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
