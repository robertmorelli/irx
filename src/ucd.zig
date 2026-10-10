//! Pinned Unicode data. The UCD source files are vendored under src/ucd/ and
//! embedded; their SHA-256 hashes are checked against the manifest at startup
//! so the host OS's Unicode tables are never consulted.
const std = @import("std");
const sys = @import("sys.zig");

pub const version = "17.0.0";
pub const manifest_json = @embedFile("ucd/manifest.json");

const case_folding_txt = @embedFile("ucd/CaseFolding.txt");
const special_casing_txt = @embedFile("ucd/SpecialCasing.txt");
const unicode_data_txt = @embedFile("ucd/UnicodeData.txt");

pub const FileHash = struct { name: []const u8, data: []const u8, sha256: []const u8 };
pub const files = [_]FileHash{
    .{ .name = "CaseFolding.txt", .data = case_folding_txt, .sha256 = "ff8d8fefbf123574205085d6714c36149eb946d717a0c585c27f0f4ef58c4183" },
    .{ .name = "SpecialCasing.txt", .data = special_casing_txt, .sha256 = "efc25faf19de21b92c1194c111c932e03d2a5eaf18194e33f1156e96de4c9588" },
    .{ .name = "UnicodeData.txt", .data = unicode_data_txt, .sha256 = "2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c" },
};

const Pair = struct { from: u21, to: u21 };
const CatRun = struct { lo: u21, hi: u21, cat: [2]u8 };

const Data = struct {
    /// Simple case folding (statuses C and S), sorted by `from`.
    scf: []Pair,
    /// Inverse of scf: sorted by (to, from).
    scf_inv: []Pair,
    /// Simple uppercase mapping (UnicodeData field 12), sorted by `from`.
    upper: []Pair,
    /// Unconditional multi-code-point uppercase mappings (SpecialCasing), length > 1.
    upper_multi: []u21,
    /// Simple lowercase mapping (UnicodeData field 13), sorted by `from`.
    lower: []Pair,
    /// Unconditional multi-code-point lowercase mappings (SpecialCasing).
    lower_multi: []u21,
    /// Zs code points.
    zs: []u21,
    /// General category runs: sorted, non-overlapping.
    cats: []CatRun,
    /// Canonicalize for /i without u/v, over all code units.
    canon_nu: [65536]u16,
    /// Code units sorted by canon_nu value; class_start indexes into it.
    nu_sorted: [65536]u16,
};

var data: Data = undefined;
var init_done = std.atomic.Value(bool).init(false);
var init_mutex: sys.Mutex = .{};

pub fn init() void {
    if (init_done.load(.acquire)) return;
    init_mutex.lock();
    defer init_mutex.unlock();
    if (init_done.load(.monotonic)) return;
    load() catch |e| {
        sys.stderrPrint("fatal: failed to load pinned Unicode data: {s}\n", .{@errorName(e)});
        std.process.exit(2);
    };
    init_done.store(true, .release);
}

pub fn verifyHashes() bool {
    var ok = true;
    for (files) |f| {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(f.data, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        if (!std.mem.eql(u8, &hex, f.sha256)) {
            sys.stderrPrint("unicode data hash mismatch for {s}\n", .{f.name});
            ok = false;
        }
    }
    return ok;
}

fn parseHex(s: []const u8) !u21 {
    return std.fmt.parseInt(u21, std.mem.trim(u8, s, " \t"), 16);
}

fn lessFrom(_: void, a: Pair, b: Pair) bool {
    return a.from < b.from;
}
fn lessTo(_: void, a: Pair, b: Pair) bool {
    return if (a.to != b.to) a.to < b.to else a.from < b.from;
}

fn load() !void {
    if (!verifyHashes()) return error.UnicodeHashMismatch;
    const gpa = std.heap.page_allocator;

    // CaseFolding: code; status; mapping; # name
    var scf: std.ArrayList(Pair) = .empty;
    var it = std.mem.splitScalar(u8, case_folding_txt, '\n');
    while (it.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var f = std.mem.splitScalar(u8, line, ';');
        const code = try parseHex(f.next() orelse continue);
        const status = std.mem.trim(u8, f.next() orelse continue, " ");
        const mapping = std.mem.trim(u8, f.next() orelse continue, " ");
        if (!(std.mem.eql(u8, status, "C") or std.mem.eql(u8, status, "S"))) continue;
        try scf.append(gpa, .{ .from = code, .to = try parseHex(mapping) });
    }
    std.mem.sort(Pair, scf.items, {}, lessFrom);
    const inv = try gpa.dupe(Pair, scf.items);
    std.mem.sort(Pair, inv, {}, lessTo);

    // UnicodeData: field 0 code, 2 category, 12 simple uppercase.
    var upper: std.ArrayList(Pair) = .empty;
    var lower: std.ArrayList(Pair) = .empty;
    var zs: std.ArrayList(u21) = .empty;
    var cats: std.ArrayList(CatRun) = .empty;
    var range_start: ?u21 = null;
    it = std.mem.splitScalar(u8, unicode_data_txt, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        var fields: [15][]const u8 = undefined;
        var n: usize = 0;
        var f = std.mem.splitScalar(u8, line, ';');
        while (f.next()) |x| : (n += 1) {
            if (n < 15) fields[n] = x;
        }
        if (n < 13) continue;
        const code = try parseHex(fields[0]);
        if (std.mem.eql(u8, fields[2], "Zs")) try zs.append(gpa, code);
        if (fields[2].len == 2) {
            const cat: [2]u8 = .{ fields[2][0], fields[2][1] };
            var lo = code;
            if (std.mem.endsWith(u8, fields[1], "First>")) {
                range_start = code;
            } else {
                if (std.mem.endsWith(u8, fields[1], "Last>")) {
                    lo = range_start orelse code;
                    range_start = null;
                }
                const nc = cats.items.len;
                if (nc > 0 and cats.items[nc - 1].hi + 1 == lo and std.mem.eql(u8, &cats.items[nc - 1].cat, &cat)) {
                    cats.items[nc - 1].hi = code;
                } else try cats.append(gpa, .{ .lo = lo, .hi = code, .cat = cat });
            }
        }
        if (fields[12].len > 0) try upper.append(gpa, .{ .from = code, .to = try parseHex(fields[12]) });
        if (n > 13 and fields[13].len > 0) try lower.append(gpa, .{ .from = code, .to = try parseHex(fields[13]) });
    }
    std.mem.sort(Pair, upper.items, {}, lessFrom);
    std.mem.sort(Pair, lower.items, {}, lessFrom);

    // SpecialCasing: code; lower; title; upper; (condition;)? # comment
    // Only unconditional entries whose uppercase has more than one code point
    // matter: they make Canonicalize (non-unicode) return the input unchanged.
    var multi: std.ArrayList(u21) = .empty;
    var lmulti: std.ArrayList(u21) = .empty;
    it = std.mem.splitScalar(u8, special_casing_txt, '\n');
    while (it.next()) |raw| {
        const line = if (std.mem.indexOfScalar(u8, raw, '#')) |h| raw[0..h] else raw;
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
        var fields: [6][]const u8 = undefined;
        var n: usize = 0;
        var f = std.mem.splitScalar(u8, line, ';');
        while (f.next()) |x| : (n += 1) {
            if (n < 6) fields[n] = x;
        }
        if (n < 4) continue;
        if (n >= 5 and std.mem.trim(u8, fields[4], " \t\r").len > 0) continue; // conditional
        const code = try parseHex(fields[0]);
        var ucount: usize = 0;
        var u = std.mem.tokenizeScalar(u8, fields[3], ' ');
        while (u.next()) |_| ucount += 1;
        if (ucount != 1) try multi.append(gpa, code);
        var lcount: usize = 0;
        var lw = std.mem.tokenizeScalar(u8, fields[1], ' ');
        while (lw.next()) |_| lcount += 1;
        if (lcount != 1) try lmulti.append(gpa, code);
    }
    std.mem.sort(u21, multi.items, {}, std.sort.asc(u21));

    data.scf = scf.items;
    data.scf_inv = inv;
    data.upper = upper.items;
    data.upper_multi = multi.items;
    std.mem.sort(u21, lmulti.items, {}, std.sort.asc(u21));
    data.lower = lower.items;
    data.lower_multi = lmulti.items;
    data.zs = zs.items;
    data.cats = cats.items;

    for (0..65536) |c| data.canon_nu[c] = canonNonUnicodeCompute(@intCast(c));
    for (0..65536) |c| data.nu_sorted[c] = @intCast(c);
    std.mem.sort(u16, &data.nu_sorted, {}, struct {
        fn lt(_: void, a: u16, b: u16) bool {
            const ca = data.canon_nu[a];
            const cb = data.canon_nu[b];
            return if (ca != cb) ca < cb else a < b;
        }
    }.lt);
}

fn lookup(tab: []const Pair, c: u21) ?u21 {
    var lo: usize = 0;
    var hi: usize = tab.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (tab[mid].from == c) return tab[mid].to;
        if (tab[mid].from < c) lo = mid + 1 else hi = mid;
    }
    return null;
}

fn isMultiUpper(c: u21) bool {
    return std.sort.binarySearch(u21, data.upper_multi, c, struct {
        fn cmp(k: u21, x: u21) std.math.Order {
            return std.math.order(k, x);
        }
    }.cmp) != null;
}

/// ES Canonicalize for IgnoreCase without either unicode flag, on one code unit.
fn canonNonUnicodeCompute(ch: u16) u16 {
    if (ch >= 0xD800 and ch <= 0xDFFF) return ch; // lone surrogate: toUppercase is identity
    const c: u21 = ch;
    if (isMultiUpper(c)) return ch; // full uppercase has length > 1
    const u = lookup(data.upper, c) orelse return ch;
    if (u > 0xFFFF) return ch; // would be two code units
    if (ch >= 128 and u < 128) return ch;
    return @intCast(u);
}

/// Simple lowercase mapping (UnicodeData field 13); identity when absent.
pub fn simpleLower(c: u21) u21 {
    return lookup(data.lower, c) orelse c;
}

/// Full lowercase mapping when it is a single code point; otherwise c (Swift-style).
pub fn lower1(c: u21) u21 {
    if (std.sort.binarySearch(u21, data.lower_multi, c, struct {
        fn cmp(k: u21, x: u21) std.math.Order {
            return std.math.order(k, x);
        }
    }.cmp) != null) return c;
    return lookup(data.lower, c) orelse c;
}

/// Simple case folding (C + S); identity when absent.
pub fn simpleFold(c: u21) u21 {
    return lookup(data.scf, c) orelse c;
}

pub fn canonNonUnicode(ch: u16) u16 {
    return data.canon_nu[ch];
}

/// Two-letter general category ("Cn" when unassigned).
pub fn category(c: u21) [2]u8 {
    var lo: usize = 0;
    var hi: usize = data.cats.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        const r = data.cats[mid];
        if (c < r.lo) hi = mid else if (c > r.hi) lo = mid + 1 else return r.cat;
    }
    return .{ 'C', 'n' };
}

pub fn isZs(c: u21) bool {
    return std.mem.indexOfScalar(u21, data.zs, c) != null;
}

/// Visits every s with Canonicalize(s) == Canonicalize(c) for the given mode.
/// `unicode` selects simple case folding (u/v) vs. toUppercase (non-unicode).
pub fn forEachEquivalent(c: u21, unicode: bool, ctx: anytype, comptime f: fn (@TypeOf(ctx), u21) bool) bool {
    if (unicode) {
        const t = simpleFold(c);
        if (f(ctx, t)) return true;
        // all s with scf(s) == t (s != t)
        var lo: usize = 0;
        var hi: usize = data.scf_inv.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (data.scf_inv[mid].to < t) lo = mid + 1 else hi = mid;
        }
        while (lo < data.scf_inv.len and data.scf_inv[lo].to == t) : (lo += 1) {
            if (data.scf_inv[lo].from != t and f(ctx, data.scf_inv[lo].from)) return true;
        }
        return false;
    } else {
        if (c > 0xFFFF) return f(ctx, c);
        const t = data.canon_nu[@intCast(c)];
        var lo: usize = 0;
        var hi: usize = 65536;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (data.canon_nu[data.nu_sorted[mid]] < t) lo = mid + 1 else hi = mid;
        }
        while (lo < 65536 and data.canon_nu[data.nu_sorted[lo]] == t) : (lo += 1) {
            if (f(ctx, data.nu_sorted[lo])) return true;
        }
        return false;
    }
}

// ---------------------------------------------------------------------------
// Equivalence classes for an arbitrary fold function (dialect case rules).

const FoldIndex = struct { f: *const fn (u21) u21, pairs: []Pair };
var fold_indexes: [8]?FoldIndex = [_]?FoldIndex{null} ** 8;
var fold_mutex: sys.Mutex = .{};

/// Pairs (from = s, to = f(s)) for every s with f(s) != s, sorted by (to, from).
fn foldIndex(f: *const fn (u21) u21) []const Pair {
    fold_mutex.lock();
    defer fold_mutex.unlock();
    for (&fold_indexes) |*slot| {
        if (slot.*) |fi| {
            if (fi.f == f) return fi.pairs;
        } else {
            var list: std.ArrayList(Pair) = .empty;
            var c: u21 = 0;
            while (c <= 0x10FFFF) : (c += 1) {
                if (c >= 0xD800 and c <= 0xDFFF) continue;
                const t = f(c);
                if (t != c) list.append(std.heap.page_allocator, .{ .from = c, .to = t }) catch @panic("oom");
            }
            std.mem.sort(Pair, list.items, {}, lessTo);
            slot.* = .{ .f = f, .pairs = list.items };
            return list.items;
        }
    }
    @panic("too many fold functions");
}

/// Visits every s with f(s) == f(c) (c itself included).
pub fn forEachFoldEquivalent(f: *const fn (u21) u21, c: u21, ctx: anytype, comptime pred: fn (@TypeOf(ctx), u21) bool) bool {
    const key = f(c);
    if (pred(ctx, c)) return true;
    if (key != c and f(key) == key and pred(ctx, key)) return true;
    const pairs = foldIndex(f);
    var lo: usize = 0;
    var hi: usize = pairs.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (pairs[mid].to < key) lo = mid + 1 else hi = mid;
    }
    while (lo < pairs.len and pairs[lo].to == key) : (lo += 1) {
        if (pairs[lo].from != c and pred(ctx, pairs[lo].from)) return true;
    }
    return false;
}

const testing = std.testing;

test "pinned data loads and hashes match" {
    init();
    try testing.expect(verifyHashes());
    try testing.expectEqual(@as(u21, 'k'), simpleFold(0x212A));
    try testing.expectEqual(@as(u21, 's'), simpleFold(0x017F));
    try testing.expectEqual(@as(u21, 'k'), simpleFold('K'));
    // non-unicode canonicalize: ſ uppercases to 'S' (ASCII) so it stays ſ
    try testing.expectEqual(@as(u16, 0x017F), canonNonUnicode(0x017F));
    try testing.expectEqual(@as(u16, 0x212A), canonNonUnicode(0x212A));
    try testing.expectEqual(@as(u16, 'K'), canonNonUnicode('k'));
    try testing.expectEqual(@as(u16, 0xDF), canonNonUnicode(0xDF)); // ß -> SS (length 2)
    try testing.expect(isZs(0x3000) and isZs(' ') and !isZs('\n'));
}
