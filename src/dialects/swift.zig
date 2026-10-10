//! Swift Regex with .unicodeScalar semantics and .simple word boundaries (exact
//! model; reference engine Swift 6.4). Rules established by probing Swift; the
//! self-check verifies them independently.
const ucd = @import("../ucd.zig");
const atoms = @import("../atoms.zig");
const perl = @import("perl.zig");
const D = @import("../dialect.zig");

fn lineTerminator(c: u21) bool {
    return (c >= 0x0A and c <= 0x0D) or c == 0x85 or c == 0x2028 or c == 0x2029;
}

/// \w: alphabetic (letters, Nl), '_' and ASCII digits; not other Nd, No or marks.
fn word(c: u21, _: D.Flags) bool {
    if (c == '_' or (c >= '0' and c <= '9')) return true;
    const k = ucd.category(c);
    return k[0] == 'L' or (k[0] == 'N' and k[1] == 'l');
}

/// \d: any numeric character (Nd, Nl, No).
fn digit(c: u21) bool {
    return ucd.category(c)[0] == 'N';
}

fn asciiLower(c: u21) u21 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

/// Case-insensitive class member: ASCII members match only ASCII subjects
/// (ASCII case-insensitively); other members match when single-scalar
/// lowercase mappings agree.
fn member(m: u21, c: u21) bool {
    if (m < 0x80) return c < 0x80 and asciiLower(c) == asciiLower(m);
    return ucd.lower1(c) == ucd.lower1(m);
}

fn matchAtom(spec: *const atoms.AtomSpec, flags: D.Flags, c: u21) bool {
    switch (spec.kind) {
        .lit => return if (flags.i) ucd.lower1(c) == ucd.lower1(spec.syms[0]) else c == spec.syms[0],
        .cls, .range => {
            var hit = false;
            if (spec.kind == .cls) {
                for (spec.syms[0..spec.n]) |m| hit = hit or (if (flags.i) member(m, c) else m == c);
            } else {
                const lo = spec.syms[0];
                const hi = spec.syms[1];
                hit = c >= lo and c <= hi;
                if (!hit and flags.i and lo < 0x80 and hi < 0x80 and c < 0x80) {
                    const l = asciiLower(c);
                    const u: u21 = if (l >= 'a' and l <= 'z') l - 32 else l;
                    hit = (l >= lo and l <= hi) or (u >= lo and u <= hi);
                }
            }
            return hit != spec.neg;
        },
        // Escapes and '.': property tests, unaffected by case-insensitivity.
        else => return atoms.matchesCaseless(spec, flags, c),
    }
}

pub const dialect: D.Dialect = .{
    .name = "swift",
    .isLineTerminator = lineTerminator,
    .isSpace = perl.space,
    .isWord = word,
    .isDigit = digit,
    .matchAtom = matchAtom,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .code_points_only = true,
};
