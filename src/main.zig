//! irx: inverted-pair regex fuzzer for d8.
//!
//!   irx [fuzz] --d8 ./d8 --config weights.toml --jobs 0 --seed 42 --out findings/
//!       [--modes interp,native,tierup] [--optional-modes linear,noopt] [--jsc PATH] [--sm PATH]
//!       [--max-cases N] [--duration SECONDS] [--no-selfcheck]
//!   irx selfcheck --d8 ./d8 [--config F] [--out DIR] [--sm PATH] [--jsc PATH]
//!   irx replay FINDING_DIR --d8 ./d8 [--config F]
//!   irx gate --d8 ./d8 [--out DIR]
const std = @import("std");
const builtin = @import("builtin");
const sys = @import("sys.zig");
const ucd = @import("ucd.zig");
const alpha = @import("alphabet.zig");
const config = @import("config.zig");
const harness = @import("harness.zig");
const finding = @import("finding.zig");
const tablemod = @import("table.zig");
const sample = @import("sample.zig");
const rngmod = @import("rng.zig");
const ast = @import("ast.zig");
const runmod = @import("run.zig");
const lanemod = @import("lane.zig");
const shrink = @import("shrink.zig");
const selfcheck = @import("selfcheck.zig");
const Budget = @import("budget.zig").Budget;

const Allocator = std.mem.Allocator;
const driver_js = @embedFile("driver.js");

test {
    _ = @import("rel.zig");
    _ = @import("ucd.zig");
    _ = @import("alphabet.zig");
    _ = @import("atoms.zig");
    _ = @import("ast.zig");
    _ = @import("budget.zig");
    _ = @import("config.zig");
    _ = @import("rng.zig");
    _ = @import("table.zig");
    _ = @import("sample.zig");
    _ = @import("harness.zig");
    _ = @import("finding.zig");
    _ = @import("shrink.zig");
    _ = @import("run.zig");
}

const Options = struct {
    command: []const u8 = "fuzz",
    positional: ?[]const u8 = null,
    d8: ?[]const u8 = null,
    config_path: ?[]const u8 = null,
    jobs: u32 = 0,
    seed: u64 = 42,
    out: []const u8 = "findings",
    modes: []const u8 = "interp,native,tierup",
    optional_modes: []const u8 = "",
    jsc: ?[]const u8 = null,
    shell: ?[]const u8 = null,
    sm: ?[]const u8 = null,
    max_cases: u64 = std.math.maxInt(u64),
    duration_s: u64 = 0,
    selfcheck: bool = true,
    quiet: bool = false,
};

fn usage() noreturn {
    sys.stderrPrint(
        \\usage: irx [fuzz] --d8 PATH [--config FILE] [--jobs N] [--seed N] [--out DIR]
        \\           [--modes interp,native,tierup] [--optional-modes linear,noopt,nopeephole,fallback0]
        \\           [--jsc PATH] [--sm PATH] [--max-cases N] [--duration SECONDS] [--no-selfcheck]
        \\       irx selfcheck --d8 PATH [--config FILE] [--out DIR] [--sm PATH] [--jsc PATH]
        \\       irx replay FINDING_DIR --d8 PATH [--config FILE]
        \\       irx gate --d8 PATH [--out DIR]
        \\       irx triage --d8 PATH --out DIR [--jobs N] [--max-cases N]   (parallel triage of untriaged findings)
        \\       irx sample [--config FILE] [--seed N] [--max-cases N]   (distribution diagnostics, no engine)
        \\
    , .{});
    std.process.exit(2);
}

fn parseArgs(args: []const [:0]const u8) Options {
    var o: Options = .{};
    var i: usize = 1;
    if (i < args.len and args[i].len > 0 and args[i][0] != '-') {
        o.command = args[i];
        i += 1;
        if (std.mem.eql(u8, o.command, "replay") and i < args.len and args[i][0] != '-') {
            o.positional = args[i];
            i += 1;
        }
    }
    while (i < args.len) : (i += 1) {
        const a: []const u8 = args[i];
        const eq = std.mem.eql;
        const val = struct {
            fn f(xs: []const [:0]const u8, j: *usize) []const u8 {
                j.* += 1;
                if (j.* >= xs.len) usage();
                return xs[j.*];
            }
        }.f;
        if (eq(u8, a, "--d8")) o.d8 = val(args, &i) else if (eq(u8, a, "--config")) o.config_path = val(args, &i) else if (eq(u8, a, "--jobs")) o.jobs = std.fmt.parseInt(u32, val(args, &i), 10) catch usage() else if (eq(u8, a, "--seed")) o.seed = std.fmt.parseInt(u64, val(args, &i), 10) catch usage() else if (eq(u8, a, "--out")) o.out = val(args, &i) else if (eq(u8, a, "--modes")) o.modes = val(args, &i) else if (eq(u8, a, "--optional-modes")) o.optional_modes = val(args, &i) else if (eq(u8, a, "--jsc")) o.jsc = val(args, &i) else if (eq(u8, a, "--shell")) o.shell = val(args, &i) else if (eq(u8, a, "--sm")) o.sm = val(args, &i) else if (eq(u8, a, "--max-cases")) o.max_cases = std.fmt.parseInt(u64, val(args, &i), 10) catch usage() else if (eq(u8, a, "--duration")) o.duration_s = std.fmt.parseInt(u64, val(args, &i), 10) catch usage() else if (eq(u8, a, "--no-selfcheck")) o.selfcheck = false else if (eq(u8, a, "--quiet")) o.quiet = true else if (eq(u8, a, "-h") or eq(u8, a, "--help")) usage() else {
            sys.stderrPrint("unknown argument: {s}\n", .{a});
            usage();
        }
    }
    return o;
}

var sigint_run: ?*runmod.Run = null;
fn onSigint(_: c_int) callconv(.c) void {
    if (sigint_run) |r| r.stop.store(true, .release);
}

extern "c" fn _NSGetExecutablePath(buf: [*]u8, size: *u32) c_int;

fn sha256File(gpa: Allocator, path: []const u8) ![64]u8 {
    const data = try sys.readFileAlloc(gpa, path, 1 << 31);
    defer gpa.free(data);
    var d: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &d, .{});
    return std.fmt.bytesToHex(d, .lower);
}

fn selfExeHash(gpa: Allocator) [64]u8 {
    var buf: [4096]u8 = undefined;
    var size: u32 = buf.len;
    if (builtin.os.tag == .macos) {
        if (_NSGetExecutablePath(&buf, &size) == 0) {
            const p = std.mem.sliceTo(&buf, 0);
            return sha256File(gpa, p) catch [_]u8{'0'} ** 64;
        }
    } else {
        return sha256File(gpa, "/proc/self/exe") catch [_]u8{'0'} ** 64;
    }
    return [_]u8{'0'} ** 64;
}

const Setup = struct {
    run: *runmod.Run,
    gpa: Allocator,
    probe_report: std.ArrayList(u8),
    crash: ?harness.CrashProbe,
    config_text: []const u8,
};

fn loadConfig(gpa: Allocator, o: *const Options, cfg: *config.Config, text_out: *[]const u8) void {
    cfg.* = .{};
    text_out.* = "";
    if (o.config_path) |p| {
        const text = sys.readFileAlloc(gpa, p, 1 << 20) catch {
            sys.stderrPrint("cannot read config {s}\n", .{p});
            std.process.exit(2);
        };
        config.loadToml(gpa, text, cfg) catch |e| {
            sys.stderrPrint("invalid config {s}: {s}\n", .{ p, @errorName(e) });
            std.process.exit(2);
        };
        text_out.* = text;
    }
    cfg.validate() catch |e| {
        sys.stderrPrint("invalid configuration: {s}\n", .{@errorName(e)});
        std.process.exit(2);
    };
}

fn resolveModes(gpa: Allocator, list: []const u8) ![]*const harness.ModeSpec {
    var out: std.ArrayList(*const harness.ModeSpec) = .empty;
    var it = std.mem.tokenizeScalar(u8, list, ',');
    while (it.next()) |name| {
        const m = harness.findMode(name) orelse {
            sys.stderrPrint("unknown mode: {s}\n", .{name});
            std.process.exit(2);
        };
        if (m.engine == .sm or m.engine == .jsc) {
            sys.stderrPrint("mode {s} is a sanity engine; use --sm/--jsc\n", .{name});
            std.process.exit(2);
        }
        try out.append(gpa, m);
    }
    return out.toOwnedSlice(gpa);
}

fn setup(gpa: Allocator, o: *const Options, quiet: bool) !Setup {
    ucd.init();
    _ = sys.signal(sys.SIGPIPE, sys.SIG_IGN);
    const d8 = o.shell orelse o.d8 orelse {
        sys.stderrPrint("--d8 PATH (or --shell \"CMD {{driver}} {{mode}}\") is required\n", .{});
        usage();
    };
    var tok_it = std.mem.tokenizeScalar(u8, d8, ' ');
    const exe0 = if (o.shell != null) (tok_it.next() orelse "") else d8;
    if (!sys.fileExists(exe0)) {
        sys.stderrPrint("engine not found: {s}\n", .{exe0});
        std.process.exit(2);
    }
    const run = try gpa.create(runmod.Run);
    var cfg: config.Config = undefined;
    var cfg_text: []const u8 = "";
    loadConfig(gpa, o, &cfg, &cfg_text);
    alpha.active_pool = cfg.poolSlice();

    try sys.mkdirp(o.out);
    var pb: [4096]u8 = undefined;
    const driver_path = try gpa.dupe(u8, try std.fmt.bufPrint(&pb, "{s}/driver.js", .{o.out}));
    try sys.writeFile(driver_path, driver_js);
    var dd: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(driver_js, &dd, .{});
    const driver_hash = try gpa.dupe(u8, &std.fmt.bytesToHex(dd, .lower));
    const d8_hash = try gpa.dupe(u8, &(sha256File(gpa, exe0) catch [_]u8{'0'} ** 64));
    const exe_hash = selfExeHash(gpa);
    const build_id = try std.fmt.allocPrint(gpa, "{s}+zig{s}+{s}+exe:{s}+d8:{s}", .{ tablemod.generator_version, builtin.zig_version_string, @tagName(builtin.mode), exe_hash[0..16], d8_hash[0..16] });

    run.* = .{
        .gpa = gpa,
        .cfg = cfg,
        .host = Budget.init("host", cfg.max_host_bytes, null),
        .global_seed = o.seed,
        .out_dir = o.out,
        .d8_exe = d8,
        .sm_exe = o.sm,
        .jsc_exe = o.jsc,
        .driver_path = driver_path,
        .driver_hash = driver_hash,
        .d8_hash = d8_hash,
        .build_id = build_id,
        .modes = &.{},
        .store = try finding.Store.init(gpa, o.out),
        .max_cases = o.max_cases,
    };
    // Validate every configured flag set's printed-length bound up front.
    for (run.cfg.flagSets()) |f| {
        _ = run.grammarFor(f) catch |e| {
            sys.stderrPrint("configuration rejected for flags \"{s}\": {s}\n", .{ finding.flagStr(f), @errorName(e) });
            std.process.exit(2);
        };
    }

    var rep: std.ArrayList(u8) = .empty;
    // Probe requested modes (required) and optional modes.
    const req_modes = try resolveModes(gpa, if (o.shell != null and std.mem.eql(u8, o.modes, "interp,native,tierup")) "shell,shell-repeat" else o.modes);
    const opt_modes = try resolveModes(gpa, o.optional_modes);
    var active: std.ArrayList(*const harness.ModeSpec) = .empty;
    const child_opts: harness.ChildOptions = .{ .exe = d8, .driver_path = driver_path, .journal_path = null, .cfg = &run.cfg };
    for (req_modes) |m| {
        const pr = harness.probeMode(gpa, m, child_opts);
        try rep.print(gpa, "mode {s}: {s} (required){s}\n", .{ m.name, pr.reason, if (pr.ok and !pr.flush_verified) " flush-unverified" else "" });
        if (!pr.ok or !pr.flush_verified) {
            sys.stderrPrint("required mode {s} unavailable: {s}\n", .{ m.name, pr.reason });
            std.process.exit(3);
        }
        if (run.d8_version.len == 0) run.d8_version = pr.version;
        try active.append(gpa, m);
    }
    for (opt_modes) |m| {
        const pr = harness.probeMode(gpa, m, child_opts);
        try rep.print(gpa, "mode {s}: {s} (optional{s})\n", .{ m.name, pr.reason, if (pr.ok) ", enabled" else ", disabled" });
        if (pr.ok and pr.flush_verified) try active.append(gpa, m);
    }
    if (active.items.len == 0) {
        sys.stderrPrint("no modes available\n", .{});
        std.process.exit(3);
    }
    if (active.items.len > runmod.max_modes) {
        sys.stderrPrint("too many modes\n", .{});
        std.process.exit(2);
    }
    run.modes = try active.toOwnedSlice(gpa);
    // Tier trace verification: probe by launching, not by --help.
    {
        const trace_spec: harness.ModeSpec = .{ .name = "tiertrace", .flags = &.{ "--regexp-tier-up", "--regexp-tier-up-ticks=1", "--trace-regexp-tier-up" }, .driver_mode = "interp" };
        const pr = harness.probeMode(gpa, &trace_spec, child_opts);
        try rep.print(gpa, "tier transition tracing: {s}\n", .{if (pr.ok) "available (diagnostics would need a separate channel); transitions still reported unverified" else "unavailable; transition coverage reported as UNVERIFIED"});
    }
    // Sanity engines.
    var sanity: std.ArrayList(*const harness.ModeSpec) = .empty;
    if (o.sm) |p| {
        const m = harness.findMode("sm").?;
        const pr = harness.probeMode(gpa, m, .{ .exe = p, .driver_path = driver_path, .journal_path = null, .cfg = &run.cfg });
        try rep.print(gpa, "sanity sm ({s}): {s}\n", .{ p, pr.reason });
        if (pr.ok) try sanity.append(gpa, m);
    }
    if (o.jsc) |p| {
        const m = harness.findMode("jsc").?;
        const pr = harness.probeMode(gpa, m, .{ .exe = p, .driver_path = driver_path, .journal_path = null, .cfg = &run.cfg });
        try rep.print(gpa, "sanity jsc ({s}): {s}\n", .{ p, pr.reason });
        if (pr.ok) try sanity.append(gpa, m);
    }
    run.sanity_modes = try sanity.toOwnedSlice(gpa);

    const crash = harness.crashProbe();
    if (crash) |c| try rep.print(gpa, "crash-report suppression: setexceptionports rc={d}, helper signal={d}, reap {d} ms\n", .{ c.excports_rc, c.signal, c.reap_ms }) else try rep.appendSlice(gpa, "crash-report suppression: probe failed to spawn\n");
    if (!quiet) sys.stderrPrint("{s}", .{rep.items});
    return .{ .run = run, .gpa = gpa, .probe_report = rep, .crash = crash, .config_text = cfg_text };
}

fn writeManifest(s: *const Setup, lanes: u32, jobs: u32) !void {
    const run = s.run;
    const gpa = s.gpa;
    var m: std.ArrayList(u8) = .empty;
    defer m.deinit(gpa);
    try m.print(gpa, "{{\n  \"generator\": \"{s}\",\n  \"numerics\": \"{s}\",\n  \"seed_expansion_version\": {d},\n  \"build_id\": \"{s}\",\n  \"zig\": \"{s}\",\n  \"optimize\": \"{s}\",\n  \"os\": \"{s}\",\n  \"arch\": \"{s}\",\n", .{
        tablemod.generator_version, tablemod.numerics_version, rngmod.seed_expansion_version, run.build_id, builtin.zig_version_string, @tagName(builtin.mode), @tagName(builtin.os.tag), @tagName(builtin.cpu.arch),
    });
    try m.print(gpa, "  \"global_seed\": {d},\n  \"d8\": {{\"path\": ", .{run.global_seed});
    try harness.jsonAscii(&m, gpa, run.d8_exe);
    try m.print(gpa, ", \"sha256\": \"{s}\", \"version\": ", .{run.d8_hash});
    try harness.jsonAscii(&m, gpa, run.d8_version);
    try m.print(gpa, "}},\n  \"driver_sha256\": \"{s}\",\n  \"unicode\": {s},\n  \"modes\": [", .{ run.driver_hash, std.mem.trimEnd(u8, ucd.manifest_json, "\n") });
    for (run.modes, 0..) |md, i| {
        if (i > 0) try m.append(gpa, ',');
        try m.print(gpa, "{{\"name\": \"{s}\", \"flags\": [", .{md.name});
        for (md.flags, 0..) |f, j| {
            if (j > 0) try m.append(gpa, ',');
            try harness.jsonAscii(&m, gpa, f);
        }
        try m.appendSlice(gpa, "]}");
    }
    try m.appendSlice(gpa, "],\n  \"sanity_engines\": [");
    for (run.sanity_modes, 0..) |md, i| {
        if (i > 0) try m.append(gpa, ',');
        try m.print(gpa, "\"{s}\"", .{md.name});
    }
    try m.print(gpa, "],\n  \"jobs\": {d},\n  \"lanes\": {d},\n  \"sampling_processes\": {d},\n  \"triage_processes\": 1,\n  \"tier_transitions\": \"unverified\",\n  \"deadlines_ms\": {{\"startup\": {d}, \"batch_base\": {d}, \"batch_per512\": {d}}},\n  \"config\": ", .{
        jobs, lanes, lanes * run.modes.len, run.cfg.startup_deadline_ms, run.cfg.batch_deadline_base_ms, run.cfg.batch_deadline_per512_ms,
    });
    try config.toJson(&run.cfg, &m, gpa);
    try m.appendSlice(gpa, ",\n  \"inventories\": {");
    for (run.cfg.flagSets(), 0..) |f, fi| {
        const g = try run.grammarFor(f);
        if (fi > 0) try m.append(gpa, ',');
        try m.print(gpa, "\n    \"{s}\": {{\"atoms\": [", .{finding.flagStr(f)});
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(gpa);
        for (g.atoms, 0..) |*at, i| {
            buf.clearRetainingCapacity();
            var p: sample.Printer = .{ .flags = f, .out = &buf, .gpa = gpa };
            try p.atom(at);
            if (i > 0) try m.append(gpa, ',');
            try harness.jsonAscii(&m, gpa, buf.items);
        }
        try m.appendSlice(gpa, "], \"quantifiers\": [");
        for (g.quants, 0..) |q, i| {
            if (i > 0) try m.append(gpa, ',');
            try m.print(gpa, "\"{s} {d} {d}{s}\"", .{ @tagName(q.form), q.min, q.max, if (q.lazy) " lazy" else "" });
        }
        try m.appendSlice(gpa, "]}");
    }
    try m.appendSlice(gpa, "\n  },\n  \"probes\": ");
    try harness.jsonAscii(&m, gpa, s.probe_report.items);
    try m.appendSlice(gpa, "\n}\n");
    var pb: [4096]u8 = undefined;
    try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/manifest.json", .{run.out_dir}), m.items);
    if (s.config_text.len > 0) try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/config.toml", .{run.out_dir}), s.config_text);
}

fn runSelfcheck(s: *const Setup) !selfcheck.Result {
    const run = s.run;
    var engines: std.ArrayList(struct { spec: *const harness.ModeSpec, exe: []const u8 }) = .empty;
    defer engines.deinit(s.gpa);
    try engines.append(s.gpa, .{ .spec = run.modes[0], .exe = run.d8_exe });
    for (run.sanity_modes) |m| try engines.append(s.gpa, .{ .spec = m, .exe = if (m.engine == .sm) run.sm_exe.? else run.jsc_exe.? });
    var ck: selfcheck.Checker = .{ .run = run, .gpa = s.gpa };
    defer ck.deinit();
    const t0 = sys.nowNs();
    const r = try ck.runAll(@ptrCast(engines.items));
    sys.stderrPrint("selfcheck: {d} probes executed, {d} mismatches, {d} engine failures in {d} ms (report: {s}/selfcheck/report.txt)\n", .{ r.cases, r.mismatches, r.engine_failures, (sys.nowNs() - t0) / std.time.ns_per_ms, run.out_dir });
    return r;
}

fn statsLine(run: *runmod.Run, t_start: u64, last_cases: *u64, last_t: *u64) void {
    const now = sys.nowNs();
    const cases = run.cases.load(.monotonic);
    const dt = @as(f64, @floatFromInt(now - last_t.*)) / 1e9;
    const rate = if (dt > 0) @as(f64, @floatFromInt(cases - last_cases.*)) / dt else 0;
    last_cases.* = cases;
    last_t.* = now;
    const per = struct {
        fn us(ns: u64, n: u64) f64 {
            return if (n == 0) 0 else @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(n)) / 1000.0;
        }
    }.us;
    var buf: [2048]u8 = undefined;
    var w: usize = 0;
    const put = struct {
        fn f(b: []u8, pos: *usize, comptime fmt: []const u8, args: anytype) void {
            const s = std.fmt.bufPrint(b[pos.*..], fmt, args) catch return;
            pos.* += s.len;
        }
    }.f;
    run.qmutex.lock();
    const pending = run.queue.items.len;
    run.qmutex.unlock();
    put(&buf, &w, "[{d}s] {d:.0} cases/s total={d} sample={d:.2}us print={d:.2}us enc={d:.2}us engine-wait={d:.1}us/case pairs={d} prods={d} tables={d} zero-mass={d} managed={d}MiB rss={d}MiB child-rss={d}MiB findings={d} new={d} pending={d} triaged={d} slow={d}", .{
        (now - t_start) / std.time.ns_per_s,         rate,                                               cases,
        per(run.sample_ns.load(.monotonic), cases),  per(run.print_ns.load(.monotonic), cases),          per(run.encode_ns.load(.monotonic), cases),
        per(run.wait_ns.load(.monotonic), cases),    run.last_pairs.load(.monotonic),                    run.last_prods.load(.monotonic),
        run.tables_built.load(.monotonic),           run.zero_mass.load(.monotonic),                     run.host.used.load(.monotonic) >> 20,
        sys.peakRss() >> 20,                         sys.childPeakRss() >> 20,                           run.findings.load(.monotonic),
        run.findings_new.load(.monotonic),           pending,                                            run.triaged.load(.monotonic),
        run.slow_cases.load(.monotonic),
    });
    for (run.modes, 0..) |m, i| {
        const st = &run.mode_stats[i];
        put(&buf, &w, " | {s}: exec={d} skip={d}/{d} mism={d} restarts={d}", .{ m.name, st.executed.load(.monotonic), st.skipped_multiline.load(.monotonic), st.skipped_unsupported.load(.monotonic), st.mismatches.load(.monotonic), st.restarts.load(.monotonic) });
        if (m.expect == .tierup) put(&buf, &w, " tier(first-seen={d} repeated={d}, transitions unverified)", .{ st.first_seen.load(.monotonic), st.repeated.load(.monotonic) });
    }
    put(&buf, &w, "\n", .{});
    sys.writeAll(2, buf[0..w]) catch {};
}

fn cmdFuzz(gpa: Allocator, o: *const Options) !u8 {
    var s = try setup(gpa, o, o.quiet);
    const run = s.run;
    const phys: u32 = @intCast(sys.physicalCpu());
    const jobs: u32 = if (o.jobs == 0) phys else o.jobs;
    const M: u32 = @intCast(run.modes.len);
    if (jobs < M) {
        sys.stderrPrint("--jobs {d} is below the number of active modes ({d}); each lane needs one process per mode\n", .{ jobs, M });
        return 2;
    }
    const lanes = jobs / M;
    run.lanes = lanes;
    sys.stderrPrint("process budget: jobs={d} (physical cores {d}), modes={d} -> lanes={d}, sampling processes={d}, unused slots={d}, +1 triage/verification child outside the sampling budget{s}\n", .{ jobs, phys, M, lanes, lanes * M, jobs - lanes * M, if (run.sanity_modes.len > 0) ", +sanity engines per lane" else "" });

    // Resource feasibility: lanes' scratch + active + replacement table + triage workspace.
    const scratch_est = sample.Scratch.bytesFor(run.cfg.max_prods, run.cfg.max_size);
    const need = @as(u64, lanes) * (scratch_est + (8 << 20)) + 2 * run.cfg.max_table_bytes + run.cfg.max_pending_finding_bytes + (64 << 20);
    if (need > run.cfg.max_host_bytes) {
        sys.stderrPrint("configuration cannot fit max_host_bytes={d}: needs ~{d} (lanes scratch + 2 tables + triage); reduce lanes or limits\n", .{ run.cfg.max_host_bytes, need });
        return 2;
    }
    if (!run.host.reserve(run.cfg.max_pending_finding_bytes)) {
        sys.stderrPrint("cannot reserve triage capacity\n", .{});
        return 2;
    }
    var pb: [4096]u8 = undefined;
    run.pending_fd = try sys.openAppend(try std.fmt.bufPrint(&pb, "{s}/triage_pending.txt", .{run.out_dir}));
    run.weight_log_fd = try sys.openAppend(try std.fmt.bufPrint(&pb, "{s}/weights.log", .{run.out_dir}));
    try writeManifest(&s, lanes, jobs);

    if (o.selfcheck) {
        const r = try runSelfcheck(&s);
        if (r.mismatches > 0) sys.stderrPrint("WARNING: atom self-check found {d} model/engine discrepancies; they are reported, not adopted\n", .{r.mismatches});
    }

    sigint_run = run;
    _ = sys.signal(2, @ptrCast(&onSigint));
    if (o.duration_s > 0) run.deadline_ns = sys.nowNs() + o.duration_s * std.time.ns_per_s;

    const builder = try std.Thread.spawn(.{}, runmod.Run.builderLoop, .{run});
    var triage: shrink.Triage = .{ .run = run, .gpa = gpa, .defer_batches = true };
    const triage_thread = try std.Thread.spawn(.{}, shrink.Triage.loop, .{&triage});
    const lane_objs = try gpa.alloc(*lanemod.Lane, lanes);
    const threads = try gpa.alloc(std.Thread, lanes);
    for (0..lanes) |i| {
        lane_objs[i] = lanemod.Lane.init(run, @intCast(i)) catch |e| {
            sys.stderrPrint("lane {d}: failed to start engine processes: {s}\n", .{ i, @errorName(e) });
            run.setStop("lane start failure", .{});
            return 3;
        };
    }
    for (0..lanes) |i| threads[i] = try std.Thread.spawn(.{}, lanemod.Lane.loop, .{lane_objs[i]});

    const t_start = sys.nowNs();
    var last_cases: u64 = 0;
    var last_t = t_start;
    var lanes_done = false;
    while (!lanes_done) {
        var slept: u32 = 0;
        while (slept < 1000) : (slept += 50) {
            _ = sys.usleep(50_000);
            if (run.stopped()) break;
            if (run.cases.load(.monotonic) >= run.max_cases or sys.nowNs() >= run.deadline_ns) break;
        }
        if (!o.quiet) statsLine(run, t_start, &last_cases, &last_t);
        if (run.stopped() or run.cases.load(.monotonic) >= run.max_cases or sys.nowNs() >= run.deadline_ns) lanes_done = true;
    }
    // Let lanes finish their in-flight batches, then stop the builder.
    for (threads) |t| t.join();
    const stop_reason = if (run.stopped()) run.stopReason() else "";
    run.setStop("campaign finished", .{});
    builder.join();
    for (lane_objs) |l| l.deinit();
    run.finishTriage();
    triage_thread.join();
    triage.deinit();
    run.shutdownTables();
    statsLine(run, t_start, &last_cases, &last_t);

    var sumb: std.ArrayList(u8) = .empty;
    try sumb.print(gpa, "{{\"cases\": {d}, \"batches\": {d}, \"findings\": {d}, \"distinct_findings\": {d}, \"coalesced\": {d}, \"triaged\": {d}, \"reproduced\": {d}, \"tables\": {d}, \"zero_mass_retries\": {d}, \"resource_rejects\": {d}, \"slow\": {d}, \"triage_overflow\": {d}, \"peak_managed_bytes\": {d}, \"peak_rss\": {d}, \"stop_reason\": ", .{
        run.cases.load(.monotonic), run.batches.load(.monotonic), run.findings.load(.monotonic), run.findings_new.load(.monotonic), run.store.coalesced, run.triaged.load(.monotonic), run.confirmed.load(.monotonic), run.tables_built.load(.monotonic), run.zero_mass.load(.monotonic), run.resource_rejects.load(.monotonic), run.slow_cases.load(.monotonic), run.overflowed.load(.monotonic), run.host.peak.load(.monotonic), sys.peakRss(),
    });
    try harness.jsonAscii(&sumb, gpa, stop_reason);
    try sumb.appendSlice(gpa, ", \"modes\": {");
    for (run.modes, 0..) |m, i| {
        const st = &run.mode_stats[i];
        if (i > 0) try sumb.append(gpa, ',');
        try sumb.print(gpa, "\"{s}\": {{\"executed\": {d}, \"skipped_multiline_wrapper\": {d}, \"skipped_engine_unsupported\": {d}, \"mismatches\": {d}, \"restarts\": {d}, \"first_seen\": {d}, \"repeated\": {d}}}", .{ m.name, st.executed.load(.monotonic), st.skipped_multiline.load(.monotonic), st.skipped_unsupported.load(.monotonic), st.mismatches.load(.monotonic), st.restarts.load(.monotonic), st.first_seen.load(.monotonic), st.repeated.load(.monotonic) });
    }
    try sumb.appendSlice(gpa, "}, \"tier_transitions\": \"unverified\"}\n");
    try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/summary.json", .{run.out_dir}), sumb.items);
    sys.stderrPrint("done: {s}", .{sumb.items});
    if (stop_reason.len > 0 and !std.mem.eql(u8, stop_reason, "campaign finished")) {
        sys.stderrPrint("stopped: {s}\n", .{stop_reason});
        if (std.mem.startsWith(u8, stop_reason, "table retry exhaustion") or std.mem.startsWith(u8, stop_reason, "lane") or std.mem.startsWith(u8, stop_reason, "sampling") or std.mem.startsWith(u8, stop_reason, "printer") or std.mem.startsWith(u8, stop_reason, "failed")) return 4;
    }
    return 0;
}

fn cmdSelfcheck(gpa: Allocator, o: *const Options) !u8 {
    var opts = o.*;
    opts.modes = if (o.shell != null) "shell" else "interp";
    var s = try setup(gpa, &opts, false);
    try writeManifest(&s, 0, 0);
    const r = try runSelfcheck(&s);
    return if (r.mismatches == 0 and r.engine_failures == 0) 0 else 1;
}

/// Replay a finding: re-verify the model on the saved AST, reconstruct the
/// table from (seed, seq, attempt) and verify its digest, re-derive the case
/// from its seed triple, then re-run it in a fresh process of the recorded mode.
fn cmdReplay(gpa: Allocator, o: *const Options) !u8 {
    const dir = o.positional orelse usage();
    var opts = o.*;
    var pb: [4096]u8 = undefined;
    const text = try sys.readFileAlloc(gpa, try std.fmt.bufPrint(&pb, "{s}/case.irx", .{dir}), 1 << 20);
    var lc: finding.LoadedCase = undefined;
    try finding.readCaseRecord(gpa, text, &lc);
    if (opts.config_path == null) {
        const cp = try std.fmt.allocPrint(gpa, "{s}/../../config.toml", .{dir});
        if (sys.fileExists(cp)) opts.config_path = cp;
    }
    opts.seed = lc.case.global_seed;
    opts.modes = lc.pred.mode;
    opts.out = try std.fmt.allocPrint(gpa, "{s}/replay", .{dir});
    const s = try setup(gpa, &opts, true);
    const run = s.run;
    var c = lc.case;
    const ma = ast.oracle(&c.tree, c.flags, c.a.slice());
    const mr = ast.oracle(&c.tree, c.flags, c.r.slice());
    sys.stdoutPrint("model: test(A)={?} test(R)={?} (expected {} {})\n", .{ ma, mr, c.exp_a, c.exp_r });
    if (!c.selfcheck) {
        switch (run.buildOne(c.table.seq, c.table.attempt)) {
            .table => |tab| {
                defer tab.release();
                const same = std.mem.eql(u8, &tab.digest, &c.table.digest);
                sys.stdoutPrint("table reconstruction: digest {s}\n", .{if (same) "verified" else "MISMATCH (different config/build?)"});
                if (same) {
                    var scratch: sample.Scratch = .{};
                    defer scratch.deinit(gpa);
                    try scratch.ensure(gpa, tab.max_prods_per_pair, tab.max_size);
                    var rng = rngmod.caseRng(c.global_seed, c.lane, c.index);
                    var t: ast.Ast = .{};
                    var smp: sample.Sampler = .{ .tab = tab, .scratch = &scratch, .rng = &rng, .out = &t };
                    _ = try smp.sample();
                    var pat: std.ArrayList(u8) = .empty;
                    try sample.printAlloc(gpa, &t, c.flags, &pat);
                    sys.stdoutPrint("case re-derivation from seed triple: {s}\n", .{if (std.mem.eql(u8, pat.items, c.pattern.items)) "identical pattern" else "DIFFERENT pattern (saved pattern/AST remain authoritative)"});
                }
            },
            else => sys.stdoutPrint("table reconstruction failed (different config?)\n", .{}),
        }
    }
    const spec = harness.findMode(lc.pred.mode) orelse return error.UnknownMode;
    var triage: shrink.Triage = .{ .run = run, .gpa = gpa };
    defer triage.deinit();
    var req: std.ArrayList(u8) = .empty;
    try req.appendSlice(gpa, "[1,[");
    try harness.encodeCase(&req, gpa, .{ .flags = finding.flagStr(c.flags), .a = c.a.slice(), .r = c.r.slice(), .pattern = c.pattern.items });
    try req.appendSlice(gpa, "]]\n");
    const ch = try harness.Child.create(gpa, spec, .{ .exe = run.d8_exe, .driver_path = run.driver_path, .journal_path = null, .cfg = &run.cfg });
    defer ch.destroy();
    try ch.start();
    var bits: [1]u8 = undefined;
    var b: harness.Batch = .{ .seq = 1, .ncases = 1, .req = req.items, .bits = &bits };
    const st = harness.runSync(ch, &b);
    if (st == .answered) {
        const p = finding.classify(spec.expect, spec.name, bits[0], c.exp_a, c.exp_r);
        sys.stdoutPrint("engine {s}: bits={x:0>2} -> {s}\n", .{ spec.name, bits[0], if (p) |pp| (if (pp.eqlShape(lc.pred)) "failure REPRODUCED" else "different failure") else "agrees with oracle (not reproduced)" });
        return if (p != null and p.?.eqlShape(lc.pred)) 1 else 0;
    }
    sys.stdoutPrint("engine {s}: batch failed ({s}, {s})\n", .{ spec.name, @tagName(ch.failure), ch.message() });
    return 1;
}

/// Performance gate: single-lane runs over a fixed, checked-in corpus of
/// scenarios, verifying oracle agreement, finite retries, replay, and
/// allocation caps; publishes per-stage timings.
fn cmdGate(gpa: Allocator, o: *const Options) !u8 {
    const corpus = @embedFile("gate_corpus.toml");
    var report: std.ArrayList(u8) = .empty;
    try report.appendSlice(gpa, "# irx performance gate\n\n| scenario | cases | cases/s | tables | zero-mass | build ms/table | sample us | print us | engine-wait us/case | peak managed MiB | peak RSS MiB | mismatches | replay | caps |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n");
    var failures: u32 = 0;
    var sections = std.mem.splitSequence(u8, corpus, "\n[[scenario]]\n");
    _ = sections.next();
    while (sections.next()) |sec| {
        var name: []const u8 = "?";
        var seed: u64 = 1;
        var cases: u64 = 2000;
        var toml: std.ArrayList(u8) = .empty;
        var lines = std.mem.splitScalar(u8, sec, '\n');
        while (lines.next()) |l| {
            if (std.mem.startsWith(u8, l, "name = ")) name = std.mem.trim(u8, l[7..], "\"") else if (std.mem.startsWith(u8, l, "seed = ")) seed = try std.fmt.parseInt(u64, l[7..], 10) else if (std.mem.startsWith(u8, l, "cases = ")) cases = try std.fmt.parseInt(u64, l[8..], 10) else {
                try toml.appendSlice(gpa, l);
                try toml.append(gpa, '\n');
            }
        }
        const out = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ o.out, name });
        try sys.mkdirp(out);
        var pb: [4096]u8 = undefined;
        const cpath = try std.fmt.allocPrint(gpa, "{s}/scenario.toml", .{out});
        try sys.writeFile(cpath, toml.items);
        _ = &pb;
        var opts = o.*;
        opts.config_path = cpath;
        opts.out = out;
        opts.seed = seed;
        opts.modes = "interp";
        opts.max_cases = cases;
        opts.jobs = 1;
        opts.quiet = true;
        opts.selfcheck = false;
        const t0 = sys.nowNs();
        var s = try setup(gpa, &opts, true);
        const run = s.run;
        run.log_tables = true;
        try writeManifest(&s, 1, 1);
        const builder = try std.Thread.spawn(.{}, runmod.Run.builderLoop, .{run});
        var lane = try lanemod.Lane.init(run, 0);
        lane.loop();
        run.setStop("gate scenario finished", .{});
        builder.join();
        lane.deinit();
        const secs = @as(f64, @floatFromInt(sys.nowNs() - t0)) / 1e9;
        const n = run.cases.load(.monotonic);
        const mism = run.mode_stats[0].mismatches.load(.monotonic);
        // Replay check: rebuild table 0 and compare digests.
        var replay_ok = true;
        if (run.current) |cur| {
            switch (run.buildOne(cur.id.seq, cur.id.attempt)) {
                .table => |t2| {
                    replay_ok = std.mem.eql(u8, &t2.digest, &cur.digest);
                    t2.release();
                },
                else => replay_ok = false,
            }
        }
        const caps_ok = run.host.peak.load(.monotonic) <= run.cfg.max_host_bytes and run.last_stats.peak_bytes <= run.cfg.max_table_bytes;
        const tables = run.tables_built.load(.monotonic);
        const per = struct {
            fn us(ns: u64, k: u64) f64 {
                return if (k == 0) 0 else @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(k)) / 1000.0;
            }
        }.us;
        try report.print(gpa, "| {s} | {d} | {d:.0} | {d} | {d} | {d:.1} | {d:.2} | {d:.2} | {d:.1} | {d} | {d} | {d} | {s} | {s} |\n", .{
            name,                                   n,                                     @as(f64, @floatFromInt(n)) / secs,                                                              tables,
            run.zero_mass.load(.monotonic),         if (tables == 0) 0 else @as(f64, @floatFromInt(run.build_ns.load(.monotonic))) / @as(f64, @floatFromInt(tables)) / 1e6, per(run.sample_ns.load(.monotonic), n),
            per(run.print_ns.load(.monotonic), n),  per(run.wait_ns.load(.monotonic), n),  run.host.peak.load(.monotonic) >> 20,                                                           sys.peakRss() >> 20,
            mism,                                   if (replay_ok) "ok" else "FAIL",       if (caps_ok) "ok" else "FAIL",
        });
        if (!replay_ok or !caps_ok) failures += 1;
        run.shutdownTables();
        if (run.stopped() and std.mem.startsWith(u8, run.stopReason(), "table retry exhaustion")) {
            try report.print(gpa, "\n> {s}: {s} (finite retries verified)\n", .{ name, run.stopReason() });
        }
    }
    var pb: [4096]u8 = undefined;
    try sys.mkdirp(o.out);
    try sys.writeFile(try std.fmt.bufPrint(&pb, "{s}/report.md", .{o.out}), report.items);
    sys.stdoutPrint("{s}", .{report.items});
    return if (failures == 0) 0 else 1;
}

fn quantDepth(t: *const ast.Ast, idx: u8) usize {
    const n = t.nodes[idx];
    return switch (n.op) {
        .atom => 0,
        .concat, .alt => @max(quantDepth(t, n.a), quantDepth(t, n.b)),
        .quant => blk: {
            const d = quantDepth(t, n.a);
            break :blk if (n.quant.max == ast.inf or n.quant.max > 1) d + 1 else d;
        },
        else => quantDepth(t, n.a),
    };
}

/// Diagnostics: build tables and print sampled patterns plus construct and
/// quantifier-nesting statistics (no engine involved).
fn cmdSample(gpa: Allocator, o: *const Options) !u8 {
    ucd.init();
    var cfg: config.Config = undefined;
    var text: []const u8 = "";
    loadConfig(gpa, o, &cfg, &text);
    var run: runmod.Run = .{
        .gpa = gpa,
        .cfg = cfg,
        .host = Budget.init("host", cfg.max_host_bytes, null),
        .global_seed = o.seed,
        .out_dir = o.out,
        .d8_exe = "",
        .driver_path = "",
        .driver_hash = "",
        .d8_hash = "",
        .build_id = "",
        .modes = &.{},
        .store = undefined,
        .log_tables = false,
    };
    const ntables: u64 = 3;
    const per: u64 = if (o.max_cases == std.math.maxInt(u64)) 2000 else o.max_cases;
    var depth_hist = [_]u64{0} ** 16;
    var counts_total = [_]u64{0} ** ast.n_constructs;
    var nodes_total: u64 = 0;
    var scratch: sample.Scratch = .{};
    for (0..ntables) |seq| {
        const t0 = sys.nowNs();
        const tab = switch (run.buildOne(seq, 0)) {
            .table => |t| t,
            else => |e| {
                sys.stdoutPrint("table {d}: {s}\n", .{ seq, @tagName(e) });
                continue;
            },
        };
        defer tab.release();
        const tb = sys.nowNs() - t0;
        var stats: std.ArrayList(u8) = .empty;
        try tab.stats.write(&stats, gpa);
        var ar: std.ArrayList(u8) = .empty;
        try ar.appendSlice(gpa, "A=");
        try harness.jsonString(&ar, gpa, tab.a16);
        try ar.appendSlice(gpa, " R=");
        try harness.jsonString(&ar, gpa, tab.r16);
        sys.stdoutPrint("table {d} flags=\"{s}\" {s} built in {d} ms\n{s}", .{ seq, finding.flagStr(tab.id.flags), ar.items, tb / 1_000_000, stats.items });
        try scratch.ensure(gpa, tab.max_prods_per_pair, tab.max_size);
        const ts = sys.nowNs();
        var pat: std.ArrayList(u8) = .empty;
        for (0..per) |i| {
            var rng = rngmod.caseRng(o.seed, 0, seq * per + i);
            var t: ast.Ast = .{};
            var smp: sample.Sampler = .{ .tab = tab, .scratch = &scratch, .rng = &rng, .out = &t };
            _ = try smp.sample();
            depth_hist[@min(quantDepth(&t, t.root), 15)] += 1;
            var cc: [ast.n_constructs]u16 = undefined;
            ast.constructCounts(&t, &cc);
            for (cc, 0..) |c, j| counts_total[j] += c;
            nodes_total += t.size(t.root);
            if (i < 8) {
                pat.clearRetainingCapacity();
                try sample.printAlloc(gpa, &t, tab.id.flags, &pat);
                sys.stdoutPrint("  {s}\n", .{pat.items});
            }
        }
        sys.stdoutPrint("  sampling: {d:.2} us/case (alias builds={d} cache hits={d} uncached={d} arena={d}KiB)\n", .{ @as(f64, @floatFromInt(sys.nowNs() - ts)) / @as(f64, @floatFromInt(per)) / 1000.0, tab.cache_builds.load(.monotonic), tab.cache_hits.load(.monotonic), tab.uncached.load(.monotonic), tab.arena_top.load(.monotonic) * 4 / 1024 });
    }
    sys.stdoutPrint("nested unbounded/ranged quantifier depth histogram:", .{});
    for (depth_hist, 0..) |h, d| if (h > 0) sys.stdoutPrint(" {d}:{d}", .{ d, h });
    sys.stdoutPrint("\nconstruct share of nodes:", .{});
    for (counts_total, 0..) |c, j| if (c > 0) sys.stdoutPrint(" {s}={d:.3}", .{ @tagName(@as(ast.Construct, @enumFromInt(j))), @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(nodes_total)) });
    sys.stdoutPrint("\n", .{});
    return 0;
}

/// Resume triage of findings listed in OUT/triage_pending.txt (and any
/// finding without a triage.json).
fn cmdTriage(gpa: Allocator, o: *const Options) !u8 {
    var opts = o.*;
    if (opts.config_path == null) {
        const cp = try std.fmt.allocPrint(gpa, "{s}/config.toml", .{o.out});
        if (sys.fileExists(cp)) opts.config_path = cp;
    }
    opts.modes = "interp";
    const s = try setup(gpa, &opts, true);
    const run = s.run;
    // Make every mode available to triage (findings name their own mode).
    var all: std.ArrayList(*const harness.ModeSpec) = .empty;
    for (&harness.builtin_modes) |*m| if (m.engine == .d8) try all.append(gpa, m);
    run.modes = all.items;
    var b: [4096]u8 = undefined;
    const fdir = try std.fmt.bufPrint(&b, "{s}/findings", .{o.out});
    // Find the highest finding id, then fan out over worker threads.
    var max_id: u64 = 0;
    {
        var id: u64 = 1;
        var misses: u32 = 0;
        while (misses < 1000) : (id += 1) {
            var pb: [4096]u8 = undefined;
            if (sys.fileExists(try std.fmt.bufPrint(&pb, "{s}/{d:0>6}/case.irx", .{ fdir, id }))) {
                max_id = id;
                misses = 0;
            } else misses += 1;
        }
    }
    const W = struct {
        run: *runmod.Run,
        gpa: Allocator,
        fdir: []const u8,
        next: *std.atomic.Value(u64),
        done: *std.atomic.Value(u64),
        max_id: u64,
        limit: u64,
        fn work(w: @This()) void {
            var triage: shrink.Triage = .{ .run = w.run, .gpa = w.gpa };
            defer triage.deinit();
            while (true) {
                const id = w.next.fetchAdd(1, .monotonic);
                if (id > w.max_id) break;
                var pb: [4096]u8 = undefined;
                const d = std.fmt.bufPrint(&pb, "{s}/{d:0>6}", .{ w.fdir, id }) catch continue;
                var cb: [4096]u8 = undefined;
                if (!sys.fileExists(std.fmt.bufPrint(&cb, "{s}/case.irx", .{d}) catch continue)) continue;
                if (sys.fileExists(std.fmt.bufPrint(&cb, "{s}/triage.json", .{d}) catch continue)) continue;
                if (w.done.load(.monotonic) >= w.limit) break;
                triage.handle(id) catch |e| sys.stderrPrint("finding {d}: {s}\n", .{ id, @errorName(e) });
                const n = w.done.fetchAdd(1, .monotonic) + 1;
                if (n % 50 == 0) sys.stderrPrint("triaged {d}\n", .{n});
            }
        }
    };
    var next = std.atomic.Value(u64).init(1);
    var done = std.atomic.Value(u64).init(0);
    const jobs: usize = if (o.jobs == 0) sys.physicalCpu() else o.jobs;
    const threads = try gpa.alloc(std.Thread, jobs);
    const w: W = .{ .run = run, .gpa = gpa, .fdir = fdir, .next = &next, .done = &done, .max_id = max_id, .limit = o.max_cases };
    for (threads) |*t| t.* = try std.Thread.spawn(.{}, W.work, .{w});
    for (threads) |t| t.join();
    sys.stderrPrint("triaged {d} findings with {d} workers\n", .{ done.load(.monotonic), jobs });
    return 0;
}

pub fn main(init: std.process.Init) !u8 {
    const gpa = std.heap.c_allocator;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const o = parseArgs(args);
    if (std.mem.eql(u8, o.command, "fuzz")) return cmdFuzz(gpa, &o);
    if (std.mem.eql(u8, o.command, "selfcheck")) return cmdSelfcheck(gpa, &o);
    if (std.mem.eql(u8, o.command, "replay")) return cmdReplay(gpa, &o);
    if (std.mem.eql(u8, o.command, "gate")) return cmdGate(gpa, &o);
    if (std.mem.eql(u8, o.command, "sample")) return cmdSample(gpa, &o);
    if (std.mem.eql(u8, o.command, "triage")) return cmdTriage(gpa, &o);
    usage();
}
