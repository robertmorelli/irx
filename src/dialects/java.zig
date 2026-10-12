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
    .atomic_groups = true,
    .possessive = true,
    .backrefs = true,
    .extended_mode = true,
    .hv_escapes = true,
    .scoped_flags = true,
    .unicode_props = true,
    .prop_case = .equivalence_invert,
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
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

/// Pattern.Bound: a side counts as a word character if it is \w, or a non-spacing mark whose
/// run of marks starts after a letter or digit (hasBaseCharacter uses Unicode isLetterOrDigit).
fn markWithBase(w: []const u21, i: usize) bool {
    var x = i + 1;
    while (x > 0) {
        x -= 1;
        // codePointAt steps back one UTF-16 unit: an astral base is seen as its low surrogate.
        if (w[x] > 0xFFFF) return false;
        const k = ucd.category(w[x]);
        if (k[0] == 'L' or (k[0] == 'N' and k[1] == 'd')) return true;
        if (!(k[0] == 'M' and k[1] == 'n')) return false;
    }
    return false;
}
fn boundSide(w: []const u21, i: usize, f: D.Flags) bool {
    const c = w[i];
    if (perl.asciiWord(c, f)) return true;
    const k = ucd.category(c);
    return k[0] == 'M' and k[1] == 'n' and markWithBase(w, i);
}
fn asciiBoundaryAt(w: []const u21, i: usize, f: D.Flags) bool {
    const left = i > 0 and boundSide(w, i - 1, f);
    const right = i < w.len and boundSide(w, i, f);
    return left != right;
}

/// Java without UNICODE_CHARACTER_CLASS (UNICODE_CASE kept): ASCII \d, \s, \w; \b follows \w
/// (JDK 19+) plus the non-spacing-mark rule above.
pub const ascii: D.Dialect = blk: {
    var d = dialect;
    d.name = "java-ascii";
    d.isWord = perl.asciiWord;
    d.isDigit = perl.asciiDigit;
    d.isSpace = perl.asciiSpace;
    d.escapes_ignore_case = true;
    d.boundaryAt = asciiBoundaryAt;
    break :blk d;
};
