//! Ruby (Onigmo, reference: Ruby 4.0): ASCII \w \d \s but Unicode \b; ^ and $ are always line
//! anchors (Ruby's /m is dotall, mapped from irx's s flag); full Unicode case
//! folding, so multi-character folds (ß, İ) are kept out of the pool.
const std = @import("std");
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
    .grapheme_escape = .extended_gb9c,
    .atomic_groups = true,
    .possessive = true,
    .backrefs = true,
    .possessive_counted = false,
    .backref_by_name = true,
    .extended_mode = true,
    .scoped_flags = true,
    .props_multi_fold = true,
    // Ruby's m is dotall; ^ and $ always match at lines, so there is no scoped m.
    .scoped_mods = 1 | 2,
    .dotall_letter = 'm',
    .unicode_props = true,
    .prop_case = .equivalence_invert,
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
    // Full case folding under i: a pattern ß (also listed in a class or inside a range) matches
    // "ss"; subjects keep multi-fold characters out.
    .full_fold = .ranges,
    .pattern_only = &.{ 0xDF, 0x1E9E, 0xFB00, 0xFB01, 0x130 },
    // Onigmo lookbehind: fixed length, no variable quantifiers, no lookahead inside, and no
    // atomic group or possessive quantifier ((?<=(?>a))b, (?<=a?+)b: "invalid pattern in
    // look-behind"; C Oniguruma accepts both).
    .lookbehind_no_atomic = true,
    .lookbehind_fixed = true,
    .lookbehind_no_variable = true,
    .lookbehind_onig = true,
    .lazy_exact_is_optional = true,
    // Capture mode: with named groups present, unnamed ones don't capture.
    .named_groups_only = true,
};

/// Oniguruma C library with ONIG_SYNTAX_RUBY and default options (reference 6.9):
/// Unicode \w \d \s (Perl-like), Ruby's always-on line anchors, full case folding.
/// Rejects a quantifier whose body is a bare assertion or an alternation offering one,
/// seen through non-capturing groups: (?:\b)*, (?:a|^)*, (?:a|(?=a))+ (captures and
/// sequences are fine: (\b)*, (?:a\b)*).
/// Oniguruma's Unicode \w: Perl's \p{Word} without the join controls (ZWNJ, ZWJ).
fn onigWord(c: u21, f: D.Flags) bool {
    return c != 0x200C and c != 0x200D and perl.word(c, f);
}

pub const oniguruma: D.Dialect = .{
    // No GB9c (Indic conjuncts) in Oniguruma 6.9.10.
    .grapheme_escape = .extended,
    .atomic_groups = true,
    .possessive = true,
    .backrefs = true,
    .possessive_counted = false,
    .backref_by_name = true,
    .extended_mode = true,
    .scoped_flags = true,
    .props_multi_fold = true,
    // Ruby's m is dotall; ^ and $ always match at lines, so there is no scoped m.
    .scoped_mods = 1 | 2,
    .dotall_letter = 'm',
    .unicode_props = true,
    .prop_case = .plain,
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
    .name = "oniguruma",
    .isLineTerminator = lineTerminator,
    .isSpace = perl.space,
    .isWord = onigWord,
    .isDigit = perl.digit,
    .anchors_always_multiline = true,
    .caret_after_trailing_newline = false,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    // Full case folding under i: a pattern ß (also listed in a class or inside a range) matches
    // "ss"; subjects keep multi-fold characters out.
    .full_fold = .ranges,
    .pattern_only = &.{ 0xDF, 0x1E9E, 0xFB00, 0xFB01, 0x130 },
    .quantify_assertions = false,
    // Lookbehind: variable-length support is uneven ((?<=a*) compiles, (?<!aa?) and
    // (?<=(?:(?:)\b)*) do not), so keep Onigmo's fixed-length rule.
    .lookbehind_fixed = true,
    .lookbehind_no_variable = true,
    .lookbehind_onig = true,
    .lazy_exact_is_optional = true,
    // Capture mode: with named groups present, unnamed ones don't capture.
    .named_groups_only = true,
};

/// Oniguruma with its Perl, Java or Python syntax (the host writes \x{H} as a literal for Java
/// and Python syntax, which lack it) (IRX_ONIG_SYNTAX): the same matcher, but ^ and $
/// start single-line (string ends, $ also before a final \n) and (?m) / the m flag make them line
/// anchors; (?s) is dotall. Python syntax spells named groups (?P<…>).
fn onigSyntax(name: []const u8, p_angle: bool) D.Dialect {
    var d = oniguruma;
    d.name = name;
    d.anchors_always_multiline = false;
    d.dollar_before_final_terminator = true;
    d.scoped_mods = 1 | 2 | 4;
    d.dotall_letter = 's';
    // Perl and Java syntax reject (?<name>…): plain captures; Python syntax spells (?P<name>…).
    d.named_group = if (p_angle) .p_angle else .plain_capture;
    // Ruby's rules do not apply here: unnamed groups capture next to named ones, and
    // backreferences may be numbered.
    d.named_groups_only = false;
    d.backref_by_name = false;
    // $ (end or before a final newline) is rejected inside lookbehind.
    d.lookbehind_no_dollar = true;
    // Java and Python syntax have no \X grapheme escape.
    if (!std.mem.eql(u8, name, "onig-perl")) d.grapheme_escape = .none;
    // Python syntax has no possessive quantifiers (a*+ is a repeated a*).
    if (std.mem.eql(u8, name, "onig-python")) d.possessive = false;
    return d;
}
pub const onig_perl: D.Dialect = onigSyntax("onig-perl", false);
pub const onig_java: D.Dialect = onigSyntax("onig-java", false);
pub const onig_python: D.Dialect = onigSyntax("onig-python", true);
/// IRX_ONIG_ASCII: ONIG_OPTION_{WORD,DIGIT,SPACE,POSIX}_IS_ASCII.
pub const onig_ascii: D.Dialect = blk: {
    var d = oniguruma;
    d.name = "onig-ascii";
    d.isWord = perl.asciiWord;
    d.isDigit = perl.asciiDigit;
    d.isSpace = perl.asciiSpace;
    d.escapes_ignore_case = true;
    break :blk d;
};
