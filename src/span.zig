//! Match-span checking: the reference [start, end) of an unanchored search and its
//! comparison with the span a host reports.
//!
//! All spans are compared as UTF-16 offsets into the subject (cases store subjects as
//! UTF-16). The reference works in model positions (code units in ES non-unicode mode,
//! code points otherwise) and maps them to UTF-16; hosts report in their native unit
//! (`[span] units`), which is mapped the same way. A host offset inside a character
//! cannot be mapped and counts as a disagreement.
//!
//! Wire format (span mode): 8 hex digits per case, bytes As Ae Rs Re. 0xFF in a start
//! byte means no match; 0xFE in the first byte means the case failed with the bits in
//! the second byte (04 syntax error, 08 exception, 40 unsupported).
//!
//! Long modes (driver modes lspan/lcapture, on each case's long pair) use the same layout
//! with 16-bit big-endian positions (4 hex digits): 0xFFFF no match, 0xFFFE in the first
//! position = failed with the bits in the low byte of the second.
const std = @import("std");
const ast = @import("ast.zig");
const alpha = @import("alphabet.zig");
const dialect = @import("dialect.zig");
const config = @import("config.zig");
const finding = @import("finding.zig");
const harness = @import("harness.zig");
const relmod = @import("rel.zig");
const longmod = @import("long.zig");

/// Position k of a raw result: one byte, or two (big-endian) in the long modes. No match
/// and failure markers are normalized to 0xFFFF and 0xFFFE.
pub fn wirePos(raw: []const u8, wide: bool, k: usize) u16 {
    if (wide) return (@as(u16, raw[2 * k]) << 8) | raw[2 * k + 1];
    return switch (raw[k]) {
        no_match => 0xFFFF,
        failed => 0xFFFE,
        else => |b| b,
    };
}

/// Failure bits if the raw result reports a failed case.
pub fn failBits(raw: []const u8, wide: bool) ?u8 {
    if (wirePos(raw, wide, 0) != 0xFFFE) return null;
    return if (wide) raw[3] else raw[1];
}

/// Decode a subject to model symbols: on the stack when short, else allocated (free with
/// `freeSyms`).
pub fn decodeAny(subject: []const u16, flags: alpha.Flags, buf: *[31]u21) ?[]u21 {
    if (alpha.decode(subject, flags, buf)) |n| return buf[0..n];
    return longmod.decode(std.heap.smp_allocator, subject, flags) catch null;
}

pub fn freeSyms(w: []u21, buf: *[31]u21) void {
    if (w.ptr != buf) std.heap.smp_allocator.free(w);
}

pub const width = 4;
pub const no_match: u8 = 0xFF;
pub const failed: u8 = 0xFE;

pub const Span = struct {
    found: bool,
    s: u16 = 0,
    e: u16 = 0,

    pub fn eql(a: Span, b: Span) bool {
        if (a.found != b.found) return false;
        return !a.found or (a.s == b.s and a.e == b.e);
    }
};

/// Reference span of an unanchored search of `subject` (UTF-16, any length). Null if the
/// reference ran out of steps.
pub fn reference(t: *const ast.Ast, flags: alpha.Flags, subject: []const u16) ?Span {
    return referenceFrom(t, flags, subject, 0);
}

/// The same search starting at UTF-16 offset `start` (a character boundary); the text before
/// it stays visible to lookbehind and assertions. Null if `start` is not a boundary.
pub fn referenceFrom(t: *const ast.Ast, flags: alpha.Flags, subject: []const u16, start: u16) ?Span {
    return referenceAt(t, flags, subject, start, false);
}

/// `anchored`: only a match starting exactly at `start` (sticky).
pub fn referenceAt(t: *const ast.Ast, flags: alpha.Flags, subject: []const u16, start: u16, anchored: bool) ?Span {
    var syms: [31]u21 = undefined;
    const w = decodeAny(subject, flags, &syms) orelse return null;
    defer freeSyms(w, &syms);
    const n = w.len;
    // Model position of the start offset.
    var k: usize = 0;
    while (k < n and utf16Offset(w, k) < start) k += 1;
    if (utf16Offset(w, k) != start) return null;
    var s_model: usize = 0;
    var e_model: usize = 0;
    var found = false;
    switch (dialect.active.span_semantics) {
        .first => {
            var mt: ast.Matcher = .{ .t = t, .flags = flags, .w = w, .budget = 200_000 + 200 * n };
            // Backreferences read capture slots.
            var caps: ast.Caps = undefined;
            if (ast.needsMatcher(t)) {
                caps = ast.Caps.init(t) orelse return null;
                mt.caps = &caps;
            }
            var i: usize = k;
            while (i <= n) : (i += 1) {
                if (anchored and i > k) break;
                const r = mt.matchAt(i) orelse return null;
                if (r) {
                    found = true;
                    s_model = i;
                    e_model = mt.end;
                    break;
                }
            }
        },
        .longest => {
            if (n > relmod.Rel16.max_len) {
                // Long subjects: the leftmost start that reaches any end, then its last end.
                const se = longmod.leftmostLongest(std.heap.smp_allocator, t, flags, w, k) orelse return null;
                if (anchored) if (se) |x| if (x[0] != k) return .{ .found = false };
                if (se) |x| return .{ .found = true, .s = utf16Offset(w, x[0]), .e = utf16Offset(w, x[1]) };
                return .{ .found = false };
            }
            const rel = ast.evalRel(relmod.Rel16, t, t.root, flags, w);
            var i: usize = k;
            outer: while (i <= n) : (i += 1) {
                if (anchored and i > k) break;
                var j: usize = n + 1;
                while (j > i) {
                    j -= 1;
                    if (rel.get(i, j)) {
                        found = true;
                        s_model = i;
                        e_model = j;
                        break :outer;
                    }
                }
            }
        },
    }
    if (!found) return .{ .found = false };
    return .{ .found = true, .s = utf16Offset(w, s_model), .e = utf16Offset(w, e_model) };
}

pub fn utf16Offset(w: []const u21, pos: usize) u16 {
    var off: u16 = 0;
    for (w[0..pos]) |c| off += if (c > 0xFFFF) 2 else 1;
    return off;
}

/// A UTF-16 offset of `subject` (at a character boundary) in the host's `units`.
pub fn utf16ToHost(subject: []const u16, off: u16, units: config.SpanUnits) u16 {
    if (units == .utf16) return off;
    var native: u16 = 0;
    var i: usize = 0;
    while (i < off and i < subject.len) {
        const u = subject[i];
        const pair = u >= 0xD800 and u <= 0xDBFF and i + 1 < subject.len and subject[i + 1] >= 0xDC00 and subject[i + 1] <= 0xDFFF;
        const cp: u21 = if (pair) 0x10000 + ((@as(u21, u) - 0xD800) << 10) + (@as(u21, subject[i + 1]) - 0xDC00) else u;
        native += switch (units) {
            .cp => 1,
            .utf8 => if (cp < 0x80) 1 else if (cp < 0x800) 2 else if (cp < 0x10000) 3 else 4,
            .utf16 => unreachable,
        };
        i += if (pair) 2 else 1;
    }
    return native;
}

/// A random character boundary of `subject` (UTF-16 offset), in model positions for `flags`.
pub fn randomBoundary(rng: anytype, subject: []const u16, flags: alpha.Flags) u16 {
    var syms: [31]u21 = undefined;
    const n = alpha.decode(subject, flags, &syms) orelse return 0;
    const k: usize = @intCast(rng.below(n + 1));
    return utf16Offset(syms[0..n], k);
}

/// Map a host offset in `units` to a UTF-16 offset of `subject`; null if it falls inside
/// a character or past the end.
pub fn hostToUtf16(subject: []const u16, off: u16, units: config.SpanUnits) ?u16 {
    if (units == .utf16) return if (off <= subject.len) off else null;
    var native: usize = 0;
    var i: usize = 0;
    while (true) {
        if (native == off) return @intCast(i);
        if (native > off or i >= subject.len) return null;
        const u = subject[i];
        const pair = u >= 0xD800 and u <= 0xDBFF and i + 1 < subject.len and subject[i + 1] >= 0xDC00 and subject[i + 1] <= 0xDFFF;
        const cp: u21 = if (pair) 0x10000 + ((@as(u21, u) - 0xD800) << 10) + (@as(u21, subject[i + 1]) - 0xDC00) else u;
        native += switch (units) {
            .cp => 1,
            .utf8 => if (cp < 0x80) 1 else if (cp < 0x800) 2 else if (cp < 0x10000) 3 else 4,
            .utf16 => unreachable,
        };
        i += if (pair) 2 else 1;
    }
}

fn hostSpan(subject: []const u16, s: u16, e: u16, units: config.SpanUnits) ?Span {
    if (s == 0xFFFF) return .{ .found = false };
    const hs = hostToUtf16(subject, s, units) orelse return null;
    const he = hostToUtf16(subject, e, units) orelse return null;
    if (he < hs) return null;
    return .{ .found = true, .s = hs, .e = he };
}

/// Result of checking one case's raw span bytes.
pub const Check = struct {
    /// Bits in the classify() domain for Expect.span: test_a set = A's span agrees,
    /// test_r set = R's span disagrees; or syntax/exception/skipped as reported.
    bits: u8,
    ref_a: ?Span = null,
    ref_r: ?Span = null,
    got_a: ?Span = null,
    got_r: ?Span = null,
};

/// Minimum match length of a subtree (assertions and lookarounds are zero-width).
pub fn minLen(t: *const ast.Ast, idx: u8) u32 {
    const n = t.nodes[idx];
    return switch (n.op) {
        .atom => if (n.atom.isConsuming()) 1 else 0,
        .concat => minLen(t, n.a) + minLen(t, n.b),
        .alt => @min(minLen(t, n.a), minLen(t, n.b)),
        .quant => minLen(t, n.a) * n.quant.min,
        .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind => 0,
        .group_cap, .group_nc, .group_named, .flag_group, .atomic => minLen(t, n.a),
        .backref => 0,
    };
}

/// Does some quantifier have a body that can match empty?
pub fn hasNullableLoop(t: *const ast.Ast, idx: u8) bool {
    const n = t.nodes[idx];
    return switch (n.op) {
        .atom => false,
        .concat, .alt => hasNullableLoop(t, n.a) or hasNullableLoop(t, n.b),
        .quant => minLen(t, n.a) == 0 or hasNullableLoop(t, n.a),
        .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind, .group_cap, .group_nc, .group_named, .flag_group, .atomic => hasNullableLoop(t, n.a),
        .backref => false,
    };
}

/// Check one case's raw span result; `long`: the long pair, with 16-bit positions;
/// `from_offset`: the search starts at the case's offsets (offset mode).
pub fn check(c: *const finding.Case, raw: []const u8, units: config.SpanUnits, long: bool) Check {
    return checkFrom(c, raw, units, long, false);
}

pub fn checkFrom(c: *const finding.Case, raw: []const u8, units: config.SpanUnits, long: bool, from_offset: bool) Check {
    return checkAt(c, raw, units, long, from_offset, false);
}

pub fn checkAt(c: *const finding.Case, raw: []const u8, units: config.SpanUnits, long: bool, from_offset: bool, anchored: bool) Check {
    if (failBits(raw, long)) |b| return .{ .bits = b };
    if (dialect.active.empty_iteration == .unmodeled and hasNullableLoop(&c.tree, c.tree.root)) return .{ .bits = harness.Bits.skipped };
    const sa = if (long) c.la else c.a.slice();
    const sr = if (long) c.lr else c.r.slice();
    const ra = referenceAt(&c.tree, c.flags, sa, if (from_offset) c.off_a else 0, anchored) orelse return .{ .bits = harness.Bits.skipped };
    const rr = referenceAt(&c.tree, c.flags, sr, if (from_offset) c.off_r else 0, anchored) orelse return .{ .bits = harness.Bits.skipped };
    const ga = hostSpan(sa, wirePos(raw, long, 0), wirePos(raw, long, 1), units);
    const gr = hostSpan(sr, wirePos(raw, long, 2), wirePos(raw, long, 3), units);
    var bits: u8 = 0;
    if (ga != null and ga.?.eql(ra)) bits |= harness.Bits.test_a;
    if (gr == null or !gr.?.eql(rr)) bits |= harness.Bits.test_r;
    return .{ .bits = bits, .ref_a = ra, .ref_r = rr, .got_a = ga, .got_r = gr };
}

/// Global mode: matches reported per subject (driver mode gspan).
pub const global_matches = 4;

/// Where a global search continues after a match ending at `e`: at `e`, or after an empty match
/// one position on (AdvanceStringIndex: a whole surrogate pair under u/v).
fn advanceAfter(subject: []const u16, sp: Span, flags: alpha.Flags) u16 {
    if (sp.e > sp.s) return sp.e;
    const i = sp.e;
    if (flags.unicode() and i + 1 < subject.len and subject[i] >= 0xD800 and subject[i] <= 0xDBFF and subject[i + 1] >= 0xDC00 and subject[i + 1] <= 0xDFFF) return i + 2;
    return i + 1;
}

/// Global mode: the first `global_matches` matches of a global search (matchAll), checked in
/// order against the reference with JavaScript's empty-match advance. The Check holds the
/// spans of the first match that differs.
pub fn checkGlobal(c: *const finding.Case, raw: []const u8, units: config.SpanUnits) Check {
    if (failBits(raw, false)) |b| return .{ .bits = b };
    if (dialect.active.empty_iteration == .unmodeled and hasNullableLoop(&c.tree, c.tree.root)) return .{ .bits = harness.Bits.skipped };
    var ck: Check = .{ .bits = harness.Bits.test_a };
    for (0..2) |k| {
        const subj = if (k == 0) c.a.slice() else c.r.slice();
        var pos: u16 = 0;
        var done = false;
        var agree = true;
        for (0..global_matches) |m| {
            var ref: Span = .{ .found = false };
            if (!done and pos <= subj.len) {
                ref = referenceAt(&c.tree, c.flags, subj, pos, false) orelse return .{ .bits = harness.Bits.skipped };
            }
            if (!ref.found) done = true else pos = advanceAfter(subj, ref, c.flags);
            const got = hostSpan(subj, wirePos(raw, false, k * 2 * global_matches + 2 * m), wirePos(raw, false, k * 2 * global_matches + 2 * m + 1), units);
            if (got == null or !got.?.eql(ref)) {
                if (k == 0) { ck.ref_a = ref; ck.got_a = got; } else { ck.ref_r = ref; ck.got_r = got; }
                agree = false;
                break;
            }
        }
        if (k == 0 and !agree) ck.bits &= ~harness.Bits.test_a;
        if (k == 1 and !agree) ck.bits |= harness.Bits.test_r;
    }
    return ck;
}

fn writeSpan(out: *std.ArrayList(u8), gpa: std.mem.Allocator, sp: ?Span) !void {
    if (sp) |x| {
        if (x.found) try out.print(gpa, "[{d},{d}]", .{ x.s, x.e }) else try out.appendSlice(gpa, "null");
    } else try out.appendSlice(gpa, "\"invalid\"");
}

/// JSON fragment for a finding: reference and reported spans (UTF-16 offsets).
pub fn extraJson(out: *std.ArrayList(u8), gpa: std.mem.Allocator, ck: Check, raw: []const u8) !void {
    try out.appendSlice(gpa, "\"span\": {\"units\": \"utf16 offsets\", \"expected_a\": ");
    try writeSpan(out, gpa, ck.ref_a);
    try out.appendSlice(gpa, ", \"observed_a\": ");
    try writeSpan(out, gpa, ck.got_a);
    try out.appendSlice(gpa, ", \"expected_r\": ");
    try writeSpan(out, gpa, ck.ref_r);
    try out.appendSlice(gpa, ", \"observed_r\": ");
    try writeSpan(out, gpa, ck.got_r);
    try out.appendSlice(gpa, ", \"raw\": \"");
    for (raw) |b| try out.print(gpa, "{x:0>2}", .{b});
    try out.appendSlice(gpa, "\"}");
}

test "host offsets map to UTF-16 offsets" {
    const t = std.testing;
    // "aé😀b": UTF-16 a(1) é(1) 😀(2) b(1); code points 4; UTF-8 bytes 1+2+4+1.
    const s = [_]u16{ 'a', 0xE9, 0xD83D, 0xDE00, 'b' };
    try t.expectEqual(@as(?u16, 2), hostToUtf16(&s, 2, .utf16));
    try t.expectEqual(@as(?u16, 4), hostToUtf16(&s, 3, .cp));
    try t.expectEqual(@as(?u16, 5), hostToUtf16(&s, 4, .cp));
    try t.expectEqual(@as(?u16, 2), hostToUtf16(&s, 3, .utf8));
    try t.expectEqual(@as(?u16, 4), hostToUtf16(&s, 7, .utf8));
    try t.expectEqual(@as(?u16, null), hostToUtf16(&s, 2, .utf8)); // inside é
    try t.expectEqual(@as(?u16, null), hostToUtf16(&s, 9, .utf8)); // past the end
}
