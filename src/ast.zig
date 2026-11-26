//! Owned regex syntax trees, direct relation evaluation, a naive JS-style
//! backtracking matcher used to cross-check the relation model, and a
//! stable s-expression serialization used by persisted findings.
const std = @import("std");
const dialect = @import("dialect.zig");
const alpha = @import("alphabet.zig");
const grapheme = @import("grapheme.zig");
const atoms = @import("atoms.zig");
const relmod = @import("rel.zig");
const thompson = @import("thompson.zig");
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
    /// Conditional group (?(N)yes|no): matches child a when capture group Node.fmod (ordinal,
    /// opening order) is set at that point of the match, else child b. Mutation mode only.
    cond = 14,
    /// \K (Perl): the reported match starts where it was last passed. Mutation mode only.
    keep = 15,
    /// \G (Perl): matches where the search started (0, or pos() in the offset modes).
    /// Mutation mode only.
    gpos = 16,
    /// Branch reset (?|…|…) (Perl): each top-level alternative of the child numbers its
    /// captures from the same number. Mutation mode only.
    branch_reset = 17,

    /// No children: atoms, backreferences, \K and \G.
    pub fn isLeaf(op: Op) bool {
        return op == .atom or op == .backref or op == .keep or op == .gpos;
    }

    pub fn isBinary(op: Op) bool {
        return op == .concat or op == .alt or op == .cond;
    }
    pub fn isLook(op: Op) bool {
        return @intFromEnum(op) >= 4 and @intFromEnum(op) <= 7;
    }
    /// One child, wrapped in a group construct (\K and \G are leaves, conditionals binary).
    pub fn isGroup(op: Op) bool {
        return switch (op) {
            .group_cap, .group_nc, .group_named, .flag_group, .atomic, .branch_reset => true,
            else => false,
        };
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
    /// flag_group: flags toggled for the subtree (fmod_i); backref, cond: the target capture ordinal.
    fmod: u8 = 0,
};

pub const max_nodes = 255;

/// Node.fmod bits: the flag a flag group toggles.
pub const fmod_i: u8 = 1;
pub const fmod_s: u8 = 2;
pub const fmod_m: u8 = 4;
pub const fmod_crlf: u8 = 8;
pub const fmod_swap: u8 = 16;
pub const fmod_u: u8 = 32;

/// Flags inside a flag group with modifier `mod`.
pub fn applyMod(f: Flags, mod: u8) Flags {
    var g = f;
    if (mod & fmod_i != 0) g.i = !g.i;
    if (mod & fmod_s != 0) g.s = !g.s;
    if (mod & fmod_m != 0) g.m = !g.m;
    if (mod & fmod_crlf != 0) g.crlf = !g.crlf;
    if (mod & fmod_swap != 0) g.swap = !g.swap;
    if (mod & fmod_u != 0) g.u = !g.u;
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
            .atom, .backref, .keep, .gpos => 1,
            .concat, .alt, .cond => 1 + self.size(n.a) + self.size(n.b),
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
            .atom, .backref, .keep, .gpos => {},
            .concat, .alt, .cond => {
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
        .group_cap, .group_nc, .group_named, .branch_reset => evalRel(R, t, n.a, flags, w),
        .flag_group => evalRel(R, t, n.a, applyMod(flags, n.fmod), w),
        // Mutation-mode constructs: the oracle uses the backtracking matcher for these trees.
        .atomic, .backref, .cond, .keep, .gpos => @panic("relation model cannot evaluate atomic groups, backreferences, conditionals, \\K or \\G"),
    };
}

/// Every backreference and conditional refers to a capture group that closes before it in
/// pattern order (so the printed \N or (?(N)…) names a group the engine has seen); false
/// otherwise.
pub fn backrefsValid(t: *const Ast) bool {
    const caps = Caps.init(t) orelse return false;
    var closed: [max_caps]bool = [_]bool{false} ** max_caps;
    return backrefWalk(t, t.root, &caps, &closed, false);
}

fn backrefWalk(t: *const Ast, idx: u8, caps: *const Caps, closed: *[max_caps]bool, in_look: bool) bool {
    const n = t.nodes[idx];
    switch (n.op) {
        .atom, .keep, .gpos => return true,
        .backref => return n.fmod < caps.count and closed[n.fmod] and (!in_look or dialect.active.backref_in_lookaround),
        .cond => {
            if (!(n.fmod < caps.count and closed[n.fmod])) return false;
            return backrefWalk(t, n.a, caps, closed, in_look) and backrefWalk(t, n.b, caps, closed, in_look);
        },
        .concat, .alt => return backrefWalk(t, n.a, caps, closed, in_look) and backrefWalk(t, n.b, caps, closed, in_look),
        else => {
            const look = in_look or n.op == .look_ahead or n.op == .neg_look_ahead or n.op == .look_behind or n.op == .neg_look_behind;
            if (!backrefWalk(t, n.a, caps, closed, look)) return false;
            if (n.op == .group_cap or n.op == .group_named) closed[caps.ordinal[idx]] = true;
            return true;
        },
    }
}

/// Spans and captures come from the Thompson NFA (dialects with empty_iteration = thompson,
/// for trees it compiles).
pub fn usesNfa(t: *const Ast) bool {
    return dialect.active.empty_iteration == .thompson and thompson.supported(t);
}

/// The tree holds constructs only the backtracking matcher evaluates (atomic groups,
/// backreferences, conditionals): oracles and long mode take the matcher path or skip.
pub fn needsMatcher(t: *const Ast) bool {
    for (t.nodes[0..t.len]) |n| switch (n.op) {
        .atomic, .backref, .cond, .keep, .gpos, .branch_reset => return true,
        else => {},
    };
    return false;
}

/// Perl's \K, \G and branch reset sit where the model's semantics are Perl's:
/// - \K never inside a lookaround (Perl: "\K not permitted in lookahead/lookbehind"), nor
///   inside an atomic group or a loop over a fixed-length body unless the dialect restores it
///   there (keep_restored).
/// - \G with only zero-width, unquantified constructs before it on its path from the match
///   start (lookaround bodies included: `(?=a\G)` counts the `a`). Elsewhere Perl starts the
///   search before pos() (gofs) or at the start of the string (GPOS_FLOAT), and under /\G…/g
///   anchors it there: perlre says \G is only fully supported at the start of the pattern.
/// - no named group inside a branch reset (Perl wants the same names at the same numbers).
pub fn perlExtrasValid(t: *const Ast) bool {
    return extrasWalk(t, t.root, false, true, false);
}

fn extrasWalk(t: *const Ast, idx: u8, in_look: bool, at_start: bool, in_atomic: bool) bool {
    const n = t.nodes[idx];
    switch (n.op) {
        .keep => return !in_look and (!in_atomic or dialect.active.keep_restored),
        .gpos => return at_start,
        .atom, .backref => return true,
        .concat => {
            const zw = (maxLenSub(t, n.a) orelse 1) == 0 and !hasQuant(t, n.a) and !hasOp(t, n.a, .cond);
            return extrasWalk(t, n.a, in_look, at_start, in_atomic) and extrasWalk(t, n.b, in_look, at_start and zw, in_atomic);
        },
        .alt => return extrasWalk(t, n.a, in_look, at_start, in_atomic) and extrasWalk(t, n.b, in_look, at_start, in_atomic),
        // A conditional's branches are alternatives for \K. \G stays out of them (and out of
        // whatever follows a conditional): how Perl anchors \G through IFTHEN is unmeasured.
        .cond => return extrasWalk(t, n.a, in_look, false, in_atomic) and extrasWalk(t, n.b, in_look, false, in_atomic),
        .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind => return extrasWalk(t, n.a, true, at_start, in_atomic),
        .branch_reset => return !hasOp(t, n.a, .group_named) and extrasWalk(t, n.a, in_look, at_start, in_atomic),
        .atomic => return extrasWalk(t, n.a, in_look, at_start, true),
        .quant => {
            // Lengths without multi-character folds: under i Perl may not see the body as fixed,
            // so this errs on the side of keeping \K out.
            const fixed = if (plainMaxLen(t, n.a)) |hi| hi == minLenSub(t, n.a) else false;
            return extrasWalk(t, n.a, in_look, at_start, in_atomic or fixed);
        },
        else => return extrasWalk(t, n.a, in_look, at_start, in_atomic),
    }
}

/// maxLenSub, but a case-folding atom counts one character.
fn plainMaxLen(t: *const Ast, idx: u8) ?usize {
    const n = t.nodes[idx];
    return switch (n.op) {
        .atom => if (n.atom.kind == .grapheme) null else n.atom.maxLen(),
        .concat => if (plainMaxLen(t, n.a)) |a| (if (plainMaxLen(t, n.b)) |b| a + b else null) else null,
        .alt, .cond => if (plainMaxLen(t, n.a)) |a| (if (plainMaxLen(t, n.b)) |b| @max(a, b) else null) else null,
        .quant => if (n.quant.max == inf) (if (plainMaxLen(t, n.a)) |a| (if (a == 0) @as(?usize, 0) else null) else null) else if (plainMaxLen(t, n.a)) |a| a * n.quant.max else null,
        .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind, .keep, .gpos => 0,
        .group_cap, .group_nc, .group_named, .flag_group, .atomic, .branch_reset => plainMaxLen(t, n.a),
        .backref => null,
    };
}

fn hasQuant(t: *const Ast, idx: u8) bool {
    return hasOp(t, idx, .quant);
}

fn hasOp(t: *const Ast, idx: u8, op: Op) bool {
    const n = t.nodes[idx];
    if (n.op == op) return true;
    if (n.op.isLeaf()) return false;
    return hasOp(t, n.a, op) or (Op.isBinary(n.op) and hasOp(t, n.b, op));
}

pub fn quantRel(comptime R: type, r: R, q: QuantSpec, dim: usize) R {
    if (q.max == inf) return r.repOpen(q.min, dim);
    return r.rep(q.min, q.max, dim);
}

/// Full-match oracle for one subject: (0, n) ∈ rel.
pub fn fullMatch(t: *const Ast, flags: Flags, w: []const u21) bool {
    return fullMatchOrNull(t, flags, w) orelse false;
}

/// Null when the backtracking matcher runs out of steps (no answer, not "no match").
pub fn fullMatchOrNull(t: *const Ast, flags: Flags, w: []const u21) ?bool {
    if (needsMatcher(t)) {
        var caps = Caps.init(t) orelse return null;
        var mt: Matcher = .{ .t = t, .flags = flags, .w = w, .caps = &caps, .reset_loop_captures = dialect.active.reset_loop_captures_hint };
        return mt.fullMatch();
    }
    if (w.len <= relmod.Rel16.max_len) return evalRel(relmod.Rel16, t, t.root, flags, w).get(0, w.len);
    return evalRel(relmod.Rel32, t, t.root, flags, w).get(0, w.len);
}

/// Decode a UTF-16 subject for `flags` and evaluate the oracle. Null if too long or the
/// matcher runs out of steps.
pub fn oracle(t: *const Ast, flags: Flags, subject: []const u16) ?bool {
    var syms: [31]u21 = undefined;
    const n = alpha.decode(subject, flags, &syms) orelse return null;
    return fullMatchOrNull(t, flags, syms[0..n]);
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
    /// \K: where the reported match starts, once passed (reset by matchAt).
    keep: ?usize = null,
    /// \G: the position where the search started (pos(); 0 for a fresh match).
    gpos: usize = 0,
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
    const ContKind = enum { done, accept, record, seq, rep, close, commit, at };
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
        if (usesNfa(self.t)) {
            const e = thompson.matchAt(self.t, self.flags, self.w, start, self.caps) catch return null;
            self.end = e orelse return false;
            return true;
        }
        const rec: Cont = .{ .kind = .record };
        self.keep = null;
        const r = self.m(self.t.root, start, .fwd, &rec);
        if (self.exhausted) return null;
        return r;
    }

    fn run(self: *Matcher, c: *const Cont, pos: usize) bool {
        switch (c.kind) {
            .done => return pos == self.w.len,
            .accept => return true,
            // Forward lookbehind body: succeed only when it ends exactly at the lookbehind position.
            .at => return pos == c.start,
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
                // Thompson dialects reach this matcher only for trees the NFA does not compile
                // (fancy-regex's own backtracking VM), which stops like Perl.
                const at_min = c.min == 0 or (c.min == 1 and (dialect.active.empty_iteration_at_min or (c.max == inf and dialect.active.empty_iteration_at_min_open)));
                if (at_min and pos == c.start and (c.max == inf or dialect.active.empty_iteration_bounded)) {
                    if (dialect.active.empty_iteration == .stop or dialect.active.empty_iteration == .thompson) return self.run(c.next.?, pos);
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
                if (a.kind == .empty) return if (a.sub == 1) false else self.run(c, pos); // sub 1: (*FAIL)
                const fl = self.flagsAt(idx);
                if (a.isAssertion()) {
                    // At this position only: a whole-string mask is O(n) per step and only 32 bits.
                    if (!atoms.assertionAt(a, fl, self.w, pos)) return false;
                    return self.run(c, pos);
                }
                if (a.kind == .linebreak) {
                    // \R: one end from each start (\r\n is atomic).
                    if (dir == .fwd) return if (atoms.linebreakEnd(self.w, pos)) |e| self.run(c, e) else false;
                    var k = pos;
                    while (k > 0 and k + 2 >= pos) {
                        k -= 1;
                        if (atoms.linebreakEnd(self.w, k) == pos and self.run(c, k)) return true;
                    }
                    return false;
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
                    if (dialect.active.fold_longest_first) {
                        // Multi-character folds first, longest first, then one character.
                        var ends: [8]usize = undefined;
                        var nends: usize = 0;
                        const Col = struct {
                            ends: *[8]usize,
                            n: *usize,
                            fn f(x: @This(), e: usize) bool {
                                for (x.ends[0..x.n.*]) |o| if (o == e) return false;
                                if (x.n.* < x.ends.len) {
                                    x.ends[x.n.*] = e;
                                    x.n.* += 1;
                                }
                                return false;
                            }
                        };
                        _ = atoms.forEachFoldMatch(a, fl, self.w, pos, Col{ .ends = &ends, .n = &nends }, Col.f);
                        std.mem.sort(usize, ends[0..nends], {}, std.sort.desc(usize));
                        for (ends[0..nends]) |e| if (self.run(c, e)) return true;
                        return pos < self.w.len and atoms.matches(a, fl, self.w[pos]) and self.run(c, pos + 1);
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
                const lazy = (n.quant.lazy and !(counted and dialect.active.lazy_counted_is_greedy)) != self.flagsAt(idx).swap;
                return self.repeat(n.a, n.quant.min, n.quant.max, !lazy, pos, dir, c);
            },
            .look_behind, .neg_look_behind => if (dialect.active.lookbehind_forward and dir == .fwd) if (maxLenSub(self.t, n.a)) |hi| {
                // Perl: from the farthest start to the nearest, match the body forward; it must end
                // exactly here. The first start that works wins (and keeps its captures).
                const lo = minLenSub(self.t, n.a);
                const neg = n.op == .neg_look_behind;
                const at: Cont = .{ .kind = .at, .start = pos };
                var saved: @TypeOf(self.caps.?.slot) = undefined;
                if (self.caps) |caps| saved = caps.slot;
                var found = false;
                if (pos >= lo) {
                    var s: usize = if (pos >= hi) pos - hi else 0;
                    while (s + lo <= pos) : (s += 1) if (self.m(n.a, s, .fwd, &at)) {
                        found = true;
                        break;
                    };
                }
                if (neg) if (self.caps) |caps| {
                    caps.slot = saved;
                };
                if (found == neg) return false;
                if (self.run(c, pos)) return true;
                if (self.caps) |caps| caps.slot = saved;
                return false;
            } else return self.lookaround(n, idx, pos, c) else return self.lookaround(n, idx, pos, c),
            .look_ahead, .neg_look_ahead => return self.lookaround(n, idx, pos, c),
            .group_cap, .group_named => {
                const caps = self.caps orelse return self.m(n.a, pos, dir, c);
                const k: Cont = .{ .kind = .close, .node = caps.ordinal[idx], .dir = dir, .start = pos, .next = c };
                return self.m(n.a, pos, dir, &k);
            },
            .group_nc, .flag_group, .branch_reset => return self.m(n.a, pos, dir, c),
            .atomic => {
                // The child's first match only: no backtracking into it once it has matched.
                var endpos: usize = pos;
                const k: Cont = .{ .kind = .commit, .out = &endpos };
                const kept = self.keep;
                if (self.caps) |caps| {
                    const saved = caps.slot;
                    if (!self.m(n.a, pos, dir, &k)) return false;
                    if (self.run(c, endpos)) return true;
                    caps.slot = saved;
                    self.keep = kept;
                    return false;
                }
                if (!self.m(n.a, pos, dir, &k)) return false;
                if (self.run(c, endpos)) return true;
                self.keep = kept;
                return false;
            },
            .keep => {
                const old = self.keep;
                self.keep = pos;
                if (self.run(c, pos)) return true;
                self.keep = old;
                return false;
            },
            .gpos => return if (pos == self.gpos) self.run(c, pos) else false,
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
            .cond => {
                // The group's state on the current path: set by a match not undone by
                // backtracking (captures are restored when backtracking out of them).
                const caps = self.caps orelse {
                    self.exhausted = true; // no capture state: no answer
                    return false;
                };
                return self.m(if (caps.slot[n.fmod].s >= 0) n.a else n.b, pos, dir, c);
            },
        }
    }

    /// A lookaround read in its own direction (lookbehind right to left from `pos`).
    fn lookaround(self: *Matcher, n: Node, idx: u8, pos: usize, c: *const Cont) bool {
        _ = idx;
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
        if (n.op == .branch_reset) {
            // Every top-level alternative numbers from the same group; the next group after
            // the reset takes the highest number any alternative reached.
            const c0 = self.count;
            var hi = c0;
            if (!self.walkAlts(t, n.a, c0, &hi)) return false;
            self.count = hi;
        } else if (!n.op.isLeaf()) {
            if (!self.walk(t, n.a)) return false;
            if (Op.isBinary(n.op) and !self.walk(t, n.b)) return false;
        }
        self.end[idx] = self.count;
        return true;
    }

    fn walkAlts(self: *Caps, t: *const Ast, idx: u8, c0: u8, hi: *u8) bool {
        const n = t.nodes[idx];
        if (n.op == .alt) {
            self.first[idx] = c0;
            if (!self.walkAlts(t, n.a, c0, hi) or !self.walkAlts(t, n.b, c0, hi)) return false;
            self.end[idx] = hi.*;
            return true;
        }
        self.count = c0;
        if (!self.walk(t, idx)) return false;
        hi.* = @max(hi.*, self.count);
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
        .cond => {
            try out.print(gpa, "(cond {d} ", .{n.fmod});
            try serNode(t, n.a, out, gpa);
            try out.append(gpa, ' ');
            try serNode(t, n.b, out, gpa);
            try out.append(gpa, ')');
        },
        .keep, .gpos => try out.print(gpa, "({s})", .{@tagName(n.op)}),
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
            .cond => {
                n.fmod = try p.int(u8, 10);
                n.a = try p.node(t);
                n.b = try p.node(t);
            },
            .keep, .gpos => {},
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
        .atomic, .branch_reset => .nc_group,
        .backref => .group,
        .cond => .alt,
        .keep, .gpos => .empty,
    };
    out[@intFromEnum(c)] +|= 1;
    if (n.op == .quant and n.quant.lazy) out[@intFromEnum(Construct.lazy)] +|= 1;
    switch (n.op) {
        .atom, .backref, .keep, .gpos => {},
        .concat, .alt, .cond => {
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

/// Minimum symbols a subtree matches (zero-width constructs 0; a backreference 0).
pub fn minLenSub(t: *const Ast, idx: u8) usize {
    const n = t.nodes[idx];
    return switch (n.op) {
        .atom => n.atom.minLen(),
        .concat => minLenSub(t, n.a) + minLenSub(t, n.b),
        .alt, .cond => @min(minLenSub(t, n.a), minLenSub(t, n.b)),
        .quant => minLenSub(t, n.a) * n.quant.min,
        .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind, .backref, .keep, .gpos => 0,
        .group_cap, .group_nc, .group_named, .flag_group, .atomic, .branch_reset => minLenSub(t, n.a),
    };
}

/// Maximum symbols a subtree matches, or null when unbounded or unknown (a backreference, \X,
/// a multi-character fold).
pub fn maxLenSub(t: *const Ast, idx: u8) ?usize {
    const n = t.nodes[idx];
    return switch (n.op) {
        .atom => if (n.atom.kind == .grapheme) null else if (n.atom.isConsuming() and atoms.foldsMulti(&n.atom, .{ .i = true })) 3 else n.atom.maxLen(),
        .concat => if (maxLenSub(t, n.a)) |a| (if (maxLenSub(t, n.b)) |b| a + b else null) else null,
        .alt, .cond => if (maxLenSub(t, n.a)) |a| (if (maxLenSub(t, n.b)) |b| @max(a, b) else null) else null,
        .quant => if (n.quant.max == inf) (if (maxLenSub(t, n.a)) |a| (if (a == 0) @as(?usize, 0) else null) else null) else if (maxLenSub(t, n.a)) |a| a * n.quant.max else null,
        .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind, .keep, .gpos => 0,
        .group_cap, .group_nc, .group_named, .flag_group, .atomic, .branch_reset => maxLenSub(t, n.a),
        .backref => null,
    };
}

test "perl: lookbehind tries the farthest start first and matches forward" {
    const t = std.testing;
    @import("ucd.zig").init();
    const saved = dialect.active;
    defer dialect.active = saved;
    dialect.active = &dialect.perl;
    const flags = try Flags.parse("u");
    const a = "(atom lit 0 0 0 61 0 0 0)";
    const b = "(atom lit 0 0 0 62 0 0 0)";
    // Measured with perl 5.44 and blead, each in a fresh process: match span and captures 1, 2.
    const Case = struct { src: []const u8, w: []const u21, s: i16, e: i16, c1: [2]i16 = .{ -1, -1 }, c2: [2]i16 = .{ -1, -1 } };
    const cases = [_]Case{
        // (?<=(a{1,3}))b and its lazy form on "aaab": the farthest start wins, $1 = [0,3).
        .{ .src = "(concat (look_behind (group_cap (quant range 1 3 0 " ++ a ++ "))) " ++ b ++ ")", .w = &.{ 'a', 'a', 'a', 'b' }, .s = 3, .e = 4, .c1 = .{ 0, 3 } },
        .{ .src = "(concat (look_behind (group_cap (quant range 1 3 1 " ++ a ++ "))) " ++ b ++ ")", .w = &.{ 'a', 'a', 'a', 'b' }, .s = 3, .e = 4, .c1 = .{ 0, 3 } },
        // (?<=(a|aa))b on "aab": $1 = [0,2).
        .{ .src = "(concat (look_behind (group_cap (alt " ++ a ++ " (concat " ++ a ++ " " ++ a ++ ")))) " ++ b ++ ")", .w = &.{ 'a', 'a', 'b' }, .s = 2, .e = 3, .c1 = .{ 0, 2 } },
        // (?<=(a)|(aa))b on "aab": $1 unset, $2 = [0,2).
        .{ .src = "(concat (look_behind (alt (group_cap " ++ a ++ ") (group_cap (concat " ++ a ++ " " ++ a ++ ")))) " ++ b ++ ")", .w = &.{ 'a', 'a', 'b' }, .s = 2, .e = 3, .c2 = .{ 0, 2 } },
        // (?<=(a?)(a))b on "xaab": $1 = [1,2), $2 = [2,3).
        .{ .src = "(concat (look_behind (concat (group_cap (quant opt 0 1 0 " ++ a ++ ")) (group_cap " ++ a ++ "))) " ++ b ++ ")", .w = &.{ 'x', 'a', 'a', 'b' }, .s = 3, .e = 4, .c1 = .{ 1, 2 }, .c2 = .{ 2, 3 } },
        // (?<=(?>a|aa))b on "aab": matches (from start 1).
        .{ .src = "(concat (look_behind (atomic (alt " ++ a ++ " (concat " ++ a ++ " " ++ a ++ ")))) " ++ b ++ ")", .w = &.{ 'a', 'a', 'b' }, .s = 2, .e = 3 },
        // (?<=a?+)b on "ab": matches; (?<=a?+)a on "a": no match (a?+ runs past the lookbehind).
        .{ .src = "(concat (look_behind (atomic (quant opt 0 1 0 " ++ a ++ "))) " ++ b ++ ")", .w = &.{ 'a', 'b' }, .s = 1, .e = 2 },
        .{ .src = "(concat (look_behind (atomic (quant opt 0 1 0 " ++ a ++ "))) " ++ a ++ ")", .w = &.{'a'}, .s = -1, .e = -1 },
        // (?<=(?>(a{0,2})))b on "aaab": $1 = [1,3).
        .{ .src = "(concat (look_behind (atomic (group_cap (quant range 0 2 0 " ++ a ++ ")))) " ++ b ++ ")", .w = &.{ 'a', 'a', 'a', 'b' }, .s = 3, .e = 4, .c1 = .{ 1, 3 } },
    };
    for (cases) |c| {
        const tree = try parse(c.src);
        var caps = Caps.init(&tree) orelse return error.Caps;
        var mt: Matcher = .{ .t = &tree, .flags = flags, .w = c.w, .caps = &caps };
        var s: i16 = -1;
        var e: i16 = -1;
        var i: usize = 0;
        while (i <= c.w.len) : (i += 1) {
            caps = Caps.init(&tree).?;
            if ((mt.matchAt(i) orelse return error.Budget)) {
                s = @intCast(i);
                e = @intCast(mt.end);
                break;
            }
        }
        errdefer std.debug.print("case {s}: got [{d},{d}) $1 [{d},{d}) $2 [{d},{d})\n", .{ c.src, s, e, caps.slot[0].s, caps.slot[0].e, caps.slot[1].s, caps.slot[1].e });
        try t.expectEqual(c.s, s);
        try t.expectEqual(c.e, e);
        if (s < 0) continue;
        try t.expectEqual(c.c1[0], caps.slot[0].s);
        try t.expectEqual(c.c1[1], caps.slot[0].e);
        try t.expectEqual(c.c2[0], caps.slot[1].s);
        try t.expectEqual(c.c2[1], caps.slot[1].e);
    }
}
