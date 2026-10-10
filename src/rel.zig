//! Span relations. For a string of length n, a relation is an (n+1)×(n+1)
//! upper-triangular boolean matrix: bit j of row i means "matches w[i..j]".
//! `N` is comptime (8 or 16) so short strings get `u8` rows.
const std = @import("std");

pub fn Rel(comptime N: comptime_int) type {
    comptime std.debug.assert(N == 8 or N == 16 or N == 32);
    return struct {
        const Self = @This();
        pub const Row = std.meta.Int(.unsigned, N);
        pub const max_len = N - 1;
        pub const n_rows = N;

        rows: [N]Row = [_]Row{0} ** N,

        pub const empty: Self = .{};

        pub fn identity(dim: usize) Self {
            var r: Self = .{};
            for (0..dim) |i| r.rows[i] = @as(Row, 1) << @intCast(i);
            return r;
        }

        pub fn single(i: usize, j: usize) Self {
            var r: Self = .{};
            r.rows[i] = @as(Row, 1) << @intCast(j);
            return r;
        }

        pub fn set(self: *Self, i: usize, j: usize) void {
            self.rows[i] |= @as(Row, 1) << @intCast(j);
        }

        pub fn get(self: Self, i: usize, j: usize) bool {
            return (self.rows[i] >> @intCast(j)) & 1 != 0;
        }

        pub fn eql(a: Self, b: Self) bool {
            return std.mem.eql(Row, &a.rows, &b.rows);
        }

        pub fn orr(a: Self, b: Self) Self {
            var r: Self = undefined;
            for (0..N) |i| r.rows[i] = a.rows[i] | b.rows[i];
            return r;
        }

        /// Relational composition: (i,k) ∈ a and (k,j) ∈ b.
        pub fn mul(a: Self, b: Self) Self {
            var r: Self = .{};
            for (0..N) |i| {
                var bits = a.rows[i];
                var acc: Row = 0;
                while (bits != 0) {
                    const k = @ctz(bits);
                    bits &= bits - 1;
                    acc |= b.rows[k];
                }
                r.rows[i] = acc;
            }
            return r;
        }

        /// Transitive closure (Warshall on rows).
        pub fn plus(a: Self) Self {
            var r = a;
            for (0..N) |k| {
                const rk_bit = @as(Row, 1) << @intCast(k);
                for (0..N) |i| {
                    if (r.rows[i] & rk_bit != 0) r.rows[i] |= r.rows[k];
                }
            }
            return r;
        }

        pub fn star(a: Self, dim: usize) Self {
            return identity(dim).orr(a.plus());
        }

        pub fn opt(a: Self, dim: usize) Self {
            return identity(dim).orr(a);
        }

        /// a^m by repeated squaring (a^0 = I).
        pub fn pow(a: Self, m: usize, dim: usize) Self {
            var result = identity(dim);
            var base = a;
            var e = m;
            while (e > 0) {
                if (e & 1 != 0) result = result.mul(base);
                e >>= 1;
                if (e > 0) base = base.mul(base);
            }
            return result;
        }

        /// e{m,n} = e^m · (I ∨ e)^(n−m)
        pub fn rep(a: Self, m: usize, n: usize, dim: usize) Self {
            std.debug.assert(m <= n);
            return a.pow(m, dim).mul(a.opt(dim).pow(n - m, dim));
        }

        /// e{m,} = e^m · e*
        pub fn repOpen(a: Self, m: usize, dim: usize) Self {
            return a.pow(m, dim).mul(a.star(dim));
        }

        /// Diagonal of positions i with some (i, j) ∈ a; negated over 0..dim-1.
        pub fn lookahead(a: Self, dim: usize, neg: bool) Self {
            var r: Self = .{};
            for (0..dim) |i| {
                const hit = a.rows[i] != 0;
                if (hit != neg) r.rows[i] = @as(Row, 1) << @intCast(i);
            }
            return r;
        }

        /// Diagonal of positions j with some (i, j) ∈ a; negated over 0..dim-1.
        pub fn lookbehind(a: Self, dim: usize, neg: bool) Self {
            var cols: Row = 0;
            for (0..N) |i| cols |= a.rows[i];
            var r: Self = .{};
            for (0..dim) |j| {
                const hit = (cols >> @intCast(j)) & 1 != 0;
                if (hit != neg) r.rows[j] = @as(Row, 1) << @intCast(j);
            }
            return r;
        }

        pub fn isDiagonal(a: Self) bool {
            for (0..N) |i| {
                if (a.rows[i] & ~(@as(Row, 1) << @intCast(i)) != 0) return false;
            }
            return true;
        }

        pub fn diagFromMask(mask: u32) Self {
            var r: Self = .{};
            for (0..N) |i| {
                if ((mask >> @intCast(i)) & 1 != 0) r.rows[i] = @as(Row, 1) << @intCast(i);
            }
            return r;
        }

        pub fn bytes(self: *const Self) []const u8 {
            return std.mem.asBytes(&self.rows);
        }
    };
}

pub const Rel8 = Rel(8);
pub const Rel16 = Rel(16);
pub const Rel32 = Rel(32);

const testing = std.testing;

test "identity, product, closure" {
    const R = Rel8;
    var a = R.single(0, 1);
    a.set(1, 2);
    const p = a.mul(a);
    try testing.expect(p.get(0, 2));
    try testing.expect(!p.get(0, 1));
    const s = a.star(3);
    try testing.expect(s.get(0, 0) and s.get(0, 1) and s.get(0, 2) and s.get(1, 2) and s.get(2, 2));
    try testing.expect(!s.get(2, 1));
}

test "bounded powers agree with naive expansion" {
    const R = Rel16;
    var prng = std.Random.DefaultPrng.init(1);
    const rnd = prng.random();
    for (0..200) |_| {
        const dim = rnd.intRangeAtMost(usize, 1, 16);
        var a: R = .{};
        for (0..dim) |i| for (i..dim) |j| {
            if (rnd.uintLessThan(u8, 4) == 0) a.set(i, j);
        };
        const m = rnd.uintAtMost(usize, 3);
        const n = m + rnd.uintAtMost(usize, 3);
        // naive: OR over k in [m, n] of a^k
        var naive: R = .{};
        var pk = R.identity(dim);
        for (0..n + 1) |k| {
            if (k >= m) naive = naive.orr(pk);
            pk = pk.mul(a);
        }
        try testing.expect(naive.eql(a.rep(m, n, dim)));
        // e{m,} = OR over k >= m, saturates by k = m + dim
        var naive_open: R = .{};
        pk = R.identity(dim);
        for (0..m + dim + 2) |k| {
            if (k >= m) naive_open = naive_open.orr(pk);
            pk = pk.mul(a);
        }
        try testing.expect(naive_open.eql(a.repOpen(m, dim)));
        try testing.expect(a.star(dim).eql(a.repOpen(0, dim)));
    }
}

test "lookarounds are diagonal" {
    const R = Rel8;
    var a = R.single(1, 3);
    a.set(2, 2);
    const la = a.lookahead(4, false);
    try testing.expect(la.isDiagonal() and la.get(1, 1) and la.get(2, 2) and !la.get(0, 0));
    const lb = a.lookbehind(4, false);
    try testing.expect(lb.get(3, 3) and lb.get(2, 2) and !lb.get(1, 1));
    const nla = a.lookahead(4, true);
    try testing.expect(nla.get(0, 0) and nla.get(3, 3) and !nla.get(1, 1));
}
