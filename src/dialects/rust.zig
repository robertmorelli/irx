//! Rust `regex` crate (and fancy-regex, which delegates to it): Unicode classes
//! like Perl's \p{Word}/Nd/White_Space, simple case folding, `.` excludes \n only.
//! Unlike Perl, `$` without (?m) matches only at the very end, and (?m)^ matches
//! after a trailing \n. No multi-character case folds (ß stays in the pool).
const perl = @import("perl.zig");
const D = @import("../dialect.zig");

fn lineTerminator(c: u21) bool {
    return c == '\n';
}

const base: D.Dialect = .{
    .extended_mode = true,
    .scoped_flags = true,
    .unicode_props = true,
    .prop_case = .equivalence_invert,
    .word_boundary_variants = true,
    .class_set_ops = true,
    // find_iter: a*  on "baa" is [0,0) [1,3), with no empty match at 3.
    .global_empty_after_match = false,
    // (?R:…) CRLF mode and (?U:…) swap-greed mode besides i, s, m.
    .scoped_mods = 1 | 2 | 4 | 8 | 16,
    .name = "rust",
    // Empty iterations follow the Thompson NFA: (?:|a)* on "aa" is [0,0) as in Perl, but
    // (?:\B|x)* on "ϑё" is [0,2) where Perl stops at [0,1).
    .empty_iteration = .thompson,
    .isLineTerminator = lineTerminator,
    .isSpace = perl.space,
    .isWord = perl.word,
    .isDigit = perl.digit,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    // linear-time engine: no lookaround
    .allow_lookahead = false,
    .allow_lookbehind = false,
};

pub const dialect: D.Dialect = base;

/// fancy-regex: backtracking front end with lookaround; rejects quantified empty bodies.
pub const fancy: D.Dialect = blk: {
    var d = base;
    d.name = "fancy";
    d.atomic_groups = true;
    d.backrefs = true;
    d.backref_by_name = true; // a numbered reference to a named group is a syntax error
    d.allow_lookahead = true;
    d.allow_lookbehind = true;
    d.allow_empty_quant = false;
    d.lookbehind_fixed = true;
    // Patterns without lookarounds, backreferences, atomic groups or word boundaries go to the
    // regex crate whole; the rest run on fancy-regex's backtracking VM, which stops unbounded
    // loops on an empty iteration and unrolls bounded ones. Not modelled: inside such a pattern
    // the VM still hands plain subexpressions to the regex crate ((?:|\b)(?:a|(?:)|k)+ on
    // "aak" is [0,3)).
    d.nfa_word_boundary = false;
    d.empty_iteration_bounded = false;
    break :blk d;
};

/// regex-lite: the same syntax and matching rules with only basic Unicode support: \d, \s, \w
/// and \b are ASCII ([0-9], [\t\n\v\f\r ], [0-9A-Za-z_]), (?i) is ASCII-only, no \p{…}.
fn liteDigit(c: u21) bool {
    return c >= '0' and c <= '9';
}
fn liteWord(c: u21, _: D.Flags) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or liteDigit(c) or c == '_';
}
fn liteSpace(c: u21) bool {
    return c == ' ' or (c >= 0x09 and c <= 0x0D);
}
fn asciiFold(c: u21) u21 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

pub const lite: D.Dialect = blk: {
    var d = base;
    d.name = "rust-lite";
    d.unicode_props = false;
    d.class_set_ops = false;
    d.isWord = liteWord;
    d.isDigit = liteDigit;
    d.isSpace = liteSpace;
    d.fold = asciiFold;
    break :blk d;
};
