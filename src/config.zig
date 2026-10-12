//! Configuration: defaults, a minimal TOML reader (sections, scalars, flat
//! arrays), validation, and JSON serialization of the resolved config for
//! run manifests.
const std = @import("std");
const alpha = @import("alphabet.zig");
const ast = @import("ast.zig");

pub const n_constructs = ast.n_constructs;
pub const Construct = ast.Construct;

pub const Weights = struct {
    // Inline flag groups are off unless a config weights them (they add a second atom context).
    w: [n_constructs]f64 = blk: {
        var a = [_]f64{1.0} ** n_constructs;
        a[@intFromEnum(Construct.flag_group)] = 0;
        break :blk a;
    },

    pub fn get(self: *const Weights, c: Construct) f64 {
        return self.w[@intFromEnum(c)];
    }
    pub fn set(self: *Weights, c: Construct, v: f64) void {
        self.w[@intFromEnum(c)] = v;
    }
    /// Defaults favour concatenation/alternation over unary chains so that
    /// deeply nested quantifiers (catastrophic backtracking, i.e. timeouts
    /// rather than semantic coverage) stay rare. Tune per campaign.
    pub fn defaults() Weights {
        var w: Weights = .{};
        const vals = [_]struct { c: Construct, v: f64 }{
            .{ .c = .dot, .v = 0.7 },     .{ .c = .empty, .v = 0.2 },
            .{ .c = .concat, .v = 4.0 },  .{ .c = .alt, .v = 1.5 },
            .{ .c = .star, .v = 0.25 },   .{ .c = .plus, .v = 0.2 },
            .{ .c = .opt, .v = 0.2 },     .{ .c = .rep, .v = 0.15 },
            .{ .c = .rep_open, .v = 0.08 }, .{ .c = .rep_exact, .v = 0.08 },
            .{ .c = .lazy, .v = 0.5 },    .{ .c = .lookahead, .v = 0.4 },
            .{ .c = .neg_lookahead, .v = 0.4 }, .{ .c = .lookbehind, .v = 0.4 },
            .{ .c = .neg_lookbehind, .v = 0.4 }, .{ .c = .group, .v = 0.05 },
            .{ .c = .nc_group, .v = 0.05 }, .{ .c = .named_group, .v = 0.03 },
        };
        for (vals) |x| w.set(x.c, x.v);
        return w;
    }
};

pub const max_size_cap = 255;

pub const SpanUnits = enum { utf16, cp, utf8 };
pub const CaptureLoop = enum { keep, reset, unmodeled };

pub const Config = struct {
    // [grammar]
    max_size: u8 = 24,
    max_rep_bound: u8 = 3,
    /// Fraction of tables drawn from an alternate character pool (alphabet.alt_pools).
    pool_rotation: f64 = 0,
    /// Duplicate named groups where the dialect allows them (off for engines that reject them).
    duplicate_names: bool = true,
    /// Mutation mode: share of cases given an atomic group, possessive loop or backreference
    /// (where the dialect has them), checked against the backtracking matcher.
    mutate_rate: f64 = 0,
    /// Extended-mode spellings where the dialect supports (?x:…).
    extended_mode: bool = true,
    /// Large repeat bounds N added as {0,N}, {1,N}, {N,} and {N} (and lazy forms), each at
    /// `big_rep_weight` times a small bound's weight. Only applied to a single consuming atom
    /// (so a large count never means exponential backtracking or an oversized compiled program).
    big_rep_bounds: [8]u8 = .{ 16, 100, 254, 0, 0, 0, 0, 0 },
    n_big_rep_bounds: u8 = 3,
    big_rep_weight: f64 = 4.0,
    class_max_members: u8 = 2,
    max_pattern_bytes: u32 = 16 * 1024,
    allow_diagonal_lookarounds: bool = false,
    usefulness_pass: bool = true,
    usefulness_workspace: u64 = 1 << 24,

    // [strings]
    min_len: u8 = 1,
    max_len: u8 = 8,
    max_symbols: u8 = 31,
    /// Fraction of draws using the long length range [long_min, long_max].
    long_fraction: f64 = 0.25,
    long_min: u8 = 10,
    long_max: u8 = 30,
    /// Character pool as code points (empty = built-in default).
    pool: [48]u21 = [_]u21{0} ** 48,
    n_pool: u8 = 0,
    /// 0 = A and R drawn independently; k > 0 = R is A after 1..k random
    /// code-point edits (insert/delete/substitute), so edit distance <= k.
    max_edit_distance: u8 = 0,

    // [sizes] D(k), index = size
    size_weights: [max_size_cap + 1]f64 = blk: {
        var d = [_]f64{0} ** (max_size_cap + 1);
        for (4..25) |k| d[k] = 1.0;
        break :blk d;
    },

    // [flags]
    flag_sets: [24]alpha.Flags = alpha.all_flag_sets,
    n_flag_sets: u8 = 24,

    // [weights]
    weights: Weights = Weights.defaults(),

    // [limits]
    max_pairs: u32 = 1 << 20,
    max_combos: u64 = 1 << 26,
    max_prods: u32 = 1 << 22,
    max_count_terms: u64 = 1 << 28,
    max_table_bytes: u64 = 1 << 30,
    max_host_bytes: u64 = 4 << 30,
    max_table_attempts: u32 = 64,
    samples_per_table: u64 = 100_000,
    alias_cache: bool = true,
    alias_arena_bytes: u64 = 256 << 20,
    max_pending_findings: u32 = 256,
    /// Findings stored per signature group (kind, mode, construct counts); later ones are
    /// only counted (groups/counts.txt). 0 = no cap. A run is reproducible from its seed,
    /// so stored findings are a sample, not the record.
    max_findings_per_group: u32 = 20,
    /// And at most this many per (kind, mode) in a run (0 = no cap).
    max_findings_per_mode: u32 = 2000,
    max_pending_finding_bytes: u64 = 64 << 20,

    // [harness]
    batch_size: u32 = 512,
    max_request_bytes: u32 = 1 << 20,
    startup_deadline_ms: u32 = 10_000,
    batch_deadline_base_ms: u32 = 2000,
    batch_deadline_per512_ms: u32 = 2000,
    recycle_cases: u64 = 1_000_000,
    novelty_cap: u32 = 100_000,
    novelty_bytes: u64 = 16 << 20,
    journal_bytes: u64 = 256 << 20,
    stderr_tail_bytes: u32 = 1 << 20,
    /// Keep the per-process request journals after the run (they are deleted otherwise;
    /// batch failures keep their exact request in batch.req).
    keep_journals: bool = false,

    // [span]
    /// Run the span mode too: an unanchored search on A and R whose reported [start, end)
    /// is checked against the reference matcher.
    span: bool = false,
    /// Index unit the host reports spans in.
    span_units: SpanUnits = .utf16,

    // [offset]
    /// Run the offset mode: span of a search that starts at a random character boundary of
    /// A and R (lastIndex, pos, start offset), with the text before it still visible to
    /// lookbehind and \b, and ^ matching only at the real start.
    offset: bool = false,
    /// Sticky mode (the match anchored at the offset): only for hosts with a native anchored
    /// search; emulating it from the offset search would repeat the offset check.
    sticky: bool = false,
    /// [global] enabled: global-search mode (first few matches, JS empty-match advance).
    global: bool = false,

    // [capture]
    /// Run the capture mode too: like span mode, plus the spans of the first groups.
    capture: bool = false,
    /// Loop bodies' captures: cleared at the start of each iteration (`reset`: ES,
    /// Perl >= 5.38) or kept until overwritten (`keep`: PCRE, Python, Java, .NET, ...).
    capture_loop: CaptureLoop = .keep,
    /// Check groups inside lookbehinds (false: engines whose lookbehind tries lengths in
    /// their own order, e.g. Java's shortest-first; such cases are skipped).
    capture_lookbehind: bool = true,

    // [long]
    /// Run the long-input mode too: each case gets a long accept/reject pair pumped from A
    /// (long.zig) and engines run the full-match test on it.
    long_mode: bool = false,
    /// Run only the long modes (a long-input campaign): the other modes are not started.
    long_mode_only: bool = false,
    /// Long spans and captures too (where [span] / [capture] are enabled).
    long_mode_span: bool = true,
    long_mode_capture: bool = true,
    /// Fraction of cases that get a long pair (the rest are skipped by the long mode).
    long_mode_fraction: f64 = 0.25,
    /// Target lengths in symbols; each pair picks one, plus a little jitter.
    long_mode_lengths: [8]u32 = .{ 64, 256, 1000, 4096, 0, 0, 0, 0 },
    n_long_mode_lengths: u8 = 4,
    /// Backtracking steps per symbol the guard allows the reference matcher (0: no guard).
    long_mode_guard_factor: u32 = 50,
    /// Request size limit for the long mode's batches.
    long_mode_max_request_bytes: u32 = 8 << 20,
    /// Extra batch deadline for the long mode per KB of request (long subjects take longer).
    long_mode_deadline_ms_per_kb: u32 = 20,
    /// And per case (engines with a per-match time limit can spend it on several cases).
    long_mode_deadline_ms_per_case: u32 = 10,

    // [adaptive]
    adaptive: bool = false,
    adaptive_factor: f64 = 1.5,
    adaptive_cap: f64 = 10.0,

    // [sanity]
    sanity_fraction: f64 = 0.01,

    pub fn poolSlice(self: *const Config) []const u21 {
        return if (self.n_pool == 0) &alpha.default_pool else self.pool[0..self.n_pool];
    }

    pub fn flagSets(self: *const Config) []const alpha.Flags {
        return self.flag_sets[0..self.n_flag_sets];
    }

    pub fn validate(self: *const Config) !void {
        for (self.weights.w) |w| if (!std.math.isFinite(w) or w < 0) return error.InvalidWeight;
        var any = false;
        for (self.size_weights, 0..) |d, k| {
            if (!std.math.isFinite(d) or d < 0) return error.InvalidSizeWeight;
            if (d > 0 and k > self.max_size) return error.SizeAboveMaxSize;
            if (d > 0) any = true;
        }
        if (!any) return error.NoPositiveSizeWeight;
        if (self.max_size < 1) return error.InvalidMaxSize;
        if (self.min_len > self.max_len) return error.InvalidLength;
        if (self.max_symbols > 31) return error.MaxSymbolsAbove31;
        if (self.long_fraction < 0 or self.long_fraction > 1) return error.InvalidLongFraction;
        if (self.long_fraction > 0 and (self.long_min < 1 or self.long_min > self.long_max or self.long_max > self.max_symbols)) return error.InvalidLongRange;
        if (self.n_flag_sets == 0) return error.NoFlagSets;
        if (self.max_rep_bound > 254) return error.RepBoundTooLarge;
        for (self.big_rep_bounds[0..self.n_big_rep_bounds]) |b| if (b <= self.max_rep_bound or b > 254) return error.BadBigRepBound;
        if (self.big_rep_weight < 0) return error.BadBigRepWeight;
        if (self.pool_rotation < 0 or self.pool_rotation > 1) return error.BadPoolRotation;
        if (self.class_max_members > 4) return error.ClassMembersTooLarge;
        if (self.batch_size == 0) return error.InvalidBatchSize;
        if (self.max_pairs == 0 or self.max_prods == 0) return error.InvalidLimits;
        if (self.adaptive_cap < 1.0 or self.adaptive_factor < 1.0) return error.InvalidAdaptive;
        if (self.sanity_fraction < 0 or self.sanity_fraction > 1) return error.InvalidSanityFraction;
        if (self.long_mode_fraction < 0 or self.long_mode_fraction > 1) return error.InvalidLongModeFraction;
        if (self.n_long_mode_lengths == 0) return error.NoLongModeLengths;
        // 16-bit wire positions: a 16000-symbol subject is at most 64000 UTF-8 bytes.
        for (self.long_mode_lengths[0..self.n_long_mode_lengths]) |l| if (l < 16 or l > 16000) return error.LongModeLengthOutOfRange;
        // Every case must fit a request: conservative escaped encoding of
        // pattern + two subjects (6 bytes per code unit) + framing.
        const per_case: u64 = @as(u64, self.max_pattern_bytes) * 6 + 2 * 16 * 6 + 64;
        if (per_case + 64 > self.max_request_bytes) return error.CaseCannotFitRequest;
    }
};

// ---------------------------------------------------------------------------
// TOML subset

const Value = union(enum) {
    num: f64,
    boolean: bool,
    str: []const u8,
    nums: []const f64,
    strs: []const []const u8,
};

pub fn loadToml(gpa: std.mem.Allocator, text: []const u8, cfg: *Config) !void {
    var section: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    var lineno: usize = 0;
    while (lines.next()) |raw| {
        lineno += 1;
        const line = std.mem.trim(u8, stripComment(raw), " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '[') {
            if (line[line.len - 1] != ']') return error.TomlSyntax;
            section = std.mem.trim(u8, line[1 .. line.len - 1], " ");
            continue;
        }
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse return error.TomlSyntax;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const vtext = std.mem.trim(u8, line[eq + 1 ..], " \t");
        const v = try parseValue(gpa, vtext);
        apply(cfg, section, key, v) catch |e| {
            if (!@import("builtin").is_test) @import("sys.zig").stderrPrint("config line {d}: [{s}] {s}: {s}\n", .{ lineno, section, key, @errorName(e) });
            return e;
        };
    }
    try cfg.validate();
}

fn stripComment(s: []const u8) []const u8 {
    var in_str = false;
    for (s, 0..) |c, i| {
        if (c == '"') in_str = !in_str;
        if (c == '#' and !in_str) return s[0..i];
    }
    return s;
}

fn parseNum(t: []const u8) !f64 {
    var buf: [64]u8 = undefined;
    var n: usize = 0;
    for (t) |c| {
        if (c == '_') continue;
        if (n >= buf.len) return error.TomlNumber;
        buf[n] = c;
        n += 1;
    }
    const s = buf[0..n];
    if (std.mem.eql(u8, s, "inf") or std.mem.eql(u8, s, "+inf") or std.mem.eql(u8, s, "-inf") or std.mem.eql(u8, s, "nan")) return error.NonFiniteNumber;
    if (s.len > 2 and s[0] == '0' and s[1] == 'x') return @floatFromInt(try std.fmt.parseInt(u64, s[2..], 16));
    return std.fmt.parseFloat(f64, s) catch error.TomlNumber;
}

fn parseValue(gpa: std.mem.Allocator, t: []const u8) !Value {
    if (t.len == 0) return error.TomlSyntax;
    if (std.mem.eql(u8, t, "true")) return .{ .boolean = true };
    if (std.mem.eql(u8, t, "false")) return .{ .boolean = false };
    if (t[0] == '"') {
        if (t.len < 2 or t[t.len - 1] != '"') return error.TomlSyntax;
        return .{ .str = try gpa.dupe(u8, t[1 .. t.len - 1]) };
    }
    if (t[0] == '[') {
        if (t[t.len - 1] != ']') return error.TomlSyntax;
        const inner = std.mem.trim(u8, t[1 .. t.len - 1], " ");
        var nums: std.ArrayList(f64) = .empty;
        var strs: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, inner, ',');
        while (it.next()) |e| {
            const x = std.mem.trim(u8, e, " \t");
            if (x.len == 0) continue;
            if (x[0] == '"') {
                if (x.len < 2 or x[x.len - 1] != '"') return error.TomlSyntax;
                try strs.append(gpa, try gpa.dupe(u8, x[1 .. x.len - 1]));
            } else try nums.append(gpa, try parseNum(x));
        }
        if (strs.items.len > 0 and nums.items.len > 0) return error.MixedArray;
        if (strs.items.len > 0) return .{ .strs = strs.items };
        return .{ .nums = nums.items };
    }
    return .{ .num = try parseNum(t) };
}

fn asInt(comptime T: type, v: Value) !T {
    const x = switch (v) {
        .num => |n| n,
        else => return error.ExpectedNumber,
    };
    if (x != @floor(x) or x < 0 or x > @as(f64, @floatFromInt(std.math.maxInt(T)))) return error.ExpectedInteger;
    return @intFromFloat(x);
}
fn asF(v: Value) !f64 {
    return switch (v) {
        .num => |n| n,
        else => error.ExpectedNumber,
    };
}
fn asBool(v: Value) !bool {
    return switch (v) {
        .boolean => |b| b,
        else => error.ExpectedBool,
    };
}

fn apply(cfg: *Config, section: []const u8, key: []const u8, v: Value) !void {
    const eq = std.mem.eql;
    // targets/<name>/target.toml metadata, read by tools/irx_target.py.
    if (eq(u8, section, "target")) return;
    if (eq(u8, section, "weights")) {
        const c = std.meta.stringToEnum(Construct, key) orelse return error.UnknownWeight;
        const x = try asF(v);
        if (!std.math.isFinite(x) or x < 0) return error.InvalidWeight;
        cfg.weights.set(c, x);
        return;
    }
    if (eq(u8, section, "sizes")) {
        if (eq(u8, key, "uniform")) {
            const r = switch (v) {
                .nums => |n| n,
                else => return error.ExpectedArray,
            };
            if (r.len != 2) return error.ExpectedRange;
            @memset(&cfg.size_weights, 0);
            const lo: usize = @intFromFloat(r[0]);
            const hi: usize = @intFromFloat(r[1]);
            if (lo < 1 or hi < lo or hi > max_size_cap) return error.BadSizeRange;
            for (lo..hi + 1) |k| cfg.size_weights[k] = 1.0;
            return;
        }
        if (eq(u8, key, "weights")) {
            // weights[0] is D(1)
            const r = switch (v) {
                .nums => |n| n,
                else => return error.ExpectedArray,
            };
            if (r.len > max_size_cap) return error.TooManySizes;
            @memset(&cfg.size_weights, 0);
            for (r, 0..) |d, i| {
                if (!std.math.isFinite(d) or d < 0) return error.InvalidSizeWeight;
                cfg.size_weights[i + 1] = d;
            }
            return;
        }
        return error.UnknownKey;
    }
    if (eq(u8, section, "strings") and eq(u8, key, "pool")) {
        const arr = switch (v) {
            .nums => |n| n,
            else => return error.ExpectedCodePointArray,
        };
        if (arr.len == 0 or arr.len > cfg.pool.len) return error.BadPoolSize;
        for (arr, 0..) |x, i| {
            if (x < 0 or x > 0x10FFFF or x != @floor(x)) return error.BadCodePoint;
            cfg.pool[i] = @intFromFloat(x);
        }
        cfg.n_pool = @intCast(arr.len);
        return;
    }
    if (eq(u8, section, "span")) {
        if (eq(u8, key, "enabled")) {
            cfg.span = try asBool(v);
            return;
        }
        if (eq(u8, key, "units")) {
            const t = switch (v) {
                .str => |x| x,
                else => return error.ExpectedString,
            };
            cfg.span_units = std.meta.stringToEnum(SpanUnits, t) orelse return error.BadSpanUnits;
            return;
        }
        return error.UnknownKey;
    }
    if (eq(u8, section, "grammar") and eq(u8, key, "big_rep_bounds")) {
        const arr = switch (v) {
            .nums => |x| x,
            else => return error.ExpectedArray,
        };
        if (arr.len > cfg.big_rep_bounds.len) return error.BadBigRepBound;
        for (arr, 0..) |x, i| {
            if (x != @floor(x) or x < 1 or x > 254) return error.BadBigRepBound;
            cfg.big_rep_bounds[i] = @intFromFloat(x);
        }
        cfg.n_big_rep_bounds = @intCast(arr.len);
        return;
    }
    if (eq(u8, section, "long")) {
        if (eq(u8, key, "enabled")) {
            cfg.long_mode = try asBool(v);
            return;
        }
        if (eq(u8, key, "only")) {
            cfg.long_mode_only = try asBool(v);
            return;
        }
        if (eq(u8, key, "span")) {
            cfg.long_mode_span = try asBool(v);
            return;
        }
        if (eq(u8, key, "capture")) {
            cfg.long_mode_capture = try asBool(v);
            return;
        }
        if (eq(u8, key, "fraction")) {
            cfg.long_mode_fraction = try asF(v);
            return;
        }
        if (eq(u8, key, "guard_factor")) {
            cfg.long_mode_guard_factor = try asInt(u32, v);
            return;
        }
        if (eq(u8, key, "max_request_bytes")) {
            cfg.long_mode_max_request_bytes = try asInt(u32, v);
            return;
        }
        if (eq(u8, key, "deadline_ms_per_kb")) {
            cfg.long_mode_deadline_ms_per_kb = try asInt(u32, v);
            return;
        }
        if (eq(u8, key, "deadline_ms_per_case")) {
            cfg.long_mode_deadline_ms_per_case = try asInt(u32, v);
            return;
        }
        if (eq(u8, key, "lengths")) {
            const arr = switch (v) {
                .nums => |x| x,
                else => return error.ExpectedArray,
            };
            if (arr.len == 0 or arr.len > cfg.long_mode_lengths.len) return error.BadLongModeLengths;
            for (arr, 0..) |x, i| {
                if (x != @floor(x) or x < 0) return error.BadLongModeLengths;
                cfg.long_mode_lengths[i] = @intFromFloat(x);
            }
            cfg.n_long_mode_lengths = @intCast(arr.len);
            return;
        }
        return error.UnknownKey;
    }
    if (eq(u8, section, "global")) {
        if (eq(u8, key, "enabled")) {
            cfg.global = try asBool(v);
            return;
        }
        return error.UnknownKey;
    }
    if (eq(u8, section, "offset")) {
        if (eq(u8, key, "enabled")) {
            cfg.offset = try asBool(v);
            return;
        }
        if (eq(u8, key, "sticky")) {
            cfg.sticky = try asBool(v);
            return;
        }
        return error.UnknownKey;
    }
    if (eq(u8, section, "capture")) {
        if (eq(u8, key, "enabled")) {
            cfg.capture = try asBool(v);
            return;
        }
        if (eq(u8, key, "lookbehind")) {
            cfg.capture_lookbehind = try asBool(v);
            return;
        }
        if (eq(u8, key, "loop")) {
            const t = switch (v) {
                .str => |x| x,
                else => return error.ExpectedString,
            };
            cfg.capture_loop = std.meta.stringToEnum(CaptureLoop, t) orelse return error.BadCaptureLoop;
            return;
        }
        return error.UnknownKey;
    }
    if (eq(u8, section, "flags")) {
        if (!eq(u8, key, "sets")) return error.UnknownKey;
        const arr = switch (v) {
            .strs => |s| s,
            .nums => |n| if (n.len == 0) &[_][]const u8{} else return error.ExpectedStrings,
            else => return error.ExpectedStrings,
        };
        if (arr.len == 0 or arr.len > 24) return error.BadFlagSets;
        for (arr, 0..) |s, i| cfg.flag_sets[i] = try alpha.Flags.parse(s);
        cfg.n_flag_sets = @intCast(arr.len);
        return;
    }
    @setEvalBranchQuota(100_000);
    inline for (@typeInfo(Config).@"struct".fields) |f| {
        const sec = comptime sectionOf(f.name);
        if (sec != null and eq(u8, key, f.name)) {
            if (!eq(u8, section, sec.?)) return error.WrongSection;
            switch (f.type) {
                bool => @field(cfg, f.name) = try asBool(v),
                f64 => @field(cfg, f.name) = try asF(v),
                u8, u32, u64 => @field(cfg, f.name) = try asInt(f.type, v),
                else => return error.UnknownKey,
            }
            return;
        }
    }
    return error.UnknownKey;
}

fn sectionOf(comptime name: []const u8) ?[]const u8 {
    @setEvalBranchQuota(100_000);
    const grammar = .{ "max_size", "max_rep_bound", "big_rep_weight", "class_max_members", "max_pattern_bytes", "allow_diagonal_lookarounds", "duplicate_names", "extended_mode", "mutate_rate", "usefulness_pass", "usefulness_workspace" };
    const strings = .{ "pool_rotation", "min_len", "max_len", "max_symbols", "max_edit_distance", "long_fraction", "long_min", "long_max" };
    const limits = .{ "max_pairs", "max_combos", "max_prods", "max_count_terms", "max_table_bytes", "max_host_bytes", "max_table_attempts", "samples_per_table", "alias_cache", "alias_arena_bytes", "max_pending_findings", "max_pending_finding_bytes", "max_findings_per_group", "max_findings_per_mode" };
    const harness = .{ "batch_size", "max_request_bytes", "startup_deadline_ms", "batch_deadline_base_ms", "batch_deadline_per512_ms", "recycle_cases", "novelty_cap", "novelty_bytes", "journal_bytes", "stderr_tail_bytes", "keep_journals" };
    const adaptive = .{ "adaptive", "adaptive_factor", "adaptive_cap" };
    const sanity = .{"sanity_fraction"};
    inline for (grammar) |g| if (comptime std.mem.eql(u8, g, name)) return "grammar";
    inline for (strings) |g| if (comptime std.mem.eql(u8, g, name)) return "strings";
    inline for (limits) |g| if (comptime std.mem.eql(u8, g, name)) return "limits";
    inline for (harness) |g| if (comptime std.mem.eql(u8, g, name)) return "harness";
    inline for (adaptive) |g| if (comptime std.mem.eql(u8, g, name)) return "adaptive";
    inline for (sanity) |g| if (comptime std.mem.eql(u8, g, name)) return "sanity";
    return null;
}

/// Resolved configuration as JSON (stored in run and finding manifests).
pub fn toJson(cfg: *const Config, out: *std.ArrayList(u8), gpa: std.mem.Allocator) !void {
    try out.appendSlice(gpa, "{");
    var first = true;
    inline for (@typeInfo(Config).@"struct".fields) |f| {
        switch (f.type) {
            bool, f64, u8, u32, u64 => {
                if (!first) try out.appendSlice(gpa, ",");
                first = false;
                try out.print(gpa, "\"{s}\":", .{f.name});
                if (f.type == f64) try out.print(gpa, "{e}", .{@field(cfg, f.name)}) else try out.print(gpa, "{}", .{@field(cfg, f.name)});
            },
            else => {},
        }
    }
    try out.appendSlice(gpa, ",\"size_weights\":{");
    first = true;
    for (cfg.size_weights, 0..) |d, k| {
        if (d == 0) continue;
        if (!first) try out.appendSlice(gpa, ",");
        first = false;
        try out.print(gpa, "\"{d}\":{e}", .{ k, d });
    }
    try out.appendSlice(gpa, "},\"weights\":{");
    for (cfg.weights.w, 0..) |w, i| {
        if (i > 0) try out.appendSlice(gpa, ",");
        try out.print(gpa, "\"{s}\":{e}", .{ @tagName(@as(Construct, @enumFromInt(i))), w });
    }
    try out.appendSlice(gpa, "},\"flag_sets\":[");
    for (cfg.flagSets(), 0..) |f, i| {
        if (i > 0) try out.appendSlice(gpa, ",");
        var b: [8]u8 = undefined;
        try out.print(gpa, "\"{s}\"", .{f.str(&b)});
    }
    try out.appendSlice(gpa, "]}");
}

test "toml parsing and validation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cfg: Config = .{};
    try loadToml(arena.allocator(),
        \\# comment
        \\[weights]
        \\star = 3.0
        \\lookbehind = 5.0  # trailing
        \\backslash_b = 2.0
        \\[sizes]
        \\uniform = [2, 10]
        \\[flags]
        \\sets = ["", "i", "iv"]
        \\[limits]
        \\max_pairs = 65_536
    , &cfg);
    try std.testing.expectEqual(@as(f64, 3.0), cfg.weights.get(.star));
    try std.testing.expectEqual(@as(u32, 65536), cfg.max_pairs);
    try std.testing.expectEqual(@as(u8, 3), cfg.n_flag_sets);
    try std.testing.expectEqual(@as(f64, 0), cfg.size_weights[11]);
    var bad: Config = .{};
    try std.testing.expectError(error.InvalidWeight, loadToml(arena.allocator(), "[weights]\nstar = -1\n", &bad));
    try std.testing.expectError(error.NonFiniteNumber, loadToml(arena.allocator(), "[weights]\nstar = nan\n", &bad));
    try std.testing.expectError(error.NoPositiveSizeWeight, loadToml(arena.allocator(), "[sizes]\nweights = [0, 0]\n", &bad));
}
