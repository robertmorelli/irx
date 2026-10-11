//! Vectorscan/Hyperscan block mode with UTF8 | UCP (reference: Vectorscan 5.4).
//! PCRE-style UCP classes (\w = L | N | _, \d = Nd, \s = White_Space), simple case
//! folding. Unsupported: lookarounds, \b/\B under UCP,
//! and ^/$ anywhere they could be embedded, so the grammar leaves all four out.
const ucd = @import("../ucd.zig");
const perl = @import("perl.zig");
const D = @import("../dialect.zig");

fn lineTerminator(c: u21) bool {
    return c == '\n';
}
fn word(c: u21, _: D.Flags) bool {
    const k = ucd.category(c);
    return c == '_' or k[0] == 'L' or k[0] == 'N';
}

pub const dialect: D.Dialect = .{
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
    .name = "vectorscan",
    .isLineTerminator = lineTerminator,
    .isSpace = perl.space,
    .isWord = word,
    .isDigit = perl.digit,
    .fold = ucd.simpleFold,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    .allow_lookahead = false,
    .allow_lookbehind = false,
    .assertions = .{ .caret = false, .dollar = false, .wordb = false, .nwordb = false },
};
