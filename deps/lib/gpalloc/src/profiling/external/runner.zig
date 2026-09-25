const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys = @import("sys");

const catalog = @import("catalog.zig");
const options = @import("options.zig");
const output = @import("output.zig");

const wait_poll_ms: u64 = 2;
const max_stdout_bytes: usize = 1024 * 1024;

pub const Execution = struct {
    wall_ns: u64,
    max_rss_kib: u64,
};

pub fn writeBenchmarks(writer: *std.Io.Writer) !void {
    var line_buffer: [256]u8 = undefined;
    for (catalog.all) |benchmark| {
        try bench.pretty.write(
            writer,
            .{ .text = try std.fmt.bufPrint(&line_buffer, "{s}\t{s}\n", .{
                benchmark.id,
                benchmark.name,
            }) },
            .{},
        );
    }
}

pub fn runSelectedBenchmarks(
    arena: std.mem.Allocator,
    process_io: std.Io,
    environ_map: *const sys.process.Environ.Map,
    writer: *std.Io.Writer,
    parsed: options.Options,
) !struct { benches: u32, errors: u32 } {
    var benches: u32 = 0;
    var errors: u32 = 0;
    if (parsed.benchmark_id) |id| {
        const benchmark = catalog.byId(id) orelse return error.UnknownBenchmark;
        runOneBenchmark(arena, process_io, environ_map, writer, parsed, benchmark) catch |err| {
            try output.writeBenchmarkError(writer, parsed, benchmark, @errorName(err));
            errors += 1;
        };
        benches += 1;
        return .{ .benches = benches, .errors = errors };
    }
    for (catalog.all) |benchmark| {
        runOneBenchmark(arena, process_io, environ_map, writer, parsed, benchmark) catch |err| {
            try output.writeBenchmarkError(writer, parsed, benchmark, @errorName(err));
            errors += 1;
        };
        benches += 1;
    }
    return .{ .benches = benches, .errors = errors };
}

fn runOneBenchmark(
    arena: std.mem.Allocator,
    process_io: std.Io,
    environ_map: *const sys.process.Environ.Map,
    writer: *std.Io.Writer,
    parsed: options.Options,
    benchmark: catalog.Benchmark,
) !void {
    const benchmark_latency = bench.phaseAt("gpalloc.external.benchmark", @src());
    benchmark_latency.setName(benchmark.id);
    defer benchmark_latency.end();

    const procs = if (parsed.procs != 0) parsed.procs else sys.thread.cpuCount();
    const binary = try catalog.binaryPath(arena, parsed.suite_dir, benchmark);
    const args = try catalog.arguments(arena, parsed.suite_dir, benchmark, parsed.profile, procs);
    const stdin_path = try catalog.stdinPath(arena, parsed.suite_dir, benchmark);
    const stdout_path: ?[]const u8 = if (benchmark.metric.parsesStdout())
        try std.fs.path.join(arena, &.{ parsed.suite_dir, "out", "gpalloc-external-stdout.log" })
    else
        null;
    const child_cwd = try std.fs.path.join(arena, &.{ parsed.suite_dir, "out", "bench" });

    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    try argv.append(arena, binary);
    try argv.appendSlice(arena, args);

    var env = try environ_map.clone(arena);
    if (try options.preloadPath(arena, parsed)) |preload| {
        try env.put("LD_PRELOAD", try sys.fs.realPathAlloc(arena, preload));
    } else if (env.get("LD_PRELOAD") != null) {
        try env.put("LD_PRELOAD", "");
    }

    var warmup_index: u32 = 0;
    while (warmup_index < parsed.warmup) : (warmup_index += 1) {
        _ = try runExecution(process_io, argv.items, &env, stdin_path, stdout_path, child_cwd);
        coz.progressNamed("gpalloc.external.warmup");
    }

    const metric_samples = try arena.alloc(u64, parsed.samples);
    const rss_samples = try arena.alloc(u64, parsed.samples);
    var sample_index: u32 = 0;
    while (sample_index < parsed.samples) : (sample_index += 1) {
        const sample_latency = bench.phaseAt("gpalloc.external.sample", @src());
        sample_latency.setName(benchmark.id);
        defer sample_latency.end();

        const execution = try runExecution(process_io, argv.items, &env, stdin_path, stdout_path, child_cwd);
        const stdout_text: []const u8 = if (stdout_path) |path|
            try sys.fs.readFileAlloc(arena, path, max_stdout_bytes)
        else
            "";
        const metric_ns = try catalog.deriveNs(benchmark.metric, stdout_text, execution.wall_ns);
        metric_samples[sample_index] = metric_ns;
        rss_samples[sample_index] = execution.max_rss_kib;
        try output.writeSample(
            writer,
            parsed,
            benchmark,
            sample_index,
            metric_ns,
            execution.wall_ns,
            execution.max_rss_kib,
        );
        coz.progressNamed("gpalloc.external.sample");
    }

    var statistics = try bench.StatisticsStorage.init(arena, .{ .samples = metric_samples.len });
    defer statistics.deinit(arena);
    statistics.activate();
    const metric_stats = try bench.computeSampleStats(&statistics, metric_samples);
    try output.writeSummary(writer, parsed, benchmark, metric_stats, medianInPlace(rss_samples));
    coz.progressNamed("gpalloc.external.benchmark.complete");
}

fn runExecution(
    process_io: std.Io,
    argv: []const []const u8,
    env: *sys.process.Environ.Map,
    stdin_path: ?[]const u8,
    stdout_path: ?[]const u8,
    child_cwd: []const u8,
) !Execution {
    const fs_io = sys.fs.debugIo();

    const stdin_file: ?std.Io.File = if (stdin_path) |path|
        if (std.mem.startsWith(u8, path, "/"))
            try sys.fs.openAbsoluteFile(path, .{})
        else
            try sys.fs.cwd().openFile(fs_io, path, .{})
    else
        null;
    defer if (stdin_file) |file| file.close(fs_io);

    const stdout_file: ?std.Io.File = if (stdout_path) |path|
        try sys.fs.createFile(path, .{})
    else
        null;
    defer if (stdout_file) |file| file.close(fs_io);

    const start = bench.nowNs();
    var child = try sys.process.spawn(process_io, .{
        .argv = argv,
        .cwd = .{ .path = child_cwd },
        .environ_map = env,
        .stdin = if (stdin_file) |file| .{ .file = file } else .ignore,
        .stdout = if (stdout_file) |file| .{ .file = file } else .ignore,
        .stderr = .ignore,
        .request_resource_usage_statistics = false,
    });
    errdefer child.kill(process_io);

    const pid = child.id.?;
    while (true) {
        if (try sys.process.waitNoHang(pid)) |outcome| {
            child.id = null;
            const wall_ns = bench.elapsedNs(start);
            if (sys.process.exitCode(outcome.term) != 0) return error.BenchmarkFailed;
            const max_rss_kib: u64 = if (outcome.usage.maxrss_kib) |kib|
                @intCast(@max(kib, 0))
            else
                0;
            return .{ .wall_ns = wall_ns, .max_rss_kib = max_rss_kib };
        }
        sys.time.sleepMilliseconds(wait_poll_ms);
    }
}

fn medianInPlace(values: []u64) u64 {
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    return values[values.len / 2];
}

test "median in place selects the middle observation" {
    var values = [_]u64{ 5, 1, 9, 3, 7 };
    try std.testing.expectEqual(@as(u64, 5), medianInPlace(&values));
    var pair = [_]u64{ 4, 2 };
    try std.testing.expectEqual(@as(u64, 4), medianInPlace(&pair));
}
