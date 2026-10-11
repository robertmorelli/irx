//! Racket `pregexp` (reference: Racket 9.3). ASCII \w \d \s (\s = space \t \n \f \r),
//! `$` only at the end without m; the irx m flag maps to Racket's multi mode, which
//! is also what keeps `.` off \n (without m, `.` matches everything; [^..] always
//! matches \n). Case-insensitive: a pattern char p matches exactly
//! {p, upcase(p), downcase(p), foldcase(p)} (asymmetric: ſ matches s, s does not
//! match ſ). Quantifiers other than `?` reject bodies that can match empty;
//! lookbehind must be bounded.
const ucd = @import("../ucd.zig");
const atoms = @import("../atoms.zig");
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
fn space(c: u21) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == 0x0C or c == '\r';
}

/// Does pattern char p match subject c under (?i:)?
fn variant(p: u21, c: u21) bool {
    return c == p or c == ucd.simpleUpper(p) or c == ucd.simpleLower(p) or c == ucd.simpleFold(p);
}

fn matchAtom(spec: *const atoms.AtomSpec, flags: D.Flags, c: u21) bool {
    if (!flags.i) return atoms.matchesGeneric(spec, flags, c);
    switch (spec.kind) {
        .lit => return variant(spec.syms[0], c),
        .cls => {
            var hit = false;
            for (spec.syms[0..spec.n]) |m| hit = hit or variant(m, c);
            return hit != spec.neg;
        },
        .range => {
            const lo = spec.syms[0];
            const hi = spec.syms[1];
            var hit = c >= lo and c <= hi;
            var m = lo;
            while (!hit and m <= hi) : (m += 1) hit = variant(m, c);
            return hit != spec.neg;
        },
        else => return atoms.matchesGeneric(spec, flags, c),
    }
}

pub const dialect: D.Dialect = .{
    // An empty loop iteration ends the loop (span mode; checked against the engine).
    .empty_iteration = .stop,
    .name = "racket",
    .isLineTerminator = lineTerminator,
    .isSpace = space,
    .isWord = word,
    .isDigit = digit,
    .matchAtom = matchAtom,
    .escapes_ignore_case = true,
    .dot_all_unless_m = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    .nullable_quant_opt_only = true,
    .lookbehind_len_cap = 16,
};
