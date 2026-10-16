//! ICU regular expressions via NSRegularExpression (reference: macOS 27 ICU).
//! UTS #18 classes (\w ~ Perl's \p{Word}, \d = Nd, \s = White_Space), line
//! terminators \n VT FF \r \r\n NEL LS PS, $ also before a final terminator, simple case folding.
const ucd = @import("../ucd.zig");
const perl = @import("perl.zig");
const D = @import("../dialect.zig");

/// Format (Cf) and Grapheme_Extend (approximated by Mn, Me) characters are transparent to \b.
fn ignorable(c: u21) bool {
    const k = ucd.category(c);
    return (k[0] == 'C' and k[1] == 'f') or (k[0] == 'M' and (k[1] == 'n' or k[1] == 'e'));
}

/// ICU's \b (RegexMatcher::isWordBoundary): never before an ignorable character; otherwise
/// compares the current character with the nearest preceding non-ignorable one.
fn boundaryAt(w: []const u21, i: usize, flags: D.Flags) bool {
    var cur = false;
    if (i < w.len) {
        if (ignorable(w[i])) return false;
        cur = perl.word(w[i], flags);
    }
    var prev = false;
    var j = i;
    while (j > 0) {
        j -= 1;
        if (!ignorable(w[j])) {
            prev = perl.word(w[j], flags);
            break;
        }
    }
    return cur != prev;
}

fn lineTerminator(c: u21) bool {
    // ICU: \n, VT, FF, \r, NEL, LS, PS.
    return (c >= '\n' and c <= '\r') or c == 0x85 or c == 0x2028 or c == 0x2029;
}

pub const dialect: D.Dialect = .{
    .grapheme_escape = .extended_gb9c,
    .atomic_groups = true,
    .possessive = true,
    .backrefs = true,
    .extended_mode = true,
    .scoped_flags = true,
    .unicode_props = true,
    .prop_case = .equivalence_invert,
    // "Look-Behind pattern matches must have a bounded maximum length": no unbounded loops.
    .lookbehind_len_cap = 16,
    // `(?<=a??)` and `(?<=a+?)` are rejected; `(?<=a{0,1}?)` compiles.
    .lookbehind_no_lazy = true,
    .lookbehind_no_lookaround = true,
    .lookbehind_no_atomic = true,
    // Bounded repeats count an empty iteration instead of ending the loop (as PCRE2):
    // (?:^|.){0,2}a on " aaa" is [0,2) (Perl [0,3)); unbounded loops still stop.
    .empty_iteration_bounded = false,
    // Full case folding for literals under i (a pattern ß matches "ss", "ſS"); listed class
    // members use simple folding. Multi-fold characters stay out of subjects.
    .full_fold = .literals,
    .pattern_only = &.{ 0xDF, 0x1E9E, 0xFB00, 0xFB01, 0x130 },
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
    .name = "icu",
    .isLineTerminator = lineTerminator,
    .boundaryAt = boundaryAt,
    .isSpace = perl.space,
    .isWord = perl.word,
    .isDigit = perl.digit,
    .fold = ucd.simpleFold,
    .dollar_before_final_terminator = true,
    .caret_after_trailing_newline = false,
    .crlf_atomic = true,
    .caret_splits_crlf = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
};
