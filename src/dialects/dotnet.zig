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

/// \b also counts ZWNJ and ZWJ as word characters (RegexCharClass.IsBoundaryWordChar).
fn boundaryWord(c: u21, f: D.Flags) bool {
    return c == 0x200C or c == 0x200D or word(c, f);
}

pub const dialect: D.Dialect = .{
    // An atomic group as a loop body is backtracked into, or not given back (IRX-DOTNET-11),
    // which would drown other findings: no atomic groups.
    .atomic_groups = false,
    .backrefs = true,
    .named_groups_last = true,
    .extended_mode = true,
    .scoped_flags = true,
    .isBoundaryWord = boundaryWord,
    .unicode_props = true,
    // IgnoreCase widens \p{Lu} and \p{Ll} to every cased letter (Lu, Ll, Lt).
    .prop_case = .cased,
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
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
    d.atomic_groups = false;
    d.backrefs = false;
    // Span mode: NonBacktracking reports the backtracking engines' match, but loops whose body
    // can match empty follow neither the ES nor the Perl rule ((?:a??)* on "a" -> [0,0),
    // (?:(?:\\b)?|aa)+ on "aaaaaa" -> [0,6)); not modelled.
    d.empty_iteration = .unmodeled;
    d.allow_lookahead = false;
    d.allow_lookbehind = false;
    break :blk d;
};

/// RegexOptions.Compiled on .NET 9: a lazy loop inside a lookbehind can crash code generation
/// ("Bad label content in ILGenerator": IRX-DOTNET-2, fixed in .NET 11), so none are generated.
pub const compiled: D.Dialect = blk: {
    var d = dialect;
    d.name = "dotnet-compiled";
    d.lookbehind_no_lazy = true;
    break :blk d;
};

/// RegexCharClass.ECMAWordClass: [0-9A-Z_a-z] plus U+0130 (İ).
fn ecmaWord(c: u21, f: D.Flags) bool {
    return c == 0x130 or perl.asciiWord(c, f);
}

/// RegexOptions.ECMAScript: ECMAScript-style classes (\w = ECMAWordClass, \d = [0-9], ASCII
/// \s) and word boundaries on the same .NET matcher; no Singleline.
pub const ecma: D.Dialect = blk: {
    var d = dialect;
    d.name = "dotnet-ecma";
    d.isWord = ecmaWord;
    d.isDigit = perl.asciiDigit;
    d.isSpace = perl.asciiSpace;
    d.isBoundaryWord = null;
    d.escapes_ignore_case = true;
    d.extended_mode = false; // ECMAScript excludes IgnorePatternWhitespace
    break :blk d;
};
