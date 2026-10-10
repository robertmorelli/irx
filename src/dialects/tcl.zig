//! Tcl ARE via `regexp` (reference: Tcl 9.0). \w = L | Nd | Pc, \d = Nd, \s = White_Space
//! plus U+180E U+200B U+2060 U+FEFF; word boundaries are \y / \Y. The irx m flag maps
//! to -lineanchor; without s (-linestop) neither `.` nor any negated class or escape
//! ([^..], \D, \W, \S) matches \n. -nocase: a pattern char p (each member of a class
//! or range) matches {p, upper(p), lower(p)}, with Tcl's extra ß -> ẞ uppercase.
const ucd = @import("../ucd.zig");
const atoms = @import("../atoms.zig");
const perl = @import("perl.zig");
const D = @import("../dialect.zig");

fn lineTerminator(c: u21) bool {
    return c == '\n';
}
fn word(c: u21, _: D.Flags) bool {
    const k = ucd.category(c);
    return k[0] == 'L' or (k[0] == 'N' and k[1] == 'd') or (k[0] == 'P' and k[1] == 'c');
}
fn space(c: u21) bool {
    return perl.space(c) or c == 0x180E or c == 0x200B or c == 0x2060 or c == 0xFEFF;
}

/// Tcl's uppercase table also maps ß to ẞ (no simple mapping in UnicodeData).
fn upper(c: u21) u21 {
    return if (c == 0xDF) 0x1E9E else ucd.simpleUpper(c);
}

fn variant(p: u21, c: u21) bool {
    return c == p or c == upper(p) or c == ucd.simpleLower(p);
}

fn isNegated(spec: *const atoms.AtomSpec) bool {
    if (spec.neg) return true;
    if (spec.kind != .esc) return false;
    const e: atoms.Esc = @enumFromInt(spec.sub);
    return e == .D or e == .W or e == .S;
}

fn matchAtom(spec: *const atoms.AtomSpec, flags: D.Flags, c: u21) bool {
    if (c == '\n' and !flags.s and isNegated(spec)) return false;
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
    .name = "tcl",
    .isLineTerminator = lineTerminator,
    .isSpace = space,
    .isWord = word,
    .isDigit = perl.digit,
    .matchAtom = matchAtom,
    .escapes_ignore_case = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    .named_group = .plain_capture,
    .word_boundary = "\\y",
    .nonword_boundary = "\\Y",
    .allow_lookbehind = false,
};
