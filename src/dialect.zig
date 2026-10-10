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
    /// `$` without multiline also matches before a final newline (Perl).
    dollar_before_final_newline: bool = false,
    escape: Escape = .es,
    any_char: AnyChar = .empty_negated_class,
    strings: Strings = .es,
    /// Case-insensitive key: c matches s iff fold(c) == fold(s) (set members
    /// included). null = ECMAScript Canonicalize.
    fold: ?*const fn (u21) u21 = null,
    named_group: NamedGroup = .angle,
    word_boundary: []const u8 = "\\b",
    nonword_boundary: []const u8 = "\\B",
    /// Grammar restrictions for constructs the engine does not support.
    allow_lookahead: bool = true,
    allow_lookbehind: bool = true,
    allow_lazy: bool = true,
    /// Quantifiers over bodies that can only match the empty string, e.g. (?:)* or (?:\\b)*.
    allow_empty_quant: bool = true,
    /// Pool characters to drop (e.g. multi-character case folds).
    pool_exclude: []const u21 = &.{},
    /// Lookbehind bodies must have a provably bounded length (< cap); 0 = no limit.
    lookbehind_len_cap: u16 = 0,
};

pub const es = @import("dialects/es.zig").dialect;
pub const perl = @import("dialects/perl.zig").dialect;
pub const swift = @import("dialects/swift.zig").dialect;
pub const all = [_]*const Dialect{ &es, &perl, &swift };

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

/// Subjects never contain lone surrogates for this dialect.
pub fn noLoneSurrogates() bool {
    return active.strings != .es;
}
