//! Deterministic randomness: xoshiro256** streams seeded from tuples by a
//! versioned SplitMix64-based expansion. Changing the expansion requires
//! bumping `seed_expansion_version` (recorded in manifests).
const std = @import("std");

pub const seed_expansion_version: u32 = 1;

pub const Rng = struct {
    s: [4]u64,

    fn splitmix(x: *u64) u64 {
        x.* +%= 0x9E3779B97F4A7C15;
        var z = x.*;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        return z ^ (z >> 31);
    }

    /// Seed from an ordered tuple of u64 parts (domain-separated by `tag`).
    pub fn fromParts(tag: u64, parts: []const u64) Rng {
        var x: u64 = tag ^ 0x6972785F73656564; // "irx_seed"
        _ = splitmix(&x);
        for (parts) |p| {
            x ^= p;
            _ = splitmix(&x);
        }
        var r: Rng = undefined;
        for (&r.s) |*w| w.* = splitmix(&x);
        if (r.s[0] | r.s[1] | r.s[2] | r.s[3] == 0) r.s[0] = 1;
        return r;
    }

    pub fn next(self: *Rng) u64 {
        const result = std.math.rotl(u64, self.s[1] *% 5, 7) *% 9;
        const t = self.s[1] << 17;
        self.s[2] ^= self.s[0];
        self.s[3] ^= self.s[1];
        self.s[1] ^= self.s[2];
        self.s[0] ^= self.s[3];
        self.s[2] ^= t;
        self.s[3] = std.math.rotl(u64, self.s[3], 45);
        return result;
    }

    /// Uniform in [0, 1) with 53 bits.
    pub fn float(self: *Rng) f64 {
        return @as(f64, @floatFromInt(self.next() >> 11)) * (1.0 / 9007199254740992.0);
    }

    /// Uniform in (0, 1).
    pub fn floatOpen(self: *Rng) f64 {
        return (@as(f64, @floatFromInt(self.next() >> 11)) + 0.5) * (1.0 / 9007199254740992.0);
    }

    /// Unbiased integer in [0, n) (Lemire).
    pub fn below(self: *Rng, n: u64) u64 {
        std.debug.assert(n > 0);
        var m: u128 = @as(u128, self.next()) * n;
        var l: u64 = @truncate(m);
        if (l < n) {
            const t = (0 -% n) % n;
            while (l < t) {
                m = @as(u128, self.next()) * n;
                l = @truncate(m);
            }
        }
        return @intCast(m >> 64);
    }
};

pub const Tag = struct {
    pub const table: u64 = 1;
    pub const case: u64 = 2;
    pub const combos: u64 = 3;
    pub const strings: u64 = 4;
    pub const shrink: u64 = 5;
};

/// Table seed from (global seed, table sequence, attempt).
pub fn tableSeed(global: u64, seq: u64, attempt: u64) u64 {
    var r = Rng.fromParts(Tag.table, &.{ global, seq, attempt });
    return r.next();
}

/// Per-case stream from (global seed, lane id, case index).
/// Case k of table (seq, attempt): independent of which lane runs it or when, so a run is a
/// pure function of its seed (with adaptive weights off).
pub fn tableCaseRng(global: u64, seq: u64, attempt: u64, k: u64) Rng {
    return Rng.fromParts(Tag.case, &.{ global, seq, attempt, k, 0x7AB1E });
}

/// Legacy (lane, per-lane index) derivation: findings recorded before `derive=table`.
pub fn caseRng(global: u64, lane: u64, case_index: u64) Rng {
    return Rng.fromParts(Tag.case, &.{ global, lane, case_index });
}

test "streams are deterministic and distinct" {
    var a = caseRng(42, 0, 7);
    var b = caseRng(42, 0, 7);
    var c = caseRng(42, 1, 7);
    try std.testing.expectEqual(a.next(), b.next());
    try std.testing.expect(a.next() != c.next());
    var r = Rng.fromParts(9, &.{});
    for (0..1000) |_| {
        const x = r.below(7);
        try std.testing.expect(x < 7);
        const f = r.float();
        try std.testing.expect(f >= 0 and f < 1);
    }
}
