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
    .name = "rust",
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
    d.allow_lookahead = true;
    d.allow_lookbehind = true;
    d.allow_empty_quant = false;
    d.lookbehind_fixed = true;
    break :blk d;
};
