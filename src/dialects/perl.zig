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

pub const dialect: D.Dialect = .{
    .scoped_flags = true,
    .unicode_props = true,
    .prop_case = .cased,
    .name = "perl",
    // An empty loop iteration ends the loop (PCRE: "the loop is forcibly broken").
    .empty_iteration = .stop,
    .isLineTerminator = lineTerminator,
    .isSpace = space,
    .isWord = word,
    .isDigit = digit,
    .caret_after_trailing_newline = false,
    .dollar_before_final_terminator = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    // /i uses full case folding: ß -> "ss", İ -> "i̇" would let one atom match two characters.
    .pool_exclude = &.{ 0xDF, 0x130 },
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
    d.isWord = pcre2Word;
    d.isSpace = pcre2Space;
    break :blk d;
};
