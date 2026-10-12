//! ICU regular expressions via NSRegularExpression (reference: macOS 27 ICU).
//! UTS #18 classes (\w ~ Perl's \p{Word}, \d = Nd, \s = White_Space), line
//! terminators \n \r \r\n NEL LS PS, $ also before a final terminator, simple case folding.
const ucd = @import("../ucd.zig");
const perl = @import("perl.zig");
const D = @import("../dialect.zig");

fn lineTerminator(c: u21) bool {
    return c == '\n' or c == '\r' or c == 0x85 or c == 0x2028 or c == 0x2029;
}

pub const dialect: D.Dialect = .{
    .scoped_flags = true,
    .unicode_props = true,
    .prop_case = .equivalence_invert,
    // "Look-Behind pattern matches must have a bounded maximum length": no unbounded loops.
    .lookbehind_len_cap = 16,
    // `(?<=a??)` and `(?<=a+?)` are rejected; `(?<=a{0,1}?)` compiles.
    .lookbehind_no_lazy = true,
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
    .name = "icu",
    .isLineTerminator = lineTerminator,
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
