//! Ruby (Onigmo, reference: Ruby 4.0): ASCII \w \d \s but Unicode \b; ^ and $ are always line
//! anchors (Ruby's /m is dotall, mapped from irx's s flag); full Unicode case
//! folding, so multi-character folds (ß, İ) are kept out of the pool.
const D = @import("../dialect.zig");
const perl = @import("perl.zig");

fn lineTerminator(c: u21) bool {
    return c == '\n';
}
fn digit(c: u21) bool {
    return c >= '0' and c <= '9';
}
fn word(c: u21, _: D.Flags) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or digit(c) or c == '_';
}
/// \s = [ \t\n\v\f\r]
fn space(c: u21) bool {
    return c == ' ' or (c >= 0x09 and c <= 0x0D);
}

pub const dialect: D.Dialect = .{
    .name = "ruby",
    .isLineTerminator = lineTerminator,
    .isSpace = space,
    .isWord = word,
    .isDigit = digit,
    .anchors_always_multiline = true,
    .caret_after_trailing_newline = false,
    // \b uses Unicode word characters although \w is ASCII-only.
    .isBoundaryWord = perl.word,
    .escapes_ignore_case = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    .pool_exclude = &.{ 0xDF, 0x130 },
};

/// Oniguruma C library with ONIG_SYNTAX_RUBY and default options (reference 6.9):
/// Unicode \w \d \s (Perl-like), Ruby's always-on line anchors, full case folding.
/// Rejects quantifiers on zero-width bodies such as (?:\b)*.
pub const oniguruma: D.Dialect = .{
    .name = "oniguruma",
    .isLineTerminator = lineTerminator,
    .isSpace = perl.space,
    .isWord = perl.word,
    .isDigit = perl.digit,
    .anchors_always_multiline = true,
    .caret_after_trailing_newline = false,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    .pool_exclude = &.{ 0xDF, 0x130 },
    .allow_empty_quant = false,
};
