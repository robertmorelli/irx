//! Extended grapheme clusters (UAX #29) for `\X`: the cluster starting at a position, with the
//! rules GB3..GB13 (GB9c, Indic conjuncts, optional: engines on Unicode before 15.1 lack it).
//! Engines start a cluster at the current position without looking behind it, so regional
//! indicator pairing and emoji ZWJ sequences count from there; the model does the same.
//! Grapheme_Cluster_Break values come from the general category plus explicit lists that
//! cover the character pools (grapheme_pool in particular); the self-check verifies them.
const std = @import("std");
const ucd = @import("ucd.zig");

pub const Gcb = enum { other, cr, lf, control, extend, zwj, ri, prepend, spacing_mark, l, v, t, lv, lvt, ext_pict };
const InCB = enum { none, consonant, linker, extend };

const R = struct { lo: u21, hi: u21 };

fn inRanges(c: u21, rs: []const R) bool {
    for (rs) |r| if (c >= r.lo and c <= r.hi) return true;
    return false;
}

const prepend = [_]R{
    .{ .lo = 0x600, .hi = 0x605 },     .{ .lo = 0x6DD, .hi = 0x6DD },     .{ .lo = 0x70F, .hi = 0x70F },     .{ .lo = 0x890, .hi = 0x891 },
    .{ .lo = 0x8E2, .hi = 0x8E2 },     .{ .lo = 0xD4E, .hi = 0xD4E },     .{ .lo = 0x110BD, .hi = 0x110BD }, .{ .lo = 0x110CD, .hi = 0x110CD },
    .{ .lo = 0x111C2, .hi = 0x111C3 }, .{ .lo = 0x1193F, .hi = 0x1193F }, .{ .lo = 0x11941, .hi = 0x11941 }, .{ .lo = 0x11A3A, .hi = 0x11A3A },
    .{ .lo = 0x11A84, .hi = 0x11A89 }, .{ .lo = 0x11D46, .hi = 0x11D46 }, .{ .lo = 0x11F02, .hi = 0x11F02 },
};

/// Spacing combining marks that are Grapheme_Extend (so Extend, not SpacingMark).
const mc_extend = [_]R{
    .{ .lo = 0x9BE, .hi = 0x9BE },     .{ .lo = 0x9D7, .hi = 0x9D7 },     .{ .lo = 0xB3E, .hi = 0xB3E },     .{ .lo = 0xB57, .hi = 0xB57 },
    .{ .lo = 0xBBE, .hi = 0xBBE },     .{ .lo = 0xBD7, .hi = 0xBD7 },     .{ .lo = 0xCC2, .hi = 0xCC2 },     .{ .lo = 0xCD5, .hi = 0xCD6 },
    .{ .lo = 0xD3E, .hi = 0xD3E },     .{ .lo = 0xD57, .hi = 0xD57 },     .{ .lo = 0xDCF, .hi = 0xDCF },     .{ .lo = 0xDDF, .hi = 0xDDF },
    .{ .lo = 0x302E, .hi = 0x302F },   .{ .lo = 0x1D165, .hi = 0x1D165 }, .{ .lo = 0x1D16E, .hi = 0x1D172 },
};

/// Spacing combining marks excluded from SpacingMark (Myanmar and others: GCB Other).
const mc_other = [_]R{
    .{ .lo = 0x102B, .hi = 0x102C }, .{ .lo = 0x1038, .hi = 0x1038 }, .{ .lo = 0x1062, .hi = 0x1064 }, .{ .lo = 0x1067, .hi = 0x106D },
    .{ .lo = 0x1083, .hi = 0x1083 }, .{ .lo = 0x1087, .hi = 0x108C }, .{ .lo = 0x108F, .hi = 0x108F }, .{ .lo = 0x109A, .hi = 0x109C },
    .{ .lo = 0x1A61, .hi = 0x1A61 }, .{ .lo = 0x1A63, .hi = 0x1A64 }, .{ .lo = 0xAA7B, .hi = 0xAA7B }, .{ .lo = 0xAA7D, .hi = 0xAA7D },
};

const ext_pict = [_]R{
    .{ .lo = 0xA9, .hi = 0xA9 },         .{ .lo = 0xAE, .hi = 0xAE },         .{ .lo = 0x203C, .hi = 0x203C },     .{ .lo = 0x2049, .hi = 0x2049 },
    .{ .lo = 0x2122, .hi = 0x2122 },     .{ .lo = 0x2139, .hi = 0x2139 },     .{ .lo = 0x2194, .hi = 0x2199 },     .{ .lo = 0x21A9, .hi = 0x21AA },
    .{ .lo = 0x231A, .hi = 0x231B },     .{ .lo = 0x2328, .hi = 0x2328 },     .{ .lo = 0x2388, .hi = 0x2388 },     .{ .lo = 0x23CF, .hi = 0x23CF },
    .{ .lo = 0x23E9, .hi = 0x23F3 },     .{ .lo = 0x23F8, .hi = 0x23FA },     .{ .lo = 0x24C2, .hi = 0x24C2 },     .{ .lo = 0x25AA, .hi = 0x25AB },
    .{ .lo = 0x25B6, .hi = 0x25B6 },     .{ .lo = 0x25C0, .hi = 0x25C0 },     .{ .lo = 0x25FB, .hi = 0x25FE },     .{ .lo = 0x2600, .hi = 0x2605 },
    .{ .lo = 0x2607, .hi = 0x2612 },     .{ .lo = 0x2614, .hi = 0x2685 },     .{ .lo = 0x2690, .hi = 0x2705 },     .{ .lo = 0x2708, .hi = 0x2712 },
    .{ .lo = 0x2714, .hi = 0x2714 },     .{ .lo = 0x2716, .hi = 0x2716 },     .{ .lo = 0x271D, .hi = 0x271D },     .{ .lo = 0x2721, .hi = 0x2721 },
    .{ .lo = 0x2728, .hi = 0x2728 },     .{ .lo = 0x2733, .hi = 0x2734 },     .{ .lo = 0x2744, .hi = 0x2744 },     .{ .lo = 0x2747, .hi = 0x2747 },
    .{ .lo = 0x274C, .hi = 0x274C },     .{ .lo = 0x274E, .hi = 0x274E },     .{ .lo = 0x2753, .hi = 0x2755 },     .{ .lo = 0x2757, .hi = 0x2757 },
    .{ .lo = 0x2763, .hi = 0x2767 },     .{ .lo = 0x2795, .hi = 0x2797 },     .{ .lo = 0x27A1, .hi = 0x27A1 },     .{ .lo = 0x27B0, .hi = 0x27B0 },
    .{ .lo = 0x27BF, .hi = 0x27BF },     .{ .lo = 0x2934, .hi = 0x2935 },     .{ .lo = 0x2B05, .hi = 0x2B07 },     .{ .lo = 0x2B1B, .hi = 0x2B1C },
    .{ .lo = 0x2B50, .hi = 0x2B50 },     .{ .lo = 0x2B55, .hi = 0x2B55 },     .{ .lo = 0x3030, .hi = 0x3030 },     .{ .lo = 0x303D, .hi = 0x303D },
    .{ .lo = 0x3297, .hi = 0x3297 },     .{ .lo = 0x3299, .hi = 0x3299 },     .{ .lo = 0x1F000, .hi = 0x1F0FF }, .{ .lo = 0x1F10D, .hi = 0x1F10F },
    .{ .lo = 0x1F12F, .hi = 0x1F12F }, .{ .lo = 0x1F16C, .hi = 0x1F171 }, .{ .lo = 0x1F17E, .hi = 0x1F17F }, .{ .lo = 0x1F18E, .hi = 0x1F18E },
    .{ .lo = 0x1F191, .hi = 0x1F19A }, .{ .lo = 0x1F1AD, .hi = 0x1F1E5 }, .{ .lo = 0x1F201, .hi = 0x1F20F }, .{ .lo = 0x1F21A, .hi = 0x1F21A },
    .{ .lo = 0x1F22F, .hi = 0x1F22F }, .{ .lo = 0x1F232, .hi = 0x1F23A }, .{ .lo = 0x1F23C, .hi = 0x1F23F }, .{ .lo = 0x1F249, .hi = 0x1F3FA },
    .{ .lo = 0x1F400, .hi = 0x1F53D }, .{ .lo = 0x1F546, .hi = 0x1F64F }, .{ .lo = 0x1F680, .hi = 0x1F6FF }, .{ .lo = 0x1F774, .hi = 0x1F77F },
    .{ .lo = 0x1F7D5, .hi = 0x1F7FF }, .{ .lo = 0x1F80C, .hi = 0x1F80F }, .{ .lo = 0x1F848, .hi = 0x1F84F }, .{ .lo = 0x1F85A, .hi = 0x1F85F },
    .{ .lo = 0x1F888, .hi = 0x1F88F }, .{ .lo = 0x1F8AE, .hi = 0x1F8FF }, .{ .lo = 0x1F90C, .hi = 0x1F93A }, .{ .lo = 0x1F93C, .hi = 0x1F945 },
    .{ .lo = 0x1F947, .hi = 0x1FAFF }, .{ .lo = 0x1FC00, .hi = 0x1FFFD },
};

const incb_linker = [_]u21{ 0x94D, 0x9CD, 0xACD, 0xB4D, 0xC4D, 0xD4D };
const incb_consonant = [_]R{
    .{ .lo = 0x915, .hi = 0x939 }, .{ .lo = 0x958, .hi = 0x95F }, .{ .lo = 0x978, .hi = 0x97F }, .{ .lo = 0x995, .hi = 0x9A8 },
    .{ .lo = 0x9AA, .hi = 0x9B0 }, .{ .lo = 0x9B2, .hi = 0x9B2 }, .{ .lo = 0x9B6, .hi = 0x9B9 }, .{ .lo = 0x9DC, .hi = 0x9DD },
    .{ .lo = 0x9DF, .hi = 0x9DF }, .{ .lo = 0x9F0, .hi = 0x9F1 }, .{ .lo = 0xA95, .hi = 0xAA8 }, .{ .lo = 0xAAA, .hi = 0xAB0 },
    .{ .lo = 0xAB2, .hi = 0xAB3 }, .{ .lo = 0xAB5, .hi = 0xAB9 }, .{ .lo = 0xAF9, .hi = 0xAF9 }, .{ .lo = 0xB15, .hi = 0xB28 },
    .{ .lo = 0xB2A, .hi = 0xB30 }, .{ .lo = 0xB32, .hi = 0xB33 }, .{ .lo = 0xB35, .hi = 0xB39 }, .{ .lo = 0xB5C, .hi = 0xB5D },
    .{ .lo = 0xB5F, .hi = 0xB5F }, .{ .lo = 0xB71, .hi = 0xB71 }, .{ .lo = 0xC15, .hi = 0xC28 }, .{ .lo = 0xC2A, .hi = 0xC39 },
    .{ .lo = 0xC58, .hi = 0xC5A }, .{ .lo = 0xD15, .hi = 0xD3A },
};

pub fn gcb(c: u21) Gcb {
    switch (c) {
        '\r' => return .cr,
        '\n' => return .lf,
        0x200D => return .zwj,
        0x200C => return .extend,
        else => {},
    }
    if (c >= 0x1F1E6 and c <= 0x1F1FF) return .ri;
    if (c >= 0x1F3FB and c <= 0x1F3FF) return .extend; // emoji modifiers
    if (c >= 0xE0020 and c <= 0xE007F) return .extend; // tags
    if (c >= 0xFF9E and c <= 0xFF9F) return .extend;
    if ((c >= 0x1100 and c <= 0x115F) or (c >= 0xA960 and c <= 0xA97C)) return .l;
    if ((c >= 0x1160 and c <= 0x11A7) or (c >= 0xD7B0 and c <= 0xD7C6)) return .v;
    if ((c >= 0x11A8 and c <= 0x11FF) or (c >= 0xD7CB and c <= 0xD7FB)) return .t;
    if (c >= 0xAC00 and c <= 0xD7A3) return if ((c - 0xAC00) % 28 == 0) .lv else .lvt;
    if (inRanges(c, &prepend)) return .prepend;
    if (inRanges(c, &ext_pict)) return .ext_pict;
    if (c == 0xE33 or c == 0xEB3) return .spacing_mark; // Thai/Lao SARA AM
    const cat = ucd.category(c);
    if (cat[0] == 'M') {
        if (cat[1] == 'c') {
            if (inRanges(c, &mc_extend)) return .extend;
            if (inRanges(c, &mc_other)) return .other;
            return .spacing_mark;
        }
        return .extend; // Mn, Me
    }
    if (cat[0] == 'C' and (cat[1] == 'c' or cat[1] == 'f')) return .control;
    if (cat[0] == 'Z' and (cat[1] == 'l' or cat[1] == 'p')) return .control;
    return .other;
}

fn incb(c: u21) InCB {
    if (std.mem.indexOfScalar(u21, &incb_linker, c) != null) return .linker;
    if (inRanges(c, &incb_consonant)) return .consonant;
    if (c == 0x200D) return .extend;
    // Extend characters with a nonzero combining class (approximated: nonspacing marks other
    // than variation selectors, emoji modifiers and tags, which have class 0).
    const g = gcb(c);
    if (g == .extend and c != 0x200C and !(c >= 0xFE00 and c <= 0xFE0F) and !(c >= 0x1F3FB and c <= 0x1F3FF) and !(c >= 0xE0020 and c <= 0xE007F)) {
        const cat = ucd.category(c);
        if (cat[0] == 'M' and cat[1] == 'n') return .extend;
    }
    return .none;
}

const State = struct {
    ri_odd: bool = false,
    /// 1: Extended_Pictographic Extend*; 2: that followed by ZWJ.
    ep: u2 = 0,
    /// 1: Consonant [Extend Linker]* without a linker yet; 2: with one.
    cb: u2 = 0,

    fn push(s: *State, c: u21, g: Gcb) void {
        s.ri_odd = if (g == .ri) !s.ri_odd else false;
        s.ep = switch (g) {
            .ext_pict => 1,
            .extend => if (s.ep == 1) 1 else 0,
            .zwj => if (s.ep == 1) 2 else 0,
            else => 0,
        };
        s.cb = switch (incb(c)) {
            .consonant => 1,
            .linker => if (s.cb != 0) 2 else 0,
            .extend => s.cb,
            .none => 0,
        };
    }
};

fn breaks(prev: Gcb, cur: Gcb, c: u21, s: *const State, gb9c: bool) bool {
    if (prev == .cr and cur == .lf) return false; // GB3
    if (prev == .cr or prev == .lf or prev == .control) return true; // GB4
    if (cur == .cr or cur == .lf or cur == .control) return true; // GB5
    if (prev == .l and (cur == .l or cur == .v or cur == .lv or cur == .lvt)) return false; // GB6
    if ((prev == .lv or prev == .v) and (cur == .v or cur == .t)) return false; // GB7
    if ((prev == .lvt or prev == .t) and cur == .t) return false; // GB8
    if (cur == .extend or cur == .zwj) return false; // GB9
    if (cur == .spacing_mark) return false; // GB9a
    if (prev == .prepend) return false; // GB9b
    if (gb9c and s.cb == 2 and incb(c) == .consonant) return false; // GB9c
    if (prev == .zwj and cur == .ext_pict and s.ep == 2) return false; // GB11
    if (prev == .ri and cur == .ri and s.ri_odd) return false; // GB12, GB13
    return true; // GB999
}

/// End of the extended grapheme cluster starting at w[i] (i < w.len).
pub fn clusterEnd(w: []const u21, i: usize, gb9c: bool) usize {
    return clusterEndOpts(w, i, .{ .gb9c = gb9c });
}

pub const Opts = struct { gb9c: bool = false, prepend_pict: bool = true, combining: bool = false };

/// The cluster end for the active dialect's \X.
pub fn clusterEndActive(w: []const u21, i: usize) usize {
    const d = @import("dialect.zig").active;
    return clusterEndOpts(w, i, .{ .gb9c = d.grapheme_escape == .extended_gb9c, .prepend_pict = d.grapheme_prepend_pict, .combining = d.grapheme_escape == .combining });
}

pub fn clusterEndOpts(w: []const u21, i: usize, o: Opts) usize {
    if (o.combining) {
        var j = i + 1;
        while (j < w.len) : (j += 1) switch (gcb(w[j])) {
            .extend, .spacing_mark, .zwj => {},
            else => break,
        };
        return j;
    }
    const gb9c = o.gb9c;
    var s: State = .{};
    var g = gcb(w[i]);
    s.push(w[i], g);
    var j = i + 1;
    while (j < w.len) : (j += 1) {
        const h = gcb(w[j]);
        if (breaks(g, h, w[j], &s, gb9c)) break;
        // PCRE2's table (IRX-PCRE2-6): Prepend does not join an emoji, and a regional indicator
        // does not join a following Extend, SpacingMark or ZWJ.
        if (!o.prepend_pict and ((g == .prepend and h == .ext_pict) or (g == .ri and (h == .extend or h == .spacing_mark or h == .zwj)))) break;
        s.push(w[j], h);
        g = h;
    }
    return j;
}

test "grapheme clusters" {
    ucd.init();
    const T = struct {
        fn end(w: []const u21) usize {
            return clusterEnd(w, 0, true);
        }
    };
    try std.testing.expectEqual(@as(usize, 2), T.end(&.{ '\r', '\n', 'a' }));
    try std.testing.expectEqual(@as(usize, 2), T.end(&.{ 'a', 0x301, 'b' }));
    try std.testing.expectEqual(@as(usize, 3), T.end(&.{ 0x1F600, 0x200D, 0x1F600 }));
    try std.testing.expectEqual(@as(usize, 2), T.end(&.{ 0x1F1E6, 0x1F1E7, 0x1F1E6 }));
    try std.testing.expectEqual(@as(usize, 3), T.end(&.{ 0x1100, 0x1161, 0x11A8 }));
    try std.testing.expectEqual(@as(usize, 3), T.end(&.{ 0x915, 0x94D, 0x915 }));
    try std.testing.expectEqual(@as(usize, 2), clusterEnd(&.{ 0x915, 0x94D, 0x915 }, 0, false));
    try std.testing.expectEqual(@as(usize, 2), T.end(&.{ 0x600, 'a', 'b' }));
    try std.testing.expectEqual(@as(usize, 1), T.end(&.{ 'a', 0x1F1E6 }));
}
