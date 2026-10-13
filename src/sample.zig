//! Weighted sampling of trees from a finalized table, and the mode-aware
//! regex printer.
const std = @import("std");
const alpha = @import("alphabet.zig");
const atoms = @import("atoms.zig");
const ast = @import("ast.zig");
const tablemod = @import("table.zig");
const rngmod = @import("rng.zig");

const Flags = alpha.Flags;
const Table = tablemod.Table;
const Op = ast.Op;
const AtomSpec = atoms.AtomSpec;
const Allocator = std.mem.Allocator;

// ---------------------------------------------------------------------------
// Sampler

/// Per-lane scratch, sized for the largest production list of a table.
pub const Scratch = struct {
    cap: usize = 0,
    w: []f64 = &.{},
    prob: []f32 = &.{},
    alias: []u32 = &.{},
    items: []u32 = &.{},
    small: []u32 = &.{},
    large: []u32 = &.{},
    split: []f64 = &.{},

    pub fn ensure(self: *Scratch, gpa: Allocator, n: usize, max_size: usize) !void {
        if (n <= self.cap and self.split.len >= max_size + 1) return;
        self.deinit(gpa);
        const c = @max(n, 1);
        self.w = try gpa.alloc(f64, c);
        self.prob = try gpa.alloc(f32, c);
        self.alias = try gpa.alloc(u32, c);
        self.items = try gpa.alloc(u32, c);
        self.small = try gpa.alloc(u32, c);
        self.large = try gpa.alloc(u32, c);
        self.split = try gpa.alloc(f64, max_size + 1);
        self.cap = c;
    }

    pub fn bytesFor(n: usize, max_size: usize) u64 {
        return @as(u64, @max(n, 1)) * (8 + 4 + 4 + 4 + 4 + 4) + (max_size + 1) * 8 + 7 * 16;
    }

    pub fn deinit(self: *Scratch, gpa: Allocator) void {
        if (self.cap == 0) return;
        gpa.free(self.w);
        gpa.free(self.prob);
        gpa.free(self.alias);
        gpa.free(self.items);
        gpa.free(self.small);
        gpa.free(self.large);
        gpa.free(self.split);
        self.* = .{};
    }
};

pub const SampleError = error{ TooManyNodes, ModelFailure };

pub const Sampler = struct {
    tab: *Table,
    scratch: *Scratch,
    rng: *rngmod.Rng,
    out: *ast.Ast,

    pub fn sample(self: *Sampler) SampleError!usize {
        const k = self.tab.size_alias.draw(self.rng);
        const sa = &self.tab.start_alias[k];
        if (sa.items.len == 0) return error.ModelFailure;
        const x = sa.draw(self.rng);
        self.out.len = 0;
        self.out.root = try self.expand(x, k);
        return k;
    }

    fn drawProd(self: *Sampler, x: u32, k: usize) SampleError!u32 {
        const tab = self.tab;
        const ci = tab.countIndex(x, k) orelse return error.ModelFailure;
        if (tab.cache_enabled) {
            const v = tab.slots[ci].load(.acquire);
            if (v != 0) {
                _ = tab.cache_hits.fetchAdd(1, .monotonic);
                const base = v - 1;
                const n = tab.arena[base];
                const items = tab.arena[base + 1 .. base + 1 + n];
                const prob: []const f32 = @ptrCast(tab.arena[base + 1 + n .. base + 1 + 2 * n]);
                const al = tab.arena[base + 1 + 2 * n .. base + 1 + 3 * n];
                return items[tablemod.drawAlias(self.rng, prob, al)];
            }
        }
        // Build the alias table for (x, k) in scratch.
        const s = self.scratch;
        var n: usize = 0;
        var mx = -std.math.inf(f64);
        for (tab.pstart[x]..tab.pstart[x + 1]) |pi| {
            const t = tab.prodTerm(tab.prods[pi], k, tab.plw[pi]);
            if (t == -std.math.inf(f64)) continue;
            s.items[n] = @intCast(pi);
            s.w[n] = t;
            mx = @max(mx, t);
            n += 1;
        }
        if (n == 0) return error.ModelFailure;
        for (s.w[0..n]) |*w| w.* = @exp(w.* - mx);
        tablemod.buildAlias(s.w[0..n], s.prob[0..n], s.alias[0..n], s.small[0..n], s.large[0..n]);
        _ = tab.cache_builds.fetchAdd(1, .monotonic);
        if (tab.cache_enabled) self.publish(ci, n) else _ = tab.uncached.fetchAdd(1, .monotonic);
        return s.items[tablemod.drawAlias(self.rng, s.prob[0..n], s.alias[0..n])];
    }

    /// Copy the scratch alias table into the shared arena and publish its slot.
    fn publish(self: *Sampler, ci: u32, n: usize) void {
        const tab = self.tab;
        const need: u64 = 1 + 3 * @as(u64, n);
        var cur = tab.arena_top.load(.monotonic);
        while (true) {
            if (cur + need > tab.arena.len) {
                _ = tab.uncached.fetchAdd(1, .monotonic);
                return;
            }
            cur = tab.arena_top.cmpxchgWeak(cur, cur + need, .monotonic, .monotonic) orelse break;
        }
        const base: usize = @intCast(cur);
        const s = self.scratch;
        tab.arena[base] = @intCast(n);
        @memcpy(tab.arena[base + 1 .. base + 1 + n], s.items[0..n]);
        @memcpy(tab.arena[base + 1 + n .. base + 1 + 2 * n], @as([]const u32, @ptrCast(s.prob[0..n])));
        @memcpy(tab.arena[base + 1 + 2 * n .. base + 1 + 3 * n], s.alias[0..n]);
        if (tab.slots[ci].cmpxchgStrong(0, @intCast(base + 1), .release, .monotonic) != null) {
            _ = tab.wasted.fetchAdd(need, .monotonic);
        }
    }

    fn expand(self: *Sampler, x: u32, k: usize) SampleError!u8 {
        const tab = self.tab;
        const pi = try self.drawProd(x, k);
        const p = tab.prods[pi];
        const op: Op = @enumFromInt(p.op);
        const g = tab.grammar;
        switch (op) {
            .atom => return self.out.add(.{ .op = .atom, .atom = g.atoms[p.arg] }),
            .concat, .alt => {
                const k1 = try self.drawSplit(p.a, p.b, k);
                const a = try self.expand(p.a, k1);
                const b = try self.expand(p.b, k - 1 - k1);
                return self.out.add(.{ .op = op, .a = a, .b = b });
            },
            .quant => {
                const a = try self.expand(p.a, k - 1);
                return self.out.add(.{ .op = .quant, .quant = g.quants[p.arg], .a = a });
            },
            else => {
                const a = try self.expand(p.a, k - 1);
                return self.out.add(.{ .op = op, .a = a, .fmod = if (op == .flag_group) g.alt_mod else 0 });
            },
        }
    }

    /// Inversion over split terms W(Y, k1)·W(Z, k−1−k1), computed in log space.
    fn drawSplit(self: *Sampler, y: u32, z: u32, k: usize) SampleError!usize {
        const tab = self.tab;
        const my = tab.ms[y];
        const mz = tab.ms[z];
        const sp = self.scratch.split;
        var mx = -std.math.inf(f64);
        var k1: usize = my;
        while (k1 + mz + 1 <= k) : (k1 += 1) {
            sp[k1] = tab.logW(y, k1) + tab.logW(z, k - 1 - k1);
            mx = @max(mx, sp[k1]);
        }
        if (mx == -std.math.inf(f64)) return error.ModelFailure;
        var total: f64 = 0;
        k1 = my;
        while (k1 + mz + 1 <= k) : (k1 += 1) {
            sp[k1] = @exp(sp[k1] - mx);
            total += sp[k1];
        }
        var u = self.rng.float() * total;
        k1 = my;
        var last: usize = my;
        while (k1 + mz + 1 <= k) : (k1 += 1) {
            if (sp[k1] > 0) last = k1;
            if (u < sp[k1]) return k1;
            u -= sp[k1];
        }
        return last;
    }
};

// ---------------------------------------------------------------------------
// Printer

pub const PrintError = error{ OutOfMemory, PatternTooLong };

const Prec = enum(u8) { alt = 0, concat = 1, quant_body = 2 };

const dialect = @import("dialect.zig");

/// Config [grammar] duplicate_names (set at startup): off for engines that reject a repeated name.
pub var allow_duplicate_names: bool = true;
/// Config [grammar] extended_mode (set at startup).
pub var allow_extended: bool = true;

pub const Printer = struct {
    flags: Flags,
    out: *std.ArrayList(u8),
    gpa: Allocator,
    group_counter: u32 = 0,
    /// Capture groups printed so far (tree captures and `()` empty-atom spellings), and the
    /// printed group number of each tree capture in opening-parenthesis order.
    printed_groups: u8 = 0,
    tree_groups: [ast.max_caps]u8 = undefined,
    n_tree_groups: u8 = 0,
    limit: usize = std.math.maxInt(usize),
    /// Spelling seed for empty atoms: 0 always prints `(?:)`; otherwise each empty atom
    /// picks `(?:)`, nothing (where the syntax allows) or `()` from (spell, ordinal).
    spell: u64 = 0,
    empty_ordinal: u32 = 0,
    /// Ordinal of the next spelling choice (rust_spellings).
    pick_ordinal: u32 = 0,
    /// Duplicate named groups (ES2025): alias[i] = the named-group node whose name node i
    /// reuses (none = 255); name_num[i] = the printed number naming node i.
    alias: [ast.max_nodes]u8 = undefined,
    name_num: [ast.max_nodes]u8 = undefined,
    /// Per tree capture (opening order): the printed name number if it is a named group, else 0.
    named_target: [ast.max_caps]u8 = [_]u8{0} ** ast.max_caps,
    /// Extended mode: the pattern is printed inside (?x:…) with spaces and # comments between
    /// concatenated items (space and # literals escaped).
    xmode: bool = false,
    x_ordinal: u32 = 0,
    /// The atom being printed sits directly in an alternative or group body, where an
    /// empty atom may print as nothing.
    bare_ok: bool = false,
    /// Inside lookarounds of a dialect without bare empties there (bare_empty_in_lookaround).
    no_bare_depth: u8 = 0,
    /// Lookbehind nesting depth (Oniguruma/Onigmo reject captures there, so no `()` spelling).
    lb_depth: u8 = 0,

    /// One of `n` equivalent spellings, from (spell, ordinal); 0 when spell is 0.
    fn pick(self: *Printer, n: u64) u64 {
        if (self.spell == 0 or n <= 1) return 0;
        self.pick_ordinal += 1;
        var x = self.spell +% @as(u64, self.pick_ordinal) *% 0x9E3779B97F4A7C15;
        x ^= x >> 31;
        x *%= 0xBF58476D1CE4E5B9;
        x ^= x >> 29;
        return x % n;
    }

    fn put(self: *Printer, s: []const u8) PrintError!void {
        if (self.out.items.len + s.len > self.limit) return error.PatternTooLong;
        try self.out.appendSlice(self.gpa, s);
    }
    fn putc(self: *Printer, c: u8) PrintError!void {
        if (self.out.items.len + 1 > self.limit) return error.PatternTooLong;
        try self.out.append(self.gpa, c);
    }
    fn fmt(self: *Printer, comptime f: []const u8, args: anytype) PrintError!void {
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, f, args) catch unreachable;
        try self.put(s);
    }

    pub fn print(self: *Printer, t: *const ast.Ast) PrintError!void {
        @memset(self.alias[0..t.len], 255);
        // A quarter of patterns (by spelling seed) let groups in different alternatives share a name.
        if (dialect.active.duplicate_names and allow_duplicate_names and self.spell != 0 and (self.spell >> 13) % 4 == 0)
            planAliases(t, &self.alias);
        // A quarter of patterns (by spelling seed) are printed in extended mode.
        self.xmode = dialect.active.extended_mode and allow_extended and self.spell != 0 and (self.spell >> 17) % 4 == 0;
        if (self.xmode) try self.put("(?x:");
        try self.node(t, t.root, .alt);
        if (self.xmode) try self.putc(')');
    }

    /// First named group (in printing order) in the subtree, or 255.
    fn firstNamed(t: *const ast.Ast, idx: u8) u8 {
        const n = t.nodes[idx];
        if (n.op == .group_named) return idx;
        if (n.op.isLeaf()) return 255;
        const l = firstNamed(t, n.a);
        if (l != 255 or !n.op.isBinary()) return l;
        return firstNamed(t, n.b);
    }

    /// For each alternation, the first named group on its right may take the name of the first
    /// on its left. A name is shared by at most two groups and an aliased group is never a target,
    /// so the two always sit in different alternatives (the ES2025 rule).
    fn planAliases(t: *const ast.Ast, alias: *[ast.max_nodes]u8) void {
        var target_used: [ast.max_nodes]bool = undefined;
        @memset(target_used[0..t.len], false);
        for (t.nodes[0..t.len]) |n| {
            if (n.op != .alt) continue;
            const i = firstNamed(t, n.a);
            const j = firstNamed(t, n.b);
            if (i == 255 or j == 255 or alias[i] != 255 or alias[j] != 255 or target_used[i] or target_used[j]) continue;
            alias[j] = i;
            target_used[i] = true;
        }
    }

    fn isQuantAtom(t: *const ast.Ast, idx: u8) bool {
        const n = t.nodes[idx];
        return switch (n.op) {
            .atom => n.atom.isConsuming() or n.atom.kind == .empty,
            .group_cap, .group_nc, .group_named, .flag_group, .atomic, .backref => true,
            else => false,
        };
    }

    fn noteTreeGroup(self: *Printer) void {
        self.printed_groups +|= 1;
        if (self.n_tree_groups < ast.max_caps) {
            self.tree_groups[self.n_tree_groups] = self.printed_groups;
            self.n_tree_groups += 1;
        }
    }

    /// Print a child where a bare empty atom is syntactically fine (alternative or group body).
    fn bareChild(self: *Printer, t: *const ast.Ast, idx: u8) PrintError!void {
        self.bare_ok = true;
        defer self.bare_ok = false;
        try self.node(t, idx, .alt);
    }

    fn emptyAtom(self: *Printer) PrintError!void {
        const bare = self.bare_ok and self.no_bare_depth == 0;
        self.bare_ok = false;
        if (self.spell == 0) return self.put("(?:)");
        var x = self.spell +% @as(u64, self.empty_ordinal) *% 0x9E3779B97F4A7C15;
        self.empty_ordinal += 1;
        x = (x ^ (x >> 30)) *% 0xBF58476D1CE4E5B9;
        x = (x ^ (x >> 27)) *% 0x94D049BB133111EB;
        x ^= x >> 31;
        switch (x % 3) {
            1 => if (bare and dialect.active.bare_empty) return,
            2 => if (dialect.active.empty_capture and !(self.lb_depth > 0 and dialect.active.lookbehind_onig)) {
                self.printed_groups +|= 1;
                return self.put("()");
            },
            else => {},
        }
        try self.put("(?:)");
    }

    fn node(self: *Printer, t: *const ast.Ast, idx: u8, prec: Prec) PrintError!void {
        const n = t.nodes[idx];
        if (n.op != .atom) self.bare_ok = false;
        switch (n.op) {
            .atom => {
                // Assertions as quantifier bodies are wrapped by the caller.
                if (n.atom.kind == .empty) return self.emptyAtom();
                self.bare_ok = false;
                try self.atom(&n.atom);
            },
            .alt => {
                const wrap = @intFromEnum(prec) > @intFromEnum(Prec.alt);
                if (wrap) try self.put("(?:");
                try self.bareChild(t, n.a);
                try self.putc('|');
                try self.bareChild(t, n.b);
                if (wrap) try self.putc(')');
            },
            .concat => {
                const wrap = @intFromEnum(prec) > @intFromEnum(Prec.concat);
                if (wrap) try self.put("(?:");
                try self.node(t, n.a, .concat);
                if (self.xmode) {
                    // Ignored whitespace, sometimes a comment running to the end of the line.
                    self.x_ordinal += 1;
                    try self.put(if (((self.spell >> 20) +% self.x_ordinal *% 7) % 5 == 0) " # c\n " else " ");
                }
                try self.node(t, n.b, .concat);
                if (wrap) try self.putc(')');
            },
            .quant => {
                const wrap = prec == .quant_body;
                if (wrap) try self.put("(?:");
                if (isQuantAtom(t, n.a)) {
                    try self.node(t, n.a, .quant_body);
                } else {
                    try self.put("(?:");
                    try self.node(t, n.a, .alt);
                    try self.putc(')');
                }
                const q = n.quant;
                switch (q.form) {
                    .star => try self.putc('*'),
                    .plus => try self.putc('+'),
                    .opt => try self.putc('?'),
                    .range => try self.fmt("{{{d},{d}}}", .{ q.min, q.max }),
                    .open => try self.fmt("{{{d},}}", .{q.min}),
                    .exact => try self.fmt("{{{d}}}", .{q.min}),
                }
                // Ruby syntax reads `{n}?` as optional; a lazy exact count equals the greedy one.
                if (q.lazy and !(q.form == .exact and dialect.active.lazy_exact_is_optional)) try self.putc('?');
                if (wrap) try self.putc(')');
            },
            .look_ahead, .neg_look_ahead, .look_behind, .neg_look_behind => {
                const wrap = prec == .quant_body;
                if (wrap) try self.put("(?:");
                try self.put(switch (n.op) {
                    .look_ahead => "(?=",
                    .neg_look_ahead => "(?!",
                    .look_behind => "(?<=",
                    else => "(?<!",
                });
                const lb = n.op == .look_behind or n.op == .neg_look_behind;
                if (lb) self.lb_depth += 1;
                defer if (lb) {
                    self.lb_depth -= 1;
                };
                const nb = !dialect.active.bare_empty_in_lookaround;
                if (nb) self.no_bare_depth += 1;
                defer if (nb) {
                    self.no_bare_depth -= 1;
                };
                try self.bareChild(t, n.a);
                try self.putc(')');
                if (wrap) try self.putc(')');
            },
            .group_cap => {
                self.noteTreeGroup();
                try self.putc('(');
                try self.bareChild(t, n.a);
                try self.putc(')');
            },
            .group_nc => {
                try self.put("(?:");
                try self.bareChild(t, n.a);
                try self.putc(')');
            },
            .flag_group => {
                // Toggles one flag relative to the pattern's flags (flag groups do not nest).
                const on = if (n.fmod & ast.fmod_i != 0) self.flags.i else if (n.fmod & ast.fmod_s != 0) self.flags.s else if (n.fmod & ast.fmod_m != 0) self.flags.m else false;
                const letter: u8 = if (n.fmod & ast.fmod_i != 0) 'i' else if (n.fmod & ast.fmod_s != 0) dialect.active.dotall_letter else if (n.fmod & ast.fmod_m != 0) 'm' else if (n.fmod & ast.fmod_crlf != 0) 'R' else 'U';
                try self.put(if (on) "(?-" else "(?");
                try self.putc(letter);
                try self.putc(':');
                try self.bareChild(t, n.a);
                try self.putc(')');
            },
            .group_named => {
                // Named after the printed group number, so hosts that number named groups
                // separately (.NET) can put them back in opening-parenthesis order.
                self.noteTreeGroup();
                self.name_num[idx] = if (self.alias[idx] != 255) self.name_num[self.alias[idx]] else self.printed_groups;
                if (self.n_tree_groups > 0) self.named_target[self.n_tree_groups - 1] = self.name_num[idx];
                const ng = if (dialect.active.rust_spellings and self.pick(2) == 1) dialect.NamedGroup.p_angle else dialect.active.named_group;
                switch (ng) {
                    .angle => try self.fmt("(?<g{d}>", .{self.name_num[idx]}),
                    .p_angle => try self.fmt("(?P<g{d}>", .{self.name_num[idx]}),
                    .plain_capture => try self.putc('('),
                }
                self.group_counter += 1;
                try self.bareChild(t, n.a);
                try self.putc(')');
            },
            .atomic => {
                // Possessive spelling (x*+) for an atomic greedy loop where the dialect has it and
                // the result is not itself quantified (x*+* would not parse); else (?>…).
                const ch = t.nodes[n.a];
                const counted = ch.op == .quant and (ch.quant.form == .range or ch.quant.form == .open or ch.quant.form == .exact);
                if (dialect.active.possessive and prec != .quant_body and ch.op == .quant and !ch.quant.lazy and isQuantAtom(t, ch.a) and (!counted or dialect.active.possessive_counted)) {
                    try self.node(t, n.a, .concat);
                    try self.putc('+');
                } else if (ch.op == .atom and ch.atom.kind == .empty) {
                    try self.put("(?>(?:))"); // some engines reject an empty atomic group
                } else {
                    try self.put("(?>");
                    try self.bareChild(t, n.a);
                    try self.putc(')');
                }
            },
            .backref => {
                // By the printed number of the target group (printed earlier: mutation only refers
                // back); wrapped so a following digit cannot extend the number.
                const num: u8 = if (n.fmod < self.n_tree_groups) self.tree_groups[n.fmod] else 0;
                const named = if (n.fmod < self.n_tree_groups) self.named_target[n.fmod] else 0;
                if (num == 0) {
                    try self.put("(?:)");
                } else if (dialect.active.backref_by_name and named != 0) {
                    try self.fmt("(?:\\k<g{d}>)", .{named});
                } else try self.fmt("(?:\\{d})", .{num});
            },
        }
    }

    fn escapedCodePoint(self: *Printer, c: u21) PrintError!void {
        if (dialect.active.rust_spellings) {
            // Raw characters: x mode ignores whitespace, and a control character stays escaped.
            const ws = c == 0xA0 or c == 0x1680 or (c >= 0x2000 and c <= 0x200A) or c == 0x2028 or c == 0x2029 or c == 0x202F or c == 0x205F or c == 0x3000;
            const raw_ok = c > 0x9F and !(self.xmode and ws);
            const forms = [_]bool{ true, c <= 0xFF, true, c <= 0xFFFF, true, raw_ok };
            var ok: [forms.len]u8 = undefined;
            var k: usize = 0;
            for (forms, 0..) |f, j| if (f) {
                ok[k] = @intCast(j);
                k += 1;
            };
            switch (ok[self.pick(k)]) {
                0 => try self.fmt("\\x{{{X}}}", .{c}),
                1 => try self.fmt("\\x{X:0>2}", .{c}),
                2 => try self.fmt("\\u{{{X}}}", .{c}),
                3 => try self.fmt("\\u{X:0>4}", .{c}),
                4 => try self.fmt("\\U{X:0>8}", .{c}),
                else => {
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(c, &buf) catch unreachable;
                    try self.put(buf[0..len]);
                },
            }
            return;
        }
        if (dialect.active.escape == .x_brace) {
            try self.fmt("\\x{{{X}}}", .{c});
        } else if (self.flags.unicode()) {
            try self.fmt("\\u{{{X}}}", .{c});
        } else {
            std.debug.assert(c <= 0xFFFF);
            try self.fmt("\\u{X:0>4}", .{c});
        }
    }

    fn isPrintableAscii(c: u21) bool {
        return c >= 0x20 and c <= 0x7E;
    }

    /// Literal outside classes.
    pub fn literal(self: *Printer, c: u21) PrintError!void {
        if (!isPrintableAscii(c) or self.extraMeta(c) or (self.xmode and (c == ' ' or c == '#'))) return self.escapedCodePoint(c);
        const b: u8 = @intCast(c);
        if (std.mem.indexOfScalar(u8, "^$\\.*+?()[]{}|/", b) != null) try self.putc('\\');
        try self.putc(b);
    }

    fn extraMeta(_: *Printer, c: u21) bool {
        return c < 0x80 and std.mem.indexOfScalar(u8, dialect.active.extra_meta, @intCast(c)) != null;
    }

    /// Literal inside a class, per mode.
    pub fn classLiteral(self: *Printer, c: u21) PrintError!void {
        if (!isPrintableAscii(c) or self.extraMeta(c) or (self.xmode and (c == ' ' or c == '#'))) return self.escapedCodePoint(c);
        const b: u8 = @intCast(c);
        const needs = if (self.flags.v)
            // ClassSetSyntaxCharacter, ClassSetReservedPunctuator, and the remaining
            // SyntaxCharacters: escaping all of them is valid and avoids doubled punctuators.
            std.mem.indexOfScalar(u8, "()[]{}/-\\|&!#%,:;<=>@`~^$.*+?", b) != null
        else if (dialect.active.class_set_ops)
            // Rust: [ opens a nested class, && and ~~ are operators.
            std.mem.indexOfScalar(u8, "\\[]-^&~", b) != null
        else
            std.mem.indexOfScalar(u8, "\\]-^", b) != null;
        if (needs) try self.putc('\\');
        try self.putc(b);
    }

    fn escName(e: atoms.Esc) []const u8 {
        return switch (e) {
            .d => "\\d",
            .D => "\\D",
            .w => "\\w",
            .W => "\\W",
            .s => "\\s",
            .S => "\\S",
            .h => "\\h",
            .H => "\\H",
            .v => "\\v",
            .V => "\\V",
        };
    }

    fn operand(self: *Printer, o: *const atoms.Operand) PrintError!void {
        switch (o.kind) {
            .esc => try self.put(escName(o.esc)),
            .range => {
                try self.putc('[');
                try self.classLiteral(o.syms[0]);
                try self.putc('-');
                try self.classLiteral(o.syms[1]);
                try self.putc(']');
            },
            .char => try self.classLiteral(o.syms[0]),
            .qstr => {
                try self.put("\\q{");
                for (o.syms[0..o.n], 0..) |c, k| {
                    if (k > 0) try self.putc('|');
                    try self.classLiteral(c);
                }
                try self.putc('}');
            },
            .prop => {
                try self.put("\\p{");
                try self.put(@tagName(@as(atoms.Prop, @enumFromInt(o.syms[0]))));
                try self.putc('}');
            },
            .list, .neglist => {
                try self.putc('[');
                if (o.kind == .neglist) try self.putc('^');
                for (o.syms[0..o.n]) |c| try self.classLiteral(c);
                try self.putc(']');
            },
        }
    }

    fn propLong(p: atoms.Prop) []const u8 {
        return switch (p) {
            .L => "Letter",
            .Lu => "Uppercase_Letter",
            .Ll => "Lowercase_Letter",
            .N => "Number",
            .Nd => "Decimal_Number",
            .P => "Punctuation",
            .Pc => "Connector_Punctuation",
            .Pd => "Dash_Punctuation",
            .Po => "Other_Punctuation",
            .S => "Symbol",
            .So => "Other_Symbol",
            .Z => "Separator",
            .Zs => "Space_Separator",
            .Zl => "Line_Separator",
            .C => "Other",
            .Cc => "Control",
        };
    }

    /// \p{X} / \P{X}, or (rust_spellings) one of Rust's equivalent forms.
    fn property(self: *Printer, p: atoms.Prop, neg: bool) PrintError!void {
        const short = @tagName(p);
        const form = if (dialect.active.rust_spellings) self.pick(8) else 0;
        if (form == 7 and neg) return self.fmt("\\p{{gc!={s}}}", .{short});
        const pre = if (neg) "\\P" else "\\p";
        switch (form) {
            1 => if (short.len == 1) return self.fmt("{s}{s}", .{ pre, short }),
            2 => return self.fmt("{s}{{{s}}}", .{ pre, propLong(p) }),
            3 => return self.fmt("{s}{{gc={s}}}", .{ pre, short }),
            4 => return self.fmt("{s}{{gc:{s}}}", .{ pre, short }),
            5 => return self.fmt("{s}{{General_Category={s}}}", .{ pre, propLong(p) }),
            6 => {
                // Loose matching: case, spaces and underscores are ignored.
                try self.put(pre);
                try self.putc('{');
                for (propLong(p)) |ch| try self.putc(if (ch == '_') ' ' else std.ascii.toLower(ch));
                return self.putc('}');
            },
            else => {},
        }
        return self.fmt("{s}{{{s}}}", .{ pre, short });
    }

    pub fn atom(self: *Printer, a: *const AtomSpec) PrintError!void {
        switch (a.kind) {
            .lit => try self.literal(a.syms[0]),
            .dot => try self.putc('.'),
            .esc => try self.put(escName(@enumFromInt(a.sub))),
            .range => {
                try self.putc('[');
                if (a.neg) try self.putc('^');
                try self.classLiteral(a.syms[0]);
                try self.putc('-');
                try self.classLiteral(a.syms[1]);
                try self.putc(']');
            },
            .cls => {
                try self.putc('[');
                if (a.neg) try self.putc('^');
                for (a.syms[0..a.n]) |c| try self.classLiteral(c);
                try self.putc(']');
            },
            .vset => {
                try self.putc('[');
                if (a.neg) try self.putc('^');
                try self.operand(&atoms.v_operands[a.syms[0]]);
                switch (@as(atoms.VOp, @enumFromInt(a.sub))) {
                    .sub => try self.put("--"),
                    .inter => try self.put("&&"),
                    .sym => try self.put("~~"),
                    .uni => {},
                }
                try self.operand(&atoms.v_operands[a.syms[1]]);
                try self.putc(']');
            },
            .grapheme => try self.put("\\X"),
            .strs => {
                // [\q{ab|c}]: a class whose alternatives are strings (ES v mode).
                try self.put("[\\q{");
                const l1: usize = a.n & 0xF;
                const l2: usize = a.n >> 4;
                for (a.syms[0..l1]) |c| try self.classLiteral(c);
                if (l2 > 0) {
                    try self.putc('|');
                    for (a.syms[l1 .. l1 + l2]) |c| try self.classLiteral(c);
                }
                try self.put("}]");
            },
            .caret => try self.put(if (a.sub == 1) "\\A" else "^"),
            .dollar => try self.put(if (a.sub == 1) "\\z" else "$"),
            .posix => {
                try self.put(if (a.neg) "[[:^" else "[[:");
                try self.put(@tagName(@as(atoms.Posix, @enumFromInt(a.sub))));
                try self.put(":]]");
            },
            .wordb => try self.put(switch (@as(atoms.WordbVariant, @enumFromInt(a.sub))) {
                .plain => dialect.active.word_boundary,
                .start => "\\b{start}",
                .end => "\\b{end}",
                .start_half => "\\b{start-half}",
                .end_half => "\\b{end-half}",
                .lt => "\\<",
                .gt => "\\>",
            }),
            .nwordb => try self.put(dialect.active.nonword_boundary),
            .empty => try self.put("(?:)"),
            .prop => try self.property(@enumFromInt(a.sub), a.neg),
        }
    }
};

pub fn printAlloc(gpa: Allocator, t: *const ast.Ast, flags: Flags, out: *std.ArrayList(u8)) PrintError!void {
    var p: Printer = .{ .flags = flags, .out = out, .gpa = gpa };
    try p.print(t);
}

/// Conservative printed-length bound for any tree of `max_size` nodes in a
/// grammar: every node is charged the longest atom plus the longest wrapper.
pub fn printedLengthBound(gpa: Allocator, g: *const tablemod.Grammar, max_size: usize) !u64 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    var max_atom: usize = 0;
    for (g.atoms) |*a| {
        buf.clearRetainingCapacity();
        var p: Printer = .{ .flags = g.flags, .out = &buf, .gpa = gpa };
        try p.atom(a);
        max_atom = @max(max_atom, buf.items.len);
    }
    // Wrappers: quant "(?:(?:" + ")" + "{255,255}?" + ")" ; named group "(?<g4294967295>" + ")";
    // lookaround "(?:(?<!" + "))"; alternation "(?:" + "|" + ")".
    const per_node: u64 = @max(@as(u64, 6 + 1 + 10 + 1), @max(@as(u64, 15 + 1), @as(u64, 7 + 2)));
    return @as(u64, max_size) * (@as(u64, max_atom) + per_node + 4);
}

// ---------------------------------------------------------------------------
// Tests

const testing = std.testing;
const ucd = @import("ucd.zig");
const config = @import("config.zig");
const Budget = @import("budget.zig").Budget;

fn lit(c: u21) ast.Node {
    return .{ .op = .atom, .atom = .{ .kind = .lit, .syms = .{ c, 0, 0, 0 } } };
}

test "printer precedence and wrapping" {
    ucd.init();
    const gpa = testing.allocator;
    var t: ast.Ast = .{};
    const a = try t.add(lit('a'));
    const b = try t.add(lit('b'));
    const alt = try t.add(.{ .op = .alt, .a = a, .b = b });
    const q = try t.add(.{ .op = .quant, .quant = .{ .form = .plus, .min = 1, .max = ast.inf }, .a = alt });
    const q2 = try t.add(.{ .op = .quant, .quant = .{ .form = .opt, .min = 0, .max = 1, .lazy = true }, .a = q });
    const caret = try t.add(.{ .op = .atom, .atom = .{ .kind = .caret } });
    const q3 = try t.add(.{ .op = .quant, .quant = .{ .form = .range, .min = 0, .max = 2 }, .a = caret });
    const la = try t.add(.{ .op = .look_ahead, .a = a });
    const q4 = try t.add(.{ .op = .quant, .quant = .{ .form = .star, .min = 0, .max = ast.inf }, .a = la });
    const c1 = try t.add(.{ .op = .concat, .a = q2, .b = q3 });
    const c2 = try t.add(.{ .op = .concat, .a = c1, .b = q4 });
    const alt2 = try t.add(.{ .op = .alt, .a = c2, .b = b });
    t.root = try t.add(.{ .op = .concat, .a = alt2, .b = a });
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try printAlloc(gpa, &t, .{}, &out);
    try testing.expectEqualStrings("(?:(?:(?:a|b)+)??(?:^){0,2}(?:(?=a))*|b)a", out.items);
}

test "literal escaping per mode" {
    ucd.init();
    const gpa = testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    var p: Printer = .{ .flags = .{}, .out = &out, .gpa = gpa };
    for ([_]u21{ '.', '\n', 0x212A, 0xD83D, 0xDE00, ' ', '/' }) |c| try p.literal(c);
    try testing.expectEqualStrings("\\.\\u000A\\u212A\\uD83D\\uDE00 \\/", out.items);
    out.clearRetainingCapacity();
    p.flags = .{ .u = true };
    for ([_]u21{ alpha.astral_char, 0xD83D, '\n' }) |c| try p.literal(c);
    try testing.expectEqualStrings("\\u{1F600}\\u{D83D}\\u{A}", out.items);
    out.clearRetainingCapacity();
    p.flags = .{ .v = true };
    const vs: AtomSpec = .{ .kind = .vset, .sub = @intFromEnum(atoms.VOp.sub), .neg = true, .syms = .{ 0, 15, 0, 0 } };
    try p.atom(&vs);
    try testing.expectEqualStrings("[^\\w--[\\u{1F600}a]]", out.items);
}

const TreeEnum = struct {
    const Entry = struct { text: []const u8, w: f64, start: bool };

    fn enumerate(gpa: Allocator, g: *const tablemod.Grammar, k: usize, a: []const u21, r: []const u21, out: *std.ArrayList(Entry)) !void {
        // enumerate all ASTs of size k and print them
        var trees: std.ArrayList(ast.Ast) = .empty;
        defer trees.deinit(gpa);
        var weights: std.ArrayList(f64) = .empty;
        defer weights.deinit(gpa);
        try gen(gpa, g, k, &trees, &weights);
        for (trees.items, weights.items) |*t, w| {
            var buf: std.ArrayList(u8) = .empty;
            try printAlloc(gpa, t, g.flags, &buf);
            const ra = ast.evalRel(@import("rel.zig").Rel16, t, t.root, g.flags, a);
            const rr = ast.evalRel(@import("rel.zig").Rel16, t, t.root, g.flags, r);
            try out.append(gpa, .{ .text = buf.items, .w = w, .start = ra.get(0, a.len) and !rr.get(0, r.len) });
        }
    }

    fn gen(gpa: Allocator, g: *const tablemod.Grammar, k: usize, trees: *std.ArrayList(ast.Ast), weights: *std.ArrayList(f64)) !void {
        if (k == 1) {
            for (g.atoms, 0..) |a, i| {
                if (g.atom_w[i] <= 0) continue;
                var t: ast.Ast = .{};
                t.root = try t.add(.{ .op = .atom, .atom = a });
                try trees.append(gpa, t);
                try weights.append(gpa, g.atom_w[i]);
            }
            return;
        }
        var sub: std.ArrayList(ast.Ast) = .empty;
        defer sub.deinit(gpa);
        var subw: std.ArrayList(f64) = .empty;
        defer subw.deinit(gpa);
        try gen(gpa, g, k - 1, &sub, &subw);
        for (sub.items, subw.items) |*s, w| for (g.unary) |u| {
            var t = s.*;
            if (u.op == .quant) {
                t.root = try t.add(.{ .op = .quant, .quant = g.quants[u.arg], .a = s.root });
            } else t.root = try t.add(.{ .op = u.op, .a = s.root });
            try trees.append(gpa, t);
            try weights.append(gpa, w * u.w);
        };
        for (1..k - 1) |k1| {
            var ys: std.ArrayList(ast.Ast) = .empty;
            defer ys.deinit(gpa);
            var yw: std.ArrayList(f64) = .empty;
            defer yw.deinit(gpa);
            var zs: std.ArrayList(ast.Ast) = .empty;
            defer zs.deinit(gpa);
            var zw: std.ArrayList(f64) = .empty;
            defer zw.deinit(gpa);
            try gen(gpa, g, k1, &ys, &yw);
            try gen(gpa, g, k - 1 - k1, &zs, &zw);
            for (ys.items, yw.items) |*y, wy| for (zs.items, zw.items) |*z, wz| for (g.binary) |b| {
                var t: ast.Ast = .{};
                const ya = try copySub(&t, y, y.root);
                const za = try copySub(&t, z, z.root);
                t.root = try t.add(.{ .op = b.op, .a = ya, .b = za });
                try trees.append(gpa, t);
                try weights.append(gpa, wy * wz * b.w);
            };
        }
    }

    fn copySub(dst: *ast.Ast, src: *const ast.Ast, idx: u8) !u8 {
        var n = src.nodes[idx];
        switch (n.op) {
            .atom, .backref => {},
            .concat, .alt => {
                n.a = try copySub(dst, src, n.a);
                n.b = try copySub(dst, src, n.b);
            },
            else => n.a = try copySub(dst, src, n.a),
        }
        return dst.add(n);
    }
};

test "sampling frequencies match exact tree probabilities" {
    ucd.init();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var cfg: config.Config = .{};
    cfg.max_size = 4;
    @memset(&cfg.size_weights, 0);
    cfg.size_weights[4] = 1;
    cfg.allow_diagonal_lookarounds = true;
    for ([_]bool{ false, true }) |cache| {
        cfg.alias_cache = cache;
        // small explicit grammar with skewed weights
        var atomsl = [_]AtomSpec{
            .{ .kind = .lit, .syms = .{ 'a', 0, 0, 0 } },
            .{ .kind = .lit, .syms = .{ 'b', 0, 0, 0 } },
            .{ .kind = .dot },
            .{ .kind = .wordb },
        };
        var aw = [_]f64{ 1.0, 0.3, 2.0, 0.5 };
        var qs = [_]ast.QuantSpec{.{ .form = .star, .min = 0, .max = ast.inf }};
        var un = [_]tablemod.UnaryEntry{ .{ .op = .quant, .arg = 0, .w = 2.0 }, .{ .op = .neg_look_ahead, .arg = 0, .w = 0.7 } };
        var bin = [_]tablemod.BinaryEntry{ .{ .op = .concat, .w = 1.0 }, .{ .op = .alt, .w = 0.25 } };
        var g: tablemod.Grammar = .{ .flags = .{}, .atoms = &atomsl, .atom_w = &aw, .quants = &qs, .unary = &un, .binary = &bin, .allow_diagonal_lookarounds = true, .quant_w = &.{}, .op_w = undefined };
        try g.indexWeights(gpa);
        var host = Budget.init("host", 1 << 30, null);
        const a16 = [_]u16{ 'a', 'b' };
        const r16 = [_]u16{'b'};
        const tab = try tablemod.build(.{ .grammar = &g, .cfg = &cfg, .a16 = &a16, .r16 = &r16, .id = .{ .seq = 0, .attempt = 0, .seed = 5, .flags = .{} }, .host = &host, .host_alloc = testing.allocator });
        defer tab.release();

        var exact: std.ArrayList(TreeEnum.Entry) = .empty;
        try TreeEnum.enumerate(gpa, &g, 4, &.{ 'a', 'b' }, &.{'b'}, &exact);
        var Z: f64 = 0;
        var map = std.StringHashMap(f64).init(gpa);
        for (exact.items) |e| if (e.start) {
            Z += e.w;
            const gop = try map.getOrPut(e.text);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += e.w;
        };
        try testing.expect(Z > 0);

        var scratch: Scratch = .{};
        try scratch.ensure(gpa, tab.max_prods_per_pair, tab.max_size);
        var counts = std.StringHashMap(u32).init(gpa);
        const N: usize = 60_000;
        var rng = rngmod.Rng.fromParts(11, &.{});
        for (0..N) |_| {
            var t: ast.Ast = .{};
            var s: Sampler = .{ .tab = tab, .scratch = &scratch, .rng = &rng, .out = &t };
            const k = try s.sample();
            try testing.expectEqual(@as(usize, 4), k);
            try testing.expect(ast.oracle(&t, .{}, &a16).? and !ast.oracle(&t, .{}, &r16).?);
            var buf: std.ArrayList(u8) = .empty;
            try printAlloc(gpa, &t, .{}, &buf);
            const gop = try counts.getOrPut(buf.items);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += 1;
        }
        // every sampled tree must be a valid start tree; frequencies within 5 sigma
        var it = counts.iterator();
        while (it.next()) |e| try testing.expect(map.contains(e.key_ptr.*));
        var mit = map.iterator();
        var max_z: f64 = 0;
        while (mit.next()) |e| {
            const p = e.value_ptr.* / Z;
            const expected = p * @as(f64, @floatFromInt(N));
            const got: f64 = @floatFromInt(counts.get(e.key_ptr.*) orelse 0);
            const sd = @sqrt(@as(f64, @floatFromInt(N)) * p * (1 - p)) + 1e-9;
            max_z = @max(max_z, @abs(got - expected) / sd);
        }
        try testing.expect(max_z < 5.5);
        if (cache) try testing.expect(tab.cache_hits.load(.monotonic) > 0);
    }
}
