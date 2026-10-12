//! nim-regex (re2 API, reference: nim-regex 0.26): Perl-like Unicode classes,
//! `(?P<name>...)` groups, `$` only at the very end without m. Case-insensitive
//! ranges also accept the ranges between the endpoints' simple lower and upper forms (so ſ
//! and the Kelvin sign miss [a-z] although they match s and k as literals, and [à-ÿ] takes
//! all of U+00C0..U+0178: IRX-NIM-1).
const ucd = @import("../ucd.zig");
const atoms = @import("../atoms.zig");
const perl = @import("perl.zig");
const D = @import("../dialect.zig");

fn matchAtom(spec: *const atoms.AtomSpec, flags: D.Flags, c: u21) bool {
    if (spec.kind == .range and flags.i) {
        const lo = spec.syms[0];
        const hi = spec.syms[1];
        const in = struct {
            fn f(x: u21, l: u21, h: u21) bool {
                return x >= l and x <= h;
            }
        }.f;
        const hit = in(c, lo, hi) or in(c, ucd.simpleLower(lo), ucd.simpleLower(hi)) or in(c, ucd.simpleUpper(lo), ucd.simpleUpper(hi));
        return hit != spec.neg;
    }
    return atoms.matchesGeneric(spec, flags, c);
}

pub const dialect: D.Dialect = blk: {
    var d = perl.dialect;
    d.name = "nim";
    d.atomic_groups = false;
    d.possessive = false;
    d.backrefs = false;
    d.named_group = .p_angle;
    d.dollar_before_final_terminator = false;
    d.caret_after_trailing_newline = true;
    d.matchAtom = matchAtom;
    d.prop_case = .plain; // \p{Lu} under /i still matches only uppercase
    // `(?<=)`, `(?=)`, `(?<=|b)` are syntax errors; `(?=(?:))` and `(?=a|)` are fine.
    d.bare_empty_in_lookaround = false;
    // {m,n} around a lookaround aborts the compiler (NIM-1, reported upstream).
    d.counted_lookaround = false;
    break :blk d;
};
