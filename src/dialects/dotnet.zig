//! .NET Regex with RegexOptions.CultureInvariant (reference: .NET 9). Strings are
//! UTF-16 code units (`.` consumes half an astral character). \w = [\p{L}\p{Mn}\p{Nd}\p{Pc}],
//! \d = Nd, \s = White_Space, only \n is a line terminator, $ also before a final \n.
//! IgnoreCase compares single-scalar lowercase mappings. The interpreter, Compiled
//! and NonBacktracking engines share these semantics (NonBacktracking: no lookaround).
const ucd = @import("../ucd.zig");
const perl = @import("perl.zig");
const D = @import("../dialect.zig");

fn lineTerminator(c: u21) bool {
    return c == '\n';
}
fn word(c: u21, _: D.Flags) bool {
    const k = ucd.category(c);
    return k[0] == 'L' or (k[0] == 'M' and k[1] == 'n') or (k[0] == 'N' and k[1] == 'd') or (k[0] == 'P' and k[1] == 'c');
}

pub const dialect: D.Dialect = .{
    .name = "dotnet",
    .isLineTerminator = lineTerminator,
    .isSpace = perl.space,
    .isWord = word,
    .isDigit = perl.digit,
    .fold = ucd.lower1,
    .dollar_before_final_terminator = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .utf16_units,
};

pub const nonbacktracking: D.Dialect = blk: {
    var d = dialect;
    d.name = "dotnet-nonbacktracking";
    d.allow_lookahead = false;
    d.allow_lookbehind = false;
    break :blk d;
};
