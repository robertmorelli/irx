//! RE# (resharp crate) in UnicodeMode::Full with multiline off (reference: resharp 0.7.5).
//! Derivative-based: no lazy quantifiers, lookbehind only at the pattern start (which
//! also rules out mid-pattern ^ \b \B, compiled as lookbehinds), no lookahead or `$`
//! under m inside unbounded `*`/`+`; `_ & ~` are operators.
const perl = @import("perl.zig");
const D = @import("../dialect.zig");

fn lineTerminator(c: u21) bool {
    return c == '\n';
}

pub const dialect: D.Dialect = .{
    .unicode_props = true,
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
    .name = "resharp",
    // Span mode: find_all reports leftmost-longest matches.
    .span_semantics = .longest,
    .isLineTerminator = lineTerminator,
    .isSpace = perl.space,
    .isWord = perl.word,
    .isDigit = perl.digit,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    .allow_lazy = false,
    .allow_lookbehind = false,
    .assertions = .{ .caret = false, .wordb = false, .nwordb = false },
    .lookahead_in_star = false,
    .extra_meta = "_&~",
    // Named groups become tags and are rejected under quantifiers; plain captures are not.
    .named_group = .plain_capture,
};
