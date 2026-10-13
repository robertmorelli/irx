//! Symbol model: flags, decoding of UTF-16 subjects into symbols (code units
//! without u/v, code points with u/v), line terminators, word characters,
//! whitespace, and Canonicalize for i / iu / iv.
const std = @import("std");
const ucd = @import("ucd.zig");

pub const Flags = packed struct(u8) {
    i: bool = false,
    m: bool = false,
    s: bool = false,
    u: bool = false,
    v: bool = false,
    /// Scoped-only modes (flag groups, never a pattern's flags): Rust's CRLF mode (?R:…) and
    /// swap-greed mode (?U:…).
    crlf: bool = false,
    swap: bool = false,
    _pad: u1 = 0,

    pub fn unicode(f: Flags) bool {
        return f.u or f.v;
    }
    pub fn bits(f: Flags) u8 {
        return @bitCast(f);
    }
    pub fn fromBits(b: u8) Flags {
        return @bitCast(b & 0x1f);
    }
    pub fn valid(f: Flags) bool {
        return !(f.u and f.v);
    }
    /// JS flags string, fixed order.
    pub fn str(f: Flags, buf: *[8]u8) []const u8 {
        var n: usize = 0;
        if (f.i) {
            buf[n] = 'i';
            n += 1;
        }
        if (f.m) {
            buf[n] = 'm';
            n += 1;
        }
        if (f.s) {
            buf[n] = 's';
            n += 1;
        }
        if (f.u) {
            buf[n] = 'u';
            n += 1;
        }
        if (f.v) {
            buf[n] = 'v';
            n += 1;
        }
        return buf[0..n];
    }
    pub fn parse(s: []const u8) !Flags {
        var f: Flags = .{};
        for (s) |c| switch (c) {
            'i' => f.i = true,
            'm' => f.m = true,
            's' => f.s = true,
            'u' => f.u = true,
            'v' => f.v = true,
            else => return error.BadFlag,
        };
        if (!f.valid()) return error.BadFlag;
        return f;
    }
};

/// All 24 valid flag sets (u and v mutually exclusive), in bit order.
pub const all_flag_sets: [24]Flags = blk: {
    var out: [24]Flags = undefined;
    var n: usize = 0;
    for (0..32) |b| {
        const f = Flags.fromBits(b);
        if (f.valid()) {
            out[n] = f;
            n += 1;
        }
    }
    break :blk out;
};

pub const astral_char: u21 = 0x1F600;

/// Default pool, as code points. Order is the canonical printing/mask order.
/// Original 15-symbol pool.
pub const base_pool = [_]u21{ 'a', 'b', 'k', 's', 'A', 'K', 'S', '0', '_', ' ', '\n', 0x017F, 0x212A, 0x2028, astral_char };
/// Default pool: base plus Latin-1 and other characters with tricky case or
/// escaping behaviour (à é ß İ ı σ ς Σ, CR, '-', '.').
pub const default_pool = base_pool ++ [_]u21{ 0xE0, 0xE9, 0xDF, 0x130, 0x131, 0x3C3, 0x3C2, 0x3A3, '\r', '-', '.' };
/// Active pool (set from the config at startup).
pub var active_pool: []const u21 = &default_pool;

pub const max_symbols = 32;

/// Alternate pools for pool rotation (config pool_rotation): a few ASCII anchors plus one
/// family of characters engines treat differently.
/// Case folding: long s, Kelvin, sharp s and capital sharp s, ligatures, dotted/dotless i,
/// Dž-style digraphs (title case), final sigma, micro sign, Angstrom sign.
pub const fold_pool = [_]u21{ 'a', 'A', 'k', 'K', 's', 'S', 'i', 'I', 'f', 'F', ' ', '\n', 0x017F, 0x212A, 0x00DF, 0x1E9E, 0xFB00, 0xFB01, 0x0130, 0x0131, 0x01C4, 0x01C5, 0x01C6, 0x03C2, 0x03C3, 0x03A3, 0x00B5, 0x03BC, 0x212B, 0x00E5 };
/// Cyrillic and Greek: case pairs, Ohm sign, theta/phi symbol variants, multi-character folds.
pub const cyrillic_greek_pool = [_]u21{ 'a', 'b', ' ', '-', '_', '0', '\n', 0x0430, 0x0410, 0x0451, 0x0401, 0x0450, 0x04CF, 0x04C0, 0x03C9, 0x03A9, 0x2126, 0x03D1, 0x03B8, 0x03F4, 0x03D5, 0x03C6, 0x03DC, 0x03DD, 0x0390, 0x1FD3 };
/// White space, digits and invisibles: \s and \d edge cases, format characters, a combining mark.
pub const space_digit_pool = [_]u21{ 'a', 'b', '_', '0', '9', ' ', '\n', '\r', '\t', 0x0B, 0x0C, 0x85, 0xA0, 0x1680, 0x180E, 0x2007, 0x202F, 0x3000, 0x2028, 0x2029, 0xFEFF, 0x200B, 0x200D, 0x0301, 0x0663, 0x1D7CE, 0x2177, 0x2460 };
/// Grapheme clusters (\X): CR LF, combining and spacing marks, ZWJ/ZWNJ, a variation selector,
/// emoji with a modifier, regional indicators, Hangul jamo and syllables, a prepended
/// concatenation mark, a Devanagari consonant and virama (GB9c), a format control.
pub const grapheme_pool = [_]u21{ 'a', 'b', ' ', '\n', '\r', 0x0301, 0x200D, 0x200C, 0xFE0F, 0x1F600, 0x2764, 0x1F3FB, 0x1F1E6, 0x1F1E7, 0x1100, 0x1161, 0x11A8, 0xAC00, 0xAC01, 0x0903, 0x0600, 0x0915, 0x094D, 0x200B };
pub const alt_pools = [_][]const u21{ &fold_pool, &cyrillic_greek_pool, &space_digit_pool, &grapheme_pool };

/// Pool symbols as decoded in the given mode: the astral char becomes its
/// two surrogate halves without u/v.
pub fn poolSymbols(pool: []const u21, flags: Flags, out: *[max_symbols * 2]u21) []const u21 {
    var n: usize = 0;
    for (pool) |c| {
        if (c > 0xFFFF and !flags.unicode() and !dialect.active.ascii_mode) {
            const hs = highSurrogate(c);
            const ls = lowSurrogate(c);
            out[n] = hs;
            out[n + 1] = ls;
            n += 2;
        } else {
            out[n] = c;
            n += 1;
        }
    }
    return out[0..n];
}

pub fn highSurrogate(c: u21) u21 {
    return @intCast(0xD800 + ((c - 0x10000) >> 10));
}
pub fn lowSurrogate(c: u21) u21 {
    return @intCast(0xDC00 + ((c - 0x10000) & 0x3FF));
}
pub fn isSurrogate(c: u21) bool {
    return c >= 0xD800 and c <= 0xDFFF;
}

/// Encode code points as UTF-16 (lone surrogates pass through).
pub fn toUtf16(cps: []const u21, out: []u16) usize {
    var n: usize = 0;
    for (cps) |c| {
        if (c > 0xFFFF) {
            out[n] = @intCast(highSurrogate(c));
            out[n + 1] = @intCast(lowSurrogate(c));
            n += 2;
        } else {
            out[n] = @intCast(c);
            n += 1;
        }
    }
    return n;
}

/// Decode UTF-16 into symbols for `flags`. Returns null if longer than `out`.
pub fn decode(units: []const u16, flags: Flags, out: []u21) ?usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < units.len) {
        if (n >= out.len) return null;
        const u = units[i];
        if (flags.unicode() and u >= 0xD800 and u <= 0xDBFF and i + 1 < units.len and units[i + 1] >= 0xDC00 and units[i + 1] <= 0xDFFF) {
            out[n] = 0x10000 + ((@as(u21, u) - 0xD800) << 10) + (@as(u21, units[i + 1]) - 0xDC00);
            i += 2;
        } else {
            out[n] = u;
            i += 1;
        }
        n += 1;
    }
    return n;
}

const dialect = @import("dialect.zig");

/// Dialect-dispatched character predicates (see dialect.zig).
pub fn isLineTerminator(c: u21) bool {
    return dialect.active.isLineTerminator(c);
}
pub fn isSpace(c: u21) bool {
    return dialect.active.isSpace(c);
}
pub fn isWordChar(c: u21, flags: Flags) bool {
    if (asciiMode(flags)) return isBasicWord(c);
    return dialect.active.isWord(c, flags);
}

/// Rust (?-u:…): \w \d \s \b and case folding are ASCII-only.
pub fn asciiMode(flags: Flags) bool {
    return dialect.active.ascii_mode and !flags.unicode();
}

fn asciiFold(c: u21) u21 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

pub fn esLineTerminator(c: u21) bool {
    return c == '\n' or c == '\r' or c == 0x2028 or c == 0x2029;
}

pub fn isDigit(c: u21) bool {
    return c >= '0' and c <= '9';
}

pub fn isBasicWord(c: u21) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or isDigit(c) or c == '_';
}

/// ECMAScript WhiteSpace ∪ LineTerminator (the \s set).
pub fn esSpace(c: u21) bool {
    return c == 0x09 or c == 0x0B or c == 0x0C or c == 0xFEFF or ucd.isZs(c) or esLineTerminator(c);
}

/// WordCharacters(rer): basic word chars, plus (iu/iv) everything whose
/// Canonicalize is a basic word char.
pub fn esWordChar(c: u21, flags: Flags) bool {
    if (isBasicWord(c)) return true;
    if (flags.i and flags.unicode()) return isBasicWord(ucd.simpleFold(c));
    // Without u/v, Canonicalize never maps non-ASCII to ASCII, so no extras.
    return false;
}

pub fn canonicalize(c: u21, flags: Flags) u21 {
    if (!flags.i) return c;
    if (asciiMode(flags)) return asciiFold(c);
    if (dialect.active.fold) |f| return f(c);
    if (flags.unicode()) return ucd.simpleFold(c);
    if (c > 0xFFFF) return c;
    return ucd.canonNonUnicode(@intCast(c));
}

/// Is `c` a character of AllCharacters(rer)?
pub fn inAllCharacters(c: u21, flags: Flags) bool {
    if (flags.v and flags.i) return ucd.simpleFold(c) == c;
    if (dialect.active.ascii_mode) return c <= 0x10FFFF;
    if (flags.unicode()) return c <= 0x10FFFF;
    return c <= 0xFFFF;
}

/// True if any s with Canonicalize(s) == Canonicalize(c) satisfies `pred`.
/// Without i this is just pred(c).
pub fn existsEquivalent(c: u21, flags: Flags, ctx: anytype, comptime pred: fn (@TypeOf(ctx), u21) bool) bool {
    if (!flags.i) return pred(ctx, c);
    if (asciiMode(flags)) {
        if (pred(ctx, c)) return true;
        if (c >= 'a' and c <= 'z') return pred(ctx, c - 32);
        if (c >= 'A' and c <= 'Z') return pred(ctx, c + 32);
        return false;
    }
    if (dialect.active.fold) |f| return ucd.forEachFoldEquivalent(f, c, ctx, pred);
    return ucd.forEachEquivalent(c, flags.unicode(), ctx, pred);
}

const testing = std.testing;

test "decode respects mode" {
    ucd.init();
    var units: [8]u16 = undefined;
    const n = toUtf16(&[_]u21{ 'a', astral_char, 'b' }, &units);
    var out: [8]u21 = undefined;
    try testing.expectEqual(@as(?usize, 4), decode(units[0..n], .{}, &out));
    try testing.expectEqual(@as(u21, 0xD83D), out[1]);
    try testing.expectEqual(@as(u21, 0xDE00), out[2]);
    try testing.expectEqual(@as(?usize, 3), decode(units[0..n], .{ .u = true }, &out));
    try testing.expectEqual(astral_char, out[1]);
    // lone surrogate stays its own symbol in u mode
    const lone = [_]u16{ 0xD83D, 'a' };
    try testing.expectEqual(@as(?usize, 2), decode(&lone, .{ .u = true }, &out));
    try testing.expectEqual(@as(u21, 0xD83D), out[0]);
}

test "word chars under iu include long s and kelvin" {
    ucd.init();
    try testing.expect(isWordChar(0x017F, .{ .i = true, .u = true }));
    try testing.expect(isWordChar(0x212A, .{ .i = true, .v = true }));
    try testing.expect(!isWordChar(0x017F, .{ .i = true }));
    try testing.expect(!isWordChar(0x212A, .{ .u = true }));
}

test "whitespace is the full ES set" {
    ucd.init();
    try testing.expect(isSpace(0xFEFF) and isSpace(0x2028) and isSpace(0x00A0) and isSpace(0x3000));
    try testing.expect(!isSpace(0x200B));
}

test "flag string round trip" {
    var buf: [8]u8 = undefined;
    const f = try Flags.parse("imsv");
    try testing.expectEqualStrings("imsv", f.str(&buf));
    try testing.expectError(error.BadFlag, Flags.parse("uv"));
}
