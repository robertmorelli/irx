//! Thin libc/Darwin bindings. Everything here is POSIX or Darwin-specific and
//! deliberately avoids Linux-only APIs. Declarations use plain C types so the
//! rest of the code does not depend on std.c's evolving wrappers.
const std = @import("std");
const builtin = @import("builtin");

pub const pid_t = c_int;

pub extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
pub extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
pub extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
pub extern "c" fn close(fd: c_int) c_int;
pub extern "c" fn pipe(fds: *[2]c_int) c_int;
pub extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
pub extern "c" fn mkdir(path: [*:0]const u8, mode: u16) c_int;
pub extern "c" fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;
pub extern "c" fn unlink(path: [*:0]const u8) c_int;
pub extern "c" fn fsync(fd: c_int) c_int;
pub extern "c" fn kill(pid: pid_t, sig: c_int) c_int;
pub extern "c" fn waitpid(pid: pid_t, status: *c_int, options: c_int) pid_t;
pub extern "c" fn getpid() pid_t;
pub extern "c" fn __error() *c_int;
pub extern "c" fn signal(sig: c_int, handler: ?*const anyopaque) ?*const anyopaque;
pub extern "c" fn sysctlbyname(name: [*:0]const u8, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*anyopaque, newlen: usize) c_int;
pub extern "c" fn clock_gettime_nsec_np(clock: c_int) u64;
pub extern "c" fn getrusage(who: c_int, usage: *[18]c_long) c_int;
pub extern "c" fn usleep(us: c_uint) c_int;
pub extern "c" fn access(path: [*:0]const u8, mode: c_int) c_int;
pub extern "c" fn realpath(path: [*:0]const u8, resolved: ?[*]u8) ?[*:0]u8;
pub extern "c" fn free(p: ?*anyopaque) void;

pub const pollfd = extern struct { fd: c_int, events: i16, revents: i16 };
pub extern "c" fn poll(fds: [*]pollfd, n: c_uint, timeout_ms: c_int) c_int;

pub const POLLIN: i16 = 0x001;
pub const POLLOUT: i16 = 0x004;
pub const POLLERR: i16 = 0x008;
pub const POLLHUP: i16 = 0x010;
pub const POLLNVAL: i16 = 0x020;

pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = 1;
pub const O_RDWR: c_int = 2;
pub const O_NONBLOCK: c_int = 0x4;
pub const O_APPEND: c_int = 0x8;
pub const O_CREAT: c_int = 0x200;
pub const O_TRUNC: c_int = 0x400;
pub const O_EXCL: c_int = 0x800;
pub const O_CLOEXEC: c_int = 0x1000000;
pub const F_GETFD: c_int = 1;
pub const F_SETFD: c_int = 2;
pub const F_GETFL: c_int = 3;
pub const F_SETFL: c_int = 4;
pub const FD_CLOEXEC: c_int = 1;

pub const EINTR: c_int = 4;
pub const EAGAIN: c_int = 35;
pub const EPIPE: c_int = 32;
pub const EEXIST: c_int = 17;
pub const ECHILD: c_int = 10;

pub const SIGKILL: c_int = 9;
pub const SIGPIPE: c_int = 13;
pub const SIG_IGN: ?*const anyopaque = @ptrFromInt(1);
pub const WNOHANG: c_int = 1;

const CLOCK_UPTIME_RAW: c_int = 8;

comptime {
    if (builtin.os.tag != .macos and builtin.os.tag != .linux) @compileError("irx supports macOS (primary) and Linux (best effort)");
}

pub fn errno() c_int {
    return __error().*;
}

/// Monotonic nanoseconds (does not advance across sleep on macOS, which is fine for deadlines).
pub fn nowNs() u64 {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

pub fn setNonblock(fd: c_int) bool {
    const fl = fcntl(fd, F_GETFL);
    if (fl < 0) return false;
    return fcntl(fd, F_SETFL, fl | O_NONBLOCK) >= 0;
}

pub fn setCloexec(fd: c_int) void {
    const fl = fcntl(fd, F_GETFD);
    if (fl >= 0) _ = fcntl(fd, F_SETFD, fl | FD_CLOEXEC);
}

pub fn physicalCpu() usize {
    var n: c_int = 0;
    var len: usize = @sizeOf(c_int);
    if (sysctlbyname("hw.physicalcpu", &n, &len, null, 0) != 0 or n <= 0) return 1;
    return @intCast(n);
}

/// Resident set size of this process, in bytes (ru_maxrss is peak, in bytes on Darwin).
pub fn peakRss() u64 {
    var ru: [18]c_long = undefined;
    if (getrusage(0, &ru) != 0) return 0;
    // struct rusage: two timevals (4 longs) then ru_maxrss.
    const v: u64 = @intCast(@max(ru[4], 0));
    return if (builtin.os.tag == .macos) v else v * 1024;
}

pub fn childPeakRss() u64 {
    var ru: [18]c_long = undefined;
    if (getrusage(-1, &ru) != 0) return 0;
    const v: u64 = @intCast(@max(ru[4], 0));
    return if (builtin.os.tag == .macos) v else v * 1024;
}

pub const Mutex = struct {
    m: std.c.pthread_mutex_t = .{},
    pub fn lock(self: *Mutex) void {
        _ = std.c.pthread_mutex_lock(&self.m);
    }
    pub fn unlock(self: *Mutex) void {
        _ = std.c.pthread_mutex_unlock(&self.m);
    }
};

pub const Cond = struct {
    c: std.c.pthread_cond_t = .{},
    pub fn wait(self: *Cond, m: *Mutex) void {
        _ = std.c.pthread_cond_wait(&self.c, &m.m);
    }
    pub fn signal(self: *Cond) void {
        _ = std.c.pthread_cond_signal(&self.c);
    }
    pub fn broadcast(self: *Cond) void {
        _ = std.c.pthread_cond_broadcast(&self.c);
    }
};

// ---------------------------------------------------------------------------
// QoS (macOS scheduling hint; not a P-core guarantee)

pub const QOS_CLASS_USER_INITIATED: c_uint = 0x19;
extern "c" fn pthread_set_qos_class_self_np(qos: c_uint, rel: c_int) c_int;

/// Returns the pthread return code (0 = applied).
pub fn setThreadQos() c_int {
    if (builtin.os.tag != .macos) return -1;
    return pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);
}

// ---------------------------------------------------------------------------
// Files

pub fn zpath(buf: []u8, path: []const u8) ![*:0]const u8 {
    if (path.len + 1 > buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return @ptrCast(buf.ptr);
}

extern "c" fn readdir(dir: *std.c.DIR) ?*std.c.dirent;
pub extern "c" fn rmdir(path: [*:0]const u8) c_int;

/// Remove a directory holding only plain files (e.g. journals/). Best effort.
pub fn removeFlatDir(path: []const u8) void {
    var b: [4096]u8 = undefined;
    const zp = zpath(&b, path) catch return;
    const d = std.c.opendir(zp) orelse return;
    while (readdir(d)) |e| {
        const name = std.mem.sliceTo(&e.name, 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        var fb: [4096]u8 = undefined;
        const fp = std.fmt.bufPrint(&fb, "{s}/{s}", .{ path, name }) catch continue;
        var zb: [4096]u8 = undefined;
        if (zpath(&zb, fp)) |z| _ = unlink(z) else |_| {}
    }
    _ = std.c.closedir(d);
    _ = rmdir(zp);
}

pub fn mkdirp(path: []const u8) !void {
    var buf: [4096]u8 = undefined;
    if (path.len >= buf.len) return error.NameTooLong;
    var i: usize = 1;
    while (i <= path.len) : (i += 1) {
        if (i == path.len or path[i] == '/') {
            @memcpy(buf[0..i], path[0..i]);
            buf[i] = 0;
            if (mkdir(@ptrCast(&buf), 0o755) != 0 and errno() != EEXIST) return error.MkdirFailed;
        }
    }
}

pub fn writeAll(fd: c_int, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = write(fd, bytes.ptr + off, bytes.len - off);
        if (n < 0) {
            if (errno() == EINTR) continue;
            return error.WriteFailed;
        }
        off += @intCast(n);
    }
}

/// Write a file atomically (temp + rename) so a crash of this process never
/// leaves a half-written finding artifact. (No fsync: OS-crash durability is
/// not required and fsync per artifact dominated persistence cost.)
pub fn writeFile(path: []const u8, bytes: []const u8) !void {
    var b1: [4096]u8 = undefined;
    var b2: [4096]u8 = undefined;
    if (path.len + 5 > b1.len) return error.NameTooLong;
    const tmp = try std.fmt.bufPrintZ(&b1, "{s}.tmp", .{path});
    const dst = try zpath(&b2, path);
    const fd = open(tmp.ptr, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, @as(c_int, 0o644));
    if (fd < 0) return error.OpenFailed;
    errdefer _ = close(fd);
    try writeAll(fd, bytes);
    _ = close(fd);
    if (rename(tmp.ptr, dst) != 0) return error.RenameFailed;
}

pub fn appendFile(fd: c_int, bytes: []const u8) !void {
    return writeAll(fd, bytes);
}

pub fn openAppend(path: []const u8) !c_int {
    var b: [4096]u8 = undefined;
    const p = try zpath(&b, path);
    const fd = open(p, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, @as(c_int, 0o644));
    if (fd < 0) return error.OpenFailed;
    return fd;
}

pub fn readFileAlloc(gpa: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    var b: [4096]u8 = undefined;
    const p = try zpath(&b, path);
    const fd = open(p, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return error.FileNotFound;
    defer _ = close(fd);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var tmp: [65536]u8 = undefined;
    while (true) {
        const n = read(fd, &tmp, tmp.len);
        if (n < 0) {
            if (errno() == EINTR) continue;
            return error.ReadFailed;
        }
        if (n == 0) break;
        if (out.items.len + @as(usize, @intCast(n)) > max) return error.FileTooBig;
        try out.appendSlice(gpa, tmp[0..@intCast(n)]);
    }
    return out.toOwnedSlice(gpa);
}

pub fn fileExists(path: []const u8) bool {
    var b: [4096]u8 = undefined;
    const p = zpath(&b, path) catch return false;
    return access(p, 0) == 0;
}

pub fn stderrPrint(comptime fmt: []const u8, args: anytype) void {
    var buf: [8192]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch blk: {
        break :blk buf[0..];
    };
    writeAll(2, s) catch {};
}

pub fn stdoutPrint(comptime fmt: []const u8, args: anytype) void {
    var buf: [8192]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch buf[0..];
    writeAll(1, s) catch {};
}
