//! Hard byte accounting. A Budget wraps the C allocator and refuses any
//! allocation that would push its (and its parent's) live total over the
//! limit. Tables get a child budget of the host budget, so `max_table_bytes`
//! and `max_host_bytes` are both enforced on every allocation, including
//! growth copies.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

pub const Budget = struct {
    name: []const u8,
    limit: u64,
    used: std.atomic.Value(u64) = .init(0),
    peak: std.atomic.Value(u64) = .init(0),
    /// Bytes promised by `reserve` but not yet allocated.
    reserved: std.atomic.Value(u64) = .init(0),
    failures: std.atomic.Value(u64) = .init(0),
    parent: ?*Budget = null,

    pub fn init(name: []const u8, limit: u64, parent: ?*Budget) Budget {
        return .{ .name = name, .limit = limit, .parent = parent };
    }

    fn charge(self: *Budget, n: u64) bool {
        var cur = self.used.load(.monotonic);
        while (true) {
            const next = std.math.add(u64, cur, n) catch return false;
            if (next + self.reserved.load(.monotonic) > self.limit) {
                _ = self.failures.fetchAdd(1, .monotonic);
                return false;
            }
            if (self.used.cmpxchgWeak(cur, next, .monotonic, .monotonic)) |actual| {
                cur = actual;
                continue;
            }
            var pk = self.peak.load(.monotonic);
            while (next > pk) {
                pk = self.peak.cmpxchgWeak(pk, next, .monotonic, .monotonic) orelse break;
            }
            break;
        }
        if (self.parent) |p| {
            if (!p.charge(n)) {
                _ = self.used.fetchSub(n, .monotonic);
                return false;
            }
        }
        return true;
    }

    fn uncharge(self: *Budget, n: u64) void {
        _ = self.used.fetchSub(n, .monotonic);
        if (self.parent) |p| p.uncharge(n);
    }

    /// Reserve capacity that later allocations may need (lane scratch, triage).
    pub fn reserve(self: *Budget, n: u64) bool {
        if (!self.charge(n)) return false;
        self.uncharge(n);
        // charge succeeded => fits; now record as reservation at every level
        var b: ?*Budget = self;
        while (b) |x| : (b = x.parent) _ = x.reserved.fetchAdd(n, .monotonic);
        return true;
    }

    pub fn unreserve(self: *Budget, n: u64) void {
        var b: ?*Budget = self;
        while (b) |x| : (b = x.parent) _ = x.reserved.fetchSub(n, .monotonic);
    }

    pub fn available(self: *const Budget) u64 {
        const u = self.used.load(.monotonic) + self.reserved.load(.monotonic);
        return if (u >= self.limit) 0 else self.limit - u;
    }

    pub fn allocator(self: *Budget) Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    // Charge the allocator's alignment slack conservatively.
    fn cost(len: usize, a: Alignment) u64 {
        return @as(u64, len) + a.toByteUnits();
    }

    fn alloc(ctx: *anyopaque, len: usize, a: Alignment, ra: usize) ?[*]u8 {
        const self: *Budget = @ptrCast(@alignCast(ctx));
        if (!self.charge(cost(len, a))) return null;
        const p = std.heap.c_allocator.vtable.alloc(std.heap.c_allocator.ptr, len, a, ra) orelse {
            self.uncharge(cost(len, a));
            return null;
        };
        return p;
    }

    fn resize(ctx: *anyopaque, mem: []u8, a: Alignment, new_len: usize, ra: usize) bool {
        const self: *Budget = @ptrCast(@alignCast(ctx));
        if (new_len > mem.len) {
            if (!self.charge(new_len - mem.len)) return false;
            if (!std.heap.c_allocator.vtable.resize(std.heap.c_allocator.ptr, mem, a, new_len, ra)) {
                self.uncharge(new_len - mem.len);
                return false;
            }
            return true;
        }
        if (!std.heap.c_allocator.vtable.resize(std.heap.c_allocator.ptr, mem, a, new_len, ra)) return false;
        self.uncharge(mem.len - new_len);
        return true;
    }

    fn remap(ctx: *anyopaque, mem: []u8, a: Alignment, new_len: usize, ra: usize) ?[*]u8 {
        // Growth copies must be charged while both buffers are live; let the
        // caller fall back to alloc+copy+free, which does exactly that.
        if (resize(ctx, mem, a, new_len, ra)) return mem.ptr;
        return null;
    }

    fn free(ctx: *anyopaque, mem: []u8, a: Alignment, ra: usize) void {
        const self: *Budget = @ptrCast(@alignCast(ctx));
        std.heap.c_allocator.vtable.free(std.heap.c_allocator.ptr, mem, a, ra);
        self.uncharge(cost(mem.len, a));
    }
};

test "budget refuses over-limit allocations and tracks parent" {
    var host = Budget.init("host", 1 << 20, null);
    var t = Budget.init("table", 1 << 16, &host);
    const a = t.allocator();
    const x = try a.alloc(u8, 1000);
    try std.testing.expect(host.used.load(.monotonic) >= 1000);
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 1 << 17));
    a.free(x);
    try std.testing.expectEqual(@as(u64, 0), t.used.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), host.used.load(.monotonic));
    try std.testing.expect(t.reserve(1 << 15));
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 1 << 15));
    t.unreserve(1 << 15);
}
