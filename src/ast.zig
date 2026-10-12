//! Owned regex syntax trees, direct relation evaluation, a naive JS-style
//! backtracking matcher used to cross-check the relation model, and a
//! stable s-expression serialization used by persisted findings.
const std = @import("std");
const dialect = @import("dialect.zig");
const alpha = @import("alphabet.zig");
const grapheme = @import("grapheme.zig");
const atoms = @import("atoms.zig");
const relmod = @import("rel.zig");
const Flags = alpha.Flags;
const AtomSpec = atoms.AtomSpec;

/// Production/AST operator codes. Values are part of the grammar digest.
pub const Op = enum(u8) {
    atom = 0,
    concat = 1,
    alt = 2,
    quant = 3,
    look_ahead = 4,
    neg_look_ahead = 5,
    look_behind = 6,
    neg_look_behind = 7,
    group_cap = 8,
    group_nc = 9,
    group_named = 10,
    /// Inline flag group (?i:…) / (?-i:…): the child sees the flags toggled by Node.fmod.
    flag_group = 11,
    /// Atomic group (?>…): commits to the child's first match (possessive quantifiers are atomic
    /// groups around a greedy loop). Mutation mode only; the relation model cannot express it.
    atomic = 12,
    /// Backreference to capture group Node.fmod (ordinal, opening order). Mutation mode only.
    backref = 13,

    /// No children: atoms and backreferences.
    pub fn isLeaf(op: Op) bool {
        return op == .atom or op == .backref;
    }

    pub fn isBinary(op: Op) bool {
        return op == .concat or op == .alt;
    }
    pub fn isLook(op: Op) bool {
        return @intFromEnum(op) >= 4 and @intFromEnum(op) <= 7;
    }
    pub fn isGroup(op: Op) bool {
        return @intFromEnum(op) >= 8;
    }
};

pub const QForm = enum(u8) { star, plus, opt, range, open, exact };
pub const inf: u8 = 255;

pub const QuantSpec = struct {
    form: QForm,
    min: u8,
    max: u8, // inf = unbounded
    lazy: bool = false,

    pub fn eql(a: QuantSpec, b: QuantSpec) bool {
        return a.form == b.form and a.min == b.min and a.max == b.max and a.lazy == b.lazy;
    }
};

pub const Node = struct {
    op: Op,
    atom: AtomSpec = .{ .kind = .empty },
    quant: QuantSpec = .{ .form = .star, .min = 0, .max = inf },
    a: u8 = 0,
    b: u8 = 0,
    /// flag_group: flags toggled for the subtree (fmod_i); backref: the target capture ordinal.
    fmod: u8 = 0,
};

pub const max_nodes = 255;

/// Node.fmod bits: the flag a flag group toggles.
pub const fmod_i: u8 = 1;
pub const fmod_s: u8 = 2;
pub const fmod_m: u8 = 4;

/// Flags inside a flag group with modifier `mod`.
pub fn applyMod(f: Flags, mod: u8) Flags {
    var g = f;
    if (mod & fmod_i != 0) g.i = !g.i;
    if (mod & fmod_s != 0) g.s = !g.s;
    if (mod & fmod_m != 0) g.m = !g.m;
    return g;
}

/// Effective flags of every node under `base` (flag groups change them for their subtree).
pub fn nodeFlags(t: *const Ast, base: Flags, out: *[max_nodes]Flags) void {
    nodeFlagsRec(t, t.root, base, out);
}

fn nodeFlagsRec(t: *const Ast, idx: u8, f: Flags, out: *[max_nodes]Flags) void {
    out[idx] = f;
    const n = t.nodes[idx];
    if (n.op.isLeaf()) return;
    const g = if (n.op == .flag_group) applyMod(f, n.fmod) else f;
    nodeFlagsRec(t, n.a, g, out);
    if (Op.isBinary(n.op)) nodeFlagsRec(t, n.b, g, out);
}

/// A tree in a fixed-capacity node buffer; nodes[root] is the root.
pub const Ast = struct {
    nodes: [max_nodes]Node = undefined,
    len: u8 = 0,
    root: u8 = 0,

    pub fn add(self: *Ast, n: Node) !u8 {
        if (self.len == max_nodes) return error.TooManyNodes;
        self.nodes[self.len] = n;
        self.len += 1;
        return self.len - 1;
    }

    pub fn size(self: *const Ast, idx: u8) usize {
        const n = self.nodes[idx];
        return switch (n.op) {
            .atom, .backref => 1,
            .concat, .alt => 1 + self.size(n.a) + self.size(n.b),
            else => 1 + self.size(n.a),
        };
    }

    /// Copy the subtree at `idx` into a fresh compacted tree.
    pub fn extract(self: *const Ast, idx: u8) Ast {
        var out: Ast = .{};
        out.root = copyInto(self, idx, &out) catch unreachable;
        return out;
    }

    fn copyInto(src: *const Ast, idx: u8, dst: *Ast) !u8 {
        var n = src.nodes[idx];
        switch (n.op) {
            .atom, .backref => {},
            .concat, .alt => {
                n.a = try copyInto(src, n.a, dst);
                n.b = try copyInto(src, n.b, dst);
            },
            else => n.a = try copyInto(src, n.a, dst),
        }
        return dst.add(n);
    }

    pub fn compact(self: *const Ast) Ast {
        return self.extract(self.root);
    }
};

// ---------------------------------------------------------------------------
// Relation semantics

pub fn evalRel(comptime R: type, t: *const Ast, idx: u8, flags: Flags, w: []const u21) R {
    const n = t.nodes[idx];
    const dim = w.len + 1;
    return switch (n.op) {
        .atom => atoms.relation(R, &n.atom, flags, w),
        .concat => evalRel(R, t, n.a, flags, w).mul(evalRel(R, t, n.b, flags, w)),
        .alt => evalRel(R, t, n.a, flags, w).orr(evalRel(R, t, n.b, flags, w)),
        .quant => quantRel(R, evalRel(R, t, n.a, flags, w), n.quant, dim),
        .look_ahead => evalRel(R, t, n.a, flags, w).lookahead(dim, false),
        .neg_look_ahead => evalRel(R, t, n.a, flags, w).lookahead(dim, true),
        .look_behind => evalRel(R, t, n.a, flags, w).lookbehind(dim, false),
        .neg_look_behind => evalRel(R, t, n.a, flags, w).lookbehind(dim, true),
        .group_cap, .group_nc, .group_named => evalRel(R, t, n.a, flags, w),
        .flag_group => evalRel(R, t, n.a, applyMod(flags, n.fmod), w),
        // Mutation-mode constructs: the oracle uses the backtracking matcher for these trees.
        .atomic, .backref => @panic("relation model cannot evaluate atomic groups or backreferences"),
    };
}

/// The tree holds constructs only the backtracking matcher evaluates (atomic groups,
/// backreferences): oracles and long mode take the matcher path or skip.
/// Every backreference refers to a capture group that closes before it in pattern order (so
/// the printed \N names a group the engine has seen); false otherwise.
pub fn backrefsValid(t: *const Ast) bool {
    const caps = Caps.init(t) orelse return false;
    var closed: [max_caps]bool = [_]bool{false} ** max_caps;
    return backrefWalk(t, t.root, &caps, &closed);
}

fn backrefWalk(t: *const Ast, idx: u8, caps: *const Caps, closed: *[max_caps]bool) bool {
    const n = t.nodes[idx];
    switch (n.op) {
        .atom => return true,
        .backref => return n.fmod < caps.count and closed[n.fmod],
        .concat, .alt => return backrefWalk(t, n.a, caps, closed) and backrefWalk(t, n.b, caps, closed),
        else => {
            if (!backrefWalk(t, n.a, caps, closed)) return false;
            if (n.op == .group_cap or n.op == .group_named) closed[caps.ordinal[idx]] = true;
            return true;
        },
    }
}

pub fn needsMatcher(t: *const Ast) bool {
    for (t.nodes[0..t.len]) |n| if (n.op == .atomic or n.op == .backref) return true;
    return false;
}

pub fn quantRel(comptime R: type, r: R, q: QuantSpec, dim: usize) R {
    if (q.max == inf) return r.repOpen(q.min, dim);
    return r.rep(q.min, q.max, dim);
}

/// Full-match oracle for one subject: (0, n) ∈ rel.
pub fn fullMatch(t: *const Ast, flags: Flags, w: []const u21) bool {
    if (needsMatcher(t)) {
        var caps = Caps.init(t) orelse return false;
        var mt: Matcher = .{ .t = t, .flags = flags, .w = w, .caps = &caps, .reset_loop_captures = dialect.active.reset_loop_captures_hint };
        return mt.fullMatch() orelse false;
    }
    if (w.len <= relmod.Rel16.max_len) return evalRel(relmod.Rel16, t, t.root, flags, w).get(0, w.len);
    return evalRel(relmod.Rel32, t, t.root, flags, w).get(0, w.len);
}

/// Decode a UTF-16 subject for `flags` and evaluate the oracle. Null if too long.
pub fn oracle(t: *const Ast, flags: Flags, subject: []const u16) ?bool {
    var syms: [31]u21 = undefined;
    const n = alpha.decode(subject, flags, &syms) orelse return null;
    return fullMatch(t, flags, syms[0..n]);
}

// ---------------------------------------------------------------------------
// Naive backtracking matcher (ES RegExp semantics, captures ignored)

pub const Matcher = struct {
    t: *const Ast,
    flags: Flags,
    w: []const u21,
    steps: usize = 0,
    budget: usize = 2_000_000,
    exhausted: bool = false,

    /// End position recorded by a `record` continuation (search).
    end: usize = 0,
    /// Capture tracking (optional): slot per capture group in opening-parenthesis order.
    caps: ?*Caps = null,
    /// Clear a loop body's captures at the start of each iteration (ES, Perl >= 5.38).
    reset_loop_captures: bool = false,
    /// Effective flags per node (flag groups), computed on first use.
    nflags: [max_nodes]Flags = undefined,
    nflags_ready: bool = false,

    fn flagsAt(self: *Matcher, idx: u8) Flags {
        if (!self.nflags_ready) {
            nodeFlags(self.t, self.flags, &self.nflags);
            self.nflags_ready = true;
        }
        return self.nflags[idx];
    }

    const Dir = enum { fwd, back };
    const ContKind = enum { done, accept, record, seq, rep, close, commit };
    const Cont = struct {
        kind: ContKind,
        node: u8 = 0,
        dir: Dir = .fwd,
        min: u8 = 0,
        max: u8 = 0,
        greedy: bool = true,
        start: usize = 0,
        next: ?*const Cont = null,
        /// commit: where the atomic child's first match ended.
        out: ?*usize = null,
    };

    pub fn fullMatch(self: *Matcher) ?bool {
        const done: Cont = .{ .kind = .done };
        const r = self.m(self.t.root, 0, .fwd, &done);
        if (self.exhausted) return null;
        return r;
    }

    /// First match in backtracking priority order starting exactly at `start`; its end
    /// position is left in `self.end`. Null when the step budget runs out.
    pub fn matchAt(self: *Matcher, start: usize) ?bool {
        const rec: Cont = .{ .kind = .record };
        const r = self.m(self.t.root, start, .fwd, &rec);
        if (self.exhausted) return null;
        return r;
    }

    fn run(self: *Matcher, c: *const Cont, pos: usize) bool {
        switch (c.kind) {
            .done => return pos == self.w.len,
            .accept => return true,
            .commit => {
                c.out.?.* = pos;
                return true;
            },
            .record => {
                self.end = pos;
                return true;
            },
            .seq => return self.m(c.node, pos, c.dir, c.next.?),
            .close => {
                const caps = self.caps.?;
                const old = caps.slot[c.node];
                caps.slot[c.node] = if (c.dir == .fwd) .{ .s = @intCast(c.start), .e = @intCast(pos) } else .{ .s = @intCast(pos), .e = @intCast(c.start) };
                if (self.run(c.next.?, pos)) return true;
                caps.slot[c.node] = old;
                return false;
            },
            .rep => {
                // RepeatMatcher continuation d: an empty iteration once min is met is rejected
                // (ES) or ends the loop (Perl/PCRE).
                if (c.min == 0 and pos == c.start) {
                    if (dialect.active.empty_iteration == .stop) return self.run(c.next.?, pos);
                    return false;
                }
                const nmin: u8 = if (c.min == 0) 0 else c.min - 1;
                const nmax: u8 = if (c.max == inf) inf else c.max - 1;
                return self.repeat(c.node, nmin, nmax, c.greedy, pos, c.dir, c.next.?);
            },
        }
    }

    fn repeat(self: *Matcher, node: u8, min: u8, max: u8, greedy: bool, pos: usize, dir: Dir, c: *const Cont) bool {
        if (max == 0) return self.run(c, pos);
        const d: Cont = .{ .kind = .rep, .node = node, .dir = dir, .min = min, .max = max, .greedy = greedy, .start = pos, .next = c };
        if (min != 0) return self.iteration(node, pos, dir, &d);
        if (!greedy) {
            if (self.run(c, pos)) return true;
            return self.iteration(node, pos, dir, &d);
        }
        if (self.iteration(node, pos, dir, &d)) return true;
        return self.run(c, pos);
    }

    /// One loop iteration, clearing the body's captures first when the dialect resets them.
    fn iteration(self: *Matcher, node: u8, pos: usize, dir: Dir, d: *const Cont) bool {
        const caps = self.caps orelse return self.m(node, pos, dir, d);
        if (!self.reset_loop_captures) return self.m(node, pos, dir, d);
        const lo = caps.first[node];
        const hi = caps.end[node];
        if (lo >= hi) return self.m(node, pos, dir, d);
        var saved: [max_caps]Caps.Span = undefined;
        @memcpy(saved[lo..hi], caps.slot[lo..hi]);
        @memset(caps.slot[lo..hi], Caps.Span.unset);
        if (self.m(node, pos, dir, d)) return true;
        @memcpy(caps.slot[lo..hi], saved[lo..hi]);
        return false;
    }

    fn m(self: *Matcher, idx: u8, pos: usize, dir: Dir, c: *const Cont) bool {
        self.steps += 1;
        if (self.steps > self.budget) {
            self.exhausted = true;
            return false;
        }
        if (self.exhausted) return false;
        const n = self.t.nodes[idx];
        switch (n.op) {
            .atom => {
                const a = &n.atom;
                if (a.kind == .empty) return self.run(c, pos);
                const fl = self.flagsAt(idx);
                if (a.isAssertion()) {
                    // At this position only: a whole-string mask is O(n) per step and only 32 bits.
                    if (!atoms.assertionAt(a, fl, self.w, pos)) return false;
                    return self.run(c, pos);
                }
                if (a.kind == .grapheme) {
                    // \X: the one cluster from here, atomically.
                    if (dir == .fwd) {
                        if (pos >= self.w.len) return false;
                        return self.run(c, grapheme.clusterEndActive(self.w, pos));
                    }
                    var k = pos;
                    while (k > 0) {
                        k -= 1;
                        if (grapheme.clusterEndActive(self.w, k) == pos and self.run(c, k)) return true;
                    }
                    return false;
                }
                if (a.kind == .strs) {
                    // Class strings: alternatives longest first, with backtracking.
                    var ss: [2][]const u21 = undefined;
                    for (ss[0..a.strings(&ss)]) |s| {
                        if (dir == .fwd) {
                            if (atoms.stringAt(s, self.w, pos, fl) and self.run(c, pos + s.len)) return true;
                        } else {
                            if (pos >= s.len and atoms.stringAt(s, self.w, pos - s.len, fl) and self.run(c, pos - s.len)) return true;
                        }
                    }
                    return false;
                }
                if (atoms.foldsMulti(a, fl)) {
                    // Full case folding: one character, or a subject string spelling the fold.
                    if (dir != .fwd) {
                        if (pos > 0 and atoms.matches(a, fl, self.w[pos - 1]) and self.run(c, pos - 1)) return true;
                        var k = pos;
                        while (k > 0) {
                            k -= 1;
                            const Hit = struct {
                                pos: usize,
                                fn f(x: @This(), e: usize) bool {
                                    return e == x.pos;
                                }
                            };
                            if (atoms.forEachFoldMatch(a, fl, self.w, k, Hit{ .pos = pos }, Hit.f) and self.run(c, k)) return true;
                        }
                        return false;
                    }
                    if (pos < self.w.len and atoms.matches(a, fl, self.w[pos]) and self.run(c, pos + 1)) return true;
                    const Go = struct {
                        m: *Matcher,
                        c: *const Cont,
                        fn f(x: @This(), e: usize) bool {
                            return x.m.run(x.c, e);
                        }
                    };
                    return atoms.forEachFoldMatch(a, fl, self.w, pos, Go{ .m = self, .c = c }, Go.f);
                }
                if (dir == .fwd) {
                    if (pos >= self.w.len or !atoms.matches(a, fl, self.w[pos])) return false;
                    return self.run(c, pos + 1);
                } else {
                    if (pos == 0 or !atoms.matches(a, fl, self.w[pos - 1])) return false;
                    return self.run(c, pos - 1);
                }
            },
            .concat => {
                if (dir == .fwd) {
                    const k: Cont = .{ .kind = .seq, .node = n.b, .dir = dir, .next = c };
                    return self.m(n.a, pos, dir, &k);
                } else {
                    const k: Cont = .{ .kind = .seq, .node = n.a, .dir = dir, .next = c };
                    return self.m(n.b, pos, dir, &k);
                }
            },
            .alt => return self.m(n.a, pos, dir, c) or self.m(n.b, pos, dir, c),
            .quant => {
                const counted = n.quant.form == .range or n.quant.form == .open or n.quant.form == .exact;
                const lazy = n.quant.lazy and !(counted and dialect.active.lazy_counted_is_greedy);
                return self.repeat(n.a, n.quant.min, n.quant.max, !lazy, pos, dir, c);
            },
            .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind => {
                const acc: Cont = .{ .kind = .accept };
                const ldir: Dir = if (n.op == .look_ahead or n.op == .neg_look_ahead) .fwd else .back;
                const neg = n.op == .neg_look_ahead or n.op == .neg_look_behind;
                if (self.caps) |caps| {
                    // Captures made inside a positive lookaround stay set; a negative one leaves none.
                    const saved = caps.slot;
                    const r = self.m(n.a, pos, ldir, &acc);
                    if (neg) caps.slot = saved;
                    if (r == neg) return false;
                    if (self.run(c, pos)) return true;
                    caps.slot = saved;
                    return false;
                }
                const r = self.m(n.a, pos, ldir, &acc);
                if (r == neg) return false;
                return self.run(c, pos);
            },
            .group_cap, .group_named => {
                const caps = self.caps orelse return self.m(n.a, pos, dir, c);
                const k: Cont = .{ .kind = .close, .node = caps.ordinal[idx], .dir = dir, .start = pos, .next = c };
                return self.m(n.a, pos, dir, &k);
            },
            .group_nc, .flag_group => return self.m(n.a, pos, dir, c),
            .atomic => {
                // The child's first match only: no backtracking into it once it has matched.
                var endpos: usize = pos;
                const k: Cont = .{ .kind = .commit, .out = &endpos };
                if (self.caps) |caps| {
                    const saved = caps.slot;
                    if (!self.m(n.a, pos, dir, &k)) return false;
                    if (self.run(c, endpos)) return true;
                    caps.slot = saved;
                    return false;
                }
                if (!self.m(n.a, pos, dir, &k)) return false;
                return self.run(c, endpos);
            },
            .backref => {
                const caps = self.caps orelse return false;
                const sp = caps.slot[n.fmod];
                if (sp.s < 0) {
                    // Unset group: matches empty in ECMAScript, fails in Perl/PCRE and most others.
                    return if (dialect.active.backref_unset_matches_empty) self.run(c, pos) else false;
                }
                const s: usize = @intCast(sp.s);
                const len: usize = @intCast(sp.e - sp.s);
                const fl = self.flagsAt(idx);
                if (dir == .fwd) {
                    if (pos + len > self.w.len) return false;
                    for (0..len) |j| if (!sameChar(self.w[s + j], self.w[pos + j], fl)) return false;
                    return self.run(c, pos + len);
                } else {
                    if (pos < len) return false;
                    for (0..len) |j| if (!sameChar(self.w[s + j], self.w[pos - len + j], fl)) return false;
                    return self.run(c, pos - len);
                }
            },
        }
    }

    /// Backreference comparison: equal, or case-equivalent under i.
    fn sameChar(a: u21, b: u21, fl: Flags) bool {
        return a == b or (fl.i and alpha.canonicalize(a, fl) == alpha.canonicalize(b, fl));
    }
};

pub const max_caps = 32;

/// Capture state for Matcher: slots in opening-parenthesis order, plus per-node indexes
/// (ordinal of a capture node; range of capture ordinals inside each subtree).
pub const Caps = struct {
    pub const Span = struct {
        s: i16,
        e: i16,
        pub const unset: Span = .{ .s = -1, .e = -1 };
    };
    slot: [max_caps]Span = [_]Span{Span.unset} ** max_caps,
    ordinal: [256]u8 = [_]u8{0} ** 256,
    first: [256]u8 = [_]u8{0} ** 256,
    end: [256]u8 = [_]u8{0} ** 256,
    count: u8 = 0,

    /// Number the capture groups of `t` in opening-parenthesis (pre-)order. Null if there
    /// are more than max_caps.
    pub fn init(t: *const Ast) ?Caps {
        var c: Caps = .{};
        if (!c.walk(t, t.root)) return null;
        return c;
    }

    fn walk(self: *Caps, t: *const Ast, idx: u8) bool {
        const n = t.nodes[idx];
        self.first[idx] = self.count;
        if (n.op == .group_cap or n.op == .group_named) {
            if (self.count >= max_caps) return false;
            self.ordinal[idx] = self.count;
            self.count += 1;
        }
        if (n.op != .atom and n.op != .backref) {
            if (!self.walk(t, n.a)) return false;
            if (Op.isBinary(n.op) and !self.walk(t, n.b)) return false;
        }
        self.end[idx] = self.count;
        return true;
    }

    pub fn clear(self: *Caps) void {
        @memset(&self.slot, Span.unset);
    }
};

// ---------------------------------------------------------------------------
// Serialization: (op ...) s-expressions with hex code points.

pub fn serialize(t: *const Ast, out: *std.ArrayList(u8), gpa: std.mem.Allocator) !void {
    try serNode(t, t.root, out, gpa);
}

fn serNode(t: *const Ast, idx: u8, out: *std.ArrayList(u8), gpa: std.mem.Allocator) !void {
    const n = t.nodes[idx];
    switch (n.op) {
        .atom => {
            const a = n.atom;
            try out.print(gpa, "(atom {s} {d} {d} {d}", .{ @tagName(a.kind), a.sub, @intFromBool(a.neg), a.n });
            for (a.syms) |s| try out.print(gpa, " {x}", .{s});
            try out.append(gpa, ')');
        },
        .quant => {
            const q = n.quant;
            try out.print(gpa, "(quant {s} {d} {d} {d} ", .{ @tagName(q.form), q.min, q.max, @intFromBool(q.lazy) });
            try serNode(t, n.a, out, gpa);
            try out.append(gpa, ')');
        },
        .flag_group => {
            try out.print(gpa, "(flag_group {d} ", .{n.fmod});
            try serNode(t, n.a, out, gpa);
            try out.append(gpa, ')');
        },
        .backref => try out.print(gpa, "(backref {d})", .{n.fmod}),
        .concat, .alt => {
            try out.print(gpa, "({s} ", .{@tagName(n.op)});
            try serNode(t, n.a, out, gpa);
            try out.append(gpa, ' ');
            try serNode(t, n.b, out, gpa);
            try out.append(gpa, ')');
        },
        else => {
            try out.print(gpa, "({s} ", .{@tagName(n.op)});
            try serNode(t, n.a, out, gpa);
            try out.append(gpa, ')');
        },
    }
}

pub fn parse(text: []const u8) !Ast {
    var t: Ast = .{};
    var p: Parser = .{ .s = text };
    t.root = try p.node(&t);
    return t;
}

const Parser = struct {
    s: []const u8,
    i: usize = 0,

    fn ws(p: *Parser) void {
        while (p.i < p.s.len and (p.s[p.i] == ' ' or p.s[p.i] == '\n')) p.i += 1;
    }
    fn expect(p: *Parser, c: u8) !void {
        p.ws();
        if (p.i >= p.s.len or p.s[p.i] != c) return error.BadAst;
        p.i += 1;
    }
    fn word(p: *Parser) ![]const u8 {
        p.ws();
        const st = p.i;
        while (p.i < p.s.len and p.s[p.i] != ' ' and p.s[p.i] != ')' and p.s[p.i] != '(') p.i += 1;
        if (st == p.i) return error.BadAst;
        return p.s[st..p.i];
    }
    fn int(p: *Parser, comptime T: type, base: u8) !T {
        return std.fmt.parseInt(T, try p.word(), base);
    }
    fn node(p: *Parser, t: *Ast) !u8 {
        try p.expect('(');
        const opname = try p.word();
        const op = std.meta.stringToEnum(Op, opname) orelse return error.BadAst;
        var n: Node = .{ .op = op };
        switch (op) {
            .atom => {
                const kind = std.meta.stringToEnum(atoms.Kind, try p.word()) orelse return error.BadAst;
                n.atom = .{ .kind = kind, .sub = try p.int(u8, 10), .neg = (try p.int(u8, 10)) != 0, .n = try p.int(u8, 10) };
                for (&n.atom.syms) |*s| s.* = try p.int(u21, 16);
            },
            .quant => {
                const form = std.meta.stringToEnum(QForm, try p.word()) orelse return error.BadAst;
                n.quant = .{ .form = form, .min = try p.int(u8, 10), .max = try p.int(u8, 10), .lazy = (try p.int(u8, 10)) != 0 };
                n.a = try p.node(t);
            },
            .concat, .alt => {
                n.a = try p.node(t);
                n.b = try p.node(t);
            },
            .flag_group => {
                n.fmod = try p.int(u8, 10);
                n.a = try p.node(t);
            },
            .backref => n.fmod = try p.int(u8, 10),
            else => n.a = try p.node(t),
        }
        try p.expect(')');
        return t.add(n);
    }
};

// ---------------------------------------------------------------------------
// Construct multiset (for grouping/adaptive weights)

pub const Construct = enum(u8) { literal, dot, class, range, escape, vset, caret, dollar, backslash_b, backslash_B, empty, property, concat, alt, star, plus, opt, rep, rep_open, rep_exact, lazy, lookahead, neg_lookahead, lookbehind, neg_lookbehind, group, nc_group, named_group, flag_group };
pub const n_constructs = @typeInfo(Construct).@"enum".fields.len;

pub fn constructCounts(t: *const Ast, out: *[n_constructs]u16) void {
    @memset(out, 0);
    countRec(t, t.root, out);
}

fn countRec(t: *const Ast, idx: u8, out: *[n_constructs]u16) void {
    const n = t.nodes[idx];
    const c: Construct = switch (n.op) {
        .atom => @enumFromInt(@intFromEnum(atoms.category(n.atom))),
        .concat => .concat,
        .alt => .alt,
        .quant => switch (n.quant.form) {
            .star => .star,
            .plus => .plus,
            .opt => .opt,
            .range => .rep,
            .open => .rep_open,
            .exact => .rep_exact,
        },
        .look_ahead => .lookahead,
        .neg_look_ahead => .neg_lookahead,
        .look_behind => .lookbehind,
        .neg_look_behind => .neg_lookbehind,
        .group_cap => .group,
        .group_nc => .nc_group,
        .group_named => .named_group,
        .flag_group => .flag_group,
        .atomic => .nc_group,
        .backref => .group,
    };
    out[@intFromEnum(c)] +|= 1;
    if (n.op == .quant and n.quant.lazy) out[@intFromEnum(Construct.lazy)] +|= 1;
    switch (n.op) {
        .atom, .backref => {},
        .concat, .alt => {
            countRec(t, n.a, out);
            countRec(t, n.b, out);
        },
        else => countRec(t, n.a, out),
    }
}

// ---------------------------------------------------------------------------
// Tests: relation model vs. naive backtracking matcher.

const testing = std.testing;
const ucd = @import("ucd.zig");

pub fn randomTree(t: *Ast, rnd: std.Random, inv: []const AtomSpec, budget: usize) !u8 {
    if (budget <= 1) return t.add(.{ .op = .atom, .atom = inv[rnd.uintLessThan(usize, inv.len)] });
    const choice = rnd.uintLessThan(u8, 10);
    switch (choice) {
        0, 1 => {
            if (budget < 3) return t.add(.{ .op = .group_nc, .a = try randomTree(t, rnd, inv, 1) });
            const l = rnd.intRangeAtMost(usize, 1, budget - 2);
            const a = try randomTree(t, rnd, inv, l);
            const b = try randomTree(t, rnd, inv, budget - 1 - l);
            return t.add(.{ .op = if (choice == 0) .concat else .alt, .a = a, .b = b });
        },
        2, 3 => {
            const a = try randomTree(t, rnd, inv, budget - 1);
            const forms = [_]QuantSpec{
                .{ .form = .star, .min = 0, .max = inf },
                .{ .form = .plus, .min = 1, .max = inf },
                .{ .form = .opt, .min = 0, .max = 1 },
                .{ .form = .range, .min = 1, .max = 3 },
                .{ .form = .open, .min = 2, .max = inf },
                .{ .form = .exact, .min = 2, .max = 2 },
                .{ .form = .range, .min = 0, .max = 2, .lazy = true },
            };
            return t.add(.{ .op = .quant, .quant = forms[rnd.uintLessThan(usize, forms.len)], .a = a });
        },
        4, 5 => {
            const a = try randomTree(t, rnd, inv, budget - 1);
            return t.add(.{ .op = @enumFromInt(4 + rnd.uintLessThan(u8, 4)), .a = a });
        },
        6 => {
            const a = try randomTree(t, rnd, inv, budget - 1);
            return t.add(.{ .op = .group_nc, .a = a });
        },
        else => return t.add(.{ .op = .atom, .atom = inv[rnd.uintLessThan(usize, inv.len)] }),
    }
}

test "relation model agrees with backtracking matcher" {
    ucd.init();
    const gpa = testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xC0FFEE);
    const rnd = prng.random();
    const flag_list = [_][]const u8{ "", "i", "m", "s", "u", "iu", "v", "iv", "ims", "imsv", "msu" };
    var compared: usize = 0;
    for (flag_list) |fs| {
        const flags = try Flags.parse(fs);
        const inv = try atoms.buildInventory(gpa, .{}, flags);
        defer gpa.free(inv);
        var symbuf: [alpha.max_symbols * 2]u21 = undefined;
        const pool = alpha.poolSymbols(alpha.active_pool, flags, &symbuf);
        for (0..400) |_| {
            var t: Ast = .{};
            t.root = try randomTree(&t, rnd, inv, rnd.intRangeAtMost(usize, 1, 12));
            var w: [8]u21 = undefined;
            const n = rnd.uintAtMost(usize, 6);
            for (0..n) |i| w[i] = pool[rnd.uintLessThan(usize, pool.len)];
            var mt: Matcher = .{ .t = &t, .flags = flags, .w = w[0..n] };
            const expect = mt.fullMatch() orelse continue;
            try testing.expectEqual(expect, fullMatch(&t, flags, w[0..n]));
            compared += 1;
        }
    }
    try testing.expect(compared > 3000);
}

test "serialization round trip" {
    ucd.init();
    var t: Ast = .{};
    const a = try t.add(.{ .op = .atom, .atom = .{ .kind = .lit, .syms = .{ 0x212A, 0, 0, 0 } } });
    const b = try t.add(.{ .op = .atom, .atom = .{ .kind = .cls, .neg = true, .n = 2, .syms = .{ 'a', '\n', 0, 0 } } });
    const c = try t.add(.{ .op = .alt, .a = a, .b = b });
    t.root = try t.add(.{ .op = .quant, .quant = .{ .form = .range, .min = 1, .max = 3, .lazy = true }, .a = c });
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try serialize(&t, &buf, testing.allocator);
    const t2 = try parse(buf.items);
    var buf2: std.ArrayList(u8) = .empty;
    defer buf2.deinit(testing.allocator);
    try serialize(&t2, &buf2, testing.allocator);
    try testing.expectEqualStrings(buf.items, buf2.items);
}
