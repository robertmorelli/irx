//! Long-input mode: each case gets a long accept/reject pair derived from its short pair,
//! and engines run the full-match test on the long strings.
//!
//! Generation pumps A: a segment A[i..j] that the pattern's loops can repeat (A with the
//! segment repeated twice and three times is still accepted) is repeated out to a target
//! length; one or two such segments are pumped at once. The long reject is a near miss: the
//! long accept with one symbol substituted, deleted or inserted at the start, the middle,
//! the end, or a power-of-two boundary (64, 128, 256, ...).
//!
//! The reference is the relation semantics of ast.evalRel evaluated as bit vectors over
//! positions instead of matrices: fwd(e, S) is the set of ends reachable from starts S,
//! bwd(e, E) the set of starts that reach an end in E. Lookarounds and assertions are
//! position masks (independent of S), so every operator distributes over union and a loop
//! closes over its frontier. Cost is about (pattern size × loop iterations × n/64) word
//! operations, with no backtracking, so it is exact on inputs where engines blow up.
//!
//! Engines that backtrack can still take exponential time on a long accepted string; the
//! guard runs the backtracking reference matcher with a step budget proportional to the
//! length and drops pairs it cannot finish.
const std = @import("std");
const ast = @import("ast.zig");
const atoms = @import("atoms.zig");
const alpha = @import("alphabet.zig");
const rngmod = @import("rng.zig");

const Allocator = std.mem.Allocator;
const Flags = alpha.Flags;

pub const Error = error{ OutOfMemory, Budget, Unsupported };

/// Bit-vector evaluation of a pattern on one subject (model symbols).
pub const Eval = struct {
    t: *const ast.Ast,
    flags: Flags,
    w: []const u21,
    gpa: Allocator,
    /// Word operations left before giving up.
    budget: u64 = 50_000_000,
    nw: usize = 0,
    masks: [256]?[]u64 = [_]?[]u64{null} ** 256,
    /// Effective flags per node (inline flag groups).
    nflags: [ast.max_nodes]Flags = undefined,
    /// Freed bitsets, reused by alloc (all bitsets have nw words).
    pool: std.ArrayList([]u64) = .empty,

    pub fn init(gpa: Allocator, t: *const ast.Ast, flags: Flags, w: []const u21) Eval {
        var ev: Eval = .{ .t = t, .flags = flags, .w = w, .gpa = gpa, .nw = (w.len + 1 + 63) / 64 };
        ast.nodeFlags(t, flags, &ev.nflags);
        return ev;
    }

    pub fn deinit(self: *Eval) void {
        for (&self.masks) |*m| if (m.*) |x| {
            self.gpa.free(x);
            m.* = null;
        };
        for (self.pool.items) |x| self.gpa.free(x);
        self.pool.deinit(self.gpa);
    }

    fn alloc(self: *Eval) Error![]u64 {
        const x = self.pool.pop() orelse try self.gpa.alloc(u64, self.nw);
        @memset(x, 0);
        return x;
    }

    /// Return a bitset to the pool (a result of fwd/bwd may also be freed with gpa).
    pub fn release(self: *Eval, x: []u64) void {
        self.pool.append(self.gpa, x) catch self.gpa.free(x);
    }

    fn charge(self: *Eval, k: u64) Error!void {
        const c = k * self.nw;
        if (c > self.budget) return error.Budget;
        self.budget -= c;
    }

    fn setBit(x: []u64, i: usize) void {
        x[i / 64] |= @as(u64, 1) << @intCast(i % 64);
    }

    fn getBit(x: []const u64, i: usize) bool {
        return (x[i / 64] >> @intCast(i % 64)) & 1 != 0;
    }

    /// Clear bits above position n.
    fn trim(self: *const Eval, x: []u64) void {
        const used = (self.w.len + 1) % 64;
        if (used != 0) x[self.nw - 1] &= (@as(u64, 1) << @intCast(used)) - 1;
    }

    fn isEmpty(x: []const u64) bool {
        for (x) |v| if (v != 0) return false;
        return true;
    }

    fn all(self: *Eval) Error![]u64 {
        const x = try self.alloc();
        @memset(x, ~@as(u64, 0));
        self.trim(x);
        return x;
    }

    /// Position mask of an atom or lookaround node, cached by node index. For a consuming
    /// atom: bit i set iff w[i] matches. For an assertion or lookaround: bit i set iff it
    /// holds at position i.
    fn mask(self: *Eval, idx: u8) Error![]const u64 {
        if (self.masks[idx]) |m| return m;
        const n = self.t.nodes[idx];
        const m = try self.alloc();
        switch (n.op) {
            .atom => switch (n.atom.kind) {
                .empty => unreachable,
                .caret, .dollar, .wordb, .nwordb => {
                    for (0..self.w.len + 1) |i| if (atoms.assertionAt(&n.atom, self.nflags[idx], self.w, i)) setBit(m, i);
                },
                else => for (self.w, 0..) |c, i| if (atoms.matches(&n.atom, self.nflags[idx], c)) setBit(m, i),
            },
            .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind => {
                const every = try self.all();
                defer self.release(every);
                const ahead = n.op == .look_ahead or n.op == .neg_look_ahead;
                // Lookahead: positions i with some (i, j) in the body; lookbehind: positions j
                // with some (i, j) in the body.
                const hit = if (ahead) try self.bwd(n.a, every) else try self.fwd(n.a, every);
                defer self.release(hit);
                @memcpy(m, hit);
                if (n.op == .neg_look_ahead or n.op == .neg_look_behind) {
                    for (m) |*v| v.* = ~v.*;
                    self.trim(m);
                }
            },
            else => unreachable,
        }
        self.masks[idx] = m;
        return m;
    }

    fn andMask(self: *Eval, s: []const u64, idx: u8) Error![]u64 {
        const m = try self.mask(idx);
        const out = try self.alloc();
        for (out, s, m) |*o, a, b| o.* = a & b;
        return out;
    }

    /// Ends reachable from the starts in `s`.
    pub fn fwd(self: *Eval, idx: u8, s: []const u64) Error![]u64 {
        return self.walk(idx, s, true);
    }

    /// Starts from which some end in `e` is reachable.
    pub fn bwd(self: *Eval, idx: u8, e: []const u64) Error![]u64 {
        return self.walk(idx, e, false);
    }

    fn walk(self: *Eval, idx: u8, s: []const u64, forward: bool) Error![]u64 {
        try self.charge(1);
        const n = self.t.nodes[idx];
        // Atomic groups and backreferences have no position-set semantics (mutation mode only).
        if (n.op == .atomic or n.op == .backref) return error.Unsupported;
        switch (n.op) {
            .atom => switch (n.atom.kind) {
                .empty => {
                    const out = try self.alloc();
                    @memcpy(out, s);
                    return out;
                },
                .caret, .dollar, .wordb, .nwordb => return self.andMask(s, idx),
                else => {
                    const m = try self.mask(idx);
                    const out = try self.alloc();
                    if (forward) {
                        // {i + 1 : i in s, w[i] matches}
                        var carry: u64 = 0;
                        for (out, s, m) |*o, a, b| {
                            const x = a & b;
                            o.* = (x << 1) | carry;
                            carry = x >> 63;
                        }
                        self.trim(out);
                    } else {
                        // {i : i + 1 in s, w[i] matches}
                        var k: usize = 0;
                        while (k < self.nw) : (k += 1) {
                            const hi: u64 = if (k + 1 < self.nw) s[k + 1] << 63 else 0;
                            out[k] = ((s[k] >> 1) | hi) & m[k];
                        }
                    }
                    return out;
                },
            },
            .concat => {
                const first, const second = if (forward) .{ n.a, n.b } else .{ n.b, n.a };
                const mid = try self.walk(first, s, forward);
                defer self.release(mid);
                return self.walk(second, mid, forward);
            },
            .alt => {
                const x = try self.walk(n.a, s, forward);
                const y = try self.walk(n.b, s, forward);
                defer self.release(y);
                for (x, y) |*a, b| a.* |= b;
                return x;
            },
            .quant => return self.quant(n.a, n.quant, s, forward),
            .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind => return self.andMask(s, idx),
            .atomic, .backref => unreachable,
            .group_cap, .group_nc, .group_named, .flag_group => return self.walk(n.a, s, forward),
        }
    }

    /// e{m,n} = e^m · (I ∨ e)^(n−m);  e{m,} = e^m · e*.
    fn quant(self: *Eval, body: u8, q: ast.QuantSpec, s: []const u64, forward: bool) Error![]u64 {
        var cur = try self.alloc();
        @memcpy(cur, s);
        var k: usize = 0;
        while (k < q.min) : (k += 1) {
            const next = try self.walk(body, cur, forward);
            self.release(cur);
            cur = next;
            if (isEmpty(cur)) return cur;
        }
        if (q.max == ast.inf) {
            // Closure over the frontier: only newly reached positions are walked again.
            const frontier = try self.alloc();
            defer self.release(frontier);
            @memcpy(frontier, cur);
            while (!isEmpty(frontier)) {
                const next = try self.walk(body, frontier, forward);
                defer self.release(next);
                for (frontier, next, cur) |*f, x, *c| {
                    f.* = x & ~c.*;
                    c.* |= x;
                }
            }
            return cur;
        }
        k = q.min;
        while (k < q.max) : (k += 1) {
            const next = try self.walk(body, cur, forward);
            defer self.release(next);
            var grew = false;
            for (cur, next) |*c, x| {
                if (x & ~c.* != 0) grew = true;
                c.* |= x;
            }
            if (!grew) break;
        }
        return cur;
    }

    /// Full match: (0, n) is in the relation.
    pub fn fullMatch(self: *Eval) Error!bool {
        const start = try self.alloc();
        defer self.release(start);
        setBit(start, 0);
        const ends = try self.fwd(self.t.root, start);
        defer self.release(ends);
        return getBit(ends, self.w.len);
    }
};

/// Leftmost-longest match of an unanchored search: the smallest start with some match, and
/// its largest end. Outer null: work budget exhausted; inner null: no match.
pub fn leftmostLongest(gpa: Allocator, t: *const ast.Ast, flags: Flags, w: []const u21, min_start: usize) ?(?[2]usize) {
    var ev = Eval.init(gpa, t, flags, w);
    defer ev.deinit();
    const every = ev.all() catch return null;
    defer ev.release(every);
    const starts = ev.bwd(t.root, every) catch return null;
    defer ev.release(starts);
    var s: usize = min_start;
    while (s <= w.len and !Eval.getBit(starts, s)) s += 1;
    if (s > w.len) return @as(?[2]usize, null);
    const one = ev.alloc() catch return null;
    defer ev.release(one);
    Eval.setBit(one, s);
    const ends = ev.fwd(t.root, one) catch return null;
    defer ev.release(ends);
    var e: usize = w.len;
    while (!Eval.getBit(ends, e)) e -= 1;
    return @as(?[2]usize, .{ s, e });
}

/// Full-match reference on a subject of any length (model symbols). Null if the work budget
/// ran out.
pub fn accepts(gpa: Allocator, t: *const ast.Ast, flags: Flags, w: []const u21) ?bool {
    var ev = Eval.init(gpa, t, flags, w);
    defer ev.deinit();
    return ev.fullMatch() catch null;
}

/// Decode UTF-16 to model symbols (code points under u/v, else code units). Caller frees.
pub fn decode(gpa: Allocator, units: []const u16, flags: Flags) ![]u21 {
    const out = try gpa.alloc(u21, units.len);
    const n = alpha.decode(units, flags, out) orelse unreachable;
    if (n == out.len) return out;
    // Surrogate pairs became single code points: return an exactly sized copy so the
    // caller frees what was allocated.
    defer gpa.free(out);
    return gpa.dupe(u21, out[0..n]);
}

/// Full-match reference on a UTF-16 subject. Null if the work budget ran out.
pub fn acceptsUnits(gpa: Allocator, t: *const ast.Ast, flags: Flags, units: []const u16) ?bool {
    const w = decode(gpa, units, flags) catch return null;
    defer gpa.free(w);
    return accepts(gpa, t, flags, w);
}

pub fn appendUtf16(out: *std.ArrayList(u16), gpa: Allocator, w: []const u21) !void {
    for (w) |c| {
        if (c > 0xFFFF) {
            const v = c - 0x10000;
            try out.append(gpa, @intCast(0xD800 + (v >> 10)));
            try out.append(gpa, @intCast(0xDC00 + (v & 0x3FF)));
        } else try out.append(gpa, @intCast(c));
    }
}

/// Backtracking cost guard: can the reference backtracking matcher decide the subject
/// within `factor` steps per symbol (plus a constant)?
pub fn guardOk(t: *const ast.Ast, flags: Flags, w: []const u21, factor: u32) bool {
    var mt: ast.Matcher = .{ .t = t, .flags = flags, .w = w, .budget = @as(usize, factor) * (w.len + 1) + 10_000 };
    return mt.fullMatch() != null;
}

pub const Options = struct {
    /// Target lengths in symbols; each pair picks one (with a little jitter).
    lengths: []const u32,
    /// Guard budget: backtracking steps per symbol (0 disables the guard).
    guard_factor: u32 = 50,
};

pub const Stats = struct {
    no_pump: u64 = 0,
    no_accept: u64 = 0,
    no_reject: u64 = 0,
    guarded: u64 = 0,
    made: u64 = 0,
    /// Time per phase (ns): pumpable segments, long accept, near-miss reject, guard.
    ns: [4]u64 = .{ 0, 0, 0, 0 },
};

fn now() u64 {
    return @import("sys.zig").nowNs();
}

const Seg = struct { i: u8, j: u8 };

/// Generate a long pair for (tree, A, R). Appends UTF-16 to la/lr (cleared first). Returns
/// false when the pattern has nothing to pump or no near-miss reject was found.
pub fn generate(gpa: Allocator, rng: *rngmod.Rng, t: *const ast.Ast, flags: Flags, a16: []const u16, r16: []const u16, opts: Options, la: *std.ArrayList(u16), lr: *std.ArrayList(u16), stats: *Stats) !bool {
    la.clearRetainingCapacity();
    lr.clearRetainingCapacity();
    var abuf: [64]u21 = undefined;
    var rbuf: [64]u21 = undefined;
    const an = alpha.decode(a16, flags, &abuf) orelse return false;
    const rn = alpha.decode(r16, flags, &rbuf) orelse return false;
    const A = abuf[0..an];
    const R = rbuf[0..rn];

    var work: std.ArrayList(u21) = .empty;
    defer work.deinit(gpa);

    var t0 = now();
    // Pumpable segments: A with A[i..j] repeated 2 and 3 times is still accepted.
    var segs: [64]Seg = undefined;
    var ns: usize = 0;
    var i: usize = 0;
    while (i < an) : (i += 1) {
        var j = i + 1;
        while (j <= an and ns < segs.len) : (j += 1) {
            var ok = true;
            for ([_]usize{ 2, 3 }) |k| {
                work.clearRetainingCapacity();
                try pumped(&work, gpa, A, &.{.{ .i = @intCast(i), .j = @intCast(j) }}, &.{k});
                if (accepts(gpa, t, flags, work.items) != true) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                segs[ns] = .{ .i = @intCast(i), .j = @intCast(j) };
                ns += 1;
            }
        }
    }
    if (ns == 0) {
        stats.no_pump += 1;
        return false;
    }

    stats.ns[0] += now() - t0;
    t0 = now();
    const base = opts.lengths[pick(rng, opts.lengths.len)];
    const jitter: i64 = @as(i64, @intCast(pick(rng, 7))) - 3;
    const target: usize = @intCast(@max(@as(i64, @intCast(an)) + 1, @as(i64, base) + jitter));

    // Long accept: pump one segment, or two disjoint ones sharing the extra length.
    var accept: std.ArrayList(u21) = .empty;
    defer accept.deinit(gpa);
    var tries: usize = 0;
    while (tries < 6) : (tries += 1) {
        const s1 = segs[pick(rng, ns)];
        var picked: [2]Seg = .{ s1, s1 };
        var np: usize = 1;
        if (pick(rng, 2) == 0) {
            const s2 = segs[pick(rng, ns)];
            if (s2.j <= s1.i or s2.i >= s1.j) {
                picked = if (s2.i < s1.i) .{ s2, s1 } else .{ s1, s2 };
                np = 2;
            }
        }
        var reps: [2]usize = .{ 1, 1 };
        const extra = target -| an;
        // Round up so the string reaches the target length.
        if (np == 1) {
            reps[0] = 1 + (std.math.divCeil(usize, extra, picked[0].j - picked[0].i) catch unreachable);
        } else {
            const share = pick(rng, extra + 1);
            reps[0] = 1 + (std.math.divCeil(usize, share, picked[0].j - picked[0].i) catch unreachable);
            reps[1] = 1 + (std.math.divCeil(usize, extra - share, picked[1].j - picked[1].i) catch unreachable);
        }
        accept.clearRetainingCapacity();
        try pumped(&accept, gpa, A, picked[0..np], reps[0..np]);
        if (accepts(gpa, t, flags, accept.items) == true) break;
        accept.clearRetainingCapacity();
    }
    if (accept.items.len == 0) {
        stats.no_accept += 1;
        return false;
    }

    stats.ns[1] += now() - t0;
    t0 = now();
    // Near-miss reject: one edit at a chosen position, using symbols from A and R.
    const L = accept.items.len;
    var alphabet: [256]u21 = undefined;
    var nalpha: usize = 0;
    var poolbuf: [alpha.max_symbols * 2]u21 = undefined;
    const pool = alpha.poolSymbols(alpha.active_pool, flags, &poolbuf);
    // Substitutes: symbols that do not occur in A first (A's own symbols are almost always
    // accepted inside the pumped region), then A's.
    for ([_][]const u21{ R, pool, A }) |src| for (src) |c| {
        if (std.mem.indexOfScalar(u21, alphabet[0..nalpha], c) == null and nalpha < alphabet.len) {
            alphabet[nalpha] = c;
            nalpha += 1;
        }
    };
    var fresh: usize = 0; // alphabet[0..fresh]: not in A
    while (fresh < nalpha and std.mem.indexOfScalar(u21, A, alphabet[fresh]) == null) fresh += 1;
    var reject: std.ArrayList(u21) = .empty;
    defer reject.deinit(gpa);
    var rejected = false;
    tries = 0;
    while (tries < 10 and !rejected) : (tries += 1) {
        const pos = editPosition(rng, L);
        const kinds = [_]usize{ 0, 0, 0, 0, 1, 2 }; // 0 substitute, 1 delete, 2 insert
        const kind = kinds[pick(rng, kinds.len)];
        reject.clearRetainingCapacity();
        try reject.appendSlice(gpa, accept.items[0..pos]);
        const c = alphabet[pick(rng, if (fresh > 0 and pick(rng, 4) != 0) fresh else nalpha)];
        switch (kind) {
            0 => {
                if (pos >= L or accept.items[pos] == c) continue;
                try reject.append(gpa, c);
                try reject.appendSlice(gpa, accept.items[pos + 1 ..]);
            },
            1 => {
                if (pos >= L) continue;
                try reject.appendSlice(gpa, accept.items[pos + 1 ..]);
            },
            else => {
                try reject.append(gpa, c);
                try reject.appendSlice(gpa, accept.items[pos..]);
            },
        }
        // Only a candidate the reference rejects is used (never a half-built one).
        rejected = accepts(gpa, t, flags, reject.items) == false;
    }
    stats.ns[2] += now() - t0;
    t0 = now();
    if (!rejected) {
        stats.no_reject += 1;
        return false;
    }
    defer stats.ns[3] += now() - t0;

    if (opts.guard_factor > 0 and !(guardOk(t, flags, accept.items, opts.guard_factor) and guardOk(t, flags, reject.items, opts.guard_factor))) {
        stats.guarded += 1;
        return false;
    }
    try appendUtf16(la, gpa, accept.items);
    try appendUtf16(lr, gpa, reject.items);
    stats.made += 1;
    return true;
}

fn pick(rng: *rngmod.Rng, n: usize) usize {
    return @intCast(rng.below(n));
}

/// A with each segment segs[k] repeated reps[k] times (segments ascending, disjoint).
fn pumped(out: *std.ArrayList(u21), gpa: Allocator, A: []const u21, segs: []const Seg, reps: []const usize) !void {
    var at: usize = 0;
    for (segs, reps) |s, r| {
        try out.appendSlice(gpa, A[at..s.i]);
        for (0..r) |_| try out.appendSlice(gpa, A[s.i..s.j]);
        at = s.j;
    }
    try out.appendSlice(gpa, A[at..]);
}

/// Where the reject's edit goes: near the start, the middle, the end, or a power-of-two
/// boundary (where engines switch chunk sizes, string representations or stack segments).
fn editPosition(rng: *rngmod.Rng, L: usize) usize {
    return switch (pick(rng, 4)) {
        0 => @min(L - 1, pick(rng, 8)),
        1 => L / 2 + pick(rng, @max(1, L / 8)),
        2 => L - 1 - @min(L - 1, pick(rng, 8)),
        else => blk: {
            var b: usize = 16;
            var cands: [16]usize = undefined;
            var nc: usize = 0;
            while (b < L and nc < cands.len) : (b *= 2) {
                cands[nc] = b;
                nc += 1;
            }
            if (nc == 0) break :blk L / 2;
            const c = cands[pick(rng, nc)];
            // b-1, b or b+1
            break :blk @min(L - 1, c - 1 + pick(rng, 3));
        },
    };
}

// ---------------------------------------------------------------------------

const testing = std.testing;

fn parseTree(s: []const u8) !ast.Ast {
    return ast.parse(s);
}

test "vector reference agrees with the relation model on short strings" {
    const gpa = testing.allocator;
    var prng = std.Random.DefaultPrng.init(7);
    const rnd = prng.random();
    // (?:ab|a)*b  and  (?=a)(?:a|b)+$  and  \b(?:a*)*
    const trees = [_][]const u8{
        "(concat (quant star 0 255 0 (alt (concat (atom lit 0 0 0 61 0 0 0) (atom lit 0 0 0 62 0 0 0)) (atom lit 0 0 0 61 0 0 0))) (atom lit 0 0 0 62 0 0 0))",
        "(concat (look_ahead (atom lit 0 0 0 61 0 0 0)) (concat (quant plus 1 255 0 (alt (atom lit 0 0 0 61 0 0 0) (atom lit 0 0 0 62 0 0 0))) (atom dollar 0 0 0 0 0 0 0)))",
        "(concat (atom wordb 0 0 0 0 0 0 0) (quant star 0 255 0 (quant star 0 255 0 (atom lit 0 0 0 61 0 0 0))))",
        "(concat (quant range 1 3 0 (alt (atom lit 0 0 0 61 0 0 0) (atom empty 0 0 0 0 0 0 0))) (look_behind (atom lit 0 0 0 62 0 0 0)))",
    };
    for (trees) |src| {
        const t = try parseTree(src);
        for (0..300) |_| {
            var w: [12]u21 = undefined;
            const n = rnd.uintAtMost(usize, 12);
            for (w[0..n]) |*c| c.* = if (rnd.boolean()) 'a' else 'b';
            const want = ast.fullMatch(&t, .{}, w[0..n]);
            try testing.expectEqual(@as(?bool, want), accepts(gpa, &t, .{}, w[0..n]));
        }
    }
}

test "vector reference agrees with the relation model on random trees, forward and backward" {
    const ucd = @import("ucd.zig");
    ucd.init();
    const gpa = testing.allocator;
    var prng = std.Random.DefaultPrng.init(0x10C6);
    const rnd = prng.random();
    const flag_list = [_][]const u8{ "", "i", "m", "s", "u", "iu", "v", "iv", "ims", "imsv", "msu" };
    var compared: usize = 0;
    for (flag_list) |fs| {
        const flags = try Flags.parse(fs);
        const inv = try atoms.buildInventory(gpa, .{}, flags);
        defer gpa.free(inv);
        var symbuf: [alpha.max_symbols * 2]u21 = undefined;
        const pool = alpha.poolSymbols(alpha.active_pool, flags, &symbuf);
        for (0..600) |_| {
            var t: ast.Ast = .{};
            t.root = try ast.randomTree(&t, rnd, inv, rnd.intRangeAtMost(usize, 1, 14));
            var w: [15]u21 = undefined;
            const n = rnd.uintAtMost(usize, 15);
            for (0..n) |i| w[i] = pool[rnd.uintLessThan(usize, pool.len)];
            const want = ast.fullMatch(&t, flags, w[0..n]);
            try testing.expectEqual(@as(?bool, want), accepts(gpa, &t, flags, w[0..n]));
            // Backward walk from {n} reaches 0 exactly when the forward walk from {0} reaches n.
            var ev = Eval.init(gpa, &t, flags, w[0..n]);
            defer ev.deinit();
            const end = try ev.alloc();
            defer gpa.free(end);
            Eval.setBit(end, n);
            const starts = try ev.bwd(t.root, end);
            defer gpa.free(starts);
            try testing.expectEqual(want, Eval.getBit(starts, 0));
            compared += 1;
        }
    }
    try testing.expect(compared > 6000);
}

test "generated pairs are accept/reject under the reference" {
    const ucd = @import("ucd.zig");
    ucd.init();
    const gpa = testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xA11);
    const rnd = prng.random();
    var made: usize = 0;
    var la: std.ArrayList(u16) = .empty;
    defer la.deinit(gpa);
    var lr: std.ArrayList(u16) = .empty;
    defer lr.deinit(gpa);
    var stats: Stats = .{};
    for ([_][]const u8{ "", "i", "u", "imsu", "v" }) |fs| {
        const flags = try Flags.parse(fs);
        const inv = try atoms.buildInventory(gpa, .{}, flags);
        defer gpa.free(inv);
        var symbuf: [alpha.max_symbols * 2]u21 = undefined;
        const pool = alpha.poolSymbols(alpha.active_pool, flags, &symbuf);
        var rng = rngmod.Rng.fromParts(9, &.{flags.bits()});
        for (0..4000) |_| {
            var t: ast.Ast = .{};
            t.root = try ast.randomTree(&t, rnd, inv, rnd.intRangeAtMost(usize, 1, 10));
            // A: a short accepted string; R: a short rejected one.
            var a: [8]u21 = undefined;
            var r: [8]u21 = undefined;
            const an = rnd.uintAtMost(usize, 6);
            for (0..an) |i| a[i] = pool[rnd.uintLessThan(usize, pool.len)];
            const rn = rnd.uintAtMost(usize, 6);
            for (0..rn) |i| r[i] = pool[rnd.uintLessThan(usize, pool.len)];
            if (!ast.fullMatch(&t, flags, a[0..an]) or ast.fullMatch(&t, flags, r[0..rn])) continue;
            var a16: [16]u16 = undefined;
            var r16: [16]u16 = undefined;
            const a16n = alpha.toUtf16(a[0..an], &a16);
            const r16n = alpha.toUtf16(r[0..rn], &r16);
            if (!try generate(gpa, &rng, &t, flags, a16[0..a16n], r16[0..r16n], .{ .lengths = &.{ 64, 300 }, .guard_factor = 0 }, &la, &lr, &stats)) continue;
            try testing.expectEqual(@as(?bool, true), acceptsUnits(gpa, &t, flags, la.items));
            try testing.expectEqual(@as(?bool, false), acceptsUnits(gpa, &t, flags, lr.items));
            try testing.expect(la.items.len >= 60);
            made += 1;
        }
    }
    try testing.expect(made > 60);
}

test "vector reference handles long strings" {
    const gpa = testing.allocator;
    // (?:ab)*c
    const t = try parseTree("(concat (quant star 0 255 0 (concat (atom lit 0 0 0 61 0 0 0) (atom lit 0 0 0 62 0 0 0))) (atom lit 0 0 0 63 0 0 0))");
    var w: std.ArrayList(u21) = .empty;
    defer w.deinit(gpa);
    for (0..3000) |_| try w.appendSlice(gpa, &.{ 'a', 'b' });
    try w.append(gpa, 'c');
    try testing.expectEqual(@as(?bool, true), accepts(gpa, &t, .{}, w.items));
    w.items[3000] = 'b';
    try testing.expectEqual(@as(?bool, false), accepts(gpa, &t, .{}, w.items));
}
