//! java.util.regex with UNICODE_CASE | UNICODE_CHARACTER_CLASS (reference: OpenJDK 23).
//! Classes as Perl's \p{Word}/Nd/White_Space; line terminators \n \r \r\n NEL LS PS;
//! case-insensitive by lower(upper(c)) on both sides. (Java itself compiles a literal
//! without simple case mappings, e.g. ß, as an exact match, so ß fails to match ẞ
//! while ẞ matches ß; the model keeps the symmetric rule and that asymmetry shows up
//! as mismatches.)
const ucd = @import("../ucd.zig");
const perl = @import("perl.zig");
const atoms = @import("../atoms.zig");
const D = @import("../dialect.zig");

fn lineTerminator(c: u21) bool {
    return c == '\n' or c == '\r' or c == 0x85 or c == 0x2028 or c == 0x2029;
}

fn fold(c: u21) u21 {
    return ucd.simpleLower(ucd.simpleUpper(c));
}

/// Ranges under CASE_INSENSITIVE: c, upper(c), lower(c) or lower(upper(c)) inside the range
/// (so K matches [a-z] but not [A-Z]); literals and members use `fold`.
fn matchAtom(spec: *const atoms.AtomSpec, flags: D.Flags, c: u21) bool {
    if (spec.kind == .range and flags.i) {
        const lo = spec.syms[0];
        const hi = spec.syms[1];
        const in = struct {
            fn f(x: u21, l: u21, h: u21) bool {
                return x >= l and x <= h;
            }
        }.f;
        const hit = in(c, lo, hi) or in(ucd.simpleUpper(c), lo, hi) or in(ucd.simpleLower(c), lo, hi) or in(fold(c), lo, hi);
        return hit != spec.neg;
    }
    return atoms.matchesGeneric(spec, flags, c);
}

pub const dialect: D.Dialect = .{
    // "Look-behind group does not have an obvious maximum length": unbounded repeats of
    // groups are rejected; `(?<=a*)` compiles (and IRX-JAVA-3 shows it misbehaves).
    .lookbehind_no_unbounded_group = true,
    .name = "java",
    .isLineTerminator = lineTerminator,
    .isSpace = perl.space,
    .isWord = perl.word,
    .isDigit = perl.digit,
    .fold = fold,
    .matchAtom = matchAtom,
    .caret_after_trailing_newline = false,
    .caret_m_never_at_end = true,
    .dollar_before_final_terminator = true,
    .crlf_atomic = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
};
