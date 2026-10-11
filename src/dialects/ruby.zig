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
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
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
    // Onigmo lookbehind: fixed length, no variable quantifiers, no lookahead inside.
    .lookbehind_fixed = true,
    .lookbehind_no_variable = true,
    .lookbehind_onig = true,
    .lazy_exact_is_optional = true,
};

/// Oniguruma C library with ONIG_SYNTAX_RUBY and default options (reference 6.9):
/// Unicode \w \d \s (Perl-like), Ruby's always-on line anchors, full case folding.
/// Rejects a quantifier whose body is a bare assertion or an alternation offering one,
/// seen through non-capturing groups: (?:\b)*, (?:a|^)*, (?:a|(?=a))+ (captures and
/// sequences are fine: (\b)*, (?:a\b)*).
pub const oniguruma: D.Dialect = .{
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
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
    .quantify_assertions = false,
    // Lookbehind: variable-length support is uneven ((?<=a*) compiles, (?<!aa?) and
    // (?<=(?:(?:)\b)*) do not), so keep Onigmo's fixed-length rule.
    .lookbehind_fixed = true,
    .lookbehind_no_variable = true,
    .lookbehind_onig = true,
    .lazy_exact_is_optional = true,
};
