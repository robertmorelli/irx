//! Engine child processes: posix_spawn (with QoS and null crash exception
//! ports where available), the line protocol, a nonblocking poll transport
//! with absolute deadlines, bounded stderr tails, per-process journals, the
//! source/flag novelty set, recycling, and mode probing.
const std = @import("std");
const builtin = @import("builtin");
const sys = @import("sys.zig");
const config = @import("config.zig");

const Allocator = std.mem.Allocator;
const is_darwin = builtin.os.tag == .macos;

// ---------------------------------------------------------------------------
// posix_spawn bindings (opaque storage works for both Darwin pointers and
// Linux structs)

const SpawnBuf = extern struct { b: [256]u8 align(16) = [_]u8{0} ** 256 };
extern "c" fn posix_spawn(pid: *sys.pid_t, path: [*:0]const u8, fa: *const SpawnBuf, attr: *const SpawnBuf, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;
extern "c" fn posix_spawn_file_actions_init(fa: *SpawnBuf) c_int;
extern "c" fn posix_spawn_file_actions_destroy(fa: *SpawnBuf) c_int;
extern "c" fn posix_spawn_file_actions_adddup2(fa: *SpawnBuf, fd: c_int, newfd: c_int) c_int;
extern "c" fn posix_spawnattr_init(attr: *SpawnBuf) c_int;
extern "c" fn posix_spawnattr_destroy(attr: *SpawnBuf) c_int;
extern "c" fn posix_spawnattr_setflags(attr: *SpawnBuf, flags: c_short) c_int;
extern "c" fn posix_spawnattr_setsigdefault(attr: *SpawnBuf, set: *const SigSet) c_int;
extern "c" fn posix_spawnattr_setsigmask(attr: *SpawnBuf, set: *const SigSet) c_int;
extern "c" fn posix_spawnattr_setpgroup(attr: *SpawnBuf, pgroup: sys.pid_t) c_int;
extern "c" fn sigemptyset(set: *SigSet) c_int;
extern "c" fn sigaddset(set: *SigSet, sig: c_int) c_int;
extern "c" var environ: [*:null]const ?[*:0]const u8;
const SigSet = extern struct { b: [128]u8 align(8) = [_]u8{0} ** 128 };

// Darwin-only
extern "c" fn posix_spawnattr_set_qos_class_np(attr: *SpawnBuf, qos: c_uint) c_int;
extern "c" fn posix_spawnattr_setexceptionports_np(attr: *SpawnBuf, mask: u32, port: u32, behavior: c_int, flavor: c_int) c_int;

const POSIX_SPAWN_SETSIGDEF: c_short = 0x04;
const POSIX_SPAWN_SETSIGMASK: c_short = 0x08;
const POSIX_SPAWN_SETPGROUP: c_short = 0x02;
const POSIX_SPAWN_CLOEXEC_DEFAULT: c_short = 0x4000;
const EXC_MASK_CRASH: u32 = 1 << 10;
const EXC_MASK_CORPSE_NOTIFY: u32 = 1 << 13;
const EXCEPTION_DEFAULT: c_int = 1;
const MACH_PORT_NULL: u32 = 0;

pub const SpawnReport = struct {
    qos_rc: c_int = -1,
    excports_rc: c_int = -1,
};

pub const SpawnResult = struct {
    pid: sys.pid_t,
    fd_in: c_int,
    fd_out: c_int,
    fd_err: c_int,
    report: SpawnReport,
};

fn closeFd(fd: *c_int) void {
    if (fd.* >= 0) _ = sys.close(fd.*);
    fd.* = -1;
}

/// Spawn argv[0] with stdin/stdout/stderr pipes. Parent ends are nonblocking
/// and close-on-exec.
pub fn spawnPiped(argv: []const [*:0]const u8, suppress_crash_reports: bool) !SpawnResult {
    var pin: [2]c_int = .{ -1, -1 };
    var pout: [2]c_int = .{ -1, -1 };
    var perr: [2]c_int = .{ -1, -1 };
    errdefer {
        for ([_]*[2]c_int{ &pin, &pout, &perr }) |p| {
            closeFd(&p[0]);
            closeFd(&p[1]);
        }
    }
    if (sys.pipe(&pin) != 0 or sys.pipe(&pout) != 0 or sys.pipe(&perr) != 0) return error.PipeFailed;
    for ([_]c_int{ pin[0], pin[1], pout[0], pout[1], perr[0], perr[1] }) |fd| sys.setCloexec(fd);

    var fa: SpawnBuf = .{};
    var attr: SpawnBuf = .{};
    if (posix_spawn_file_actions_init(&fa) != 0) return error.SpawnFailed;
    defer _ = posix_spawn_file_actions_destroy(&fa);
    if (posix_spawnattr_init(&attr) != 0) return error.SpawnFailed;
    defer _ = posix_spawnattr_destroy(&attr);
    _ = posix_spawn_file_actions_adddup2(&fa, pin[0], 0);
    _ = posix_spawn_file_actions_adddup2(&fa, pout[1], 1);
    _ = posix_spawn_file_actions_adddup2(&fa, perr[1], 2);

    // The parent ignores SIGPIPE; restore the default for the child.
    var defsig: SigSet = .{};
    _ = sigemptyset(&defsig);
    _ = sigaddset(&defsig, sys.SIGPIPE);
    _ = posix_spawnattr_setsigdefault(&attr, &defsig);
    var mask: SigSet = .{};
    _ = sigemptyset(&mask);
    _ = posix_spawnattr_setsigmask(&attr, &mask);
    // Each child leads its own process group so a kill also takes down any
    // grandchildren (e.g. the shell a bridge launched).
    _ = posix_spawnattr_setpgroup(&attr, 0);
    var flags: c_short = POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETPGROUP;
    if (is_darwin) flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;
    _ = posix_spawnattr_setflags(&attr, flags);

    var report: SpawnReport = .{};
    if (is_darwin) {
        report.qos_rc = posix_spawnattr_set_qos_class_np(&attr, sys.QOS_CLASS_USER_INITIATED);
        if (suppress_crash_reports) {
            report.excports_rc = posix_spawnattr_setexceptionports_np(&attr, EXC_MASK_CRASH | EXC_MASK_CORPSE_NOTIFY, MACH_PORT_NULL, EXCEPTION_DEFAULT, 0);
        }
    }

    var argz: [64]?[*:0]const u8 = undefined;
    if (argv.len >= argz.len) return error.TooManyArgs;
    for (argv, 0..) |a, i| argz[i] = a;
    argz[argv.len] = null;
    var pid: sys.pid_t = 0;
    const rc = posix_spawn(&pid, argv[0], &fa, &attr, @ptrCast(&argz), environ);
    if (rc != 0) return error.SpawnFailed;
    closeFd(&pin[0]);
    closeFd(&pout[1]);
    closeFd(&perr[1]);
    _ = sys.setNonblock(pin[1]);
    _ = sys.setNonblock(pout[0]);
    _ = sys.setNonblock(perr[0]);
    return .{ .pid = pid, .fd_in = pin[1], .fd_out = pout[0], .fd_err = perr[0], .report = report };
}

pub const ExitInfo = struct {
    exited: bool = false,
    code: u8 = 0,
    signal: u8 = 0,

    pub fn describe(self: ExitInfo, buf: []u8) []const u8 {
        if (self.signal != 0) return std.fmt.bufPrint(buf, "signal {d}", .{self.signal}) catch "signal";
        if (self.exited) return std.fmt.bufPrint(buf, "exit {d}", .{self.code}) catch "exit";
        return "running";
    }
};

fn decodeStatus(st: c_int) ExitInfo {
    const s: u32 = @bitCast(st);
    const low = s & 0x7f;
    if (low == 0) return .{ .exited = true, .code = @intCast((s >> 8) & 0xff) };
    if (low != 0x7f) return .{ .exited = true, .signal = @intCast(low) };
    return .{};
}

pub fn reapBlocking(pid: sys.pid_t) ExitInfo {
    var st: c_int = 0;
    while (true) {
        const r = sys.waitpid(pid, &st, 0);
        if (r == pid) return decodeStatus(st);
        if (r < 0 and sys.errno() == sys.EINTR) continue;
        return .{ .exited = true };
    }
}

pub fn reapNonblocking(pid: sys.pid_t) ?ExitInfo {
    var st: c_int = 0;
    const r = sys.waitpid(pid, &st, sys.WNOHANG);
    if (r == pid) return decodeStatus(st);
    if (r < 0 and sys.errno() == sys.ECHILD) return .{ .exited = true };
    return null;
}

// ---------------------------------------------------------------------------
// Modes

/// shell: any JS shell given as a command template (`--shell "CMD {driver} {mode}"`).
pub const Engine = enum { d8, sm, jsc, shell, perl };
pub const Expect = enum { normal, tierup, linear };

pub const ModeSpec = struct {
    name: []const u8,
    engine: Engine = .d8,
    flags: []const []const u8,
    driver_mode: []const u8,
    expect: Expect = .normal,
    optional: bool = false,
};

pub const builtin_modes = [_]ModeSpec{
    .{ .name = "interp", .flags = &.{"--regexp-interpret-all"}, .driver_mode = "interp" },
    .{ .name = "native", .flags = &.{"--no-regexp-tier-up"}, .driver_mode = "native" },
    .{ .name = "tierup", .flags = &.{ "--regexp-tier-up", "--regexp-tier-up-ticks=1" }, .driver_mode = "tierup", .expect = .tierup },
    .{ .name = "linear", .flags = &.{"--enable-experimental-regexp-engine"}, .driver_mode = "linear", .expect = .linear, .optional = true },
    .{ .name = "noopt", .flags = &.{"--no-regexp-optimization"}, .driver_mode = "noopt", .optional = true },
    .{ .name = "nopeephole", .flags = &.{"--no-regexp-peephole-optimization"}, .driver_mode = "nopeephole", .optional = true },
    .{ .name = "fallback0", .flags = &.{ "--enable-experimental-regexp-engine-on-excessive-backtracks", "--regexp-backtracks-before-fallback=0" }, .driver_mode = "fallback0", .optional = true },
    .{ .name = "sm", .engine = .sm, .flags = &.{}, .driver_mode = "sanity", .optional = true },
    .{ .name = "jsc", .engine = .jsc, .flags = &.{}, .driver_mode = "sanity", .optional = true },
    .{ .name = "shell", .engine = .shell, .flags = &.{}, .driver_mode = "interp" },
    .{ .name = "shell-repeat", .engine = .shell, .flags = &.{}, .driver_mode = "tierup", .expect = .tierup },
    .{ .name = "perl", .engine = .perl, .flags = &.{}, .driver_mode = "perl" },
    .{ .name = "perl-repeat", .engine = .perl, .flags = &.{}, .driver_mode = "repeat", .expect = .tierup },
};

pub fn findMode(name: []const u8) ?*const ModeSpec {
    for (&builtin_modes) |*m| if (std.mem.eql(u8, m.name, name)) return m;
    return null;
}

/// Result bit layout.
pub const Bits = struct {
    pub const test_a: u8 = 1;
    pub const test_r: u8 = 2;
    pub const syntax: u8 = 4;
    pub const exception: u8 = 8;
    pub const test_a2: u8 = 16;
    pub const test_r2: u8 = 32;
    pub const skipped: u8 = 64;
    pub const reserved: u8 = 128;
};

/// Bits a mode may legally report.
pub fn validBits(expect: Expect, b: u8) bool {
    if (b & Bits.reserved != 0) return false;
    if (expect != .tierup and b & (Bits.test_a2 | Bits.test_r2) != 0) return false;
    if (b & Bits.skipped != 0) return expect == .linear and b == Bits.skipped;
    if (b & (Bits.syntax | Bits.exception) != 0) return b == Bits.syntax or b == Bits.exception;
    return true;
}

// ---------------------------------------------------------------------------
// Batches and children

pub const BatchState = enum { queued, answered, failed };

pub const Batch = struct {
    seq: u64,
    ncases: u32,
    req: []u8, // includes trailing '\n'
    sent: usize = 0,
    deadline: u64 = 0,
    state: BatchState = .queued,
    bits: []u8 = &.{},
};

pub const Failure = enum { none, timeout, crash, protocol, eof, spawn };

pub const Ring = struct {
    buf: []u8,
    head: usize = 0,
    len: usize = 0,
    truncated: u64 = 0,

    pub fn push(self: *Ring, data: []const u8) void {
        if (self.buf.len == 0) {
            self.truncated += data.len;
            return;
        }
        for (data) |c| {
            if (self.len == self.buf.len) {
                self.head = (self.head + 1) % self.buf.len;
                self.len -= 1;
                self.truncated += 1;
            }
            self.buf[(self.head + self.len) % self.buf.len] = c;
            self.len += 1;
        }
    }

    pub fn copyOut(self: *const Ring, gpa: Allocator) ![]u8 {
        const out = try gpa.alloc(u8, self.len);
        for (0..self.len) |i| out[i] = self.buf[(self.head + i) % self.buf.len];
        return out;
    }
};

/// Collision-checked set of (flags, pattern) seen by one process.
pub const Novelty = struct {
    map: std.HashMapUnmanaged(u64, Entry, std.hash_map.AutoContext(u64), 80) = .empty,
    store: std.ArrayList(u8) = .empty,
    entries: u32 = 0,
    first_seen: u64 = 0,
    repeated: u64 = 0,
    const Entry = struct { off: u32, len: u32 };

    /// Returns true if first seen. Hash collisions are resolved by probing
    /// successive keys and comparing the stored bytes.
    pub fn note(self: *Novelty, gpa: Allocator, flags: u8, pattern: []const u8) !bool {
        var h = std.hash.Wyhash.init(flags);
        h.update(pattern);
        var key = h.final();
        while (self.map.get(key)) |e| {
            const s = self.store.items[e.off .. e.off + e.len];
            if (s.len == pattern.len + 1 and s[0] == flags and std.mem.eql(u8, s[1..], pattern)) {
                self.repeated += 1;
                return false;
            }
            key +%= 0x9E3779B97F4A7C15;
        }
        const off: u32 = @intCast(self.store.items.len);
        try self.store.append(gpa, flags);
        try self.store.appendSlice(gpa, pattern);
        try self.map.put(gpa, key, .{ .off = off, .len = @intCast(pattern.len + 1) });
        self.entries += 1;
        self.first_seen += 1;
        return true;
    }

    pub fn bytes(self: *const Novelty) u64 {
        return self.store.capacity + @as(u64, self.map.capacity()) * (8 + 8 + 1);
    }

    pub fn deinit(self: *Novelty, gpa: Allocator) void {
        self.map.deinit(gpa);
        self.store.deinit(gpa);
    }
};

pub const ChildOptions = struct {
    exe: []const u8,
    driver_path: []const u8,
    journal_path: ?[]const u8,
    cfg: *const config.Config,
    suppress_crash_reports: bool = true,
};

pub const Child = struct {
    gpa: Allocator,
    spec: *const ModeSpec,
    opts: ChildOptions,
    pid: sys.pid_t = 0,
    fd_in: c_int = -1,
    fd_out: c_int = -1,
    fd_err: c_int = -1,
    alive: bool = false,
    version: [160]u8 = undefined,
    version_len: usize = 0,
    line: std.ArrayList(u8) = .empty,
    max_line: usize = 0,
    err: Ring,
    queue: std.ArrayList(*Batch) = .empty,
    journal_fd: c_int = -1,
    journal_path: []u8 = &.{},
    journal_bytes: u64 = 0,
    journal_referenced: bool = false,
    cases_run: u64 = 0,
    novelty: Novelty = .{},
    failure: Failure = .none,
    exit: ExitInfo = .{},
    reaped: bool = false,
    msg: [256]u8 = undefined,
    msg_len: usize = 0,
    spawn_report: SpawnReport = .{},
    started_ns: u64 = 0,
    startup_ns: u64 = 0,

    pub fn versionStr(self: *const Child) []const u8 {
        return self.version[0..self.version_len];
    }
    pub fn message(self: *const Child) []const u8 {
        return self.msg[0..self.msg_len];
    }
    fn setMsg(self: *Child, comptime f: []const u8, args: anytype) void {
        const s = std.fmt.bufPrint(&self.msg, f, args) catch self.msg[0..];
        self.msg_len = s.len;
    }

    pub fn create(gpa: Allocator, spec: *const ModeSpec, opts: ChildOptions) !*Child {
        const c = try gpa.create(Child);
        errdefer gpa.destroy(c);
        c.* = .{ .gpa = gpa, .spec = spec, .opts = opts, .err = .{ .buf = try gpa.alloc(u8, opts.cfg.stderr_tail_bytes) } };
        c.max_line = 2 * @as(usize, opts.cfg.batch_size) * 2 + 4096;
        return c;
    }

    pub fn destroy(self: *Child) void {
        self.kill();
        self.retireJournal();
        self.line.deinit(self.gpa);
        self.queue.deinit(self.gpa);
        self.novelty.deinit(self.gpa);
        self.gpa.free(self.err.buf);
        if (self.journal_path.len > 0) self.gpa.free(self.journal_path);
        self.gpa.destroy(self);
    }

    pub fn argv(self: *const Child, buf: *[24][*:0]const u8, zbuf: *[24][512]u8) ![]const [*:0]const u8 {
        var n: usize = 0;
        const put = struct {
            fn f(b: *[24][*:0]const u8, z: *[24][512]u8, i: *usize, s: []const u8) !void {
                if (i.* >= 24 or s.len >= 512) return error.ArgTooLong;
                @memcpy(z[i.*][0..s.len], s);
                z[i.*][s.len] = 0;
                b[i.*] = @ptrCast(&z[i.*]);
                i.* += 1;
            }
        }.f;
        if (self.spec.engine == .shell) {
            // exe holds the command template; {driver} and {mode} are substituted.
            var it = std.mem.tokenizeScalar(u8, self.opts.exe, ' ');
            while (it.next()) |tok| {
                if (std.mem.eql(u8, tok, "{driver}")) try put(buf, zbuf, &n, self.opts.driver_path)
                else if (std.mem.eql(u8, tok, "{mode}")) try put(buf, zbuf, &n, self.spec.driver_mode)
                else try put(buf, zbuf, &n, tok);
            }
            return buf[0..n];
        }
        try put(buf, zbuf, &n, self.opts.exe);
        for (self.spec.flags) |f| try put(buf, zbuf, &n, f);
        try put(buf, zbuf, &n, self.opts.driver_path);
        switch (self.spec.engine) {
            .d8 => {
                try put(buf, zbuf, &n, "--");
                try put(buf, zbuf, &n, self.spec.driver_mode);
            },
            .sm, .perl => try put(buf, zbuf, &n, self.spec.driver_mode),
            .jsc => {
                try put(buf, zbuf, &n, "--");
                try put(buf, zbuf, &n, self.spec.driver_mode);
            },
            .shell => unreachable,
        }
        return buf[0..n];
    }

    /// Spawn and complete the `ready` handshake within the startup deadline.
    pub fn start(self: *Child) !void {
        var ab: [24][*:0]const u8 = undefined;
        var zb: [24][512]u8 = undefined;
        const av = try self.argv(&ab, &zb);
        self.started_ns = sys.nowNs();
        const r = spawnPiped(av, self.opts.suppress_crash_reports) catch {
            self.failure = .spawn;
            self.setMsg("spawn failed: {s}", .{self.opts.exe});
            return error.SpawnFailed;
        };
        self.pid = r.pid;
        self.fd_in = r.fd_in;
        self.fd_out = r.fd_out;
        self.fd_err = r.fd_err;
        self.spawn_report = r.report;
        self.alive = true;
        self.reaped = false;
        self.exit = .{};
        self.failure = .none;
        self.line.clearRetainingCapacity();
        self.err.head = 0;
        self.err.len = 0;
        self.err.truncated = 0;
        self.cases_run = 0;
        self.novelty.deinit(self.gpa);
        self.novelty = .{};

        if (self.opts.journal_path) |jp| {
            if (self.journal_path.len > 0) self.gpa.free(self.journal_path);
            self.journal_path = try std.fmt.allocPrint(self.gpa, "{s}.{d}", .{ jp, self.pid });
            self.journal_fd = try sys.openAppend(self.journal_path);
            self.journal_bytes = 0;
            self.journal_referenced = false;
            var hdr: std.ArrayList(u8) = .empty;
            defer hdr.deinit(self.gpa);
            try hdr.print(self.gpa, "# irx journal v1 mode={s} pid={d} call-order=construct,test(A),test(R)", .{ self.spec.name, self.pid });
            if (self.spec.expect == .tierup) try hdr.appendSlice(self.gpa, ",test(A),test(R)");
            try hdr.appendSlice(self.gpa, " argv=");
            for (av) |a| try hdr.print(self.gpa, "{s} ", .{std.mem.span(a)});
            try hdr.append(self.gpa, '\n');
            try sys.appendFile(self.journal_fd, hdr.items);
            self.journal_bytes += hdr.items.len;
        }

        const deadline = self.started_ns + @as(u64, self.opts.cfg.startup_deadline_ms) * std.time.ns_per_ms;
        while (true) {
            if (std.mem.indexOfScalar(u8, self.line.items, '\n')) |nl| {
                const l = self.line.items[0..nl];
                if (!std.mem.startsWith(u8, l, "ready ")) {
                    self.setMsg("malformed handshake: {s}", .{l[0..@min(l.len, 200)]});
                    self.failure = .protocol;
                    self.kill();
                    return error.BadHandshake;
                }
                const v = l[6..];
                self.version_len = @min(v.len, self.version.len);
                @memcpy(self.version[0..self.version_len], v[0..self.version_len]);
                const rest = self.line.items.len - nl - 1;
                std.mem.copyForwards(u8, self.line.items[0..rest], self.line.items[nl + 1 ..]);
                self.line.shrinkRetainingCapacity(rest);
                self.startup_ns = sys.nowNs() - self.started_ns;
                return;
            }
            const now = sys.nowNs();
            if (now >= deadline) {
                self.setMsg("startup deadline exceeded", .{});
                self.failure = .timeout;
                self.kill();
                return error.StartupTimeout;
            }
            var pfds = [_]sys.pollfd{
                .{ .fd = self.fd_out, .events = sys.POLLIN, .revents = 0 },
                .{ .fd = self.fd_err, .events = sys.POLLIN, .revents = 0 },
            };
            const to: c_int = @intCast(@max(1, @min((deadline - now) / std.time.ns_per_ms, 1000)));
            const pr = sys.poll(&pfds, 2, to);
            if (pr < 0 and sys.errno() != sys.EINTR) return error.PollFailed;
            if (pfds[1].revents != 0) self.drainErr();
            if (pfds[0].revents != 0) {
                if (!self.readOut()) {
                    self.setMsg("eof before handshake", .{});
                    self.failure = .eof;
                    self.kill();
                    return error.BadHandshake;
                }
            }
        }
    }

    /// Kill and reap, closing descriptors. Idempotent.
    pub fn kill(self: *Child) void {
        if (self.pid > 0) _ = sys.kill(-self.pid, sys.SIGKILL); // stragglers in the group
        if (self.alive) {
            if (!self.reaped) {
                if (reapNonblocking(self.pid)) |e| {
                    self.exit = e;
                } else {
                    _ = sys.kill(-self.pid, sys.SIGKILL); // whole process group
                    _ = sys.kill(self.pid, sys.SIGKILL);
                    self.exit = reapBlocking(self.pid);
                }
                self.reaped = true;
            }
            self.alive = false;
        }
        closeFd(&self.fd_in);
        closeFd(&self.fd_out);
        closeFd(&self.fd_err);
    }

    /// Close stdin and wait (bounded) for a clean exit.
    pub fn shutdown(self: *Child, timeout_ms: u64) void {
        if (!self.alive) return;
        closeFd(&self.fd_in);
        const end = sys.nowNs() + timeout_ms * std.time.ns_per_ms;
        while (sys.nowNs() < end) {
            self.drainErr();
            _ = self.readOut();
            if (reapNonblocking(self.pid)) |e| {
                self.exit = e;
                self.reaped = true;
                break;
            }
            _ = sys.usleep(1000);
        }
        self.kill();
    }

    fn retireJournal(self: *Child) void {
        if (self.journal_fd >= 0) {
            _ = sys.close(self.journal_fd);
            self.journal_fd = -1;
        }
    }

    /// Delete the journal if no finding references it (call after all of its
    /// cases are resolved and the process has retired).
    pub fn discardJournalIfUnreferenced(self: *Child) void {
        self.retireJournal();
        if (!self.journal_referenced and self.journal_path.len > 0) {
            var b: [4096]u8 = undefined;
            if (sys.zpath(&b, self.journal_path)) |p| _ = sys.unlink(p) else |_| {}
        }
    }

    pub fn canAdmit(self: *const Child, req_bytes: usize) bool {
        if (!self.alive) return false;
        if (self.journal_fd >= 0 and self.journal_bytes + req_bytes > self.opts.cfg.journal_bytes) return false;
        return true;
    }

    pub fn needsRecycle(self: *const Child) bool {
        const c = self.opts.cfg;
        return self.cases_run >= c.recycle_cases or self.novelty.entries >= c.novelty_cap or self.novelty.bytes() >= c.novelty_bytes or
            (self.journal_fd >= 0 and self.journal_bytes >= c.journal_bytes);
    }

    /// Journal the exact request, then queue it with an absolute deadline.
    pub fn admit(self: *Child, b: *Batch, deadline: u64) !void {
        if (self.journal_fd >= 0) {
            sys.appendFile(self.journal_fd, b.req) catch return error.JournalWriteFailed;
            self.journal_bytes += b.req.len;
        }
        b.deadline = deadline;
        b.sent = 0;
        b.state = .queued;
        try self.queue.append(self.gpa, b);
    }

    fn readOut(self: *Child) bool {
        var tmp: [65536]u8 = undefined;
        var budget: usize = 4; // bounded per-fd work per poll round
        while (budget > 0) : (budget -= 1) {
            const n = sys.read(self.fd_out, &tmp, tmp.len);
            if (n < 0) {
                const e = sys.errno();
                if (e == sys.EINTR) continue;
                return true; // EAGAIN
            }
            if (n == 0) return false;
            const un: usize = @intCast(n);
            if (self.line.items.len + un > self.max_line + 2 * self.max_line) {
                // keep the protocol check bounded; extraction below flags it
                self.line.appendSlice(self.gpa, tmp[0..@min(un, self.max_line)]) catch {};
                return true;
            }
            self.line.appendSlice(self.gpa, tmp[0..un]) catch return true;
        }
        return true;
    }

    pub fn drainErr(self: *Child) void {
        if (self.fd_err < 0) return;
        var tmp: [65536]u8 = undefined;
        var budget: usize = 4;
        while (budget > 0) : (budget -= 1) {
            const n = sys.read(self.fd_err, &tmp, tmp.len);
            if (n < 0) {
                if (sys.errno() == sys.EINTR) continue;
                return;
            }
            if (n == 0) {
                closeFd(&self.fd_err);
                return;
            }
            self.err.push(tmp[0..@intCast(n)]);
        }
    }

    fn writeSome(self: *Child) void {
        for (self.queue.items) |b| {
            if (b.sent == b.req.len) continue;
            while (b.sent < b.req.len) {
                const n = sys.write(self.fd_in, b.req.ptr + b.sent, b.req.len - b.sent);
                if (n < 0) {
                    const e = sys.errno();
                    if (e == sys.EINTR) continue;
                    if (e == sys.EAGAIN) return;
                    // EPIPE or other: child is gone or not reading
                    self.fail(.eof, "write failed (errno {d})", .{e});
                    return;
                }
                b.sent += @intCast(n);
            }
            return; // one batch per round keeps per-fd work bounded
        }
    }

    fn hasUnsent(self: *const Child) bool {
        for (self.queue.items) |b| if (b.sent < b.req.len) return true;
        return false;
    }

    pub fn earliestDeadline(self: *const Child) ?u64 {
        var d: ?u64 = null;
        for (self.queue.items) |b| d = if (d) |x| @min(x, b.deadline) else b.deadline;
        return d;
    }

    /// Mark the child failed: kill/reap it and fail all unanswered batches.
    pub fn fail(self: *Child, why: Failure, comptime f: []const u8, args: anytype) void {
        if (self.failure == .none) {
            self.failure = why;
            self.setMsg(f, args);
        }
        self.drainErr();
        self.kill();
        for (self.queue.items) |b| b.state = .failed;
        self.queue.clearRetainingCapacity();
    }

    fn hexVal(c: u8) ?u8 {
        return switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            else => null,
        };
    }

    fn processLines(self: *Child) void {
        while (self.alive) {
            const nl = std.mem.indexOfScalar(u8, self.line.items, '\n') orelse {
                if (self.line.items.len > self.max_line) self.fail(.protocol, "response line exceeds {d} bytes", .{self.max_line});
                return;
            };
            const l = self.line.items[0..nl];
            if (self.queue.items.len == 0) return self.fail(.protocol, "unsolicited output: {s}", .{l[0..@min(l.len, 120)]});
            const b = self.queue.items[0];
            if (b.sent < b.req.len) return self.fail(.protocol, "response before request fully sent", .{});
            const sp = std.mem.indexOfScalar(u8, l, ' ') orelse return self.fail(.protocol, "missing separator: {s}", .{l[0..@min(l.len, 120)]});
            const seq = std.fmt.parseInt(u64, l[0..sp], 10) catch return self.fail(.protocol, "bad sequence: {s}", .{l[0..@min(sp, 60)]});
            if (seq != b.seq) return self.fail(.protocol, "sequence {d}, expected {d}", .{ seq, b.seq });
            const hex = l[sp + 1 ..];
            if (hex.len != 2 * @as(usize, b.ncases)) return self.fail(.protocol, "hex length {d}, expected {d}", .{ hex.len, 2 * b.ncases });
            for (0..b.ncases) |i| {
                const hi = hexVal(hex[2 * i]) orelse return self.fail(.protocol, "bad hex digit", .{});
                const lo = hexVal(hex[2 * i + 1]) orelse return self.fail(.protocol, "bad hex digit", .{});
                const v = hi * 16 + lo;
                if (!validBits(self.spec.expect, v)) return self.fail(.protocol, "disallowed result bits {x:0>2} for mode {s}", .{ v, self.spec.name });
                b.bits[i] = v;
            }
            b.state = .answered;
            self.cases_run += b.ncases;
            _ = self.queue.orderedRemove(0);
            const rest = self.line.items.len - nl - 1;
            std.mem.copyForwards(u8, self.line.items[0..rest], self.line.items[nl + 1 ..]);
            self.line.shrinkRetainingCapacity(rest);
        }
    }

    pub fn busy(self: *const Child) bool {
        return self.queue.items.len > 0;
    }
};

/// One poll round over the given children: write pending requests, read
/// responses and stderr, enforce deadlines. Never blocks past the earliest
/// pending deadline (or `max_wait_ms`).
pub fn pump(children: []const *Child, max_wait_ms: u64) void {
    var pfds: [64]sys.pollfd = undefined;
    var owners: [64]struct { c: *Child, kind: u8 } = undefined;
    var n: usize = 0;
    var now = sys.nowNs();
    var earliest: ?u64 = null;
    for (children) |c| {
        if (!c.alive) continue;
        if (c.earliestDeadline()) |d| {
            if (d <= now) {
                c.fail(.timeout, "batch deadline exceeded", .{});
                continue;
            }
            earliest = if (earliest) |e| @min(e, d) else d;
        }
        if (n + 3 > pfds.len) break;
        if (c.hasUnsent()) {
            pfds[n] = .{ .fd = c.fd_in, .events = sys.POLLOUT, .revents = 0 };
            owners[n] = .{ .c = c, .kind = 0 };
            n += 1;
        }
        pfds[n] = .{ .fd = c.fd_out, .events = sys.POLLIN, .revents = 0 };
        owners[n] = .{ .c = c, .kind = 1 };
        n += 1;
        if (c.fd_err >= 0) {
            pfds[n] = .{ .fd = c.fd_err, .events = sys.POLLIN, .revents = 0 };
            owners[n] = .{ .c = c, .kind = 2 };
            n += 1;
        }
    }
    if (n == 0) return;
    var wait_ns: u64 = max_wait_ms * std.time.ns_per_ms;
    if (earliest) |e| wait_ns = @min(wait_ns, e - now);
    const to: c_int = @intCast(@max(@as(u64, 1), (wait_ns + std.time.ns_per_ms - 1) / std.time.ns_per_ms));
    const pr = sys.poll(&pfds, @intCast(n), to);
    if (pr < 0) return; // EINTR: caller loops
    for (pfds[0..n], owners[0..n]) |p, o| {
        if (p.revents == 0 or !o.c.alive) continue;
        switch (o.kind) {
            0 => if (p.revents & (sys.POLLOUT | sys.POLLERR | sys.POLLHUP) != 0) o.c.writeSome(),
            1 => {
                if (!o.c.readOut()) {
                    o.c.processLines();
                    if (o.c.alive) {
                        o.c.drainErr();
                        // EOF on stdout: the process exited or closed it. Give it a
                        // short bounded window to finish dying so the signal is kept.
                        var tries: usize = 0;
                        while (tries < 100 and !o.c.reaped) : (tries += 1) {
                            if (reapNonblocking(o.c.pid)) |e| {
                                o.c.exit = e;
                                o.c.reaped = true;
                                break;
                            }
                            _ = sys.usleep(1000);
                        }
                        const why: Failure = if (o.c.reaped) (if (o.c.exit.signal != 0) .crash else .eof) else if (reapNonblocking(o.c.pid)) |e| blk: {
                            o.c.exit = e;
                            o.c.reaped = true;
                            break :blk if (e.signal != 0) .crash else .eof;
                        } else .eof;
                        o.c.fail(why, "stdout closed", .{});
                    }
                } else o.c.processLines();
            },
            2 => o.c.drainErr(),
            else => {},
        }
    }
    now = sys.nowNs();
    for (children) |c| {
        if (!c.alive) continue;
        if (c.earliestDeadline()) |d| if (d <= now) c.fail(.timeout, "batch deadline exceeded", .{});
    }
}

/// Batch deadline: max(base, per512 × n / 512).
pub fn batchDeadlineNs(cfg: *const config.Config, ncases: usize) u64 {
    const base: u64 = cfg.batch_deadline_base_ms;
    const scaled: u64 = @as(u64, cfg.batch_deadline_per512_ms) * ncases / 512;
    return @max(base, scaled) * std.time.ns_per_ms;
}

/// Run one batch to completion on one child (used by probes, replay and triage).
pub fn runSync(c: *Child, b: *Batch) BatchState {
    if (!c.alive) return .failed;
    c.admit(b, sys.nowNs() + batchDeadlineNs(c.opts.cfg, b.ncases)) catch return .failed;
    while (b.state == .queued and c.alive) pump(&.{c}, 1000);
    if (b.state == .queued) b.state = .failed;
    return b.state;
}

// ---------------------------------------------------------------------------
// Request encoding

pub fn jsonString(out: *std.ArrayList(u8), gpa: Allocator, units: []const u16) !void {
    try out.append(gpa, '"');
    for (units) |u| {
        if (u == '"' or u == '\\') {
            try out.append(gpa, '\\');
            try out.append(gpa, @intCast(u));
        } else if (u >= 0x20 and u < 0x7f) {
            try out.append(gpa, @intCast(u));
        } else {
            try out.print(gpa, "\\u{x:0>4}", .{u});
        }
    }
    try out.append(gpa, '"');
}

pub fn jsonAscii(out: *std.ArrayList(u8), gpa: Allocator, s: []const u8) !void {
    try out.append(gpa, '"');
    for (s) |c| {
        if (c == '"' or c == '\\') {
            try out.append(gpa, '\\');
            try out.append(gpa, c);
        } else if (c >= 0x20 and c < 0x7f) try out.append(gpa, c) else try out.print(gpa, "\\u{x:0>4}", .{c});
    }
    try out.append(gpa, '"');
}

pub const WireCase = struct {
    flags: []const u8,
    a: []const u16,
    r: []const u16,
    pattern: []const u8,
};

pub fn encodeCase(out: *std.ArrayList(u8), gpa: Allocator, c: WireCase) !void {
    try out.append(gpa, '[');
    try jsonAscii(out, gpa, c.flags);
    try out.append(gpa, ',');
    try jsonString(out, gpa, c.a);
    try out.append(gpa, ',');
    try jsonString(out, gpa, c.r);
    try out.append(gpa, ',');
    try jsonAscii(out, gpa, c.pattern);
    try out.append(gpa, ']');
}

// ---------------------------------------------------------------------------
// Probing

pub const ProbeResult = struct {
    ok: bool,
    reason: []const u8,
    version: []const u8 = &.{},
    startup_ns: u64 = 0,
    flush_verified: bool = false,
};

/// Launch a short-lived child for `spec`, check the handshake, flushing
/// (a response must arrive while the child stays alive), and a known answer.
pub fn probeMode(gpa: Allocator, spec: *const ModeSpec, opts: ChildOptions) ProbeResult {
    var o = opts;
    o.journal_path = null;
    const c = Child.create(gpa, spec, o) catch return .{ .ok = false, .reason = "alloc" };
    defer c.destroy();
    c.start() catch return .{ .ok = false, .reason = gpa.dupe(u8, c.message()) catch "handshake failed" };
    // Known-answer batch: /a/ on ("a", "b") -> test(A)=1, test(R)=0.
    var req: std.ArrayList(u8) = .empty;
    defer req.deinit(gpa);
    req.appendSlice(gpa, "[1,[") catch return .{ .ok = false, .reason = "alloc" };
    encodeCase(&req, gpa, .{ .flags = "", .a = &.{'a'}, .r = &.{'b'}, .pattern = "a" }) catch return .{ .ok = false, .reason = "alloc" };
    req.appendSlice(gpa, ",") catch return .{ .ok = false, .reason = "alloc" };
    const astral_pat = if (spec.engine == .perl) "\\x{1F600}" else "\\u{1F600}";
    const astral_r: []const u16 = if (spec.engine == .perl) &.{'a'} else &.{0xD83D};
    encodeCase(&req, gpa, .{ .flags = "u", .a = &.{ 0xD83D, 0xDE00 }, .r = astral_r, .pattern = astral_pat }) catch return .{ .ok = false, .reason = "alloc" };
    req.appendSlice(gpa, "]]\n") catch return .{ .ok = false, .reason = "alloc" };
    var bits: [2]u8 = undefined;
    var b: Batch = .{ .seq = 1, .ncases = 2, .req = req.items, .bits = &bits };
    if (runSync(c, &b) != .answered) return .{ .ok = false, .reason = gpa.dupe(u8, c.message()) catch "no response" };
    // Response arrived while the child is still alive: output is flushed per line.
    const flushed = c.alive;
    const want: u8 = if (spec.expect == .tierup) 0x11 else 0x01;
    // The linear engine may legitimately mark the u-flag case unsupported.
    const second_ok = bits[1] == want or (spec.expect == .linear and bits[1] == Bits.skipped);
    if (bits[0] != want or !second_ok) return .{ .ok = false, .reason = "known-answer mismatch" };
    // A second batch must also be answered on the same process.
    bits = .{ 0, 0 };
    req.items[1] = '2';
    var b2: Batch = .{ .seq = 2, .ncases = 2, .req = req.items, .bits = &bits };
    if (runSync(c, &b2) != .answered) return .{ .ok = false, .reason = "second batch unanswered" };
    const v = gpa.dupe(u8, c.versionStr()) catch &.{};
    const st = c.startup_ns;
    c.shutdown(2000);
    return .{ .ok = true, .reason = "ok", .version = v, .startup_ns = st, .flush_verified = flushed };
}

/// Verify crash-report suppression with a controlled crashing helper. Returns
/// the spawn attribute return code, the observed signal, and the reap latency.
pub const CrashProbe = struct { excports_rc: c_int, signal: u8, reap_ms: u64 };
pub fn crashProbe() ?CrashProbe {
    const av = [_][*:0]const u8{ "/bin/sh", "-c", "kill -SEGV $$" };
    const t0 = sys.nowNs();
    const r = spawnPiped(&av, true) catch return null;
    defer {
        _ = sys.close(r.fd_in);
        _ = sys.close(r.fd_out);
        _ = sys.close(r.fd_err);
    }
    const e = reapBlocking(r.pid);
    return .{ .excports_rc = r.report.excports_rc, .signal = e.signal, .reap_ms = (sys.nowNs() - t0) / std.time.ns_per_ms };
}

// ---------------------------------------------------------------------------
// Tests: transport behavior with a fake child (/bin/sh scripts).

const testing = std.testing;

fn fakeSpec(name: []const u8) ModeSpec {
    return .{ .name = name, .flags = &.{}, .driver_mode = "x" };
}

fn shChild(gpa: Allocator, script: [:0]const u8, cfg: *const config.Config, spec: *const ModeSpec) !*Child {
    // exe=/bin/sh, driver_path="-c" is abused as argv: sh <flags> -c script -- mode
    _ = script;
    return Child.create(gpa, spec, .{ .exe = "/bin/sh", .driver_path = "/dev/null", .journal_path = null, .cfg = cfg, .suppress_crash_reports = true });
}

fn startScript(c: *Child, script: []const u8) !void {
    // Override argv by writing the script to a temp file and using it as the driver path.
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/tmp/irx-test-{d}-{d}.sh", .{ sys.getpid(), @intFromPtr(c) });
    try sys.writeFile(path, script);
    c.opts.driver_path = try c.gpa.dupe(u8, path);
    try c.start();
}

fn makeBatch(gpa: Allocator, seq: u64, n: u32, payload_len: usize) !*Batch {
    const b = try gpa.create(Batch);
    var req = try gpa.alloc(u8, payload_len + 1);
    @memset(req[0..payload_len], 'x');
    req[payload_len] = '\n';
    b.* = .{ .seq = seq, .ncases = n, .req = req, .bits = try gpa.alloc(u8, n) };
    return b;
}

test "transport: normal response, malformed response, hang with second batch, stderr flood, death" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    _ = sys.signal(sys.SIGPIPE, sys.SIG_IGN);
    var cfg: config.Config = .{};
    cfg.startup_deadline_ms = 3000;
    cfg.batch_deadline_base_ms = 400;
    cfg.batch_deadline_per512_ms = 0;
    cfg.stderr_tail_bytes = 1024;
    const spec = fakeSpec("fake");

    // 1. well-behaved: echo "<seq> 01" per line read
    {
        const c = try shChild(gpa, "", &cfg, &spec);
        try startScript(c, "echo ready fake\nn=1\nwhile read l; do echo \"$n 0101\"; n=$((n+1)); done\n");
        const b1 = try makeBatch(gpa, 1, 2, 100);
        try testing.expectEqual(BatchState.answered, runSync(c, b1));
        try testing.expectEqual(@as(u8, 1), b1.bits[0]);
        // large request exercising partial writes
        const b2 = try makeBatch(gpa, 2, 2, 600_000);
        try testing.expectEqual(BatchState.answered, runSync(c, b2));
        c.shutdown(500);
        c.destroy();
    }
    // 2. malformed response (bad hex length) is a protocol failure
    {
        const c = try shChild(gpa, "", &cfg, &spec);
        try startScript(c, "echo ready fake\nwhile read l; do echo \"1 0\"; done\n");
        const b = try makeBatch(gpa, 1, 2, 10);
        try testing.expectEqual(BatchState.failed, runSync(c, b));
        try testing.expectEqual(Failure.protocol, c.failure);
        c.destroy();
    }
    // 3. child stops reading during batch 1 while batch 2 is being sent: deadline recovers
    {
        const c = try shChild(gpa, "", &cfg, &spec);
        try startScript(c, "echo ready fake\nsleep 30\n");
        const b1 = try makeBatch(gpa, 1, 1, 10);
        const b2 = try makeBatch(gpa, 2, 1, 2_000_000);
        const t0 = sys.nowNs();
        try c.admit(b1, t0 + 400 * std.time.ns_per_ms);
        try c.admit(b2, t0 + 400 * std.time.ns_per_ms);
        while (c.busy() and c.alive) pump(&.{c}, 1000);
        const el = (sys.nowNs() - t0) / std.time.ns_per_ms;
        try testing.expect(el < 1500);
        try testing.expectEqual(BatchState.failed, b1.state);
        try testing.expectEqual(BatchState.failed, b2.state);
        try testing.expectEqual(Failure.timeout, c.failure);
        c.destroy();
    }
    // 4. stderr flood while answering: tail is bounded and the response still arrives
    {
        const c = try shChild(gpa, "", &cfg, &spec);
        try startScript(c, "echo ready fake\nread l\nhead -c 3000000 /dev/zero | tr '\\0' 'e' >&2\necho \"1 01\"\nsleep 5\n");
        const b = try makeBatch(gpa, 1, 1, 10);
        cfg.batch_deadline_base_ms = 5000;
        try testing.expectEqual(BatchState.answered, runSync(c, b));
        try testing.expect(c.err.len <= 1024);
        c.drainErr();
        try testing.expect(c.err.truncated > 0);
        c.destroy();
        cfg.batch_deadline_base_ms = 400;
    }
    // 5. child dies (signal) mid-batch
    {
        const c = try shChild(gpa, "", &cfg, &spec);
        try startScript(c, "echo ready fake\nread l\nkill -SEGV $$\n");
        const b = try makeBatch(gpa, 1, 1, 10);
        try testing.expectEqual(BatchState.failed, runSync(c, b));
        try testing.expect(c.failure == .crash or c.failure == .eof);
        try testing.expectEqual(@as(u8, 11), c.exit.signal);
        c.destroy();
    }
    // 6. EOF before handshake / malformed handshake
    {
        const c = try shChild(gpa, "", &cfg, &spec);
        try testing.expectError(error.BadHandshake, startScript(c, "echo Warning: unknown flag\n"));
        c.destroy();
    }
}

test "valid bits per mode" {
    try testing.expect(validBits(.normal, 0x01));
    try testing.expect(!validBits(.normal, 0x11));
    try testing.expect(validBits(.tierup, 0x11));
    try testing.expect(validBits(.linear, 0x40));
    try testing.expect(!validBits(.linear, 0x41));
    try testing.expect(!validBits(.normal, 0x40));
    try testing.expect(!validBits(.normal, 0x05));
    try testing.expect(!validBits(.normal, 0x80));
}

test "novelty set" {
    var n: Novelty = .{};
    defer n.deinit(testing.allocator);
    try testing.expect(try n.note(testing.allocator, 0, "a*"));
    try testing.expect(!try n.note(testing.allocator, 0, "a*"));
    try testing.expect(try n.note(testing.allocator, 1, "a*"));
    try testing.expectEqual(@as(u32, 2), n.entries);
}
