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
const std = @import("std");
const ast = @import("ast.zig");
const alpha = @import("alphabet.zig");
const dialect = @import("dialect.zig");
const config = @import("config.zig");
const finding = @import("finding.zig");
const harness = @import("harness.zig");
const relmod = @import("rel.zig");

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

/// Reference span of an unanchored search of `subject` (UTF-16). Null if the subject is
/// too long or the backtracking reference ran out of steps.
pub fn reference(t: *const ast.Ast, flags: alpha.Flags, subject: []const u16) ?Span {
    var syms: [31]u21 = undefined;
    const n = alpha.decode(subject, flags, &syms) orelse return null;
    const w = syms[0..n];
    var s_model: usize = 0;
    var e_model: usize = 0;
    var found = false;
    switch (dialect.active.span_semantics) {
        .first => {
            var mt: ast.Matcher = .{ .t = t, .flags = flags, .w = w, .budget = 200_000 };
            var i: usize = 0;
            while (i <= n) : (i += 1) {
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
            if (n > relmod.Rel16.max_len) return null;
            const rel = ast.evalRel(relmod.Rel16, t, t.root, flags, w);
            var i: usize = 0;
            outer: while (i <= n) : (i += 1) {
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

/// Map a host offset in `units` to a UTF-16 offset of `subject`; null if it falls inside
/// a character or past the end.
pub fn hostToUtf16(subject: []const u16, off: u8, units: config.SpanUnits) ?u16 {
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

fn hostSpan(subject: []const u16, s: u8, e: u8, units: config.SpanUnits) ?Span {
    if (s == no_match) return .{ .found = false };
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
        .group_cap, .group_nc, .group_named => minLen(t, n.a),
    };
}

/// Does some quantifier have a body that can match empty?
pub fn hasNullableLoop(t: *const ast.Ast, idx: u8) bool {
    const n = t.nodes[idx];
    return switch (n.op) {
        .atom => false,
        .concat, .alt => hasNullableLoop(t, n.a) or hasNullableLoop(t, n.b),
        .quant => minLen(t, n.a) == 0 or hasNullableLoop(t, n.a),
        .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind, .group_cap, .group_nc, .group_named => hasNullableLoop(t, n.a),
    };
}

pub fn check(c: *const finding.Case, raw: []const u8, units: config.SpanUnits) Check {
    if (raw[0] == failed) return .{ .bits = raw[1] };
    if (dialect.active.empty_iteration == .unmodeled and hasNullableLoop(&c.tree, c.tree.root)) return .{ .bits = harness.Bits.skipped };
    const ra = reference(&c.tree, c.flags, c.a.slice()) orelse return .{ .bits = harness.Bits.skipped };
    const rr = reference(&c.tree, c.flags, c.r.slice()) orelse return .{ .bits = harness.Bits.skipped };
    const ga = hostSpan(c.a.slice(), raw[0], raw[1], units);
    const gr = hostSpan(c.r.slice(), raw[2], raw[3], units);
    var bits: u8 = 0;
    if (ga != null and ga.?.eql(ra)) bits |= harness.Bits.test_a;
    if (gr == null or !gr.?.eql(rr)) bits |= harness.Bits.test_r;
    return .{ .bits = bits, .ref_a = ra, .ref_r = rr, .got_a = ga, .got_r = gr };
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
    try out.print(gpa, ", \"raw\": \"{x:0>2}{x:0>2}{x:0>2}{x:0>2}\"}}", .{ raw[0], raw[1], raw[2], raw[3] });
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
