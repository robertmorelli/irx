//! Emacs Lisp regexps (reference: Emacs 31.1, -Q --batch), reached through the host's
//! Perl-to-Emacs translation. \w, \b and [[:space:]] follow the *scratch* buffer's
//! syntax table (most non-ASCII is word syntax, `_` is symbol syntax, \n is a comment
//! ender, not whitespace); \d is [0-9]. \b also holds at the string edges and between
//! word chars of different scripts (category.c word_boundary_p). ^ and $ are always line anchors, and
//! case-fold-search canonicalizes both sides (ς Σ -> σ, ẞ -> ß, but ſ and the Kelvin
//! sign stay distinct). No lookarounds.
const tables = @import("emacs_tables.zig");
const ucd = @import("../ucd.zig");
const D = @import("../dialect.zig");

fn inRanges(rs: []const [2]u21, c: u21) bool {
    var lo: usize = 0;
    var hi: usize = rs.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (rs[mid][1] < c) lo = mid + 1 else if (rs[mid][0] > c) hi = mid else return true;
    }
    return false;
}

fn lineTerminator(c: u21) bool {
    return c == '\n';
}
fn digit(c: u21) bool {
    return c >= '0' and c <= '9';
}
fn word(c: u21, _: D.Flags) bool {
    return inRanges(&tables.word, c);
}
fn space(c: u21) bool {
    return inRanges(&tables.space, c);
}
fn fold(c: u21) u21 {
    var lo: usize = 0;
    var hi: usize = tables.canon.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (tables.canon[mid][0] < c) lo = mid + 1 else if (tables.canon[mid][0] > c) hi = mid else return tables.canon[mid][1];
    }
    return c;
}

fn script(c: u21) u21 {
    var lo: usize = 0;
    var hi: usize = tables.scripts.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (tables.scripts[mid][1] < c) lo = mid + 1 else if (tables.scripts[mid][0] > c) hi = mid else return tables.scripts[mid][2];
    }
    return 0xFFFF;
}

fn has(rs: []const [2]u21, c: u21) bool {
    return inRanges(rs, c);
}

/// category.c word_boundary_p: a (cat1 . cat2) entry matches when c1 has cat1 and c2 does not,
/// and c2 has cat2 and c1 does not (nil matches anything).
fn catPair(c1: u21, c2: u21, cat1: ?[]const [2]u21, cat2: ?[]const [2]u21) bool {
    if (cat1) |k| if (!has(k, c1) or has(k, c2)) return false;
    if (cat2) |k| if (has(k, c1) or !has(k, c2)) return false;
    return true;
}

/// regex-emacs.c wordbound: \b holds at the string edges, where word syntax changes, and
/// between two word chars when WORD_BOUNDARY_P: never for two single-byte chars (< 256);
/// otherwise category.c word_boundary_p. Different scripts are a boundary unless an entry of
/// word-combining-categories ((nil . ^) (^ . nil) (C . H) (C . K)) matches; the same script
/// is not, unless word-separating-categories ((H . K)) matches.
fn boundaryAt(w: []const u21, i: usize, flags: D.Flags) bool {
    if (i == 0 or i == w.len) return true;
    const a = w[i - 1];
    const b = w[i];
    const wa = word(a, flags);
    if (wa != word(b, flags)) return true;
    if (!wa) return false;
    if (a < 0x100 and b < 0x100) return false;
    if (script(a) == script(b)) return catPair(a, b, &tables.cat_hiragana, &tables.cat_katakana);
    const combine = catPair(a, b, null, &tables.cat_combining) or catPair(a, b, &tables.cat_combining, null) or
        catPair(a, b, &tables.cat_chinese, &tables.cat_hiragana) or catPair(a, b, &tables.cat_chinese, &tables.cat_katakana);
    return !combine;
}

pub const dialect: D.Dialect = .{
    // The host drops the lazy `?` after `{m,n}` (Emacs would read it as optional).
    .lazy_counted_is_greedy = true,
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
    .name = "emacs",
    .isLineTerminator = lineTerminator,
    .isSpace = space,
    .isWord = word,
    .isDigit = digit,
    .fold = fold,
    .anchors_always_multiline = true,
    .boundaryAt = boundaryAt,
    .escapes_ignore_case = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    .allow_lookahead = false,
    .allow_lookbehind = false,
};
