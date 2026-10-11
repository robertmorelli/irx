//! Pair table: a budgeted, deterministic, bottom-up build of the regular tree
//! grammar whose nonterminals are interned (rel_A, rel_R) pairs, followed by
//! optional usefulness pruning, renumbering, and log-space weighted counts.
//!
//! Soundness never depends on completeness: any retained subgrammar yields
//! only regexes that fully match A and fully reject R.
const std = @import("std");
const alpha = @import("alphabet.zig");
const atoms = @import("atoms.zig");
const ast = @import("ast.zig");
const relmod = @import("rel.zig");
const config = @import("config.zig");
const budget_mod = @import("budget.zig");
const rngmod = @import("rng.zig");
const sys = @import("sys.zig");
const dialect_mod = @import("dialect.zig");

const Flags = alpha.Flags;
const AtomSpec = atoms.AtomSpec;
const Op = ast.Op;
const QuantSpec = ast.QuantSpec;
const Budget = budget_mod.Budget;
const Allocator = std.mem.Allocator;

pub const generator_version = "irx-gen-1";
pub const numerics_version = "irx-num-1 (f32 log counts, f64 log-sum-exp, Vose alias f32)";

pub const none: u32 = 0xFFFF_FFFF;

pub const Prod = extern struct {
    op: u8,
    _pad: u8 = 0,
    arg: u16,
    lhs: u32,
    a: u32,
    b: u32,
};
comptime {
    std.debug.assert(@sizeOf(Prod) == 16);
}

// ---------------------------------------------------------------------------
// Grammar inventory for one flag set (deterministic in config + flags)

pub const UnaryEntry = struct { op: Op, arg: u16, w: f64 };
pub const BinaryEntry = struct { op: Op, w: f64 };

/// Pair-key aux layout: saturating max length in bits 0..7, min in 8..15, subtree flags in 16..31.
pub const aux_len_mask: u32 = 0xFF;
pub const aux_min_shift: u5 = 8;
pub const aux_flags: u32 = 0xFFFF0000;
/// contains a lookahead
pub const aux_la: u32 = 1 << 16;
/// contains `$` under the m flag
pub const aux_md: u32 = 1 << 17;
/// contains a quantifier with min != max
pub const aux_vq: u32 = 1 << 18;
/// contains a quantifier Java refuses inside lookbehind: unbounded over a non-atom, lazy
/// unbounded, or counted (other than {0,1}) over a group holding an alternation or quantifier
pub const aux_uq: u32 = 1 << 19;
/// is a single consuming atom (possibly in non-capturing groups)
pub const aux_atom: u32 = 1 << 20;
/// is an assertion, or an alternation/non-capturing group offering one as a branch
pub const aux_za: u32 = 1 << 21;
/// contains an alternation or quantifier
pub const aux_cx: u32 = 1 << 22;
/// contains a lookaround
pub const aux_lk: u32 = 1 << 23;
/// contains a capture group
pub const aux_cp: u32 = 1 << 24;
/// contains a capture group under a quantifier
pub const aux_cq: u32 = 1 << 25;
/// contains a lazy `??`, `*?` or `+?` (ICU rejects them inside lookbehind; `{m,n}?` is fine)
pub const aux_lz: u32 = 1 << 26;
/// flags a parent inherits from its children (atom/za are positional)
pub const aux_inherit: u32 = aux_la | aux_md | aux_vq | aux_uq | aux_cx | aux_lk | aux_cp | aux_cq | aux_lz;

/// The quantifier flags of `q` applied to a body with flags `bf` (shared with dialect.treeAllowed).
pub fn quantFlags(bf: u32, min: u32, max: u32, inf: u32, lazy: bool, opt_like: bool, shorthand: bool) u32 {
    var f = (bf & aux_inherit) | aux_cx;
    if (lazy and shorthand) f |= aux_lz;
    if (min != max) f |= aux_vq;
    if (bf & aux_cp != 0) f |= aux_cq;
    const non_atom = bf & aux_atom == 0;
    if ((max == inf and (non_atom or lazy)) or (!opt_like and non_atom and bf & aux_cx != 0)) f |= aux_uq;
    return f;
}

pub const Grammar = struct {
    flags: Flags,
    atoms: []AtomSpec,
    atom_w: []f64,
    quants: []QuantSpec,
    unary: []UnaryEntry,
    binary: []BinaryEntry,
    allow_diagonal_lookarounds: bool,
    /// Weight by quant parameter id, and by op for non-quant, non-atom ops.
    quant_w: []f64,
    op_w: [11]f64,
    /// >0 (Perl): track max match length saturating at this cap and only
    /// apply lookbehind to bodies shorter than it.
    lookbehind_len_cap: u16 = 0,
    /// Saturating max-length tracking cap in the pair key (0 = no tracking).
    len_cap: u16 = 0,
    /// Forbid quantifiers over bodies whose max length is 0.
    no_empty_quant: bool = false,
    /// Lookbehind bodies must have min == max length.
    lookbehind_fixed: bool = false,
    /// Forbid lookaheads (and `$` under m) inside quantifiers that can repeat (max >= 2).
    no_la_in_star: bool = false,
    /// Lookbehind bodies may not hold an unbounded quantifier over anything but a single
    /// consuming atom (Java: "no obvious maximum length").
    lb_no_unbounded_group: bool = false,
    /// Lookbehind bodies may not hold variable quantifiers (min != max) or lookaheads (Onigmo).
    lb_no_var: bool = false,
    /// Quantifier bodies may not be (or offer as an alternative) a bare assertion (Oniguruma).
    no_quant_assert: bool = false,
    /// Oniguruma lookbehind: no lookarounds or quantified captures inside; no captures in a negative one.
    lb_onig: bool = false,
    /// No `??`, `*?`, `+?` inside lookbehind (ICU).
    lb_no_lazy: bool = false,
    /// Only the `?` form may quantify a nullable body (min length 0).
    nullable_opt_only: bool = false,

    pub fn init(gpa: Allocator, cfg: *const config.Config, flags: Flags) !Grammar {
        const W = &cfg.weights;
        const inv = try atoms.buildInventory(gpa, .{ .pool = alpha.active_pool, .class_max_members = cfg.class_max_members }, flags);
        var cat_count = [_]u32{0} ** @typeInfo(atoms.Category).@"enum".fields.len;
        for (inv) |a| cat_count[@intFromEnum(atoms.category(a))] += 1;
        const aw = try gpa.alloc(f64, inv.len);
        for (inv, 0..) |a, i| {
            const cat = atoms.category(a);
            const c: config.Construct = @enumFromInt(@intFromEnum(cat));
            aw[i] = W.get(c) / @as(f64, @floatFromInt(cat_count[@intFromEnum(cat)]));
        }

        // Quantifier parameter inventory.
        var qs: std.ArrayList(QuantSpec) = .empty;
        const B = cfg.max_rep_bound;
        try qs.append(gpa, .{ .form = .star, .min = 0, .max = ast.inf });
        try qs.append(gpa, .{ .form = .plus, .min = 1, .max = ast.inf });
        try qs.append(gpa, .{ .form = .opt, .min = 0, .max = 1 });
        var m: u8 = 0;
        while (m <= B) : (m += 1) {
            var n: u8 = @max(m, 1);
            while (n <= B) : (n += 1) try qs.append(gpa, .{ .form = .range, .min = m, .max = n });
        }
        m = 0;
        while (m <= B) : (m += 1) try qs.append(gpa, .{ .form = .open, .min = m, .max = ast.inf });
        m = 1;
        while (m <= B) : (m += 1) try qs.append(gpa, .{ .form = .exact, .min = m, .max = m });
        const n_greedy = qs.items.len;
        if (W.get(.lazy) > 0) {
            for (0..n_greedy) |i| {
                var q = qs.items[i];
                q.lazy = true;
                try qs.append(gpa, q);
            }
        }
        if (qs.items.len > 65536) return error.QuantInventoryTooLarge;
        var form_count = [_]u32{0} ** 6;
        for (qs.items[0..n_greedy]) |q| form_count[@intFromEnum(q.form)] += 1;

        var un: std.ArrayList(UnaryEntry) = .empty;
        for (qs.items, 0..) |q, i| {
            const c: config.Construct = switch (q.form) {
                .star => .star,
                .plus => .plus,
                .opt => .opt,
                .range => .rep,
                .open => .rep_open,
                .exact => .rep_exact,
            };
            var w = W.get(c) / @as(f64, @floatFromInt(form_count[@intFromEnum(q.form)]));
            if (q.lazy) w *= W.get(.lazy);
            if (q.lazy and !dialect_mod.active.allow_lazy) continue;
            if (w > 0) try un.append(gpa, .{ .op = .quant, .arg = @intCast(i), .w = w });
        }
        const others = [_]struct { op: Op, c: config.Construct }{
            .{ .op = .look_ahead, .c = .lookahead },
            .{ .op = .neg_look_ahead, .c = .neg_lookahead },
            .{ .op = .look_behind, .c = .lookbehind },
            .{ .op = .neg_look_behind, .c = .neg_lookbehind },
            .{ .op = .group_cap, .c = .group },
            .{ .op = .group_nc, .c = .nc_group },
            .{ .op = .group_named, .c = .named_group },
        };
        const dl = dialect_mod.active;
        for (others) |o| {
            if ((o.op == .look_ahead or o.op == .neg_look_ahead) and !dl.allow_lookahead) continue;
            if ((o.op == .look_behind or o.op == .neg_look_behind) and !dl.allow_lookbehind) continue;
            if (W.get(o.c) > 0) try un.append(gpa, .{ .op = o.op, .arg = 0, .w = W.get(o.c) });
        }

        var bin: std.ArrayList(BinaryEntry) = .empty;
        if (W.get(.concat) > 0) try bin.append(gpa, .{ .op = .concat, .w = W.get(.concat) });
        if (W.get(.alt) > 0) try bin.append(gpa, .{ .op = .alt, .w = W.get(.alt) });

        var g: Grammar = .{
            .flags = flags,
            .atoms = inv,
            .atom_w = aw,
            .quants = try qs.toOwnedSlice(gpa),
            .unary = try un.toOwnedSlice(gpa),
            .binary = try bin.toOwnedSlice(gpa),
            .allow_diagonal_lookarounds = cfg.allow_diagonal_lookarounds,
            .quant_w = &.{},
            .op_w = undefined,
            .lookbehind_len_cap = dialect_mod.active.lookbehind_len_cap,
            .len_cap = if (dialect_mod.active.lookbehind_len_cap > 0) dialect_mod.active.lookbehind_len_cap else if (dialect_mod.active.lookbehind_fixed or !dialect_mod.active.allow_empty_quant or dialect_mod.active.nullable_quant_opt_only) @intCast(dialect_mod.len_cap_default) else 0,
            .lookbehind_fixed = dialect_mod.active.lookbehind_fixed,
            .no_empty_quant = !dialect_mod.active.allow_empty_quant,
            .no_la_in_star = !dialect_mod.active.lookahead_in_star,
            .lb_no_unbounded_group = dialect_mod.active.lookbehind_no_unbounded_group,
            .lb_no_var = dialect_mod.active.lookbehind_no_variable,
            .no_quant_assert = !dialect_mod.active.quantify_assertions,
            .lb_onig = dialect_mod.active.lookbehind_onig,
            .lb_no_lazy = dialect_mod.active.lookbehind_no_lazy,
            .nullable_opt_only = dialect_mod.active.nullable_quant_opt_only,
        };
        try g.indexWeights(gpa);
        return g;
    }

    pub fn indexWeights(self: *Grammar, gpa: Allocator) !void {
        self.quant_w = try gpa.alloc(f64, self.quants.len);
        @memset(self.quant_w, 0);
        @memset(&self.op_w, 0);
        for (self.unary) |u| {
            if (u.op == .quant) self.quant_w[u.arg] = u.w else self.op_w[@intFromEnum(u.op)] = u.w;
        }
        for (self.binary) |b| self.op_w[@intFromEnum(b.op)] = b.w;
    }

    pub fn deinit(self: *Grammar, gpa: Allocator) void {
        gpa.free(self.atoms);
        gpa.free(self.atom_w);
        gpa.free(self.quants);
        gpa.free(self.unary);
        gpa.free(self.binary);
        gpa.free(self.quant_w);
    }

    /// Linear weight of a production.
    pub fn prodWeight(self: *const Grammar, p: Prod) f64 {
        const op: Op = @enumFromInt(p.op);
        return switch (op) {
            .atom => self.atom_w[p.arg],
            .quant => self.quant_w[p.arg],
            else => self.op_w[p.op],
        };
    }

    /// Subtree flags (aux bits 24..31) the active restrictions need; others are masked to keep keys compact.
    pub fn flagMask(self: *const Grammar) u32 {
        var m: u32 = 0;
        if (self.no_la_in_star) m |= aux_la | aux_md;
        if (self.lb_no_var) m |= aux_la | aux_vq;
        if (self.lb_no_unbounded_group) m |= aux_uq | aux_atom | aux_cx;
        if (self.no_quant_assert) m |= aux_za;
        if (self.lb_onig) m |= aux_lk | aux_cp | aux_cq;
        if (self.lb_no_lazy) m |= aux_lz;
        return m;
    }

    pub fn tracksAux(self: *const Grammar) bool {
        return self.len_cap > 0 or self.flagMask() != 0;
    }

    pub fn hashInto(self: *const Grammar, h: *std.crypto.hash.sha2.Sha256) void {
        h.update(&[_]u8{self.flags.bits()});
        h.update(std.mem.asBytes(&self.lookbehind_len_cap));
        h.update(std.mem.asBytes(&self.len_cap));
        h.update(&[_]u8{ @intFromBool(self.no_empty_quant), @intFromBool(self.lookbehind_fixed), @intFromBool(self.no_la_in_star), @intFromBool(self.nullable_opt_only), @intFromBool(self.lb_no_unbounded_group), @intFromBool(self.lb_no_var), @intFromBool(self.no_quant_assert), @intFromBool(self.lb_onig), @intFromBool(self.lb_no_lazy) });
        for (self.atoms, self.atom_w) |a, w| {
            h.update(std.mem.asBytes(&a.kind));
            h.update(&[_]u8{ a.sub, @intFromBool(a.neg), a.n });
            for (a.syms) |s| h.update(std.mem.asBytes(&@as(u32, s)));
            h.update(std.mem.asBytes(&w));
        }
        for (self.quants) |q| h.update(&[_]u8{ @intFromEnum(q.form), q.min, q.max, @intFromBool(q.lazy) });
        for (self.unary) |u| {
            h.update(&[_]u8{@intFromEnum(u.op)});
            h.update(std.mem.asBytes(&u.arg));
            h.update(std.mem.asBytes(&u.w));
        }
        for (self.binary) |b| {
            h.update(&[_]u8{@intFromEnum(b.op)});
            h.update(std.mem.asBytes(&b.w));
        }
    }
};

// ---------------------------------------------------------------------------
// Uniform sequential selection without replacement (Vitter 1987, Method D
// with Method A fallback): streams `n` ranks of [0, N) in ascending order in
// O(1) memory.

pub const Selector = struct {
    rng: rngmod.Rng,
    n: u64,
    N: u64,
    pos: u64 = 0,
    vprime: f64 = 0,
    threshold: u64 = 0,
    const alpha_inv: u64 = 13;

    pub fn init(n: u64, N: u64, rng: rngmod.Rng) Selector {
        var s: Selector = .{ .rng = rng, .n = @min(n, N), .N = N };
        if (s.n > 0) s.vprime = @exp(@log(s.rng.floatOpen()) / @as(f64, @floatFromInt(s.n)));
        s.threshold = alpha_inv * s.n;
        return s;
    }

    pub fn next(self: *Selector) ?u64 {
        if (self.n == 0) return null;
        const S = if (self.n == 1) self.skipLast() else if (self.threshold < self.N) self.skipD() else self.skipA();
        const sel = self.pos + S;
        self.pos = sel + 1;
        self.N -= S + 1;
        self.n -= 1;
        if (self.threshold >= alpha_inv) self.threshold -= alpha_inv;
        return sel;
    }

    fn skipLast(self: *Selector) u64 {
        const S: u64 = @intFromFloat(@floor(@as(f64, @floatFromInt(self.N)) * self.rng.float()));
        return @min(S, self.N - 1);
    }

    fn skipA(self: *Selector) u64 {
        var top: f64 = @floatFromInt(self.N - self.n);
        var Nreal: f64 = @floatFromInt(self.N);
        const V = self.rng.float();
        var S: u64 = 0;
        var quot = top / Nreal;
        while (quot > V) {
            S += 1;
            top -= 1;
            Nreal -= 1;
            quot = quot * top / Nreal;
        }
        return S;
    }

    fn skipD(self: *Selector) u64 {
        const n = self.n;
        const N = self.N;
        const nreal: f64 = @floatFromInt(n);
        const Nreal: f64 = @floatFromInt(N);
        const ninv = 1.0 / nreal;
        const nmin1inv = 1.0 / (nreal - 1.0);
        const qu1: u64 = N - n + 1;
        const qu1real: f64 = @floatFromInt(qu1);
        var vprime = self.vprime;
        var S: u64 = 0;
        while (true) {
            var X: f64 = 0;
            while (true) {
                X = Nreal * (1.0 - vprime);
                S = @intFromFloat(@floor(X));
                if (S < qu1) break;
                vprime = @exp(@log(self.rng.floatOpen()) * ninv);
            }
            const U = self.rng.floatOpen();
            const negSreal = -@as(f64, @floatFromInt(S));
            const y1 = @exp(@log(U * Nreal / qu1real) * nmin1inv);
            vprime = y1 * (-X / Nreal + 1.0) * (qu1real / (negSreal + qu1real));
            if (vprime <= 1.0) break;
            var y2: f64 = 1.0;
            var top = Nreal - 1.0;
            var bottom: f64 = undefined;
            var limit: u64 = undefined;
            if (n - 1 > S) {
                bottom = Nreal - nreal;
                limit = N - S;
            } else {
                bottom = negSreal + Nreal - 1.0;
                limit = qu1;
            }
            var t = N - 1;
            while (t >= limit) : (t -= 1) {
                y2 = (y2 * top) / bottom;
                top -= 1.0;
                bottom -= 1.0;
            }
            if (Nreal / (Nreal - X) >= y1 * @exp(@log(y2) * nmin1inv)) {
                vprime = @exp(@log(self.rng.floatOpen()) * nmin1inv);
                break;
            }
            vprime = @exp(@log(self.rng.floatOpen()) * ninv);
        }
        // For the next draw vprime must correspond to n-1 selections.
        self.vprime = vprime;
        return S;
    }
};

// ---------------------------------------------------------------------------
// Alias tables (Vose)

pub fn buildAlias(weights: []const f64, prob: []f32, alias: []u32, small: []u32, large: []u32) void {
    const n = weights.len;
    var total: f64 = 0;
    for (weights) |w| total += w;
    std.debug.assert(n > 0 and total > 0);
    var ns: usize = 0;
    var nl: usize = 0;
    // Residuals are kept in f32; the resulting sampling error is measured in tests.
    const scale = @as(f64, @floatFromInt(n)) / total;
    for (weights, 0..) |w, i| {
        const s = w * scale;
        prob[i] = @floatCast(s);
        if (s < 1.0) {
            small[ns] = @intCast(i);
            ns += 1;
        } else {
            large[nl] = @intCast(i);
            nl += 1;
        }
    }
    while (ns > 0 and nl > 0) {
        ns -= 1;
        const l = small[ns];
        const g = large[nl - 1];
        alias[l] = g;
        prob[g] = (prob[g] + prob[l]) - 1.0;
        if (prob[g] < 1.0) {
            nl -= 1;
            small[ns] = g;
            ns += 1;
        }
    }
    while (nl > 0) {
        nl -= 1;
        prob[large[nl]] = 1.0;
        alias[large[nl]] = large[nl];
    }
    while (ns > 0) {
        ns -= 1;
        prob[small[ns]] = 1.0;
        alias[small[ns]] = small[ns];
    }
}

pub fn drawAlias(rng: *rngmod.Rng, prob: []const f32, alias: []const u32) u32 {
    const i: u32 = @intCast(rng.below(prob.len));
    return if (rng.float() < prob[i]) i else alias[i];
}

pub const Alias = struct {
    prob: []f32,
    alias: []u32,
    items: []u32,

    pub fn draw(self: *const Alias, rng: *rngmod.Rng) u32 {
        return self.items[drawAlias(rng, self.prob, self.alias)];
    }
};

fn makeAlias(gpa: Allocator, items: []const u32, weights: []const f64) !Alias {
    const n = items.len;
    const prob = try gpa.alloc(f32, n);
    errdefer gpa.free(prob);
    const al = try gpa.alloc(u32, n);
    errdefer gpa.free(al);
    const it = try gpa.dupe(u32, items);
    errdefer gpa.free(it);
    const small = try gpa.alloc(u32, n);
    defer gpa.free(small);
    const large = try gpa.alloc(u32, n);
    defer gpa.free(large);
    buildAlias(weights, prob, al, small, large);
    return .{ .prob = prob, .alias = al, .items = it };
}

fn freeAlias(gpa: Allocator, a: *Alias) void {
    gpa.free(a.prob);
    gpa.free(a.alias);
    gpa.free(a.items);
}

// ---------------------------------------------------------------------------
// Stats

pub const Truncation = enum { none, max_pairs_quota, max_combos, max_prods, max_count_terms, bytes };

pub const LevelStats = struct {
    new_pairs: u32 = 0,
    prods: u32 = 0,
    unary_visits: u64 = 0,
    combos_total: u64 = 0,
    combos_visited: u64 = 0,
    dropped: u64 = 0,
    diag_skipped: u64 = 0,
    sampled: bool = false,
};

pub const BuildStats = struct {
    levels: [config.max_size_cap + 1]LevelStats = [_]LevelStats{.{}} ** (config.max_size_cap + 1),
    max_size: u8 = 0,
    atoms: u32 = 0,
    pairs_built: u32 = 0,
    prods_built: u32 = 0,
    pairs: u32 = 0,
    prods: u32 = 0,
    start_pairs: u32 = 0,
    stop_level: u8 = 0,
    stop_reason: Truncation = .none,
    quota_limited: bool = false,
    combos_limited: bool = false,
    count_terms_charged: u64 = 0,
    count_terms_visited: u64 = 0,
    prune_abandoned: bool = false,
    pruned: bool = false,
    build_ns: u64 = 0,
    prune_ns: u64 = 0,
    count_ns: u64 = 0,
    peak_bytes: u64 = 0,
    feasible_sizes: u32 = 0,
    excluded_sizes: u32 = 0,

    pub fn write(self: *const BuildStats, out: *std.ArrayList(u8), gpa: Allocator) !void {
        try out.print(gpa, "table: atoms={d} built pairs={d} prods={d} -> retained pairs={d} prods={d} start={d} stop={s}@{d}{s}{s} terms={d}/{d} peak={d}KiB build={d}ms prune={d}ms count={d}ms sizes={d} feasible/{d} excluded\n", .{
            self.atoms,                     self.pairs_built,              self.prods_built,      self.pairs,                    self.prods,
            self.start_pairs,               @tagName(self.stop_reason),    self.stop_level,       if (self.quota_limited) " quota" else "", if (self.combos_limited) " combos-sampled" else "",
            self.count_terms_visited,       self.count_terms_charged,      self.peak_bytes / 1024, self.build_ns / 1_000_000,     self.prune_ns / 1_000_000,
            self.count_ns / 1_000_000,      self.feasible_sizes,           self.excluded_sizes,
        });
        for (1..@as(usize, self.max_size) + 1) |k| {
            const l = self.levels[k];
            if (l.new_pairs == 0 and l.prods == 0 and l.combos_visited == 0 and l.unary_visits == 0) continue;
            try out.print(gpa, "  level {d}: new={d} prods={d} unary={d} combos={d}/{d}{s} dropped={d} diag_skip={d}\n", .{ k, l.new_pairs, l.prods, l.unary_visits, l.combos_visited, l.combos_total, if (l.sampled) " (sampled)" else "", l.dropped, l.diag_skipped });
        }
    }
};

// ---------------------------------------------------------------------------
// Finalized table (independent of N)

pub const Identity = struct {
    seq: u64,
    attempt: u32,
    seed: u64,
    flags: Flags,
};

pub const Table = struct {
    budget: Budget,
    refs: std.atomic.Value(u32) = .init(1),
    id: Identity,
    grammar: *const Grammar,
    max_size: u8,
    a16: []u16,
    r16: []u16,
    npairs: u32,
    ms: []u8,
    pstart: []u32,
    prods: []Prod,
    /// log weight of each production (f64; production weight only)
    plw: []f64,
    coff: []u32,
    counts: []f32,
    size_alias: Alias,
    /// per size k: alias over start pairs (empty when infeasible)
    start_alias: []Alias,
    size_dist: []f64,
    max_prods_per_pair: u32,
    // Lazy shared SampIdx cache
    slots: []std.atomic.Value(u32),
    arena: []u32,
    arena_top: std.atomic.Value(u64) = .init(0),
    cache_enabled: bool,
    cache_hits: std.atomic.Value(u64) = .init(0),
    uncached: std.atomic.Value(u64) = .init(0),
    cache_builds: std.atomic.Value(u64) = .init(0),
    wasted: std.atomic.Value(u64) = .init(0),
    stats: BuildStats,
    digest: [32]u8,
    host_alloc: Allocator,
    /// Decremented when the table is destroyed (live-table accounting).
    live_counter: ?*std.atomic.Value(u32) = null,

    pub fn alloc(self: *Table) Allocator {
        return self.budget.allocator();
    }

    /// log W(X, k), or -inf.
    pub fn logW(self: *const Table, x: u32, k: usize) f64 {
        const m = self.ms[x];
        if (k < m or k > self.max_size) return -std.math.inf(f64);
        return self.counts[self.coff[x] + (k - m)];
    }

    pub fn countIndex(self: *const Table, x: u32, k: usize) ?u32 {
        const m = self.ms[x];
        if (k < m or k > self.max_size) return null;
        return self.coff[x] + @as(u32, @intCast(k - m));
    }

    pub fn acquire(self: *Table) void {
        _ = self.refs.fetchAdd(1, .monotonic);
    }

    pub fn release(self: *Table) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) self.destroy();
    }

    fn destroy(self: *Table) void {
        const a = self.alloc();
        a.free(self.a16);
        a.free(self.r16);
        a.free(self.ms);
        a.free(self.pstart);
        a.free(self.prods);
        a.free(self.plw);
        a.free(self.coff);
        a.free(self.counts);
        freeAlias(a, &self.size_alias);
        for (self.start_alias) |*sa| if (sa.items.len > 0) freeAlias(a, sa);
        a.free(self.start_alias);
        a.free(self.size_dist);
        a.free(self.slots);
        a.free(self.arena);
        std.debug.assert(self.budget.used.load(.monotonic) == 0);
        const lc = self.live_counter;
        const host = self.host_alloc;
        host.destroy(self);
        if (lc) |c| _ = c.fetchSub(1, .acq_rel);
    }

    /// Production term at size k in log space (−inf when zero).
    pub fn prodTerm(self: *const Table, p: Prod, k: usize, lw: f64) f64 {
        const op: Op = @enumFromInt(p.op);
        switch (op) {
            .atom => return if (k == 1) lw else -std.math.inf(f64),
            .concat, .alt => {
                if (k < 3) return -std.math.inf(f64);
                const my = self.ms[p.a];
                const mz = self.ms[p.b];
                if (k < @as(usize, my) + mz + 1) return -std.math.inf(f64);
                var acc = Lse{};
                var k1: usize = my;
                while (k1 + mz + 1 <= k) : (k1 += 1) {
                    acc.add(self.logW(p.a, k1) + self.logW(p.b, k - 1 - k1));
                }
                return lw + acc.result();
            },
            else => {
                if (k < 2) return -std.math.inf(f64);
                return lw + self.logW(p.a, k - 1);
            },
        }
    }
};

/// Streaming log-sum-exp in f64.
pub const Lse = struct {
    m: f64 = -std.math.inf(f64),
    s: f64 = 0,
    pub fn add(self: *Lse, t: f64) void {
        if (t == -std.math.inf(f64)) return;
        if (t > self.m) {
            self.s = self.s * @exp(self.m - t) + 1.0;
            self.m = t;
        } else self.s += @exp(t - self.m);
    }
    pub fn result(self: Lse) f64 {
        if (self.m == -std.math.inf(f64)) return self.m;
        return self.m + @log(self.s);
    }
};

// ---------------------------------------------------------------------------
// Builder

pub const BuildError = error{ ZeroMass, Resource, InvalidInput, ModelFailure };

pub const BuildInput = struct {
    grammar: *const Grammar,
    cfg: *const config.Config,
    a16: []const u16,
    r16: []const u16,
    id: Identity,
    host: *Budget,
    host_alloc: Allocator,
    /// Weights may be overridden by adaptive mode (already folded into grammar).
    log: ?*const fn (comptime []const u8, anytype) void = null,
};

pub fn build(in: BuildInput) BuildError!*Table {
    var sa: [32]u21 = undefined;
    var sr: [32]u21 = undefined;
    const na = alpha.decode(in.a16, in.id.flags, &sa) orelse return error.InvalidInput;
    const nr = alpha.decode(in.r16, in.id.flags, &sr) orelse return error.InvalidInput;
    if (na > in.cfg.max_symbols or nr > in.cfg.max_symbols) return error.InvalidInput;
    if (na == nr and std.mem.eql(u21, sa[0..na], sr[0..nr])) return error.InvalidInput;
    if (@max(na, nr) <= relmod.Rel8.max_len) return Builder(relmod.Rel8).run(in, sa[0..na], sr[0..nr]);
    if (@max(na, nr) <= relmod.Rel16.max_len) return Builder(relmod.Rel16).run(in, sa[0..na], sr[0..nr]);
    return Builder(relmod.Rel32).run(in, sa[0..na], sr[0..nr]);
}

fn Builder(comptime R: type) type {
    return struct {
        const Self = @This();
        /// aux: saturating max match length (Perl lookbehind restriction); 0 in JS mode.
        const Key = extern struct { a: [R.n_rows]R.Row, r: [R.n_rows]R.Row, aux: u32 = 0 };
        const Slot = extern struct { id: u32, hash: u32 };

        table: *Table,
        alloc: Allocator,
        g: *const Grammar,
        cfg: *const config.Config,
        wa: []const u21,
        wr: []const u21,
        K: u8,

        keys: std.ArrayList(Key) = .empty,
        ms: std.ArrayList(u8) = .empty,
        slots: []Slot = &.{},
        nslots_used: usize = 0,
        prods: std.ArrayList(Prod) = .empty,
        pset: []u32 = &.{},
        pset_used: usize = 0,
        level_start: [config.max_size_cap + 2]u32 = undefined,

        quota_left: u64 = 0,
        terms: u64 = 0,
        stopped: bool = false,
        stats: *BuildStats,
        cur_level: u8 = 1,

        fn keyOf(ra: R, rr: R) Key {
            return .{ .a = ra.rows, .r = rr.rows };
        }

        fn keyAux(ra: R, rr: R, aux: u32) Key {
            return .{ .a = ra.rows, .r = rr.rows, .aux = aux };
        }
        fn relA(k: Key) R {
            return .{ .rows = k.a };
        }
        fn relR(k: Key) R {
            return .{ .rows = k.r };
        }
        fn hashKey(k: *const Key) u64 {
            return std.hash.Wyhash.hash(0x1A2B, std.mem.asBytes(k));
        }
        fn hashProd(op: u8, arg: u16, a: u32, b: u32) u64 {
            const x: [3]u32 = .{ @as(u32, op) | (@as(u32, arg) << 8), a, b };
            return std.hash.Wyhash.hash(0x5EED, std.mem.asBytes(&x));
        }

        // ---- interner (Robin Hood) ----
        fn find(self: *Self, k: *const Key, h: u64) ?u32 {
            if (self.slots.len == 0) return null;
            const mask = self.slots.len - 1;
            const h32: u32 = @truncate(h);
            var idx: usize = h32 & mask;
            var dist: usize = 0;
            while (true) {
                const s = self.slots[idx];
                if (s.id == 0) return null;
                const sd = (idx -% (s.hash & mask)) & mask;
                if (sd < dist) return null;
                if (s.hash == h32 and std.mem.eql(u8, std.mem.asBytes(&self.keys.items[s.id - 1]), std.mem.asBytes(k))) return s.id - 1;
                idx = (idx + 1) & mask;
                dist += 1;
            }
        }

        fn slotInsert(slots: []Slot, id: u32, h32: u32) void {
            const mask = slots.len - 1;
            var cur: Slot = .{ .id = id + 1, .hash = h32 };
            var idx: usize = h32 & mask;
            var dist: usize = 0;
            while (true) {
                const s = slots[idx];
                if (s.id == 0) {
                    slots[idx] = cur;
                    return;
                }
                const sd = (idx -% (s.hash & mask)) & mask;
                if (sd < dist) {
                    slots[idx] = cur;
                    cur = s;
                    dist = sd;
                }
                idx = (idx + 1) & mask;
                dist += 1;
            }
        }

        fn ensureSlots(self: *Self) bool {
            if ((self.nslots_used + 1) * 2 <= self.slots.len) return true;
            const ncap = @max(64, self.slots.len * 2);
            const ns = self.alloc.alloc(Slot, ncap) catch return false;
            @memset(ns, .{ .id = 0, .hash = 0 });
            for (self.keys.items, 0..) |*k, i| slotInsert(ns, @intCast(i), @truncate(hashKey(k)));
            self.alloc.free(self.slots);
            self.slots = ns;
            return true;
        }

        // ---- production set ----
        fn psetFind(self: *Self, op: u8, arg: u16, a: u32, b: u32, h: u64) bool {
            if (self.pset.len == 0) return false;
            const mask = self.pset.len - 1;
            var idx: usize = @as(usize, @truncate(h)) & mask;
            while (true) {
                const id = self.pset[idx];
                if (id == 0) return false;
                const p = self.prods.items[id - 1];
                if (p.op == op and p.arg == arg and p.a == a and p.b == b) return true;
                idx = (idx + 1) & mask;
            }
        }
        fn psetInsertRaw(set: []u32, prods: []const Prod, id: u32) void {
            const p = prods[id];
            const mask = set.len - 1;
            var idx: usize = @as(usize, @truncate(hashProd(p.op, p.arg, p.a, p.b))) & mask;
            while (set[idx] != 0) idx = (idx + 1) & mask;
            set[idx] = id + 1;
        }
        fn ensurePset(self: *Self) bool {
            if ((self.pset_used + 1) * 2 <= self.pset.len) return true;
            const ncap = @max(64, self.pset.len * 2);
            const ns = self.alloc.alloc(u32, ncap) catch return false;
            @memset(ns, 0);
            for (0..self.prods.items.len) |i| psetInsertRaw(ns, self.prods.items, @intCast(i));
            self.alloc.free(self.pset);
            self.pset = ns;
            return true;
        }

        fn termsFor(self: *Self, op: Op, a: u32, b: u32) u64 {
            const K: u64 = self.K;
            return switch (op) {
                .atom => 1,
                .concat, .alt => blk: {
                    const s: u64 = @as(u64, self.ms.items[a]) + self.ms.items[b];
                    if (s >= K) break :blk 0;
                    const T = K - s;
                    break :blk T * (T + 1) / 2;
                },
                else => K - self.ms.items[a],
            };
        }

        fn stop(self: *Self, why: Truncation) void {
            if (!self.stopped) {
                self.stopped = true;
                self.stats.stop_reason = why;
                self.stats.stop_level = self.cur_level;
            }
        }

        /// Record production `op(arg; a, b)` with resulting pair `key`.
        fn record(self: *Self, op: Op, arg: u16, a: u32, b: u32, key: *const Key) void {
            const opb = @intFromEnum(op);
            const ph = hashProd(opb, arg, a, b);
            if (self.psetFind(opb, arg, a, b, ph)) return;
            const h = hashKey(key);
            const existing = self.find(key, h);
            if (existing == null and self.quota_left == 0) {
                self.stats.levels[self.cur_level].dropped += 1;
                self.stats.quota_limited = true;
                return;
            }
            if (self.prods.items.len >= self.cfg.max_prods) return self.stop(.max_prods);
            const t = self.termsFor(op, a, b);
            if (self.terms + t > self.cfg.max_count_terms) return self.stop(.max_count_terms);
            // Reserve everything first so admission is atomic.
            if (!self.ensurePset()) return self.stop(.bytes);
            self.prods.ensureUnusedCapacity(self.alloc, 1) catch return self.stop(.bytes);
            var lhs: u32 = undefined;
            if (existing) |e| {
                lhs = e;
            } else {
                if (!self.ensureSlots()) return self.stop(.bytes);
                self.keys.ensureUnusedCapacity(self.alloc, 1) catch return self.stop(.bytes);
                self.ms.ensureUnusedCapacity(self.alloc, 1) catch return self.stop(.bytes);
                lhs = @intCast(self.keys.items.len);
                self.keys.appendAssumeCapacity(key.*);
                self.ms.appendAssumeCapacity(self.cur_level);
                slotInsert(self.slots, lhs, @truncate(h));
                self.nslots_used += 1;
                self.quota_left -= 1;
                self.stats.levels[self.cur_level].new_pairs += 1;
            }
            self.prods.appendAssumeCapacity(.{ .op = opb, .arg = arg, .lhs = lhs, .a = a, .b = b });
            psetInsertRaw(self.pset, self.prods.items, @intCast(self.prods.items.len - 1));
            self.pset_used += 1;
            self.terms += t;
            self.stats.levels[self.cur_level].prods += 1;
        }

        fn setQuota(self: *Self, k: usize) void {
            const so_far: u64 = self.keys.items.len;
            const left: u64 = if (so_far >= self.cfg.max_pairs) 0 else self.cfg.max_pairs - so_far;
            self.quota_left = left / (@as(u64, self.K) - k + 1);
        }

        fn applyUnary(self: *Self, u: UnaryEntry, y: u32) void {
            const ky = self.keys.items[y];
            const ra = relA(ky);
            const rr = relR(ky);
            const da = self.wa.len + 1;
            const dr = self.wr.len + 1;
            var na: R = undefined;
            var nr: R = undefined;
            switch (u.op) {
                .quant => {
                    const q = self.g.quants[u.arg];
                    na = ast.quantRel(R, ra, q, da);
                    nr = ast.quantRel(R, rr, q, dr);
                },
                .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind => {
                    if (!self.g.allow_diagonal_lookarounds and ra.isDiagonal() and rr.isDiagonal()) {
                        self.stats.levels[self.cur_level].diag_skipped += 1;
                        return;
                    }
                    const neg = u.op == .neg_look_ahead or u.op == .neg_look_behind;
                    if (u.op == .look_ahead or u.op == .neg_look_ahead) {
                        na = ra.lookahead(da, neg);
                        nr = rr.lookahead(dr, neg);
                    } else {
                        na = ra.lookbehind(da, neg);
                        nr = rr.lookbehind(dr, neg);
                    }
                },
                else => {
                    na = ra;
                    nr = rr;
                },
            }
            // aux packs saturating (max, min) subtree lengths and subtree flags (see aux_*).
            var aux: u32 = 0;
            if (self.g.tracksAux()) {
                const cap: u32 = self.g.len_cap;
                const ymax = ky.aux & aux_len_mask;
                const ymin = (ky.aux >> aux_min_shift) & aux_len_mask;
                const yf = ky.aux & aux_flags;
                var f: u32 = 0;
                var mx: u32 = 0;
                var mn: u32 = 0;
                switch (u.op) {
                    .quant => {
                        if (self.g.no_empty_quant and ymax == 0) return;
                        const q = self.g.quants[u.arg];
                        if (self.g.no_la_in_star and yf & (aux_la | aux_md) != 0 and q.max >= 2) return;
                        if (self.g.no_quant_assert and yf & aux_za != 0) return;
                        if (self.g.nullable_opt_only and ymin == 0 and q.form != .opt) return;
                        mx = if (q.max == ast.inf) cap else @min(cap, ymax * @as(u32, q.max));
                        mn = @min(cap, ymin * @as(u32, q.min));
                        f = quantFlags(yf, q.min, q.max, ast.inf, q.lazy, q.min == 0 and q.max == 1, q.form == .star or q.form == .plus or q.form == .opt);
                    },
                    .look_ahead, .neg_look_ahead => f = aux_la | aux_lk | aux_za | (yf & aux_inherit),
                    .look_behind, .neg_look_behind => {
                        if (self.g.lookbehind_len_cap > 0 and ymax >= cap) return;
                        if (self.g.lookbehind_fixed and (ymin != ymax or ymax >= cap)) return;
                        if (self.g.lb_no_unbounded_group and yf & aux_uq != 0) return;
                        if (self.g.lb_no_var and yf & (aux_vq | aux_la) != 0) return;
                        if (self.g.lb_onig and (yf & (aux_lk | aux_cq) != 0 or (u.op == .neg_look_behind and yf & aux_cp != 0))) return;
                        if (self.g.lb_no_lazy and yf & aux_lz != 0) return;
                        f = aux_lk | aux_za | (yf & aux_inherit);
                    },
                    .group_nc => {
                        mx = ymax;
                        mn = ymin;
                        f = yf;
                    },
                    .group_cap, .group_named => {
                        mx = ymax;
                        mn = ymin;
                        f = (yf & aux_inherit) | aux_cp;
                    },
                    else => {
                        mx = ymax;
                        mn = ymin;
                        f = yf & aux_inherit;
                    },
                }
                aux = mx | (mn << aux_min_shift) | (f & self.g.flagMask());
            }
            const key = keyAux(na, nr, aux);
            self.record(u.op, u.arg, y, none, &key);
        }

        fn applyBinary(self: *Self, op: Op, y: u32, z: u32) void {
            const ky = self.keys.items[y];
            const kz = self.keys.items[z];
            const cap: u32 = self.g.len_cap;
            const aux: u32 = if (!self.g.tracksAux()) 0 else blk: {
                const amax = ky.aux & aux_len_mask;
                const amin = (ky.aux >> aux_min_shift) & aux_len_mask;
                const bmax = kz.aux & aux_len_mask;
                const bmin = (kz.aux >> aux_min_shift) & aux_len_mask;
                const fl = ky.aux | kz.aux;
                if (op == .concat) break :blk @min(cap, amax + bmax) | (@min(cap, amin + bmin) << aux_min_shift) | (fl & aux_inherit & self.g.flagMask());
                break :blk @max(amax, bmax) | (@min(amin, bmin) << aux_min_shift) | (((fl & (aux_inherit | aux_za)) | aux_cx) & self.g.flagMask());
            };
            const key = if (op == .concat)
                keyAux(relA(ky).mul(relA(kz)), relR(ky).mul(relR(kz)), aux)
            else
                keyAux(relA(ky).orr(relA(kz)), relR(ky).orr(relR(kz)), aux);
            self.record(op, 0, y, z, &key);
        }

        fn levelLen(self: *const Self, k: usize) u64 {
            return self.level_start[k + 1] - self.level_start[k];
        }

        fn decodeAndApply(self: *Self, k: usize, rank: u64) void {
            const nb: u64 = self.g.binary.len;
            var r = rank;
            var k1: usize = 1;
            while (k1 + 1 < k) : (k1 += 1) {
                const k2 = k - 1 - k1;
                const block = self.levelLen(k1) * self.levelLen(k2) * nb;
                if (r < block) {
                    const l2 = self.levelLen(k2);
                    const yi = r / (l2 * nb);
                    const rem = r % (l2 * nb);
                    const zi = rem / nb;
                    const oi = rem % nb;
                    const y: u32 = self.level_start[k1] + @as(u32, @intCast(yi));
                    const z: u32 = self.level_start[k2] + @as(u32, @intCast(zi));
                    self.applyBinary(self.g.binary[oi].op, y, z);
                    return;
                }
                r -= block;
            }
            unreachable;
        }

        fn run(in: BuildInput, wa: []const u21, wr: []const u21) BuildError!*Table {
            const t0 = sys.nowNs();
            const tab = in.host_alloc.create(Table) catch return error.Resource;
            tab.* = undefined;
            tab.budget = Budget.init("table", in.cfg.max_table_bytes, in.host);
            tab.stats = .{};
            tab.host_alloc = in.host_alloc;
            var ok = false;
            defer if (!ok) {
                in.host_alloc.destroy(tab);
            };
            var self: Self = .{
                .table = tab,
                .alloc = tab.budget.allocator(),
                .g = in.grammar,
                .cfg = in.cfg,
                .wa = wa,
                .wr = wr,
                .K = in.cfg.max_size,
                .stats = &tab.stats,
            };
            defer self.freeBuild();
            const K = self.K;
            tab.stats.max_size = K;

            // Level 1: atoms.
            self.level_start[1] = 0;
            self.cur_level = 1;
            self.setQuota(1);
            for (self.g.atoms, 0..) |*a, i| {
                if (self.g.atom_w[i] <= 0) continue;
                var af: u32 = 0;
                if (a.kind == .dollar and self.g.flags.m) af |= aux_md;
                if (a.isConsuming()) af |= aux_atom;
                if (a.kind == .caret or a.kind == .dollar or a.kind == .wordb or a.kind == .nwordb) af |= aux_za;
                const len: u32 = if (self.g.len_cap > 0 and a.isConsuming()) (1 | (@as(u32, 1) << aux_min_shift)) else 0;
                const key = keyAux(atoms.relation(R, a, self.g.flags, wa), atoms.relation(R, a, self.g.flags, wr), len | (af & self.g.flagMask()));
                self.record(.atom, @intCast(i), none, none, &key);
                tab.stats.atoms += 1;
                if (self.stopped) break;
            }
            if (self.keys.items.len == 0) return error.Resource;
            self.level_start[2] = @intCast(self.keys.items.len);

            var rng = rngmod.Rng.fromParts(rngmod.Tag.combos, &.{in.id.seed});
            var k: usize = 2;
            while (k <= K) : (k += 1) {
                self.level_start[k + 1] = self.level_start[k];
                if (self.stopped) continue;
                self.cur_level = @intCast(k);
                self.setQuota(k);
                const ls = &tab.stats.levels[k];
                // unary over level k-1, by child ID then parameter ID
                var y = self.level_start[k - 1];
                outer: while (y < self.level_start[k]) : (y += 1) {
                    for (self.g.unary) |u| {
                        ls.unary_visits += 1;
                        self.applyUnary(u, y);
                        if (self.stopped) break :outer;
                    }
                }
                // binary over all ordered splits
                if (!self.stopped and self.g.binary.len > 0 and k >= 3) {
                    var total: u64 = 0;
                    var k1: usize = 1;
                    while (k1 + 1 < k) : (k1 += 1) {
                        const prod = std.math.mul(u64, self.levelLen(k1), self.levelLen(k - 1 - k1)) catch std.math.maxInt(u64) / 4;
                        total +|= prod *| self.g.binary.len;
                    }
                    ls.combos_total = total;
                    if (total <= self.cfg.max_combos) {
                        var r: u64 = 0;
                        while (r < total) : (r += 1) {
                            self.decodeAndApply(k, r);
                            ls.combos_visited += 1;
                            if (self.stopped) break;
                        }
                    } else {
                        ls.sampled = true;
                        tab.stats.combos_limited = true;
                        var sel = Selector.init(self.cfg.max_combos, total, rng);
                        while (sel.next()) |r| {
                            self.decodeAndApply(k, r);
                            ls.combos_visited += 1;
                            if (self.stopped) break;
                        }
                        rng = sel.rng;
                    }
                }
                self.level_start[k + 1] = @intCast(self.keys.items.len);
            }
            tab.stats.pairs_built = @intCast(self.keys.items.len);
            tab.stats.prods_built = @intCast(self.prods.items.len);
            tab.stats.count_terms_charged = self.terms;
            tab.stats.build_ns = sys.nowNs() - t0;

            try self.finalize(in);
            tab.stats.peak_bytes = tab.budget.peak.load(.monotonic);
            ok = true;
            return tab;
        }

        fn freeBuild(self: *Self) void {
            self.keys.deinit(self.alloc);
            self.ms.deinit(self.alloc);
            self.alloc.free(self.slots);
            self.slots = &.{};
            self.prods.deinit(self.alloc);
            self.alloc.free(self.pset);
            self.pset = &.{};
        }

        fn isStart(self: *const Self, x: u32) bool {
            const kx = self.keys.items[x];
            return relA(kx).get(0, self.wa.len) and !relR(kx).get(0, self.wr.len);
        }

        fn finalize(self: *Self, in: BuildInput) BuildError!void {
            const tab = self.table;
            const a = self.alloc;
            const np: u32 = @intCast(self.keys.items.len);
            const K = self.K;

            // Free the hash sets: only keys, ms, prods are needed from here.
            a.free(self.slots);
            self.slots = &.{};
            a.free(self.pset);
            self.pset = &.{};

            // CSR by lhs over unsorted productions.
            const t_prune = sys.nowNs();
            const keep_pair = a.alloc(bool, np) catch return error.Resource;
            defer a.free(keep_pair);
            const best = a.alloc(u8, np) catch return error.Resource;
            defer a.free(best);
            var any_start = false;
            for (0..np) |x| {
                const s = self.isStart(@intCast(x));
                any_start = any_start or s;
            }
            // A build cut short by the byte cap is a resource rejection, not zero mass.
            if (!any_start) return if (tab.stats.stop_reason == .bytes) error.Resource else error.ZeroMass;

            const prods = self.prods.items;
            const keep_prod = a.alloc(bool, prods.len) catch return error.Resource;
            defer a.free(keep_prod);
            @memset(keep_prod, true);
            @memset(keep_pair, true);

            if (self.cfg.usefulness_pass) prune: {
                // CSR index of productions by lhs.
                const cnt = a.alloc(u32, np + 1) catch {
                    tab.stats.prune_abandoned = true;
                    break :prune;
                };
                defer a.free(cnt);
                @memset(cnt, 0);
                for (prods) |p| cnt[p.lhs + 1] += 1;
                for (1..np + 1) |i| cnt[i] += cnt[i - 1];
                const order = a.alloc(u32, prods.len) catch {
                    tab.stats.prune_abandoned = true;
                    break :prune;
                };
                defer a.free(order);
                {
                    const fill = a.alloc(u32, np) catch {
                        tab.stats.prune_abandoned = true;
                        break :prune;
                    };
                    defer a.free(fill);
                    @memcpy(fill, cnt[0..np]);
                    for (prods, 0..) |p, i| {
                        order[fill[p.lhs]] = @intCast(i);
                        fill[p.lhs] += 1;
                    }
                }
                @memset(best, 0);
                var work: std.ArrayList(u32) = .empty;
                defer work.deinit(a);
                const ws_limit = self.cfg.usefulness_workspace / @sizeOf(u32);
                for (0..np) |x| {
                    if (self.isStart(@intCast(x))) {
                        best[x] = K;
                        work.append(a, @intCast(x)) catch {
                            tab.stats.prune_abandoned = true;
                            break :prune;
                        };
                    }
                }
                var pushes: u64 = 0;
                while (work.pop()) |x| {
                    const r = best[x];
                    for (order[cnt[x]..cnt[x + 1]]) |pi| {
                        const p = prods[pi];
                        const op: Op = @enumFromInt(p.op);
                        if (op == .atom) continue;
                        if (op.isBinary()) {
                            const my = self.ms.items[p.a];
                            const mz = self.ms.items[p.b];
                            if (@as(usize, my) + mz + 1 > r) continue;
                            const ry: u8 = r - 1 - mz;
                            const rz: u8 = r - 1 - my;
                            inline for (.{ .{ p.a, ry }, .{ p.b, rz } }) |cr| {
                                if (cr[1] > best[cr[0]]) {
                                    best[cr[0]] = cr[1];
                                    pushes += 1;
                                    if (pushes > ws_limit) {
                                        tab.stats.prune_abandoned = true;
                                        break :prune;
                                    }
                                    work.append(a, cr[0]) catch {
                                        tab.stats.prune_abandoned = true;
                                        break :prune;
                                    };
                                }
                            }
                        } else {
                            const my = self.ms.items[p.a];
                            if (@as(usize, my) + 1 > r) continue;
                            if (r - 1 > best[p.a]) {
                                best[p.a] = r - 1;
                                pushes += 1;
                                if (pushes > ws_limit) {
                                    tab.stats.prune_abandoned = true;
                                    break :prune;
                                }
                                work.append(a, p.a) catch {
                                    tab.stats.prune_abandoned = true;
                                    break :prune;
                                };
                            }
                        }
                    }
                }
                for (0..np) |x| keep_pair[x] = best[x] >= self.ms.items[x] and best[x] > 0;
                for (prods, 0..) |p, i| {
                    const op: Op = @enumFromInt(p.op);
                    var keep = keep_pair[p.lhs];
                    if (keep and op != .atom) {
                        const r = best[p.lhs];
                        if (op.isBinary()) {
                            keep = keep_pair[p.a] and keep_pair[p.b] and @as(usize, self.ms.items[p.a]) + self.ms.items[p.b] + 1 <= r;
                        } else keep = keep_pair[p.a] and @as(usize, self.ms.items[p.a]) + 1 <= r;
                    }
                    keep_prod[i] = keep;
                }
                tab.stats.pruned = true;
            }
            if (tab.stats.prune_abandoned) {
                @memset(keep_prod, true);
                @memset(keep_pair, true);
            }
            tab.stats.prune_ns = sys.nowNs() - t_prune;

            // Renumber surviving pairs in original ID order.
            const remap = a.alloc(u32, np) catch return error.Resource;
            defer a.free(remap);
            var nk: u32 = 0;
            for (0..np) |x| {
                if (keep_pair[x]) {
                    remap[x] = nk;
                    nk += 1;
                } else remap[x] = none;
            }
            var nprod: usize = 0;
            for (keep_prod) |kp| nprod += @intFromBool(kp);

            const fprods = a.alloc(Prod, nprod) catch return error.Resource;
            var fp_ok = false;
            defer if (!fp_ok) a.free(fprods);
            {
                var j: usize = 0;
                for (prods, 0..) |p, i| {
                    if (!keep_prod[i]) continue;
                    var q = p;
                    q.lhs = remap[p.lhs];
                    if (q.a != none) q.a = remap[p.a];
                    if (q.b != none) q.b = remap[p.b];
                    fprods[j] = q;
                    j += 1;
                }
            }
            std.mem.sort(Prod, fprods, {}, struct {
                fn lt(_: void, x: Prod, y: Prod) bool {
                    if (x.lhs != y.lhs) return x.lhs < y.lhs;
                    if (x.op != y.op) return x.op < y.op;
                    if (x.arg != y.arg) return x.arg < y.arg;
                    if (x.a != y.a) return x.a < y.a;
                    return x.b < y.b;
                }
            }.lt);
            const fms = a.alloc(u8, nk) catch return error.Resource;
            var fms_ok = false;
            defer if (!fms_ok) a.free(fms);
            var start_flags = a.alloc(bool, nk) catch return error.Resource;
            defer a.free(start_flags);
            for (0..np) |x| if (remap[x] != none) {
                fms[remap[x]] = self.ms.items[x];
                start_flags[remap[x]] = self.isStart(@intCast(x));
            };
            // Free build-only storage now (keys, ms, raw prods).
            self.keys.deinit(a);
            self.keys = .empty;
            self.ms.deinit(a);
            self.ms = .empty;
            self.prods.deinit(a);
            self.prods = .empty;

            const pstart = a.alloc(u32, nk + 1) catch return error.Resource;
            var ps_ok = false;
            defer if (!ps_ok) a.free(pstart);
            @memset(pstart, 0);
            for (fprods) |p| pstart[p.lhs + 1] += 1;
            var maxpp: u32 = 0;
            for (1..nk + 1) |i| {
                maxpp = @max(maxpp, pstart[i]);
                pstart[i] += pstart[i - 1];
            }

            // Count storage.
            const coff = a.alloc(u32, nk) catch return error.Resource;
            var co_ok = false;
            defer if (!co_ok) a.free(coff);
            var total: u64 = 0;
            for (0..nk) |x| {
                if (total > std.math.maxInt(u32)) return error.Resource;
                coff[x] = @intCast(total);
                total += @as(u64, K) - fms[x] + 1;
            }
            if (total > std.math.maxInt(u32) - 1) return error.Resource;
            const counts = a.alloc(f32, total) catch return error.Resource;
            var c_ok = false;
            defer if (!c_ok) a.free(counts);
            const plw = a.alloc(f64, nprod) catch return error.Resource;
            var plw_ok = false;
            defer if (!plw_ok) a.free(plw);
            for (fprods, 0..) |p, i| plw[i] = @log(self.g.prodWeight(p));

            tab.id = in.id;
            tab.grammar = in.grammar;
            tab.max_size = K;
            tab.a16 = &.{};
            tab.r16 = &.{};
            tab.npairs = nk;
            tab.ms = fms;
            tab.pstart = pstart;
            tab.prods = fprods;
            tab.plw = plw;
            tab.coff = coff;
            tab.counts = counts;
            tab.start_alias = &.{};
            tab.size_dist = &.{};
            tab.max_prods_per_pair = maxpp;
            tab.slots = &.{};
            tab.arena = &.{};
            tab.cache_enabled = false;
            tab.host_alloc = in.host_alloc;
            tab.live_counter = null;
            tab.refs = .init(1);
            fp_ok = true;
            fms_ok = true;
            ps_ok = true;
            co_ok = true;
            c_ok = true;
            plw_ok = true;
            errdefer {
                // partial cleanup of what has been attached so far
                a.free(tab.ms);
                a.free(tab.pstart);
                a.free(tab.prods);
                a.free(tab.plw);
                a.free(tab.coff);
                a.free(tab.counts);
                if (tab.a16.len > 0) a.free(tab.a16);
                if (tab.r16.len > 0) a.free(tab.r16);
            }
            tab.a16 = a.dupe(u16, in.a16) catch return error.Resource;
            tab.r16 = a.dupe(u16, in.r16) catch return error.Resource;

            // Count W(X, k) bottom-up.
            const tc = sys.nowNs();
            var visited: u64 = 0;
            for (1..@as(usize, K) + 1) |k| {
                for (0..nk) |x| {
                    if (k < fms[x]) continue;
                    var acc = Lse{};
                    for (pstart[x]..pstart[x + 1]) |pi| {
                        const p = fprods[pi];
                        const op: Op = @enumFromInt(p.op);
                        if (op.isBinary()) {
                            const my = fms[p.a];
                            const mz = fms[p.b];
                            if (k < @as(usize, my) + mz + 1) continue;
                            visited += k - my - mz;
                        } else visited += 1;
                        acc.add(tab.prodTerm(p, k, plw[pi]));
                    }
                    const v = acc.result();
                    if (std.math.isNan(v) or v == std.math.inf(f64)) return error.ModelFailure;
                    counts[coff[x] + (k - fms[x])] = @floatCast(v);
                }
            }
            tab.stats.count_terms_visited = visited;
            tab.stats.count_ns = sys.nowNs() - tc;
            tab.stats.pairs = nk;
            tab.stats.prods = @intCast(nprod);

            // Start pairs, feasible sizes, start alias per size.
            var nstart: u32 = 0;
            for (start_flags) |s| nstart += @intFromBool(s);
            tab.stats.start_pairs = nstart;
            const start_list = a.alloc(u32, nstart) catch return error.Resource;
            defer a.free(start_list);
            {
                var j: usize = 0;
                for (start_flags, 0..) |s, x| if (s) {
                    start_list[j] = @intCast(x);
                    j += 1;
                };
            }
            const sal = a.alloc(Alias, @as(usize, K) + 1) catch return error.Resource;
            for (sal) |*s| s.* = .{ .prob = &.{}, .alias = &.{}, .items = &.{} };
            tab.start_alias = sal;
            errdefer {
                for (tab.start_alias) |*s| if (s.items.len > 0) freeAlias(a, s);
                a.free(tab.start_alias);
            }
            const wtmp = a.alloc(f64, @max(nstart, @as(u32, K) + 1)) catch return error.Resource;
            defer a.free(wtmp);
            const itmp = a.alloc(u32, @max(nstart, @as(u32, K) + 1)) catch return error.Resource;
            defer a.free(itmp);
            const dist = a.alloc(f64, @as(usize, K) + 1) catch return error.Resource;
            @memset(dist, 0);
            tab.size_dist = dist;
            var feasible: u32 = 0;
            var excluded: u32 = 0;
            var dsum: f64 = 0;
            for (1..@as(usize, K) + 1) |k| {
                const D = self.cfg.size_weights[k];
                var mx = -std.math.inf(f64);
                var n: usize = 0;
                for (start_list) |x| {
                    const lw = tab.logW(x, k);
                    if (lw == -std.math.inf(f64)) continue;
                    mx = @max(mx, lw);
                    itmp[n] = x;
                    n += 1;
                }
                if (n == 0) {
                    if (D > 0) excluded += 1;
                    continue;
                }
                for (0..n) |j| wtmp[j] = @exp(tab.logW(itmp[j], k) - mx);
                var pos = false;
                for (wtmp[0..n]) |w| pos = pos or w > 0;
                if (!pos) {
                    if (D > 0) excluded += 1;
                    continue;
                }
                sal[k] = makeAlias(a, itmp[0..n], wtmp[0..n]) catch return error.Resource;
                if (D > 0) {
                    dist[k] = D;
                    dsum += D;
                    feasible += 1;
                }
            }
            tab.stats.feasible_sizes = feasible;
            tab.stats.excluded_sizes = excluded;
            if (dsum <= 0) return error.ZeroMass;
            var ns: usize = 0;
            for (1..@as(usize, K) + 1) |k| if (dist[k] > 0) {
                dist[k] /= dsum;
                itmp[ns] = @intCast(k);
                wtmp[ns] = dist[k];
                ns += 1;
            };
            tab.size_alias = makeAlias(a, itmp[0..ns], wtmp[0..ns]) catch return error.Resource;
            errdefer freeAlias(a, &tab.size_alias);

            // Lazy SampIdx: one slot per count entry, plus the arena.
            tab.cache_enabled = self.cfg.alias_cache;
            const nslots: usize = if (tab.cache_enabled) total else 0;
            tab.slots = a.alloc(std.atomic.Value(u32), nslots) catch return error.Resource;
            for (tab.slots) |*s| s.* = .init(0);
            // The arena only caches alias tables (draws are identical with or
            // without it), so it takes at most half of what the table budget has left.
            const arena_cap: u64 = @min(self.cfg.alias_arena_bytes, (tab.budget.available() -| nslots * 4) / 2);
            const arena_words: usize = if (tab.cache_enabled) @intCast(@min(arena_cap / 4, std.math.maxInt(u32) - 1)) else 0;
            tab.arena = a.alloc(u32, arena_words) catch {
                a.free(tab.slots);
                return error.Resource;
            };
            tab.arena_top = .init(0);
            tab.cache_hits = .init(0);
            tab.uncached = .init(0);
            tab.cache_builds = .init(0);
            tab.wasted = .init(0);

            // Digest of the finalized grammar and counts.
            var h = std.crypto.hash.sha2.Sha256.init(.{});
            h.update(generator_version);
            h.update(numerics_version);
            self.g.hashInto(&h);
            h.update(std.mem.sliceAsBytes(tab.a16));
            h.update(&[_]u8{0xff});
            h.update(std.mem.sliceAsBytes(tab.r16));
            h.update(std.mem.sliceAsBytes(fms));
            h.update(std.mem.sliceAsBytes(fprods));
            h.update(std.mem.sliceAsBytes(counts));
            h.final(&tab.digest);
        }
    };
}

pub fn digestHex(t: *const Table) [64]u8 {
    return std.fmt.bytesToHex(t.digest, .lower);
}

// ---------------------------------------------------------------------------
// Tests

const testing = std.testing;
const ucd = @import("ucd.zig");

test "selector draws exactly n ascending ranks uniformly" {
    var hist = [_]u32{0} ** 20;
    for (0..4000) |s| {
        var sel = Selector.init(5, 20, rngmod.Rng.fromParts(77, &.{s}));
        var last: ?u64 = null;
        var c: usize = 0;
        while (sel.next()) |r| {
            try testing.expect(r < 20);
            if (last) |l| try testing.expect(r > l);
            last = r;
            hist[r] += 1;
            c += 1;
        }
        try testing.expectEqual(@as(usize, 5), c);
    }
    for (hist) |h| try testing.expect(h > 800 and h < 1200); // expected 1000
    // Large N exercises Method D.
    var sel = Selector.init(1000, 1 << 40, rngmod.Rng.fromParts(78, &.{}));
    var c: usize = 0;
    var last: u64 = 0;
    while (sel.next()) |r| : (c += 1) {
        try testing.expect(r < 1 << 40);
        if (c > 0) try testing.expect(r > last);
        last = r;
    }
    try testing.expectEqual(@as(usize, 1000), c);
}

fn testCfg() config.Config {
    var cfg: config.Config = .{};
    cfg.max_size = 6;
    @memset(&cfg.size_weights, 0);
    for (1..7) |k| cfg.size_weights[k] = 1;
    cfg.usefulness_pass = false;
    cfg.allow_diagonal_lookarounds = true;
    return cfg;
}

fn u16s(comptime s: []const u8) [s.len]u16 {
    var out: [s.len]u16 = undefined;
    for (s, 0..) |c, i| out[i] = c;
    return out;
}

/// Exhaustively enumerate all trees up to max size over the grammar and sum
/// weights per (root pair key bytes, size); compare to table counts.
fn Exhaustive(comptime R: type) type {
    return struct {
        const Tree = struct { ra: R, rr: R, w: f64 };
        fn run(gpa: Allocator, g: *const Grammar, wa: []const u21, wr: []const u21, K: usize) ![][]Tree {
            const levels = try gpa.alloc([]Tree, K + 1);
            levels[0] = &.{};
            for (1..K + 1) |k| {
                var list: std.ArrayList(Tree) = .empty;
                if (k == 1) {
                    for (g.atoms, 0..) |*a, i| {
                        if (g.atom_w[i] <= 0) continue;
                        try list.append(gpa, .{ .ra = atoms.relation(R, a, g.flags, wa), .rr = atoms.relation(R, a, g.flags, wr), .w = g.atom_w[i] });
                    }
                } else {
                    for (levels[k - 1]) |t| for (g.unary) |u| {
                        var na = t.ra;
                        var nr = t.rr;
                        const da = wa.len + 1;
                        const dr = wr.len + 1;
                        switch (u.op) {
                            .quant => {
                                na = ast.quantRel(R, t.ra, g.quants[u.arg], da);
                                nr = ast.quantRel(R, t.rr, g.quants[u.arg], dr);
                            },
                            .look_ahead => {
                                na = t.ra.lookahead(da, false);
                                nr = t.rr.lookahead(dr, false);
                            },
                            .neg_look_ahead => {
                                na = t.ra.lookahead(da, true);
                                nr = t.rr.lookahead(dr, true);
                            },
                            .look_behind => {
                                na = t.ra.lookbehind(da, false);
                                nr = t.rr.lookbehind(dr, false);
                            },
                            .neg_look_behind => {
                                na = t.ra.lookbehind(da, true);
                                nr = t.rr.lookbehind(dr, true);
                            },
                            else => {},
                        }
                        try list.append(gpa, .{ .ra = na, .rr = nr, .w = t.w * u.w });
                    };
                    for (1..k - 1) |k1| {
                        const k2 = k - 1 - k1;
                        for (levels[k1]) |y| for (levels[k2]) |z| for (g.binary) |b| {
                            if (b.op == .concat)
                                try list.append(gpa, .{ .ra = y.ra.mul(z.ra), .rr = y.rr.mul(z.rr), .w = y.w * z.w * b.w })
                            else
                                try list.append(gpa, .{ .ra = y.ra.orr(z.ra), .rr = y.rr.orr(z.rr), .w = y.w * z.w * b.w });
                        };
                    }
                }
                levels[k] = try list.toOwnedSlice(gpa);
            }
            return levels;
        }
    };
}

fn smallGrammar(gpa: Allocator, flags: Flags, weighted: bool) !Grammar {
    // literals a, b, k plus caret; ops: concat, alt, star, opt, lookahead, group_nc
    var atomsl: std.ArrayList(AtomSpec) = .empty;
    for ([_]u21{ 'a', 'b', 'K' }) |c| try atomsl.append(gpa, .{ .kind = .lit, .syms = .{ c, 0, 0, 0 } });
    try atomsl.append(gpa, .{ .kind = .wordb });
    try atomsl.append(gpa, .{ .kind = .empty });
    const aw = try gpa.alloc(f64, atomsl.items.len);
    for (aw, 0..) |*w, i| w.* = if (weighted) @as(f64, @floatFromInt(i + 1)) * 0.7 else 1.0;
    const qs = try gpa.dupe(QuantSpec, &.{ .{ .form = .star, .min = 0, .max = ast.inf }, .{ .form = .range, .min = 1, .max = 2 } });
    const un = try gpa.dupe(UnaryEntry, &.{
        .{ .op = .quant, .arg = 0, .w = if (weighted) 3.0 else 1.0 },
        .{ .op = .quant, .arg = 1, .w = if (weighted) 1e-3 else 1.0 },
        .{ .op = .neg_look_ahead, .arg = 0, .w = if (weighted) 50.0 else 1.0 },
        .{ .op = .group_nc, .arg = 0, .w = 1.0 },
    });
    const bin = try gpa.dupe(BinaryEntry, &.{ .{ .op = .concat, .w = 1.0 }, .{ .op = .alt, .w = if (weighted) 0.01 else 1.0 } });
    var g: Grammar = .{ .flags = flags, .atoms = try atomsl.toOwnedSlice(gpa), .atom_w = aw, .quants = qs, .unary = un, .binary = bin, .allow_diagonal_lookarounds = true, .quant_w = &.{}, .op_w = undefined };
    try g.indexWeights(gpa);
    return g;
}

fn checkCounts(weighted: bool, flags: Flags, a_str: []const u21, r_str: []const u21) !void {
    ucd.init();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var cfg = testCfg();
    cfg.max_size = 5;
    @memset(&cfg.size_weights, 0);
    for (1..6) |k| cfg.size_weights[k] = 1;
    var g = try smallGrammar(gpa, flags, weighted);
    var host = Budget.init("host", 1 << 30, null);
    var a16: [16]u16 = undefined;
    var r16: [16]u16 = undefined;
    const na = alpha.toUtf16(a_str, &a16);
    const nr = alpha.toUtf16(r_str, &r16);
    const tab = try build(.{ .grammar = &g, .cfg = &cfg, .a16 = a16[0..na], .r16 = r16[0..nr], .id = .{ .seq = 0, .attempt = 0, .seed = 1, .flags = flags }, .host = &host, .host_alloc = testing.allocator });
    defer tab.release();
    try testing.expectEqual(Truncation.none, tab.stats.stop_reason);
    const R = relmod.Rel8;
    const levels = try Exhaustive(R).run(gpa, &g, a_str, r_str, cfg.max_size);
    // Sum exhaustive weight by size over start trees, and per-size totals per start pair compare via Z_k.
    for (1..@as(usize, cfg.max_size) + 1) |k| {
        var exact: f64 = 0;
        for (levels[k]) |t| {
            if (t.ra.get(0, a_str.len) and !t.rr.get(0, r_str.len)) exact += t.w;
        }
        var lse = Lse{};
        for (0..tab.npairs) |x| {
            // start pairs: those included in start alias for some size; recompute via counts
            var is_start = false;
            for (tab.start_alias) |sa| {
                for (sa.items) |it| if (it == x) {
                    is_start = true;
                };
            }
            if (is_start) lse.add(tab.logW(@intCast(x), k));
        }
        const got = @exp(lse.result());
        if (exact == 0) {
            try testing.expect(lse.result() == -std.math.inf(f64));
        } else {
            const relerr = @abs(got - exact) / exact;
            try testing.expect(relerr < 1e-5);
        }
    }
}

test "counts match exhaustive enumeration (uniform weights)" {
    try checkCounts(false, .{}, &.{ 'a', 'b' }, &.{'b'});
}

test "counts match exhaustive enumeration (extreme weights, i flag)" {
    try checkCounts(true, .{ .i = true }, &.{ 'a', 'K', 'a' }, &.{ 'a', 'k' });
}

test "A = R is rejected and inseparable pairs have zero mass" {
    ucd.init();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var cfg = testCfg();
    var g = try smallGrammar(gpa, .{ .i = true }, false);
    var host = Budget.init("host", 1 << 30, null);
    const s1 = u16s("ab");
    try testing.expectError(error.InvalidInput, build(.{ .grammar = &g, .cfg = &cfg, .a16 = &s1, .r16 = &s1, .id = .{ .seq = 0, .attempt = 0, .seed = 1, .flags = .{ .i = true } }, .host = &host, .host_alloc = testing.allocator }));
    const s2 = u16s("aB");
    try testing.expectError(error.ZeroMass, build(.{ .grammar = &g, .cfg = &cfg, .a16 = &s1, .r16 = &s2, .id = .{ .seq = 0, .attempt = 0, .seed = 1, .flags = .{ .i = true } }, .host = &host, .host_alloc = testing.allocator }));
}

test "tiny budgets truncate deterministically and stay sound" {
    ucd.init();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var cfg: config.Config = .{};
    cfg.max_size = 10;
    @memset(&cfg.size_weights, 0);
    for (1..11) |k| cfg.size_weights[k] = 1;
    cfg.max_pairs = 3000;
    cfg.max_combos = 20000;
    cfg.max_prods = 50000;
    var g = try Grammar.init(gpa, &cfg, .{});
    var host = Budget.init("host", 1 << 30, null);
    const a = u16s("ab k");
    const r = u16s("ab K");
    var digests: [2][32]u8 = undefined;
    for (0..2) |i| {
        const tab = try build(.{ .grammar = &g, .cfg = &cfg, .a16 = &a, .r16 = &r, .id = .{ .seq = 0, .attempt = 0, .seed = 99, .flags = .{} }, .host = &host, .host_alloc = testing.allocator });
        defer tab.release();
        digests[i] = tab.digest;
        try testing.expect(tab.stats.stop_reason != .none or tab.stats.quota_limited or tab.stats.combos_limited);
        try testing.expect(tab.stats.pairs_built <= 3000);
    }
    try testing.expectEqualSlices(u8, &digests[0], &digests[1]);
    // byte budget too small for the minimum viable table
    cfg.max_table_bytes = 64;
    try testing.expectError(error.Resource, build(.{ .grammar = &g, .cfg = &cfg, .a16 = &a, .r16 = &r, .id = .{ .seq = 0, .attempt = 0, .seed = 99, .flags = .{} }, .host = &host, .host_alloc = testing.allocator }));
    try testing.expectEqual(@as(u64, 0), host.used.load(.monotonic));
}
