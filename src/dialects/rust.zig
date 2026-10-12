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
    .name = "rust",
    // Span mode: empty-loop handling of the automata (and fancy-regex's delegation to
    // them) is implementation-specific; not modelled.
    .empty_iteration = .unmodeled,
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
    d.isWord = liteWord;
    d.isDigit = liteDigit;
    d.isSpace = liteSpace;
    d.fold = asciiFold;
    break :blk d;
};
