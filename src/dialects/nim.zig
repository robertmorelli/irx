//! nim-regex (re2 API, reference: nim-regex 0.26): Perl-like Unicode classes,
//! `(?P<name>...)` groups, `$` only at the very end without m. Case-insensitive
//! ranges add only the simple upper/lower partners of their members (so ſ and the
//! Kelvin sign miss [a-z] although they match s and k as literals).
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
        const u = ucd.simpleUpper(c);
        const l = ucd.simpleLower(c);
        const hit = in(c, lo, hi) or (in(u, lo, hi) and ucd.simpleLower(u) == c) or (in(l, lo, hi) and ucd.simpleUpper(l) == c);
        return hit != spec.neg;
    }
    return atoms.matchesGeneric(spec, flags, c);
}

pub const dialect: D.Dialect = blk: {
    var d = perl.dialect;
    d.name = "nim";
    d.named_group = .p_angle;
    d.dollar_before_final_terminator = false;
    d.caret_after_trailing_newline = true;
    d.matchAtom = matchAtom;
    break :blk d;
};
