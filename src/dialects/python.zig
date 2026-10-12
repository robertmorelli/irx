//! Python `re` on str patterns (exact model; reference engine CPython 3.14).
//! \w = str.isalnum() or '_' (letters + all numerics), \d = Nd, \s = str.isspace().
//! IGNORECASE: simple lowercase mapping plus sre's fixed equivalence groups.
const ucd = @import("../ucd.zig");
const D = @import("../dialect.zig");
const perl = @import("perl.zig");

fn lineTerminator(c: u21) bool {
    return c == '\n';
}
fn digit(c: u21) bool {
    const k = ucd.category(c);
    return k[0] == 'N' and k[1] == 'd';
}
fn word(c: u21, _: D.Flags) bool {
    if (c == '_') return true;
    const k = ucd.category(c);
    return k[0] == 'L' or k[0] == 'N';
}
/// str.isspace(): bidi classes WS/B/S plus Zs; i.e. White_Space plus U+001C..U+001F.
fn space(c: u21) bool {
    return (c >= 0x09 and c <= 0x0D) or (c >= 0x1C and c <= 0x20) or c == 0x85 or c == 0xA0 or c == 0x1680 or
        (c >= 0x2000 and c <= 0x200A) or c == 0x2028 or c == 0x2029 or c == 0x202F or c == 0x205F or c == 0x3000;
}

/// sre_compile._equivalences: characters that also match case-insensitively.
const equivalences = [_][]const u21{
    &.{ 0x69, 0x131 },          &.{ 0x73, 0x17f },  &.{ 0xb5, 0x3bc },  &.{ 0x345, 0x3b9, 0x1fbe },
    &.{ 0x390, 0x1fd3 },        &.{ 0x3b0, 0x1fe3 }, &.{ 0x3b2, 0x3d0 }, &.{ 0x3b5, 0x3f5 },
    &.{ 0x3b8, 0x3d1 },         &.{ 0x3ba, 0x3f0 },  &.{ 0x3c0, 0x3d6 }, &.{ 0x3c1, 0x3f1 },
    &.{ 0x3c2, 0x3c3 },         &.{ 0x3c6, 0x3d5 },  &.{ 0x1e61, 0x1e9b }, &.{ 0xfb05, 0xfb06 },
};

fn simpleLower(c: u21) u21 {
    return ucd.simpleLower(c);
}

fn fold(c: u21) u21 {
    const l = simpleLower(c);
    for (equivalences) |g| {
        for (g) |m| if (m == l) return g[0];
    }
    return l;
}

pub const dialect: D.Dialect = .{
    .atomic_groups = true,
    .possessive = true,
    .backrefs = true,
    .extended_mode = true,
    .scoped_flags = true,
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
    .name = "python",
    .isLineTerminator = lineTerminator,
    .isSpace = space,
    .isWord = word,
    .isDigit = digit,
    .fold = fold,
    .dollar_before_final_terminator = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    .named_group = .p_angle,
    .lookbehind_fixed = true,
};

/// The third-party `regex` module (default VERSION0): Perl-like Unicode classes (\w = \p{Word},
/// \s = White_Space), `re`'s case equivalences (i, I, ı, İ are one class), \p{…} with Lu/Ll
/// standing for any cased letter under IGNORECASE, and variable-length lookbehind.
pub const regex_module: D.Dialect = blk: {
    var d = dialect;
    d.name = "python-regex";
    d.isWord = perl.word;
    d.isSpace = perl.space;
    d.unicode_props = true;
    d.prop_case = .cased;
    d.lookbehind_fixed = false;
    // IGNORECASE relates ı to I and İ to i but not ı to İ: not an equivalence, so not a fold
    // function; ı and İ stay out of the pool.
    d.pool_exclude = &.{ 0x130, 0x131 };
    break :blk d;
};
