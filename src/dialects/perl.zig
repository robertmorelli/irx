//! Perl /u on character strings (exact model; reference engine perl 5.44).
//! Also the closest available model for PCRE2-family hosts.
const ucd = @import("../ucd.zig");
const D = @import("../dialect.zig");

/// \d under /u: Unicode decimal digits (Nd).
pub fn digit(c: u21) bool {
    const k = ucd.category(c);
    return k[0] == 'N' and k[1] == 'd';
}

/// \w under /u: \p{Word} ~ letters, marks, Nd, Nl, Pc, join controls.
pub fn word(c: u21, _: D.Flags) bool {
    if (c == 0x200C or c == 0x200D) return true;
    const k = ucd.category(c);
    return k[0] == 'L' or k[0] == 'M' or (k[0] == 'N' and (k[1] == 'd' or k[1] == 'l')) or (k[0] == 'P' and k[1] == 'c');
}

/// \s: White_Space (includes VT and NEL, excludes U+FEFF).
pub fn space(c: u21) bool {
    return (c >= 0x09 and c <= 0x0D) or c == 0x20 or c == 0x85 or c == 0xA0 or c == 0x1680 or (c >= 0x2000 and c <= 0x200A) or
        c == 0x2028 or c == 0x2029 or c == 0x202F or c == 0x205F or c == 0x3000;
}

fn lineTerminator(c: u21) bool {
    return c == '\n';
}

/// Perl's \h: Unicode Blank (tab plus Zs), so not U+180E (no longer Zs since Unicode 6.3).
fn hspace(c: u21) bool {
    return c != 0x180E and D.defaultHSpace(c);
}

pub const dialect: D.Dialect = .{
    .atomic_groups = true,
    .possessive = true,
    .backrefs = true,
    .extended_mode = true,
    .scoped_flags = true,
    .hv_escapes = true,
    .grapheme_escape = .extended_gb9c,
    .isHSpace = hspace,
    .unicode_props = true,
    .prop_case = .cased,
    .name = "perl",
    // An empty loop iteration ends the loop (PCRE: "the loop is forcibly broken").
    .empty_iteration = .stop,
    .empty_iteration_at_min = true,
    // Lookbehind bodies are matched forward from a start position, so an atomic group or
    // possessive loop can run past the lookbehind ((?<=a?+)a fails on "a"); the model reads
    // lookbehind right to left. Keeps them out (inherited by PCRE2 and Boost).
    .lookbehind_no_atomic = true,
    .isLineTerminator = lineTerminator,
    .isSpace = space,
    .isWord = word,
    .isDigit = digit,
    .caret_after_trailing_newline = false,
    .dollar_before_final_terminator = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    // /i uses full case folding: a pattern ß matches "ss", also when listed in a class. Subjects
    // keep these characters out (a subject ß would also match the pattern `ss`).
    .full_fold = .classes,
    .pattern_only = &.{ 0xDF, 0x1E9E, 0xFB00, 0xFB01, 0x130 },
    // Perl rejects unbounded lookbehind ("Lookbehind longer than 255").
    .lookbehind_len_cap = 16,
};

/// PCRE2 10.43+ with UCP: \w is \p{L}, \p{N}, \p{Mn}, \p{Pc} (no join controls; all of N);
/// \s is \h plus \v, whose fixed list includes U+180E MONGOLIAN VOWEL SEPARATOR.
pub fn pcre2Word(c: u21, _: D.Flags) bool {
    const k = ucd.category(c);
    return k[0] == 'L' or k[0] == 'N' or (k[0] == 'M' and k[1] == 'n') or (k[0] == 'P' and k[1] == 'c');
}
pub fn pcre2Space(c: u21) bool {
    return space(c) or c == 0x180E;
}

pub const pcre2: D.Dialect = blk: {
    var d = dialect;
    d.name = "pcre2";
    d.empty_iteration_at_min = false;
    // Bounded loops are unrolled, so an empty iteration there just counts: `(?:^|.){1,3}a` on
    // "baa" is [0,2) (Perl [0,3)).
    d.empty_iteration_bounded = false;
    // Prepend followed by an Extended_Pictographic character splits (IRX-PCRE2-6).
    d.grapheme_prepend_pict = false;
    // No GB9c (Indic conjuncts) in PCRE2 10.49.
    d.grapheme_escape = .extended;
    // Simple case folding only (ß ~ ẞ); multi-fold characters stay out of the pool.
    d.full_fold = .none;
    d.pattern_only = &.{};
    d.pool_exclude = &.{ 0xDF, 0x130 };
    d.isHSpace = D.defaultHSpace; // PCRE2's fixed \h list includes U+180E
    d.isWord = pcre2Word;
    d.isSpace = pcre2Space;
    break :blk d;
};

/// ASCII classes: \d = [0-9], \s = [\t\n\v\f\r ], \w = [0-9A-Za-z_] (Perl /a, PCRE2 without
/// UCP, Java without UNICODE_CHARACTER_CLASS).
pub fn asciiDigit(c: u21) bool {
    return c >= '0' and c <= '9';
}
pub fn asciiWord(c: u21, _: D.Flags) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or asciiDigit(c) or c == '_';
}
pub fn asciiSpace(c: u21) bool {
    return c == ' ' or (c >= 0x09 and c <= 0x0D);
}
fn asciiClasses(d0: D.Dialect, name: []const u8) D.Dialect {
    var d = d0;
    d.name = name;
    d.isWord = asciiWord;
    d.isDigit = asciiDigit;
    d.isSpace = asciiSpace;
    // \w, \d, \s are fixed ASCII sets: case-insensitivity does not close them (\w misses the
    // Kelvin sign, \W misses k).
    d.escapes_ignore_case = true;
    return d;
}

/// Perl /aa: also no case-insensitive match between ASCII and non-ASCII (K stays apart from the
/// Kelvin sign, s from ſ).
fn aaFold(c: u21) u21 {
    const f = ucd.simpleFold(c);
    return if ((c < 0x80) == (f < 0x80)) f else c;
}

pub const perl_a: D.Dialect = asciiClasses(dialect, "perl-a");
pub const perl_aa: D.Dialect = blk: {
    var d = asciiClasses(dialect, "perl-aa");
    d.fold = aaFold;
    // /aa: no ASCII/non-ASCII fold matches, so ß never matches "ss".
    d.full_fold = .none;
    d.pattern_only = &.{};
    d.pool_exclude = &.{ 0xDF, 0x130 };
    break :blk d;
};
/// PCRE2 in UTF mode without PCRE2_UCP: ASCII classes; case folding above 127 stays Unicode.
pub const pcre2_ascii: D.Dialect = asciiClasses(pcre2, "pcre2-ascii");

fn asciiFold(c: u21) u21 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
/// Boost's line separators (`.` without mod_s, ^/$ under m): \n, \f, \r, NEL, LS, PS (not \v).
fn boostLineTerminator(c: u21) bool {
    return c == 0x0A or c == 0x0C or c == 0x0D or c == 0x85 or c == 0x2028 or c == 0x2029;
}

/// Boost.Regex (boost::wregex, Perl syntax, default traits in the C locale): ASCII classes and
/// case folding, an ASCII pool, fixed-length lookbehind, no \p{…} (that needs the ICU traits).
pub const boost: D.Dialect = blk: {
    var d = asciiClasses(dialect, "boost");
    d.empty_iteration_at_min = false;
    // \X is a combining sequence, but after an optional or repeated element regex_match fails
    // (IRX-BOOST-3), which would drown other findings: no \X.
    d.grapheme_escape = .none;
    // Captures set inside an atomic group (or a possessive loop) survive when backtracking
    // abandons it (IRX-BOOST-4), which would drown capture findings: no atomic groups.
    d.atomic_groups = false;
    d.possessive = false;
    d.full_fold = .none;
    d.pattern_only = &.{};
    d.pool_exclude = &.{ 0xDF, 0x130 };
    d.fold = asciiFold;
    d.unicode_props = false;
    d.isLineTerminator = boostLineTerminator;
    // no_mod_m: $ only at the very end (Perl also matches before a final \n); under m, ^ also
    // matches at the very end after a trailing separator.
    d.dollar_before_final_terminator = false;
    d.caret_after_trailing_newline = true;
    // Lookbehind bodies must be fixed-length with no quantifier at all ((?<=(?:)?) is rejected).
    d.lookbehind_no_variable = true;
    d.lookbehind_no_quant = true; // not even {1}
    // Under m, \r\n is one line break: no ^ or $ between \r and \n.
    d.crlf_atomic = true;
    d.ascii_only = true;
    d.lookbehind_fixed = true;
    // A loop whose body matches empty at an assertion fails ((?:$)+, (?:$(?:))+ under m on "":
    // IRX-BOOST-1); nullable loop bodies only under ?.
    d.quantify_assertions = false;
    d.nullable_quant_opt_only = true;
    break :blk d;
};

/// PCRE1 8.45 with UCP: \w is \p{L}, \p{N} and _ (PCRE2 10.43 added Mn and Pc).
fn pcre1Word(c: u21, _: D.Flags) bool {
    const k = ucd.category(c);
    return c == '_' or k[0] == 'L' or k[0] == 'N';
}
pub const pcre1: D.Dialect = blk: {
    var d = pcre2;
    d.name = "pcre1";
    // Unicode 10-era grapheme data (emoji modifiers had their own class): no \X.
    d.grapheme_escape = .none;
    d.isWord = pcre1Word;
    // Fixed-length lookbehind branches only: no variable quantifier inside, not even ()?.
    d.lookbehind_no_variable = true;
    // Different-length alternatives only at the top level of a lookbehind: model it as fixed.
    d.lookbehind_fixed = true;
    // /i does not reach \p{Lu} / \p{Ll} (PCRE2 treats them as any cased letter).
    d.prop_case = .plain;
    // Older Unicode case data: no simple fold between U+0390/U+1FD3 or U+03B0/U+1FE3 (PCRE2
    // and the model fold them), and an older category for U+1F3FB (emoji modifier): keep them
    // out of the pool.
    d.pool_exclude = &.{ 0xDF, 0x130, 0x390, 0x3B0, 0x1FD3, 0x1FE3, 0x1F3FB };
    break :blk d;
};
