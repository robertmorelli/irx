//! Mutation mode: constructs the relation model cannot express (atomic groups, possessive
//! quantifiers, backreferences, conditionals) are spliced into a sampled tree, and the case's expected answers
//! come from the backtracking reference matcher instead (ast.fullMatch takes the matcher path for
//! such trees). Spans and captures already use the matcher.
const std = @import("std");
const ast = @import("ast.zig");
const alpha = @import("alphabet.zig");
const dialect = @import("dialect.zig");
const rngmod = @import("rng.zig");
const span = @import("span.zig");

pub const Kind = enum { atomic, possessive, backref, keep, gpos, branch_reset, cond };
pub const n_kinds = @typeInfo(Kind).@"enum".fields.len;

/// Relative weight of each mutation kind, in Kind order (config [grammar] mutate_atomic,
/// mutate_possessive, mutate_backref, mutate_keep, mutate_gpos, mutate_branch_reset,
/// mutate_conditional); a kind the dialect lacks is never drawn.
pub const Weights = [n_kinds]f64;
/// The config defaults.
pub const default_weights: Weights = .{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.5 };

/// Parent of every node (255 = root / unreached).
fn parents(t: *const ast.Ast, out: *[ast.max_nodes]u8) void {
    @memset(out[0..t.len], 255);
    for (t.nodes[0..t.len], 0..) |n, i| {
        if (n.op.isLeaf()) continue;
        out[n.a] = @intCast(i);
        if (ast.Op.isBinary(n.op)) out[n.b] = @intCast(i);
    }
}

/// Is node `idx` inside a quantifier or lookaround (walking up from it)?
fn inLoopOrLook(par: *const [ast.max_nodes]u8, t: *const ast.Ast, idx: u8) bool {
    var p = par[idx];
    while (p != 255) : (p = par[p]) {
        switch (t.nodes[p].op) {
            .quant, .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind, .atomic => return true,
            else => {},
        }
    }
    return false;
}

fn hasCapture(t: *const ast.Ast, idx: u8) bool {
    const n = t.nodes[idx];
    if (n.op == .group_cap) return true;
    if (n.op.isLeaf()) return false;
    return hasCapture(t, n.a) or (ast.Op.isBinary(n.op) and hasCapture(t, n.b));
}

/// Wrap node `idx` in a new node `wrap` (its child): the parent (or the root) points at it.
fn wrapNode(t: *ast.Ast, par: *const [ast.max_nodes]u8, idx: u8, wrap: ast.Node) !void {
    var w = wrap;
    w.a = idx;
    const ni = try t.add(w);
    const p = par[idx];
    if (p == 255) {
        t.root = ni;
    } else if (t.nodes[p].a == idx) {
        t.nodes[p].a = ni;
    } else {
        t.nodes[p].b = ni;
    }
}

/// Splice leaf `leaf` next to node `idx` (before or after it) in a new concatenation.
fn spliceConcat(t: *ast.Ast, par: *const [ast.max_nodes]u8, idx: u8, leaf: ast.Node, before: bool) !void {
    const li = try t.add(leaf);
    const p = par[idx];
    const ci = try t.add(.{ .op = .concat, .a = if (before) li else idx, .b = if (before) idx else li });
    if (p == 255) {
        t.root = ci;
    } else if (t.nodes[p].a == idx) {
        t.nodes[p].a = ci;
    } else {
        t.nodes[p].b = ci;
    }
}

fn kindAllowed(d: *const dialect.Dialect, k: Kind) bool {
    return switch (k) {
        .atomic, .possessive => d.atomic_groups,
        .backref => d.backrefs,
        .keep => d.keep_escape,
        .gpos => d.gpos_escape,
        .branch_reset => d.branch_reset,
        .cond => d.conditionals,
    };
}

/// Mutate `t` in place for `flags`; false (tree unchanged) when no mutation applies or the
/// result is not something the dialect accepts. Tries a few random choices.
pub fn apply(t: *ast.Ast, rng: *rngmod.Rng) bool {
    return applyWeighted(t, rng, &default_weights);
}

pub fn applyWeighted(t: *ast.Ast, rng: *rngmod.Rng, weights: *const Weights) bool {
    const d = dialect.active;
    var total: f64 = 0;
    for (weights, 0..) |w, i| {
        if (kindAllowed(d, @enumFromInt(i))) total += w;
    }
    if (!(total > 0)) return false;
    const orig = t.*;
    var attempt: usize = 0;
    while (attempt < 8) : (attempt += 1) {
        t.* = orig;
        var par: [ast.max_nodes]u8 = undefined;
        parents(t, &par);
        var kind: Kind = .atomic;
        var x = rng.float() * total;
        for (weights, 0..) |w, i| {
            const k: Kind = @enumFromInt(i);
            if (!kindAllowed(d, k) or w <= 0) continue;
            kind = k;
            if (x < w) break;
            x -= w;
        }
        const ok = switch (kind) {
            .atomic => blk: {
                const idx: u8 = @intCast(rng.below(t.len));
                wrapNode(t, &par, idx, .{ .op = .atomic }) catch break :blk false;
                break :blk true;
            },
            .possessive => blk: {
                var qs: [ast.max_nodes]u8 = undefined;
                var nq: usize = 0;
                for (t.nodes[0..t.len], 0..) |n, i| if (n.op == .quant and !n.quant.lazy) {
                    qs[nq] = @intCast(i);
                    nq += 1;
                };
                if (nq == 0) break :blk false;
                wrapNode(t, &par, qs[rng.below(nq)], .{ .op = .atomic }) catch break :blk false;
                break :blk true;
            },
            .backref => blk: {
                const caps = ast.Caps.init(t) orelse break :blk false;
                // Target: a capture group outside loops and lookarounds; site: an atom after it.
                var gs: [ast.max_nodes]u8 = undefined;
                var ng: usize = 0;
                for (t.nodes[0..t.len], 0..) |n, i| if ((n.op == .group_cap or n.op == .group_named) and !inLoopOrLook(&par, t, @intCast(i))) {
                    gs[ng] = @intCast(i);
                    ng += 1;
                };
                // Onigmo/Oniguruma: once a named group exists, unnamed groups do not capture and
                // references must be by name, so only named targets.
                if (d.backref_by_name) {
                    var any_named = false;
                    for (t.nodes[0..t.len]) |n| if (n.op == .group_named) {
                        any_named = true;
                    };
                    if (any_named) {
                        var k: usize = 0;
                        for (gs[0..ng]) |gi| if (t.nodes[gi].op == .group_named) {
                            gs[k] = gi;
                            k += 1;
                        };
                        ng = k;
                    }
                }
                if (ng == 0) break :blk false;
                const g = gs[rng.below(ng)];
                var sites: [ast.max_nodes]u8 = undefined;
                var ns: usize = 0;
                for (t.nodes[0..t.len], 0..) |n, i| if (n.op == .atom) {
                    sites[ns] = @intCast(i);
                    ns += 1;
                };
                if (ns == 0) break :blk false;
                const site = sites[rng.below(ns)];
                t.nodes[site] = .{ .op = .backref, .fmod = caps.ordinal[g] };
                break :blk ast.backrefsValid(t);
            },
            // \K or \G before or after a random node; ast.perlExtrasValid keeps \K out of
            // lookarounds and \G where Perl's search start is pos().
            .keep, .gpos => blk: {
                const idx: u8 = @intCast(rng.below(t.len));
                const leaf: ast.Node = .{ .op = if (kind == .keep) .keep else .gpos };
                spliceConcat(t, &par, idx, leaf, rng.below(4) != 0) catch break :blk false;
                break :blk true;
            },
            .branch_reset => blk: {
                // An alternation holding a capture group (and no named group).
                var alts: [ast.max_nodes]u8 = undefined;
                var na: usize = 0;
                for (t.nodes[0..t.len], 0..) |n, i| if (n.op == .alt and hasCapture(t, @intCast(i))) {
                    alts[na] = @intCast(i);
                    na += 1;
                };
                if (na == 0) break :blk false;
                wrapNode(t, &par, alts[rng.below(na)], .{ .op = .branch_reset }) catch break :blk false;
                break :blk true;
            },
            .cond => condMutation(t, &par, rng),
        };
        if (!ast.perlExtrasValid(t)) continue;
        if (!ok) continue;
        if (!dialect.treeAllowed(t)) continue;
        // What an atomic group commits to, and what a group captures for a backreference, follow
        // the engine's empty-iteration rule: not modelled for some dialects.
        if (d.empty_iteration == .unmodeled and span.hasNullableLoop(t, t.root)) continue;
        return true;
    }
    t.* = orig;
    return false;
}

/// Can a conditional test capture group `g` exactly? Not under a loop that can repeat (Perl
/// >= 5.38 clears some loop captures per iteration and not others: the capture model's
/// `loop = "unmodeled"`), nor under an optional whose body can match empty (which iteration
/// records the group differs between engines); lookbehind only where the model runs it like
/// the engine (Perl's forward lookbehind).
fn condTarget(par: *const [ast.max_nodes]u8, t: *const ast.Ast, g: u8) bool {
    var p = par[g];
    while (p != 255) : (p = par[p]) {
        const n = t.nodes[p];
        switch (n.op) {
            .quant => if (n.quant.max != 1 or span.minLen(t, n.a) == 0) return false,
            .look_behind, .neg_look_behind => if (!dialect.active.lookbehind_forward) return false,
            else => {},
        }
    }
    return true;
}

/// Pre-order number of every node reachable from the root.
fn preorder(t: *const ast.Ast, idx: u8, k: *u8, out: *[ast.max_nodes]u8) void {
    out[idx] = k.*;
    k.* +%= 1;
    const n = t.nodes[idx];
    if (n.op.isLeaf()) return;
    preorder(t, n.a, k, out);
    if (ast.Op.isBinary(n.op)) preorder(t, n.b, k, out);
}

/// Splice in a conditional on a capture group G: some node X after G (in pattern order) becomes
/// (?(G)X|Y), (?(G)X), (?(G)|X) or (?(G)Y|X), Y a copy of an atom of the tree. G is sometimes
/// first made optional, so that it is set on some paths and not on others, or put in an atomic
/// group or lookahead.
fn condMutation(t: *ast.Ast, par: *[ast.max_nodes]u8, rng: *rngmod.Rng) bool {
    var gs: [ast.max_nodes]u8 = undefined;
    var ng: usize = 0;
    for (t.nodes[0..t.len], 0..) |n, i| if ((n.op == .group_cap or n.op == .group_named) and condTarget(par, t, @intCast(i))) {
        gs[ng] = @intCast(i);
        ng += 1;
    };
    if (ng == 0) return false;
    const g = gs[rng.below(ng)];
    // Make G optional, (G)? or (G)??, when no quantifier encloses it and it cannot match empty;
    // or put it in an atomic group or (outside quantifiers) a lookahead, whose captures must be
    // undone when backtracking goes back past them (IRX-PERL-11).
    var under_quant = false;
    var p = par[g];
    while (p != 255) : (p = par[p]) {
        if (t.nodes[p].op == .quant) under_quant = true;
    }
    const wrap: ?ast.Node = switch (rng.below(6)) {
        0, 1 => if (!under_quant and span.minLen(t, g) > 0) .{ .op = .quant, .quant = .{ .form = .opt, .min = 0, .max = 1, .lazy = rng.below(4) == 0 } } else null,
        2 => if (dialect.active.atomic_groups) .{ .op = .atomic } else null,
        3 => if (!under_quant and dialect.active.allow_lookahead) .{ .op = .look_ahead } else null,
        else => null,
    };
    if (wrap) |w| {
        wrapNode(t, par, g, w) catch return false;
        parents(t, par);
    }
    const caps = ast.Caps.init(t) orelse return false;
    var pre: [ast.max_nodes]u8 = undefined;
    @memset(pre[0..t.len], 255);
    var k: u8 = 0;
    preorder(t, t.root, &k, &pre);
    const after: usize = @as(usize, pre[g]) + t.size(g);
    var sites: [ast.max_nodes]u8 = undefined;
    var ns: usize = 0;
    for (0..t.len) |i| if (pre[i] != 255 and pre[i] >= after) {
        sites[ns] = @intCast(i);
        ns += 1;
    };
    if (ns == 0) return false;
    const x = sites[rng.below(ns)];
    var atoms_: [ast.max_nodes]u8 = undefined;
    var na: usize = 0;
    for (t.nodes[0..t.len], 0..) |n, i| if (n.op == .atom and pre[i] != 255) {
        atoms_[na] = @intCast(i);
        na += 1;
    };
    const form = rng.below(4);
    const other: ast.Node = switch (form) {
        0, 3 => if (na > 0) t.nodes[atoms_[rng.below(na)]] else .{ .op = .atom, .atom = .{ .kind = .empty } },
        else => .{ .op = .atom, .atom = .{ .kind = .empty } },
    };
    const y = t.add(other) catch return false;
    const yes_x = form == 0 or form == 1;
    const ci = t.add(.{ .op = .cond, .fmod = caps.ordinal[g], .a = if (yes_x) x else y, .b = if (yes_x) y else x }) catch return false;
    const px = par[x];
    if (px == 255) {
        t.root = ci;
    } else if (t.nodes[px].a == x) {
        t.nodes[px].a = ci;
    } else {
        t.nodes[px].b = ci;
    }
    return ast.backrefsValid(t);
}

// ---------------------------------------------------------------------------
// Tests

const testing = std.testing;

fn sx(comptime c: u8) []const u8 {
    return std.fmt.comptimePrint("(atom lit 0 0 0 {x} 0 0 0)", .{c});
}
const sx_empty = "(atom empty 0 0 0 0 0 0 0)";
const sx_caret = "(atom caret 0 0 0 0 0 0 0)";
fn sxCat(comptime a: []const u8, comptime b: []const u8) []const u8 {
    return "(concat " ++ a ++ " " ++ b ++ ")";
}
fn sxAlt(comptime a: []const u8, comptime b: []const u8) []const u8 {
    return "(alt " ++ a ++ " " ++ b ++ ")";
}
fn sxCap(comptime a: []const u8) []const u8 {
    return "(group_cap " ++ a ++ ")";
}
fn sxOpt(comptime a: []const u8) []const u8 {
    return "(quant opt 0 1 0 " ++ a ++ ")";
}
fn sxCond(comptime g: u8, comptime y: []const u8, comptime n: []const u8) []const u8 {
    return std.fmt.comptimePrint("(cond {d} ", .{g}) ++ y ++ " " ++ n ++ ")";
}

test "perl: conditional groups print and match like perl" {
    const sample = @import("sample.zig");
    const spanmod = @import("span.zig");
    @import("ucd.zig").init();
    const saved = dialect.active;
    defer dialect.active = saved;
    dialect.active = &dialect.perl_blead;
    const gpa = testing.allocator;
    const flags = try alpha.Flags.parse("u");
    const a = comptime sx('a');
    const b = comptime sx('b');
    const c = comptime sx('c');
    const x = comptime sx('x');
    const y = comptime sx('y');
    const d = comptime sx('d');
    const Sub = struct { w: []const u8, s: i16, e: i16 = -1, c1: [2]i16 = .{ -1, -1 } };
    const Case = struct { src: []const u8, pat: []const u8, subs: []const Sub };
    // Expected: perl built from PR #25087 (701da6a); blead 1ac3f11 and perl 5.34 agree on every
    // subject except the IRX-PERL-11 shape (marked below), where they keep a stale $1.
    const cases = comptime [_]Case{
        .{ .src = sxCat(sxOpt(sxCap(a)), sxCond(0, b, c)), .pat = "(a)?(?(1)b|c)", .subs = &.{
            .{ .w = "ab", .s = 0, .e = 2, .c1 = .{ 0, 1 } }, .{ .w = "c", .s = 0, .e = 1 }, .{ .w = "ac", .s = 1, .e = 2 }, .{ .w = "b", .s = -1 },
        } },
        .{ .src = sxCat(sxAlt(sxCat(sxCap(a), x), sxCat(a, y)), sxCond(0, b, c)), .pat = "(?:(a)x|ay)(?(1)b|c)", .subs = &.{
            .{ .w = "ayc", .s = 0, .e = 3 }, .{ .w = "axb", .s = 0, .e = 3, .c1 = .{ 0, 1 } }, .{ .w = "axc", .s = -1 },
        } },
        .{ .src = sxCat(sxAlt(sxCat("(look_ahead " ++ sxCap(a) ++ ")", sxCat(a, b)), sxCat(a, c)), sxCond(0, x, y)), .pat = "(?:(?=(a))ab|ac)(?(1)x|y)", .subs = &.{
            .{ .w = "acy", .s = 0, .e = 3 }, .{ .w = "abx", .s = 0, .e = 3, .c1 = .{ 0, 1 } }, .{ .w = "acx", .s = -1 },
        } },
        .{ .src = sxCat(sxAlt(sxCat("(atomic " ++ sxCap(a) ++ ")", b), sxCat(a, c)), sxCond(0, x, y)), .pat = "(?:(?>(a))b|ac)(?(1)x|y)", .subs = &.{
            .{ .w = "acy", .s = 0, .e = 3 }, .{ .w = "abx", .s = 0, .e = 3, .c1 = .{ 0, 1 } },
        } },
        // IRX-PERL-11 through a conditional: blead and 5.34 match "ax" with $1 = [1,1), not "ay".
        .{ .src = sxCat(sxCat(sxCat("(quant star 0 255 0 " ++ a ++ ")", "(look_ahead " ++ sxAlt(sx_caret, sxCap(sx_empty)) ++ ")"), a), sxCond(0, x, y)), .pat = "a*(?=^|((?:)))a(?(1)x|y)", .subs = &.{
            .{ .w = "ay", .s = 0, .e = 2 }, .{ .w = "ax", .s = -1 }, .{ .w = "aax", .s = 0, .e = 3, .c1 = .{ 1, 1 } },
        } },
        .{ .src = sxCat(sxOpt(sxCap(a)), sxCond(0, b, sx_empty)), .pat = "(a)?(?(1)b)", .subs = &.{
            .{ .w = "", .s = 0, .e = 0 }, .{ .w = "ab", .s = 0, .e = 2, .c1 = .{ 0, 1 } }, .{ .w = "a", .s = 0, .e = 0 },
        } },
        .{ .src = sxCat("(neg_look_ahead " ++ sxCap(a) ++ ")", sxCond(0, x, y)), .pat = "(?!(a))(?(1)x|y)", .subs = &.{
            .{ .w = "y", .s = 0, .e = 1 }, .{ .w = "ay", .s = 1, .e = 2 },
        } },
        .{ .src = sxCat(sxOpt(sxCap(a)), sxCond(0, sxAlt(b, c), d)), .pat = "(a)?(?(1)(?:b|c)|d)", .subs = &.{
            .{ .w = "ac", .s = 0, .e = 2, .c1 = .{ 0, 1 } }, .{ .w = "d", .s = 0, .e = 1 }, .{ .w = "ad", .s = 1, .e = 2 },
        } },
        .{ .src = sxCat("(quant opt 0 1 1 " ++ sxCap(a) ++ ")", sxCond(0, a, b)), .pat = "(a)??(?(1)a|b)", .subs = &.{
            .{ .w = "aa", .s = 0, .e = 2, .c1 = .{ 0, 1 } }, .{ .w = "ab", .s = 1, .e = 2 },
        } },
        .{ .src = sxCat(sxAlt("(look_behind " ++ sxCap(a) ++ ")", x), sxCond(0, b, c)), .pat = "(?:(?<=(a))|x)(?(1)b|c)", .subs = &.{
            .{ .w = "ab", .s = 1, .e = 2, .c1 = .{ 0, 1 } }, .{ .w = "xc", .s = 0, .e = 2 },
        } },
        .{ .src = sxCat(sxOpt(sxCap(a)), "(quant plus 1 255 0 " ++ sxCond(0, b, c) ++ ")"), .pat = "(a)?(?(1)b|c)+", .subs = &.{
            .{ .w = "abb", .s = 0, .e = 3, .c1 = .{ 0, 1 } }, .{ .w = "cc", .s = 0, .e = 2 }, .{ .w = "acc", .s = 1, .e = 3 },
        } },
        .{ .src = sxCat(sxOpt(sxCap(a)), sxCond(0, sx_empty, c)), .pat = "(a)?(?(1)(?:)|c)", .subs = &.{
            .{ .w = "a", .s = 0, .e = 1, .c1 = .{ 0, 1 } }, .{ .w = "c", .s = 0, .e = 1 }, .{ .w = "x", .s = -1 },
        } },
    };
    inline for (cases) |cs| {
        const tree = try ast.parse(cs.src);
        try testing.expect(ast.backrefsValid(&tree));
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try sample.printAlloc(gpa, &tree, flags, &out);
        try testing.expectEqualStrings(cs.pat, out.items);
        // Serialization round trip.
        var ser: std.ArrayList(u8) = .empty;
        defer ser.deinit(gpa);
        try ast.serialize(&tree, &ser, gpa);
        try testing.expectEqualStrings(cs.src, ser.items);
        for (cs.subs) |sub| {
            var w: [8]u21 = undefined;
            var w16: [8]u16 = undefined;
            for (sub.w, 0..) |ch, i| {
                w[i] = ch;
                w16[i] = ch;
            }
            const ws = w[0..sub.w.len];
            var caps = ast.Caps.init(&tree) orelse return error.Caps;
            var mt: ast.Matcher = .{ .t = &tree, .flags = flags, .w = ws, .caps = &caps };
            var s: i16 = -1;
            var e: i16 = -1;
            var i: usize = 0;
            while (i <= ws.len) : (i += 1) {
                caps.clear();
                if (mt.matchAt(i) orelse return error.Budget) {
                    s = @intCast(i);
                    e = @intCast(mt.end);
                    break;
                }
            }
            errdefer std.debug.print("{s} on \"{s}\": got [{d},{d}) $1 [{d},{d})\n", .{ cs.pat, sub.w, s, e, caps.slot[0].s, caps.slot[0].e });
            try testing.expectEqual(sub.s, s);
            if (s >= 0) {
                try testing.expectEqual(sub.e, e);
                try testing.expectEqual(sub.c1[0], caps.slot[0].s);
                try testing.expectEqual(sub.c1[1], caps.slot[0].e);
            }
            // The span reference (a fresh search) agrees.
            const sp = spanmod.reference(&tree, flags, w16[0..sub.w.len]) orelse return error.Budget;
            try testing.expectEqual(sub.s >= 0, sp.found);
            if (sp.found) try testing.expect(sp.s == sub.s and sp.e == sub.e);
        }
    }
}

test "conditional mutation: generated, valid, printed with an existing group number" {
    const sample = @import("sample.zig");
    @import("ucd.zig").init();
    const saved = dialect.active;
    defer dialect.active = saved;
    var cw = default_weights;
    cw[@intFromEnum(Kind.cond)] = 1000;
    const gpa = testing.allocator;
    const flags = try alpha.Flags.parse("u");
    var prng = std.Random.DefaultPrng.init(0xC0D1);
    const rnd = prng.random();
    // No conditionals where the dialect has none (ES).
    dialect.active = &dialect.es;
    {
        const inv = try @import("atoms.zig").buildInventory(gpa, .{}, flags);
        defer gpa.free(inv);
        for (0..200) |k| {
            var t: ast.Ast = .{};
            t.root = try ast.randomTree(&t, rnd, inv, 10);
            t.root = try t.add(.{ .op = .concat, .a = try t.add(.{ .op = .group_cap, .a = try t.add(.{ .op = .atom, .atom = inv[0] }) }), .b = t.root });
            var r = rngmod.Rng.fromParts(1, &.{k});
            if (applyWeighted(&t, &r, &cw)) for (t.nodes[0..t.len]) |n| try testing.expect(n.op != .cond);
        }
    }
    dialect.active = &dialect.perl_blead;
    const inv = try @import("atoms.zig").buildInventory(gpa, .{}, flags);
    defer gpa.free(inv);
    var made: usize = 0;
    var optional: usize = 0;
    var named: usize = 0;
    for (0..3000) |k| {
        var t: ast.Ast = .{};
        t.root = try ast.randomTree(&t, rnd, inv, 10);
        // A capture group first (sometimes named), so most trees have a target.
        const g = try t.add(.{ .op = if (k % 3 == 0) .group_named else .group_cap, .a = try t.add(.{ .op = .atom, .atom = inv[k % inv.len] }) });
        t.root = try t.add(.{ .op = .concat, .a = g, .b = t.root });
        if (!dialect.treeAllowed(&t)) continue;
        var r = rngmod.Rng.fromParts(2, &.{k});
        if (!applyWeighted(&t, &r, &cw)) continue;
        const tc = t.compact();
        var ncond: usize = 0;
        for (tc.nodes[0..tc.len]) |n| if (n.op == .cond) {
            ncond += 1;
        };
        if (ncond == 0) continue;
        made += 1;
        try testing.expect(ast.backrefsValid(&tc));
        try testing.expect(dialect.treeAllowed(&tc));
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        var pr: sample.Printer = .{ .flags = flags, .out = &out, .gpa = gpa, .spell = r.next() | 1 };
        try pr.print(&tc);
        const at = std.mem.indexOf(u8, out.items, "(?(") orelse return error.NoCond;
        if (std.mem.indexOf(u8, out.items[0..at], ")?") != null) optional += 1;
        const rest = out.items[at + 3 ..];
        if (rest[0] == '<' or rest[0] == '\'') {
            named += 1;
        } else {
            const close = std.mem.indexOfScalar(u8, rest, ')') orelse return error.Bad;
            const num = try std.fmt.parseInt(u8, rest[0..close], 10);
            try testing.expect(num >= 1 and num <= pr.printed_groups);
        }
        // The oracle answers (the matcher, with capture state).
        const w = [_]u21{ 'a', 'b' };
        _ = ast.fullMatchOrNull(&tc, flags, &w);
    }
    try testing.expect(made > 300);
    try testing.expect(optional > 0);
    try testing.expect(named > 0);
}

test "perl-pr: every mutation kind is drawn; \\K and \\G rules hold inside conditionals" {
    @import("ucd.zig").init();
    const saved = dialect.active;
    defer dialect.active = saved;
    dialect.active = dialect.byName("perl-pr") orelse return error.NoDialect;
    for (std.enums.values(Kind)) |k| try testing.expect(kindAllowed(dialect.active, k));
    const a = comptime sx('a');
    const b = comptime sx('b');
    // \K in a conditional's branch is an alternative like any other; \G never inside one.
    try testing.expect(ast.perlExtrasValid(&(try ast.parse(sxCat(sxOpt(sxCap(a)), sxCond(0, sxCat(a, "(keep)"), b))))));
    try testing.expect(!ast.perlExtrasValid(&(try ast.parse(sxCat(sxCap(sx_empty), sxCond(0, sxCat("(gpos)", a), b))))));
    try testing.expect(!ast.perlExtrasValid(&(try ast.parse(sxCat("(look_ahead " ++ sxCond(0, "(keep)", b) ++ ")", sxCap(a))))));
    // Each kind alone, at full weight, gets applied on some tree.
    const gpa = testing.allocator;
    const flags = try alpha.Flags.parse("u");
    const inv = try @import("atoms.zig").buildInventory(gpa, .{}, flags);
    defer gpa.free(inv);
    var prng = std.Random.DefaultPrng.init(0x5EED);
    const rnd = prng.random();
    const want = [_]ast.Op{ .atomic, .atomic, .backref, .keep, .gpos, .branch_reset, .cond };
    for (std.enums.values(Kind), 0..) |k, ki| {
        var w: Weights = [_]f64{0} ** n_kinds;
        w[@intFromEnum(k)] = 1;
        var hit = false;
        var i: usize = 0;
        while (i < 2000 and !hit) : (i += 1) {
            var t: ast.Ast = .{};
            t.root = try ast.randomTree(&t, rnd, inv, 10);
            const g = try t.add(.{ .op = .group_cap, .a = try t.add(.{ .op = .atom, .atom = inv[i % inv.len] }) });
            t.root = try t.add(.{ .op = .concat, .a = g, .b = try t.add(.{ .op = .alt, .a = t.root, .b = try t.add(.{ .op = .group_cap, .a = try t.add(.{ .op = .atom, .atom = inv[(i + 1) % inv.len] }) }) }) });
            if (!dialect.treeAllowed(&t)) continue;
            var r = rngmod.Rng.fromParts(3, &.{ ki, i });
            if (!applyWeighted(&t, &r, &w)) continue;
            try testing.expect(ast.perlExtrasValid(&t) and ast.backrefsValid(&t));
            for (t.nodes[0..t.len]) |n| if (n.op == want[ki]) {
                hit = true;
            };
        }
        errdefer std.debug.print("kind {s} never applied\n", .{@tagName(k)});
        try testing.expect(hit);
    }
}
