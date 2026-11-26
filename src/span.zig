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
            // \G matches where the search started (Perl: pos(), or 0 without one).
            var mt: ast.Matcher = .{ .t = t, .flags = flags, .w = w, .budget = 200_000 + 200 * n, .gpos = k };
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
                    s_model = mt.keep orelse i; // \K moves the reported start
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
        .atom => n.atom.minLen(),
        .concat => minLen(t, n.a) + minLen(t, n.b),
        .alt, .cond => @min(minLen(t, n.a), minLen(t, n.b)),
        .quant => minLen(t, n.a) * n.quant.min,
        .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind => 0,
        .group_cap, .group_nc, .group_named, .flag_group, .atomic, .branch_reset => minLen(t, n.a),
        .backref, .keep, .gpos => 0,
    };
}

/// Does some quantifier have a body that can match empty?
pub fn hasNullableLoop(t: *const ast.Ast, idx: u8) bool {
    const n = t.nodes[idx];
    return switch (n.op) {
        .atom => false,
        .concat, .alt, .cond => hasNullableLoop(t, n.a) or hasNullableLoop(t, n.b),
        .quant => minLen(t, n.a) == 0 or hasNullableLoop(t, n.a),
        .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind, .group_cap, .group_nc, .group_named, .flag_group, .atomic, .branch_reset => hasNullableLoop(t, n.a),
        .backref, .keep, .gpos => false,
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
        var last_end: ?u16 = null;
        for (0..global_matches) |m| {
            var ref: Span = .{ .found = false };
            if (!done and pos <= subj.len) {
                ref = referenceAt(&c.tree, c.flags, subj, pos, false) orelse return .{ .bits = harness.Bits.skipped };
                // Rust: an empty match where the last match ended is skipped; search again one
                // character on.
                if (!dialect.active.global_empty_after_match and ref.found and ref.s == ref.e and last_end != null and ref.s == last_end.?) {
                    const next = advanceAfter(subj, ref, c.flags);
                    ref = if (next <= subj.len) referenceAt(&c.tree, c.flags, subj, next, false) orelse return .{ .bits = harness.Bits.skipped } else .{ .found = false };
                }
            }
            if (!ref.found) done = true else {
                last_end = ref.e;
                pos = if (dialect.active.global_empty_after_match) advanceAfter(subj, ref, c.flags) else ref.e;
            }
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

test "perl: a class with a multi-character fold takes the longest fold first" {
    const t = std.testing;
    @import("ucd.zig").init();
    const saved = dialect.active;
    defer dialect.active = saved;
    const flags = try alpha.Flags.parse("iu");
    // a[S\x{DF}].a on "aSSaa": Perl takes "SS" through ß, so the match is [0,5), not [0,4).
    const tree = try ast.parse("(concat (atom lit 0 0 0 61 0 0 0) (concat (atom cls 0 0 2 53 df 0 0) (concat (atom dot 0 0 0 0 0 0 0) (atom lit 0 0 0 61 0 0 0))))");
    const s = [_]u16{ 'a', 'S', 'S', 'a', 'a' };
    dialect.active = &dialect.perl;
    try t.expect((reference(&tree, flags, &s) orelse return error.NoResult).eql(.{ .found = true, .s = 0, .e = 5 }));
    // It still falls back to one character: on "aSaa" the match is [0,4).
    const s2 = [_]u16{ 'a', 'S', 'a', 'a' };
    try t.expect((reference(&tree, flags, &s2) orelse return error.NoResult).eql(.{ .found = true, .s = 0, .e = 4 }));
}

test "perl: \\R is (?>\\r\\n|\\v): \\r\\n as one unit, never split" {
    const t = std.testing;
    @import("ucd.zig").init();
    const saved = dialect.active;
    defer dialect.active = saved;
    dialect.active = &dialect.perl;
    const flags = try alpha.Flags.parse("u");
    const R = try ast.parse("(atom linebreak 0 0 0 0 0 0 0)");
    // Whole-string matches measured with perl 5.44 and blead.
    const yes = [_][]const u21{ &.{ '\r', '\n' }, &.{'\r'}, &.{'\n'}, &.{0x0B}, &.{0x0C}, &.{0x85}, &.{0x2028}, &.{0x2029} };
    const no = [_][]const u21{ &.{ '\n', '\r' }, &.{ '\r', '\r' }, &.{'a'}, &.{' '}, &.{0xA0} };
    for (yes) |w| try t.expect(ast.fullMatch(&R, flags, w));
    for (no) |w| try t.expect(!ast.fullMatch(&R, flags, w));
    // Atomic: \R\n does not match "\r\n" (\R takes both), and neither does \R?\n (Perl's
    // documented (?>\r\n|\v)?\n; perl itself matches, a bug).
    const Rn = try ast.parse("(concat (atom linebreak 0 0 0 0 0 0 0) (atom lit 0 0 0 a 0 0 0))");
    const Rqn = try ast.parse("(concat (quant opt 0 1 0 (atom linebreak 0 0 0 0 0 0 0)) (atom lit 0 0 0 a 0 0 0))");
    try t.expect(!ast.fullMatch(&Rn, flags, &.{ '\r', '\n' }));
    try t.expect(!ast.fullMatch(&Rqn, flags, &.{ '\r', '\n' }));
    // Span: the first \R in "x\r\ny" is [1,3).
    const s = [_]u16{ 'x', '\r', '\n', 'y' };
    try t.expect((reference(&R, flags, &s) orelse return error.NoResult).eql(.{ .found = true, .s = 1, .e = 3 }));
}

test "perl: (*FAIL) never matches" {
    const t = std.testing;
    @import("ucd.zig").init();
    const saved = dialect.active;
    defer dialect.active = saved;
    dialect.active = &dialect.perl;
    const flags = try alpha.Flags.parse("u");
    // Measured with perl 5.44 and blead, on "a" and "b": a(*FAIL)|b -> 0 1, (*FAIL)*a -> 1 0,
    // (*FAIL)?a -> 1 0, (?<=(*FAIL))a -> 0 0, (?<!(*FAIL))a -> 1 0.
    const cases = [_]struct { ast: []const u8, a: bool, b: bool }{
        .{ .ast = "(alt (concat (atom lit 0 0 0 61 0 0 0) (atom empty 1 0 0 0 0 0 0)) (atom lit 0 0 0 62 0 0 0))", .a = false, .b = true },
        .{ .ast = "(concat (quant star 0 255 0 (atom empty 1 0 0 0 0 0 0)) (atom lit 0 0 0 61 0 0 0))", .a = true, .b = false },
        .{ .ast = "(concat (quant opt 0 1 0 (atom empty 1 0 0 0 0 0 0)) (atom lit 0 0 0 61 0 0 0))", .a = true, .b = false },
        .{ .ast = "(concat (look_behind (atom empty 1 0 0 0 0 0 0)) (atom lit 0 0 0 61 0 0 0))", .a = false, .b = false },
        .{ .ast = "(concat (neg_look_behind (atom empty 1 0 0 0 0 0 0)) (atom lit 0 0 0 61 0 0 0))", .a = true, .b = false },
    };
    for (cases) |c| {
        const tree = try ast.parse(c.ast);
        try t.expectEqual(c.a, ast.fullMatch(&tree, flags, &.{'a'}));
        try t.expectEqual(c.b, ast.fullMatch(&tree, flags, &.{'b'}));
    }
}

test "perl: the multi_fold_pool characters match their full folds in every case mix under /i" {
    const t = std.testing;
    @import("ucd.zig").init();
    const saved = dialect.active;
    defer dialect.active = saved;
    dialect.active = &dialect.perl;
    const flags = try alpha.Flags.parse("iu");
    const plain = try alpha.Flags.parse("u");
    const atoms = @import("atoms.zig");
    // Measured with perl 5.44 and blead: \A X \z, \A[X]\z and \A[aX]\z all match every case mix of
    // the fold (180 checks), and nothing matches without /i.
    for ([_]u21{ 0x149, 0x1F0, 0x3B0, 0x1E96, 0xFB02, 0xFB06, 0xFB13, 0x587 }) |x| {
        const fold = atoms.multiFold(x) orelse return error.NoFold;
        var buf: [96]u8 = undefined;
        const lit = try std.fmt.bufPrint(buf[0..48], "(atom lit 0 0 0 {x} 0 0 0)", .{x});
        const cls = try std.fmt.bufPrint(buf[48..], "(atom cls 0 0 2 61 {x} 0 0)", .{x});
        for ([_][]const u8{ lit, cls }) |src| {
            const tree = try ast.parse(src);
            var mask: usize = 0;
            while (mask < (@as(usize, 1) << @intCast(fold.len))) : (mask += 1) {
                var w: [3]u21 = undefined;
                for (fold, 0..) |c, k| w[k] = if (mask >> @intCast(k) & 1 == 1) @import("ucd.zig").simpleUpper(c) else c;
                try t.expect(ast.fullMatch(&tree, flags, w[0..fold.len]));
                try t.expect(!ast.fullMatch(&tree, plain, w[0..fold.len]));
            }
        }
    }
}

test "perl: \\K moves the reported start, \\G matches at the search start" {
    const t = std.testing;
    @import("ucd.zig").init();
    const saved = dialect.active;
    defer dialect.active = saved;
    dialect.active = &dialect.perl_blead;
    const flags = try alpha.Flags.parse("u");
    const a = "(atom lit 0 0 0 61 0 0 0)";
    const b = "(atom lit 0 0 0 62 0 0 0)";
    const c = "(atom lit 0 0 0 63 0 0 0)";
    const x = "(atom lit 0 0 0 78 0 0 0)";
    const dot = "(atom dot 0 0 0 0 0 0 0)";
    // Measured with perl-blead and perl-pr (offset cases: pos() set, `anch`: /\G$re/g).
    const Case = struct { src: []const u8, w: []const u8, off: u16 = 0, anch: bool = false, s: u16 = 0, e: u16 = 0, found: bool = true, valid: bool = true };
    const cases = [_]Case{
        // a\Kbc on "abcd": [1,3); a(?:b\K)*c: [2,3) (not generated: \K in a fixed-length loop).
        .{ .src = "(concat " ++ a ++ " (concat (keep) (concat " ++ b ++ " " ++ c ++ ")))", .w = "abcd", .s = 1, .e = 3 },
        .{ .src = "(concat " ++ a ++ " (concat (quant star 0 255 0 (concat " ++ b ++ " (keep))) " ++ c ++ "))", .w = "abcd", .s = 2, .e = 3, .valid = false },
        // (?:a\K)x|ab on "ab": the \K is undone with its alternative: [0,2).
        .{ .src = "(alt (concat (group_nc (concat " ++ a ++ " (keep))) " ++ x ++ ") (concat " ++ a ++ " " ++ b ++ "))", .w = "ab", .s = 0, .e = 2 },
        // \Gb\K|a on "bbxa" from 1: [2,2).
        .{ .src = "(alt (concat (gpos) (concat " ++ b ++ " (keep))) " ++ a ++ ")", .w = "bbxa", .off = 1, .s = 2, .e = 2 },
        // \Ga|b on "bxb" from 1: [2,3); without an offset \G is 0: a\G never matches.
        .{ .src = "(alt (concat (gpos) " ++ a ++ ") " ++ b ++ ")", .w = "bxb", .off = 1, .s = 2, .e = 3 },
        .{ .src = "(concat " ++ a ++ " (gpos))", .w = "aab", .found = false, .valid = false },
        // (?<=\G.)x on "bxbx" from 2: [3,4); from 1: no match.
        .{ .src = "(concat (look_behind (concat (gpos) " ++ dot ++ ")) " ++ x ++ ")", .w = "bxbx", .off = 2, .s = 3, .e = 4 },
        .{ .src = "(concat (look_behind (concat (gpos) " ++ dot ++ ")) " ++ x ++ ")", .w = "bxbx", .off = 1, .found = false },
        // (?:\Gb|\Gx)a on "bbxa" from 2: [2,4), also anchored; \Gb|a anchored from 2: no match.
        .{ .src = "(concat (alt (concat (gpos) " ++ b ++ ") (concat (gpos) " ++ x ++ ")) " ++ a ++ ")", .w = "bbxa", .off = 2, .s = 2, .e = 4 },
        .{ .src = "(concat (alt (concat (gpos) " ++ b ++ ") (concat (gpos) " ++ x ++ ")) " ++ a ++ ")", .w = "bbxa", .off = 2, .anch = true, .s = 2, .e = 4 },
        .{ .src = "(alt (concat (gpos) " ++ b ++ ") " ++ a ++ ")", .w = "bbxa", .off = 2, .anch = true, .found = false },
    };
    for (cases) |k| {
        const tree = try ast.parse(k.src);
        try t.expectEqual(k.valid, ast.perlExtrasValid(&tree));
        var s16: [8]u16 = undefined;
        for (k.w, 0..) |ch, i| s16[i] = ch;
        const got = referenceAt(&tree, flags, s16[0..k.w.len], k.off, k.anch) orelse return error.NoResult;
        errdefer std.debug.print("case {s}: got {any}\n", .{ k.src, got });
        try t.expect(got.eql(.{ .found = k.found, .s = k.s, .e = k.e }));
    }
}

test "perl: where \\K, \\G and branch reset may go" {
    const t = std.testing;
    const saved = dialect.active;
    defer dialect.active = saved;
    dialect.active = &dialect.perl_blead;
    const a = "(atom lit 0 0 0 61 0 0 0)";
    const bad = [_][]const u8{
        "(look_ahead (concat " ++ a ++ " (keep)))", // \K not permitted in lookahead/lookbehind
        "(concat (atomic (concat " ++ a ++ " (keep))) " ++ a ++ ")", // Perl keeps it after backtracking
        "(concat (quant opt 0 1 0 (concat " ++ a ++ " (keep))) " ++ a ++ ")", // likewise: (?:a\K)?a is [1,1) on "a"
        "(concat " ++ a ++ " (gpos))", // Perl starts the search at pos()-1
        "(concat (quant opt 0 1 0 " ++ a ++ ") (gpos))", // GPOS_FLOAT: from the string start
        // In a lookaround too: perl-sticky "a" =~ /\G(?:(?!a\G))/g from 1 is no match.
        "(concat (look_behind (concat " ++ a ++ " (gpos))) " ++ a ++ ")",
        "(neg_look_ahead (concat " ++ a ++ " (gpos)))",
        "(branch_reset (alt (group_named " ++ a ++ ") (group_cap " ++ a ++ ")))",
    };
    for (bad) |src| try t.expect(!ast.perlExtrasValid(&(try ast.parse(src))));
    const good = [_][]const u8{
        "(concat (look_ahead " ++ a ++ ") (concat (gpos) " ++ a ++ "))",
        "(alt " ++ a ++ " (concat (gpos) " ++ a ++ "))",
        "(concat " ++ a ++ " (keep))",
        "(concat (quant star 0 255 0 (alt " ++ a ++ " (concat " ++ a ++ " (concat " ++ a ++ " (keep))))) " ++ a ++ ")",
    };
    for (good) |src| try t.expect(ast.perlExtrasValid(&(try ast.parse(src))));
    // PCRE2 has all three and undoes \\K on backtracking, so it may sit in an atomic group or an
    // optional group there: (?>a\\K)x|ab on "ab" is [0,2) and (?:a\\K)?a on "a" is [0,1)
    // (pcre2test 10.49). \\K in a lookaround is a compile error.
    dialect.active = &dialect.pcre2;
    try t.expect(dialect.treeAllowed(&(try ast.parse("(concat " ++ a ++ " (keep))"))));
    try t.expect(dialect.treeAllowed(&(try ast.parse("(concat (gpos) " ++ a ++ ")"))));
    try t.expect(dialect.treeAllowed(&(try ast.parse("(branch_reset (alt " ++ a ++ " " ++ a ++ "))"))));
    try t.expect(ast.perlExtrasValid(&(try ast.parse("(concat (atomic (concat " ++ a ++ " (keep))) " ++ a ++ ")"))));
    try t.expect(ast.perlExtrasValid(&(try ast.parse("(concat (quant opt 0 1 0 (concat " ++ a ++ " (keep))) " ++ a ++ ")"))));
    try t.expect(!ast.perlExtrasValid(&(try ast.parse("(look_ahead (concat " ++ a ++ " (keep)))"))));
    // Other dialects: none of them.
    dialect.active = &dialect.pcre1;
    try t.expect(!dialect.treeAllowed(&(try ast.parse("(concat " ++ a ++ " (keep))"))));
    try t.expect(!dialect.treeAllowed(&(try ast.parse("(concat (gpos) " ++ a ++ ")"))));
    try t.expect(!dialect.treeAllowed(&(try ast.parse("(branch_reset (alt " ++ a ++ " " ++ a ++ "))"))));
}

test "pcre2: an empty iteration at the minimum ends an open-ended loop, not a bounded one" {
    const t = std.testing;
    @import("ucd.zig").init();
    const saved = dialect.active;
    defer dialect.active = saved;
    dialect.active = &dialect.pcre2;
    const flags = try alpha.Flags.parse("u");
    // Measured with pcre2test 10.49 (interpreter and JIT) on "xa": ^(?:x|\\B()|\\1a){2,}$ is no
    // match, {2,3} and {3,} match. The second iteration can only be the empty \\B(), and \\1a
    // needs it to have run.
    const body = "(alt (alt (atom lit 0 0 0 78 0 0 0) (concat (atom nwordb 0 0 0 0 0 0 0) (group_cap (atom empty 0 0 0 0 0 0 0)))) (concat (backref 0) (atom lit 0 0 0 61 0 0 0)))";
    const cases = [_]struct { ast: []const u8, m: bool }{
        .{ .ast = "(quant open 2 255 0 " ++ body ++ ")", .m = false },
        .{ .ast = "(quant range 2 3 0 " ++ body ++ ")", .m = true },
        .{ .ast = "(quant open 3 255 0 " ++ body ++ ")", .m = true },
    };
    for (cases) |c| {
        const tree = try ast.parse(c.ast);
        try t.expectEqual(c.m, ast.fullMatch(&tree, flags, &.{ 'x', 'a' }));
    }
}

test "perl-pr: atomic groups inside lookbehind; perl-blead keeps them out" {
    const t = std.testing;
    const saved = dialect.active;
    defer dialect.active = saved;
    const src = "(concat (look_behind (atomic (quant opt 0 1 0 (atom lit 0 0 0 61 0 0 0)))) (atom lit 0 0 0 62 0 0 0))";
    const tree = try ast.parse(src);
    dialect.active = &dialect.perl_blead;
    try t.expect(!dialect.treeAllowed(&tree));
    dialect.active = dialect.byName("perl-pr") orelse return error.NoDialect;
    try t.expect(dialect.treeAllowed(&tree));
}
