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
    /// Strings are code points only: every flag set gets `u`, no lone surrogates,
    /// no `v` set syntax.
    code_points_only: bool = false,
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
