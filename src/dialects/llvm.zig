//! llvm::Regex (Henry Spencer POSIX ERE over bytes, reference: LLVM 21) via the host's
//! Perl-to-ERE translation; modelled on ASCII only (`.` and classes see UTF-8 bytes).
//! C-locale classes, ASCII case folding. Without m, `.` matches \n; with m
//! (REG_NEWLINE) neither `.` nor a negated class matches \n and ^/$ match at lines.
//! No lookarounds, lazy quantifiers or \b.
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
    return c == ' ' or (c >= 0x09 and c <= 0x0D);
}
fn fold(c: u21) u21 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

fn negated(spec: *const atoms.AtomSpec) bool {
    if (spec.neg) return true;
    if (spec.kind != .esc) return false;
    const e: atoms.Esc = @enumFromInt(spec.sub);
    return e == .D or e == .W or e == .S;
}

fn matchAtom(spec: *const atoms.AtomSpec, flags: D.Flags, c: u21) bool {
    if (c == '\n' and flags.m and negated(spec)) return false;
    return atoms.matchesGeneric(spec, flags, c);
}

pub const dialect: D.Dialect = .{
    .name = "llvm",
    .isLineTerminator = lineTerminator,
    .isSpace = space,
    .isWord = word,
    .isDigit = digit,
    .fold = fold,
    .matchAtom = matchAtom,
    .dot_all_unless_m = true,
    .escape = .x_brace,
    .any_char = .space_or_nonspace,
    .strings = .code_points,
    .ascii_only = true,
    .allow_lookahead = false,
    .allow_lookbehind = false,
    .allow_lazy = false,
    .assertions = .{ .wordb = false, .nwordb = false },
};
