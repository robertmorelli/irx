//! RE2 and Go regexp (RE2 syntax): ASCII-only \w, \d, \s and \b; (?i) by Unicode
//! simple case folding; `.` excludes \n only; without (?m), $ is the very end.
//! Linear time: no lookaround.
const D = @import("../dialect.zig");

fn lineTerminator(c: u21) bool {
    return c == '\n';
}
fn digit(c: u21) bool {
    return c >= '0' and c <= '9';
}
fn word(c: u21, _: D.Flags) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or digit(c) or c == '_';
}
/// \s = [\t\n\f\r ] (no \v).
fn space(c: u21) bool {
    return c == '\t' or c == '\n' or c == 0x0C or c == '\r' or c == ' ';
}

pub const dialect: D.Dialect = .{
    // Span mode: the automaton's handling of loops whose body matches empty is its own
    // ((?:\\B|a)* on "aa" -> [0,2), (?:a*?)* on "a" -> [0,0)); not modelled.
    .empty_iteration = .unmodeled,
    .name = "re2",
    .isLineTerminator = lineTerminator,
    .isSpace = space,
    .isWord = word,
    .isDigit = digit,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    .negated_escapes_invert = true,
    .allow_lookahead = false,
    .allow_lookbehind = false,
};

pub const go: D.Dialect = blk: {
    var d = dialect;
    d.name = "go";
    break :blk d;
};
