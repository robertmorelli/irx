//! Regex dialect component. A Dialect describes *what a regex means* in one
//! regex family: character predicates, case-insensitive matching, anchor rules,
//! pattern syntax, and constraints on strings, flags and grammar. It says nothing
//! about the oracle's question: today irx asks "does r fully match w?", which the
//! relation model answers from the span relation; a future match-range oracle
//! (leftmost/longest spans, captures) can reuse the same Dialect unchanged and add
//! its own engine-priority semantics alongside.
//!
//! Adding a dialect = one file in src/dialects/ registered in `all`, plus a
//! self-check that reaches zero mismatches against a reference engine.
const std = @import("std");
const alpha = @import("alphabet.zig");
const atoms = @import("atoms.zig");

pub const Flags = alpha.Flags;

/// How code points that need escaping are spelled in patterns.
pub const Escape = enum {
    /// ECMAScript: \uXXXX without u/v, \u{H} with u/v.
    es,
    /// Perl/PCRE family: \x{H}.
    x_brace,
};

/// How subjects are decoded into symbols.
pub const Strings = enum {
    /// ECMAScript: code units without u/v, code points with u/v (both allowed).
    es,
    /// Code points only: every flag set gets `u`, no lone surrogates, no `v`.
    code_points,
    /// UTF-16 code units only (.NET): no `u`/`v`; astral characters are two symbols.
    utf16_units,
};

/// Named-group spelling.
pub const NamedGroup = enum { angle, p_angle, plain_capture };

/// How the self-check spells "any single character".
pub const AnyChar = enum { empty_negated_class, space_or_nonspace };

pub const Dialect = struct {
    name: []const u8,
    /// Character predicates over code points. `isWord` gets flags because some
    /// dialects (ES with iu/iv) widen \w under case-insensitivity.
    isLineTerminator: *const fn (u21) bool,
    isSpace: *const fn (u21) bool,
    isWord: *const fn (u21, Flags) bool,
    isDigit: *const fn (u21) bool,
    /// Optional replacement for the generic CharacterSetMatcher on consuming
    /// atoms (dialects whose case-insensitive class rules differ, e.g. Swift).
    matchAtom: ?*const fn (*const atoms.AtomSpec, Flags, u21) bool = null,
    /// `^` under multiline also matches after a newline that ends the string.
    caret_after_trailing_newline: bool = true,
    /// `^`/`$` are always line anchors, regardless of the m flag (Ruby).
    anchors_always_multiline: bool = false,
    /// Word set used by \\b/\\B when it differs from \\w (null = isWord).
    isBoundaryWord: ?*const fn (u21, Flags) bool = null,
    /// `^` under multiline never matches at the end of input (Java: not even in "").
    caret_m_never_at_end: bool = false,
    /// `$` without multiline also matches before a final line terminator (Perl, Java).
    dollar_before_final_terminator: bool = false,
    /// "\\r\\n" is one line terminator: no ^/$ between \\r and \\n (Java, ICU).
    crlf_atomic: bool = false,
    /// With crlf_atomic, `^` may still match between \\r and \\n (ICU); only `$` treats CRLF as one.
    caret_splits_crlf: bool = false,
    escape: Escape = .es,
    any_char: AnyChar = .empty_negated_class,
    strings: Strings = .es,
    /// Case-insensitive key: c matches s iff fold(c) == fold(s) (set members
    /// included). null = ECMAScript Canonicalize.
    fold: ?*const fn (u21) u21 = null,
    named_group: NamedGroup = .angle,
    word_boundary: []const u8 = "\\b",
    nonword_boundary: []const u8 = "\\B",
    /// \W \D \S negate after case folding (no case variant is in the positive
    /// set) instead of complementing before folding as ECMAScript does.
    negated_escapes_invert: bool = false,
    /// \\w \\d \\s and their negations are plain property tests, unaffected by i.
    escapes_ignore_case: bool = false,
    /// `.` matches everything unless m, and excludes \\n under m (Racket multi mode).
    dot_all_unless_m: bool = false,
    /// Grammar restrictions for constructs the engine does not support.
    allow_lookahead: bool = true,
    allow_lookbehind: bool = true,
    /// `^`, `\\b`, `\\B` usable mid-pattern (resharp compiles them as start-only lookbehinds).
    allow_lookbehind_assertions: bool = true,
    /// Lookaheads (and `$` under m) allowed inside unbounded `*`/`+` (resharp: no).
    lookahead_in_star: bool = true,
    /// Extra ASCII metacharacters, printed as code-point escapes (resharp: _ & ~).
    extra_meta: []const u8 = "",
    allow_lazy: bool = true,
    /// Quantifiers over bodies that can only match the empty string, e.g. (?:)* or (?:\\b)*.
    allow_empty_quant: bool = true,
    /// Only `?` may quantify a body that can match empty (Racket).
    nullable_quant_opt_only: bool = false,
    /// Pool characters to drop (e.g. multi-character case folds).
    pool_exclude: []const u21 = &.{},
    /// Lookbehind bodies must have a provably bounded length (< cap); 0 = no limit.
    lookbehind_len_cap: u16 = 0,
    /// Lookbehind bodies must have a fixed length (min == max); implies a cap.
    lookbehind_fixed: bool = false,
};

pub const es = @import("dialects/es.zig").dialect;
pub const perl = @import("dialects/perl.zig").dialect;
pub const swift = @import("dialects/swift.zig").dialect;
pub const rust = @import("dialects/rust.zig").dialect;
pub const fancy = @import("dialects/rust.zig").fancy;
pub const re2 = @import("dialects/re2.zig").dialect;
pub const go = @import("dialects/re2.zig").go;
pub const python = @import("dialects/python.zig").dialect;
pub const java = @import("dialects/java.zig").dialect;
pub const ruby = @import("dialects/ruby.zig").dialect;
pub const oniguruma = @import("dialects/ruby.zig").oniguruma;
pub const dotnet = @import("dialects/dotnet.zig").dialect;
pub const dotnet_nb = @import("dialects/dotnet.zig").nonbacktracking;
pub const icu = @import("dialects/icu.zig").dialect;
pub const resharp = @import("dialects/resharp.zig").dialect;
pub const nim = @import("dialects/nim.zig").dialect;
pub const racket = @import("dialects/racket.zig").dialect;
pub const tcl = @import("dialects/tcl.zig").dialect;
pub const all = [_]*const Dialect{ &es, &perl, &swift, &rust, &fancy, &re2, &go, &python, &java, &ruby, &oniguruma, &dotnet, &dotnet_nb, &icu, &resharp, &nim, &racket, &tcl };

/// The active dialect (process-wide; chosen once at startup).
pub var active: *const Dialect = &es;

pub fn byName(name: []const u8) ?*const Dialect {
    for (all) |d| if (std.mem.eql(u8, d.name, name)) return d;
    if (std.mem.eql(u8, name, "js")) return &es;
    return null;
}

pub fn isEs() bool {
    return active == &es;
}

/// Strings decode to code points only (no lone surrogates on the wire).
pub fn codePointsOnly() bool {
    return active.strings == .code_points;
}

/// Length bounds of a subtree: (min, max) symbols, saturating at `cap`.
/// Subtree length bounds; `la`: contains a lookahead or `$` (no flags here, so conservative).
pub const Len = struct { min: u32, max: u32, la: bool = false };
pub const len_cap_default: u32 = 16;

/// Does a tree respect the active dialect's grammar restrictions? (Used by the
/// shrinker so candidates stay inside the grammar the tables generate.)
pub fn treeAllowed(t: anytype) bool {
    var ok = true;
    _ = lenOf(t, t.root, &ok);
    return ok;
}

fn lenOf(t: anytype, idx: u8, ok: *bool) Len {
    const ast = @import("ast.zig");
    const n = t.nodes[idx];
    const cap = len_cap_default;
    const d = active;
    switch (n.op) {
        .atom => {
            if (!d.allow_lookbehind_assertions and (n.atom.kind == .caret or n.atom.kind == .wordb or n.atom.kind == .nwordb)) ok.* = false;
            return if (n.atom.isConsuming()) .{ .min = 1, .max = 1 } else .{ .min = 0, .max = 0, .la = n.atom.kind == .dollar };
        },
        .concat => {
            const a = lenOf(t, n.a, ok);
            const b = lenOf(t, n.b, ok);
            return .{ .min = @min(cap, a.min + b.min), .max = @min(cap, a.max + b.max), .la = a.la or b.la };
        },
        .alt => {
            const a = lenOf(t, n.a, ok);
            const b = lenOf(t, n.b, ok);
            return .{ .min = @min(a.min, b.min), .max = @max(a.max, b.max), .la = a.la or b.la };
        },
        .quant => {
            const c = lenOf(t, n.a, ok);
            const q = n.quant;
            if (q.lazy and !d.allow_lazy) ok.* = false;
            if (!d.allow_empty_quant and c.max == 0) ok.* = false;
            if (d.nullable_quant_opt_only and c.min == 0 and q.form != .opt) ok.* = false;
            if (!d.lookahead_in_star and c.la and q.max == ast.inf) ok.* = false;
            return .{ .min = @min(cap, c.min * q.min), .max = if (q.max == ast.inf) cap else @min(cap, c.max * q.max), .la = c.la };
        },
        .look_ahead, .neg_look_ahead => {
            _ = lenOf(t, n.a, ok);
            if (!d.allow_lookahead) ok.* = false;
            return .{ .min = 0, .max = 0, .la = true };
        },
        .look_behind, .neg_look_behind => {
            const c = lenOf(t, n.a, ok);
            if (!d.allow_lookbehind) ok.* = false;
            if (d.lookbehind_len_cap > 0 and c.max >= d.lookbehind_len_cap) ok.* = false;
            if (d.lookbehind_fixed and (c.min != c.max or c.max >= cap)) ok.* = false;
            return .{ .min = 0, .max = 0 };
        },
        else => return lenOf(t, n.a, ok),
    }
}

/// Subjects never contain lone surrogates for this dialect.
pub fn noLoneSurrogates() bool {
    return active.strings != .es;
}
