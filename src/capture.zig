//! Capture-group checking (phase 2): the reference whole-match and group spans of an
//! unanchored search, compared with what a host reports.
//!
//! Wire format (capture mode), per case: subject A then subject R, each as 1 + `groups`
//! position pairs (whole match, then printed groups 1..groups), one byte per position in
//! the host's unit (`[span] units`); `ff ff` = no match / unset group. `fe` + bits in the
//! first byte means the case failed (04 syntax error, 08 exception, 40 unsupported).
//!
//! Group numbers: hosts report groups by printed number (opening-parenthesis order). The
//! printer's `()` empty-atom spelling adds groups the tree doesn't have, so each tree
//! capture is mapped to its printed number by re-printing the pattern with the case's
//! spelling seed; the extra groups are not checked.
//!
//! Semantics (docs/phase2-captures.md): a loop body's captures are cleared per iteration
//! or kept (`[capture] loop`); empty iterations follow the dialect's `empty_iteration`
//! (engines where that is `unmodeled` skip patterns with nullable loops). Positive
//! lookarounds keep their captures, negative ones leave none. Leftmost-longest dialects
//! (POSIX subexpression rules) are not modelled.
const std = @import("std");
const ast = @import("ast.zig");
const alpha = @import("alphabet.zig");
const dialect = @import("dialect.zig");
const config = @import("config.zig");
const finding = @import("finding.zig");
const harness = @import("harness.zig");
const sample = @import("sample.zig");
const span = @import("span.zig");

pub const groups = 6;
const pairs = 1 + groups;
pub const width = 2 * 2 * pairs;

/// Spans of one subject (UTF-16 offsets): [0] whole match, [1..] printed groups.
pub const Spans = struct {
    found: bool = false,
    s: [pairs]i16 = [_]i16{-1} ** pairs,
    e: [pairs]i16 = [_]i16{-1} ** pairs,
    invalid: bool = false,

    pub fn eql(a: Spans, b: Spans) bool {
        if (a.invalid or b.invalid or a.found != b.found) return false;
        if (!a.found) return true;
        return std.mem.eql(i16, &a.s, &b.s) and std.mem.eql(i16, &a.e, &b.e);
    }
};

/// Printed group number of each tree capture (opening-parenthesis order); `live[t]` is
/// false for a tree group the engine doesn't capture (expected unset).
const GroupMap = struct { n: u8, num: [ast.max_caps]u8, live: [ast.max_caps]bool };

fn groupMap(c: *const finding.Case) ?GroupMap {
    var buf: [1 << 16]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var out: std.ArrayList(u8) = .empty;
    var pr: sample.Printer = .{ .flags = c.flags, .out = &out, .gpa = fba.allocator(), .spell = c.spell };
    pr.print(&c.tree) catch return null;
    var gm: GroupMap = .{ .n = pr.n_tree_groups, .num = pr.tree_groups, .live = [_]bool{true} ** ast.max_caps };
    if (dialect.active.named_groups_only) {
        // Tree captures in opening-parenthesis order: kind of each, then drop unnamed ones
        // when any named group exists.
        var named = [_]bool{false} ** ast.max_caps;
        var k: usize = 0;
        var any = false;
        collectNamed(&c.tree, c.tree.root, &named, &k, &any);
        if (any) for (0..gm.n) |t| {
            gm.live[t] = named[t];
        };
    }
    return gm;
}

fn collectNamed(t: *const ast.Ast, idx: u8, named: *[ast.max_caps]bool, k: *usize, any: *bool) void {
    const n = t.nodes[idx];
    if (n.op == .group_cap or n.op == .group_named) {
        if (k.* < ast.max_caps) named[k.*] = n.op == .group_named;
        if (n.op == .group_named) any.* = true;
        k.* += 1;
    }
    if (n.op == .atom) return;
    collectNamed(t, n.a, named, k, any);
    if (ast.Op.isBinary(n.op)) collectNamed(t, n.b, named, k, any);
}

/// Reference spans for one subject, or null if not modelled / budget exhausted.
pub fn reference(c: *const finding.Case, subject: []const u16, gm: *const GroupMap, loop: config.CaptureLoop) ?Spans {
    var syms: [31]u21 = undefined;
    const n = alpha.decode(subject, c.flags, &syms) orelse return null;
    const w = syms[0..n];
    var caps = ast.Caps.init(&c.tree) orelse return null;
    var mt: ast.Matcher = .{ .t = &c.tree, .flags = c.flags, .w = w, .budget = 200_000, .caps = &caps, .reset_loop_captures = loop == .reset };
    var out: Spans = .{};
    var i: usize = 0;
    while (i <= n) : (i += 1) {
        caps.clear();
        const r = mt.matchAt(i) orelse return null;
        if (!r) continue;
        out.found = true;
        out.s[0] = @intCast(span.utf16Offset(w, i));
        out.e[0] = @intCast(span.utf16Offset(w, mt.end));
        for (0..gm.n) |t| {
            const p = gm.num[t];
            if (p > groups or !gm.live[t]) continue;
            const sl = caps.slot[t];
            if (sl.s < 0) continue;
            out.s[p] = @intCast(span.utf16Offset(w, @intCast(sl.s)));
            out.e[p] = @intCast(span.utf16Offset(w, @intCast(sl.e)));
        }
        return out;
    }
    return out;
}

fn hostSpans(subject: []const u16, raw: []const u8, units: config.SpanUnits) Spans {
    var out: Spans = .{};
    if (raw[0] == span.no_match) return out;
    out.found = true;
    for (0..pairs) |k| {
        const s = raw[2 * k];
        const e = raw[2 * k + 1];
        if (s == span.no_match) continue;
        const hs = span.hostToUtf16(subject, s, units);
        const he = span.hostToUtf16(subject, e, units);
        if (hs == null or he == null or he.? < hs.?) {
            out.invalid = true;
            continue;
        }
        out.s[k] = @intCast(hs.?);
        out.e[k] = @intCast(he.?);
    }
    return out;
}

pub const Check = struct {
    /// classify() domain for Expect.capture: test_a = A agrees, test_r = R disagrees.
    bits: u8,
    ref: [2]?Spans = .{ null, null },
    got: [2]?Spans = .{ null, null },
};

/// Does a quantifier whose body can match empty contain a capture group? Which iteration
/// records such a group differs between non-ES engines (docs/phase2-captures.md).
fn groupInNullableLoop(t: *const ast.Ast, idx: u8, in_nullable: bool) bool {
    const n = t.nodes[idx];
    if ((n.op == .group_cap or n.op == .group_named) and in_nullable) return true;
    if (n.op == .atom) return false;
    const inner = in_nullable or (n.op == .quant and span.minLen(t, n.a) == 0);
    if (groupInNullableLoop(t, n.a, inner)) return true;
    return ast.Op.isBinary(n.op) and groupInNullableLoop(t, n.b, inner);
}

/// Is there a capture group inside a quantifier body (`in_quant`) or a lookbehind?
fn groupContexts(t: *const ast.Ast, idx: u8, in_quant: bool, in_lb: bool, out: *[2]bool) void {
    const n = t.nodes[idx];
    if (n.op == .group_cap or n.op == .group_named) {
        if (in_quant) out[0] = true;
        if (in_lb) out[1] = true;
    }
    if (n.op == .atom) return;
    const q = in_quant or n.op == .quant;
    const lb = in_lb or n.op == .look_behind or n.op == .neg_look_behind;
    groupContexts(t, n.a, q, lb, out);
    if (ast.Op.isBinary(n.op)) groupContexts(t, n.b, q, lb, out);
}

pub fn check(c: *const finding.Case, raw: []const u8, cfg: *const config.Config) Check {
    if (raw[0] == span.failed) return .{ .bits = raw[1] };
    const skip: Check = .{ .bits = harness.Bits.skipped };
    if (dialect.active.span_semantics != .first) return skip;
    if (dialect.active.empty_iteration == .unmodeled and span.hasNullableLoop(&c.tree, c.tree.root)) return skip;
    if (dialect.active.empty_iteration != .reject and groupInNullableLoop(&c.tree, c.tree.root, false)) return skip;
    if (cfg.capture_loop == .unmodeled or !cfg.capture_lookbehind) {
        var ctx = [2]bool{ false, false };
        groupContexts(&c.tree, c.tree.root, false, false, &ctx);
        if (cfg.capture_loop == .unmodeled and ctx[0]) return skip;
        if (!cfg.capture_lookbehind and ctx[1]) return skip;
    }
    const gm = groupMap(c) orelse return skip;
    var ck: Check = .{ .bits = 0 };
    const subjects = [2][]const u16{ c.a.slice(), c.r.slice() };
    for (subjects, 0..) |subj, k| {
        ck.ref[k] = reference(c, subj, &gm, cfg.capture_loop) orelse return skip;
        ck.got[k] = hostSpans(subj, raw[k * (width / 2) ..][0 .. width / 2], cfg.span_units);
        // Only groups that exist in the tree are checked; `()` empty-atom spellings are not.
        var checked = [_]bool{false} ** pairs;
        checked[0] = true;
        for (gm.num[0..gm.n]) |num| {
            if (num <= groups) checked[num] = true;
        }
        for (1..pairs) |g| {
            if (!checked[g]) {
                ck.got[k].?.s[g] = -1;
                ck.got[k].?.e[g] = -1;
            }
        }
    }
    if (ck.ref[0].?.eql(ck.got[0].?)) ck.bits |= harness.Bits.test_a;
    if (!ck.ref[1].?.eql(ck.got[1].?)) ck.bits |= harness.Bits.test_r;
    return ck;
}

fn writeSpans(out: *std.ArrayList(u8), gpa: std.mem.Allocator, sp: ?Spans) !void {
    const x = sp orelse return out.appendSlice(gpa, "null");
    if (x.invalid) try out.appendSlice(gpa, "\"invalid\", ");
    if (!x.found) return out.appendSlice(gpa, "\"no match\"");
    try out.append(gpa, '[');
    for (0..pairs) |k| {
        if (k > 0) try out.appendSlice(gpa, ", ");
        if (x.s[k] < 0) try out.appendSlice(gpa, "null") else try out.print(gpa, "[{d},{d}]", .{ x.s[k], x.e[k] });
    }
    try out.append(gpa, ']');
}

/// JSON fragment: whole match then groups 1..6, UTF-16 offsets.
pub fn extraJson(out: *std.ArrayList(u8), gpa: std.mem.Allocator, ck: Check, raw: []const u8) !void {
    try out.appendSlice(gpa, "\"captures\": {\"units\": \"utf16 offsets; [whole, group 1, ...]\", \"expected_a\": ");
    try writeSpans(out, gpa, ck.ref[0]);
    try out.appendSlice(gpa, ", \"observed_a\": ");
    try writeSpans(out, gpa, ck.got[0]);
    try out.appendSlice(gpa, ", \"expected_r\": ");
    try writeSpans(out, gpa, ck.ref[1]);
    try out.appendSlice(gpa, ", \"observed_r\": ");
    try writeSpans(out, gpa, ck.got[1]);
    try out.appendSlice(gpa, ", \"raw\": \"");
    for (raw) |b| try out.print(gpa, "{x:0>2}", .{b});
    try out.appendSlice(gpa, "\"}");
}
