//! Mutation mode: constructs the relation model cannot express (atomic groups, possessive
//! quantifiers, backreferences) are spliced into a sampled tree, and the case's expected answers
//! come from the backtracking reference matcher instead (ast.fullMatch takes the matcher path for
//! such trees). Spans and captures already use the matcher.
const std = @import("std");
const ast = @import("ast.zig");
const alpha = @import("alphabet.zig");
const dialect = @import("dialect.zig");
const rngmod = @import("rng.zig");

pub const Kind = enum { atomic, possessive, backref };

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

/// Mutate `t` in place for `flags`; false (tree unchanged) when no mutation applies or the
/// result is not something the dialect accepts. Tries a few random choices.
pub fn apply(t: *ast.Ast, rng: *rngmod.Rng) bool {
    const d = dialect.active;
    var kinds: [3]Kind = undefined;
    var nk: usize = 0;
    if (d.atomic_groups) {
        kinds[nk] = .atomic;
        nk += 1;
        kinds[nk] = .possessive;
        nk += 1;
    }
    if (d.backrefs) {
        kinds[nk] = .backref;
        nk += 1;
    }
    if (nk == 0) return false;
    const orig = t.*;
    var attempt: usize = 0;
    while (attempt < 8) : (attempt += 1) {
        t.* = orig;
        var par: [ast.max_nodes]u8 = undefined;
        parents(t, &par);
        const kind = kinds[rng.below(nk)];
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
        };
        if (!ok) continue;
        if (!dialect.treeAllowed(t)) continue;
        // What an atomic group commits to, and what a group captures for a backreference, follow
        // the engine's empty-iteration rule: not modelled for some dialects.
        if (d.empty_iteration == .unmodeled and @import("span.zig").hasNullableLoop(t, t.root)) continue;
        return true;
    }
    t.* = orig;
    return false;
}
