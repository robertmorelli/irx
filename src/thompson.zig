//! Leftmost-first matching the way Rust's regex-automata does it: the tree compiles to a
//! Thompson NFA shaped like regex-automata's (a nullable `e*` becomes `(e+)?`, `e{n,}` becomes
//! `e{n-1}e+`, bounded repeats unroll), and a backtracker that never revisits a
//! (state, position) pair walks it in priority order, as regex-automata's BoundedBacktracker
//! does. Revisits matter only on empty cycles, so this decides what an empty loop iteration
//! does: `(?:|a)*` on "aa" is [0,0) as in Perl, but `(?:\B|x)*` on "ϑё" is [0,2) where Perl
//! stops at [0,1). Lookarounds, atomic groups and backreferences are not compiled.
const std = @import("std");
const ast = @import("ast.zig");
const atoms = @import("atoms.zig");
const alpha = @import("alphabet.zig");
const dialect = @import("dialect.zig");
const Flags = alpha.Flags;

const none: u32 = std.math.maxInt(u32);
pub const max_states: u32 = 1 << 16;

const Kind = enum(u8) { char, look, empty, alt, cap_start, cap_end, match };

const State = struct {
    kind: Kind,
    /// char / look: the AST atom node.
    node: u8 = 0,
    /// cap_start / cap_end: capture ordinal.
    slot: u8 = 0,
    /// alt: alternates are traversed last-patched first.
    reverse: bool = false,
    next: u32 = none,
    /// alt: first and last edge in `edges`.
    head: u32 = none,
    tail: u32 = none,
};

const Edge = struct { to: u32, next: u32 = none };

const Ref = struct { start: u32, end: u32 };

pub const Nfa = struct {
    states: [max_states]State = undefined,
    nstates: u32 = 0,
    edges: [max_states * 2]Edge = undefined,
    nedges: u32 = 0,
    start: u32 = 0,
    t: *const ast.Ast = undefined,
    caps: ?*const ast.Caps = null,
    nflags: [ast.max_nodes]Flags = undefined,
    /// classEmpty per node: 0 unknown, 1 empty, 2 not empty.
    empty_memo: [ast.max_nodes]u2 = undefined,

    fn add(self: *Nfa, s: State) error{TooBig}!u32 {
        if (self.nstates == max_states) return error.TooBig;
        self.states[self.nstates] = s;
        self.nstates += 1;
        return self.nstates - 1;
    }

    fn patch(self: *Nfa, from: u32, to: u32) error{TooBig}!void {
        const s = &self.states[from];
        if (s.kind != .alt) {
            std.debug.assert(s.next == none);
            s.next = to;
            return;
        }
        if (self.nedges == self.edges.len) return error.TooBig;
        self.edges[self.nedges] = .{ .to = to };
        if (s.tail == none) s.head = self.nedges else self.edges[s.tail].next = self.nedges;
        s.tail = self.nedges;
        self.nedges += 1;
    }

    fn alt(self: *Nfa, greedy: bool) error{TooBig}!u32 {
        return self.add(.{ .kind = .alt, .reverse = !greedy });
    }

    fn empty(self: *Nfa) error{TooBig}!u32 {
        return self.add(.{ .kind = .empty });
    }

    /// Compile `t` (null: unsupported constructs or too many states).
    pub fn build(self: *Nfa, t: *const ast.Ast, flags: Flags, caps: ?*const ast.Caps) ?void {
        self.nstates = 0;
        self.nedges = 0;
        self.t = t;
        self.caps = caps;
        ast.nodeFlags(t, flags, &self.nflags);
        @memset(self.empty_memo[0..t.len], 0);
        const r = self.c(t.root) catch return null;
        const m = self.add(.{ .kind = .match }) catch return null;
        self.patch(r.end, m) catch return null;
        self.start = r.start;
    }

    fn c(self: *Nfa, idx: u8) error{ TooBig, Unsupported }!Ref {
        const n = self.t.nodes[idx];
        switch (n.op) {
            .atom => {
                if (n.atom.kind == .empty) {
                    const e = try self.empty();
                    return .{ .start = e, .end = e };
                }
                if (n.atom.kind == .strs or n.atom.kind == .grapheme) return error.Unsupported;
                const s = try self.add(.{ .kind = if (n.atom.isAssertion()) .look else .char, .node = idx });
                return .{ .start = s, .end = s };
            },
            .concat => {
                const a = try self.c(n.a);
                const b = try self.c(n.b);
                try self.patch(a.end, b.start);
                return .{ .start = a.start, .end = b.end };
            },
            .alt => {
                const u = try self.alt(true);
                const e = try self.empty();
                for ([_]u8{ n.a, n.b }) |k| {
                    const r = try self.c(k);
                    try self.patch(u, r.start);
                    try self.patch(r.end, e);
                }
                return .{ .start = u, .end = e };
            },
            .group_cap, .group_named => {
                const caps = self.caps orelse return self.c(n.a);
                const slot = caps.ordinal[idx];
                const s = try self.add(.{ .kind = .cap_start, .slot = slot });
                const r = try self.c(n.a);
                const e = try self.add(.{ .kind = .cap_end, .slot = slot });
                try self.patch(s, r.start);
                try self.patch(r.end, e);
                return .{ .start = s, .end = e };
            },
            .group_nc, .flag_group => return self.c(n.a),
            .quant => {
                const q = n.quant;
                const greedy = q.lazy == self.nflags[idx].swap;
                if (q.max == ast.inf) return self.atLeast(n.a, greedy, q.min);
                return self.bounded(n.a, greedy, q.min, q.max);
            },
            else => return error.Unsupported,
        }
    }

    fn exactly(self: *Nfa, body: u8, k: u8) !Ref {
        if (k == 0) {
            const e = try self.empty();
            return .{ .start = e, .end = e };
        }
        var r = try self.c(body);
        for (1..k) |_| {
            const x = try self.c(body);
            try self.patch(r.end, x.start);
            r.end = x.end;
        }
        return r;
    }

    fn atLeast(self: *Nfa, body: u8, greedy: bool, k: u8) !Ref {
        if (k == 0) {
            if ((minLen(self, body) orelse 0) > 0) {
                const u = try self.alt(greedy);
                const r = try self.c(body);
                try self.patch(u, r.start);
                try self.patch(r.end, u);
                return .{ .start = u, .end = u };
            }
            // x* with a nullable x compiles as (x+)? (regex issue #779).
            const r = try self.c(body);
            const plus = try self.alt(greedy);
            try self.patch(r.end, plus);
            try self.patch(plus, r.start);
            const question = try self.alt(greedy);
            const e = try self.empty();
            try self.patch(question, r.start);
            try self.patch(question, e);
            try self.patch(plus, e);
            return .{ .start = question, .end = e };
        }
        if (k == 1) {
            const r = try self.c(body);
            const u = try self.alt(greedy);
            try self.patch(r.end, u);
            try self.patch(u, r.start);
            return .{ .start = r.start, .end = u };
        }
        const prefix = try self.exactly(body, k - 1);
        const last = try self.c(body);
        const u = try self.alt(greedy);
        try self.patch(prefix.end, last.start);
        try self.patch(last.end, u);
        try self.patch(u, last.start);
        return .{ .start = prefix.start, .end = u };
    }

    fn bounded(self: *Nfa, body: u8, greedy: bool, lo: u8, hi: u8) !Ref {
        const prefix = try self.exactly(body, lo);
        if (lo == hi) return prefix;
        const e = try self.empty();
        var prev = prefix.end;
        for (lo..hi) |_| {
            const u = try self.alt(greedy);
            const r = try self.c(body);
            try self.patch(prev, u);
            try self.patch(u, r.start);
            try self.patch(u, e);
            prev = r.end;
        }
        try self.patch(prev, e);
        return .{ .start = prefix.start, .end = e };
    }
};

/// Shortest length a subtree can match (regex-syntax's minimum_len); assertions are 0. Null when
/// it can match nothing: an empty class poisons every concatenation, alternation and repetition
/// around it, except that an alternation whose branches (flattened, `a|b|c` is one alternation)
/// are all single characters and classes is one class first.
fn minLen(self: *Nfa, idx: u8) ?usize {
    const t = self.t;
    const n = t.nodes[idx];
    if (n.op == .alt and classLike(self, idx)) return if (classEmpty(self, idx)) null else 1;
    return switch (n.op) {
        .atom => if (n.atom.kind == .empty or n.atom.isAssertion()) 0 else if (classEmpty(self, idx)) null else 1,
        .concat => (minLen(self, n.a) orelse return null) + (minLen(self, n.b) orelse return null),
        .alt => @min(branchMin(self, n.a) orelse return null, branchMin(self, n.b) orelse return null),
        .quant => (minLen(self, n.a) orelse return null) * n.quant.min,
        .group_cap, .group_named, .group_nc, .flag_group => minLen(self, n.a),
        else => 0,
    };
}

/// One branch of a flattened alternation that is not merged into a class.
fn branchMin(self: *Nfa, idx: u8) ?usize {
    const n = self.t.nodes[idx];
    if (n.op != .alt) return minLen(self, idx);
    return @min(branchMin(self, n.a) orelse return null, branchMin(self, n.b) orelse return null);
}

/// A single character or class after translation (non-capturing and flag groups vanish).
fn classLike(self: *const Nfa, idx: u8) bool {
    const n = self.t.nodes[idx];
    return switch (n.op) {
        .atom => n.atom.isConsuming() and n.atom.kind != .strs and n.atom.kind != .grapheme,
        .alt => classLike(self, n.a) and classLike(self, n.b),
        .group_nc, .flag_group => classLike(self, n.a),
        else => false,
    };
}

/// A class-like subtree matches no scalar value. Only set operations and negated classes can be
/// empty, so only those are scanned.
fn classEmpty(self: *Nfa, idx: u8) bool {
    const n = self.t.nodes[idx];
    switch (n.op) {
        .alt => return classEmpty(self, n.a) and classEmpty(self, n.b),
        .group_nc, .flag_group => return classEmpty(self, n.a),
        .atom => {},
        else => return false,
    }
    const a = &n.atom;
    if (!(a.kind == .vset or (a.kind == .cls and a.neg))) return false;
    // Memoized, with a cheap probe first: the full scan runs for every negated class each time
    // the NFA is built, and minLen asks again for each enclosing repetition.
    if (self.empty_memo[idx] != 0) return self.empty_memo[idx] == 1;
    const empty = scan: {
        for ([_]u21{ 'a', 'Z', '0', ' ', '_', '-', '\n', 0xE9, 0x3B1, 0x430, 0x4E00, 0x1F600 }) |c| {
            if (atoms.matches(a, self.nflags[idx], c)) break :scan false;
        }
        var c: u21 = 0;
        while (c <= 0x10FFFF) : (c += 1) {
            if (c == 0xD800) c = 0xE000;
            if (atoms.matches(a, self.nflags[idx], c)) break :scan false;
        }
        break :scan true;
    };
    self.empty_memo[idx] = if (empty) 1 else 2;
    return empty;
}

/// The tree has only constructs the NFA compiles.
pub fn supported(t: *const ast.Ast) bool {
    for (t.nodes[0..t.len]) |n| switch (n.op) {
        .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind, .atomic, .backref => return false,
        .atom => {
            if (n.atom.kind == .strs or n.atom.kind == .grapheme) return false;
            if ((n.atom.kind == .wordb or n.atom.kind == .nwordb) and !dialect.active.nfa_word_boundary) return false;
        },
        else => {},
    };
    return true;
}

threadlocal var nfa_store: ?*Nfa = null;
threadlocal var visited_store: []u64 = &.{};

const Frame = union(enum) {
    step: struct { sid: u32, at: u32 },
    restore: struct { half: u16, old: i16 },
};

/// First match starting exactly at `start` in priority order: its end, or null for no match.
/// Error when the NFA or the visited set would be too large.
pub fn matchAt(t: *const ast.Ast, flags: Flags, w: []const u21, start: usize, caps: ?*ast.Caps) error{TooBig}!?usize {
    if (nfa_store == null) nfa_store = std.heap.page_allocator.create(Nfa) catch return error.TooBig;
    const nfa = nfa_store.?;
    nfa.build(t, flags, caps) orelse return error.TooBig;
    const width: usize = w.len + 1;
    const bits = @as(usize, nfa.nstates) * width;
    if (bits > 1 << 28) return error.TooBig;
    const words = (bits + 63) / 64;
    if (visited_store.len < words) {
        if (visited_store.len != 0) std.heap.page_allocator.free(visited_store);
        visited_store = std.heap.page_allocator.alloc(u64, @max(words, 1024)) catch return error.TooBig;
    }
    const visited = visited_store[0..words];
    @memset(visited, 0);

    var nflags: [ast.max_nodes]Flags = undefined;
    ast.nodeFlags(t, flags, &nflags);

    // Capture halves: 2*k is group k's start, 2*k+1 its end.
    var halves: [2 * ast.max_caps]i16 = [_]i16{-1} ** (2 * ast.max_caps);
    var stack: std.ArrayList(Frame) = .empty;
    defer stack.deinit(std.heap.page_allocator);
    stack.append(std.heap.page_allocator, .{ .step = .{ .sid = nfa.start, .at = @intCast(start) } }) catch return error.TooBig;
    while (stack.pop()) |f| switch (f) {
        .restore => |r| halves[r.half] = r.old,
        .step => |st| {
            var sid = st.sid;
            var at: usize = st.at;
            while (true) {
                const bit = @as(usize, sid) * width + at;
                if (visited[bit / 64] & (@as(u64, 1) << @intCast(bit % 64)) != 0) break;
                visited[bit / 64] |= @as(u64, 1) << @intCast(bit % 64);
                const s = nfa.states[sid];
                switch (s.kind) {
                    .char => {
                        const a = &t.nodes[s.node].atom;
                        if (at >= w.len or !atoms.matches(a, nflags[s.node], w[at])) break;
                        at += 1;
                        sid = s.next;
                    },
                    .look => {
                        if (!atoms.assertionAt(&t.nodes[s.node].atom, nflags[s.node], w, at)) break;
                        sid = s.next;
                    },
                    .empty => sid = s.next,
                    .cap_start, .cap_end => {
                        const half: u16 = @as(u16, s.slot) * 2 + @intFromBool(s.kind == .cap_end);
                        stack.append(std.heap.page_allocator, .{ .restore = .{ .half = half, .old = halves[half] } }) catch return error.TooBig;
                        halves[half] = @intCast(at);
                        sid = s.next;
                    },
                    .alt => {
                        // Collect alternates in priority order, push all but the first.
                        var order: [64]u32 = undefined;
                        var k: usize = 0;
                        var e = s.head;
                        while (e != none) : (e = nfa.edges[e].next) {
                            if (k == order.len) return error.TooBig;
                            order[k] = nfa.edges[e].to;
                            k += 1;
                        }
                        if (k == 0) break;
                        if (s.reverse) std.mem.reverse(u32, order[0..k]);
                        var j = k;
                        while (j > 1) {
                            j -= 1;
                            stack.append(std.heap.page_allocator, .{ .step = .{ .sid = order[j], .at = @intCast(at) } }) catch return error.TooBig;
                        }
                        sid = order[0];
                    },
                    .match => {
                        if (caps) |cp| {
                            for (0..cp.count) |g| cp.slot[g] = if (halves[2 * g] >= 0 and halves[2 * g + 1] >= 0)
                                .{ .s = halves[2 * g], .e = halves[2 * g + 1] }
                            else
                                ast.Caps.Span.unset;
                        }
                        return at;
                    },
                }
            }
        },
    };
    return null;
}
