const std = @import("std");
const alloc_phase = @import("alloc_phase");
const sys = @import("sys");

const options = @import("options.zig");
const reader = @import("reader.zig");
const report = @import("report.zig");
const stats = @import("stats/root.zig");

const Options = options.Options;

const max_input_bytes: usize = 256 * 1024 * 1024;

pub const usage_text =
    \\usage: gpalloc-bench-driver compare BASE.ndjson CANDIDATE.ndjson [options]
    \\
    \\Options:
    \\  --iterations N         Bootstrap resamples per workload. Default: 4000.
    \\  --seed N               Bootstrap PRNG seed. Default: 20260612.
    \\  --fail-on-regression   Exit 1 when any workload regresses.
    \\  --json                 Emit NDJSON instead of the text table.
    \\  -h, --help             Print this message.
    \\
    \\Each input holds appended driver runs. Per workload, every summary
    \\median becomes one observation, the ratio is candidate over base, and
    \\the 95% interval comes from bootstrap resampling of run medians. When
    \\both inputs carry median_max_rss_kib summaries, a max_rss_kib section
    \\reports memory verdicts alongside the wall_ns section, and
    \\--fail-on-regression covers both measures.
;

pub fn run(arena: std.mem.Allocator, writer: *std.Io.Writer, parsed: Options) !u8 {
    const base_bytes = try readInput(arena, parsed.base_path);
    const candidate_bytes = try readInput(arena, parsed.candidate_path);
    const base = try reader.parse(arena, base_bytes);
    const candidate = try reader.parse(arena, candidate_bytes);

    var comparison_storage: ?stats.ComparisonStorage = if (comparisonLimits(&base, &candidate, parsed.iterations)) |limits|
        try stats.ComparisonStorage.init(arena, limits)
    else
        null;
    defer if (comparison_storage) |*storage| storage.deinit(arena);
    if (comparison_storage) |*storage| storage.activate();
    const storage_ptr = if (comparison_storage) |*storage| storage else null;

    var sections: std.ArrayListUnmanaged(report.Section) = .empty;
    try appendSection(arena, &sections, .wall, &base.wall, &candidate.wall, parsed, storage_ptr);
    try appendSection(arena, &sections, .rss, &base.rss, &candidate.rss, parsed, storage_ptr);

    const header: report.Header = .{
        .base_path = parsed.base_path,
        .candidate_path = parsed.candidate_path,
        .base_runs = base.runs,
        .candidate_runs = candidate.runs,
        .iterations = parsed.iterations,
        .seed = parsed.seed,
    };
    if (parsed.json) {
        try report.writeJson(writer, header, sections.items);
    } else {
        try report.writeText(writer, header, sections.items);
    }

    var regressed: u32 = 0;
    for (sections.items) |section| regressed += section.counts.regressed;
    if (parsed.fail_on_regression and regressed > 0) return 1;
    return 0;
}

fn appendSection(
    arena: std.mem.Allocator,
    sections: *std.ArrayListUnmanaged(report.Section),
    measure: report.Measure,
    base_series: *const reader.Series,
    candidate_series: *const reader.Series,
    parsed: Options,
    storage: ?*stats.ComparisonStorage,
) !void {
    var rows: std.ArrayListUnmanaged(report.Row) = .empty;
    var counts: report.Counts = .{};
    for (base_series.keys()) |workload| {
        const base_values = reader.seriesValues(base_series, workload);
        const candidate_values = reader.seriesValues(candidate_series, workload);
        if (base_values.len == 0 or candidate_values.len == 0) continue;
        std.debug.assert(storage != null);
        const result = try stats.compareSeries(
            storage.?,
            base_values,
            candidate_values,
            parsed.iterations,
            parsed.seed,
        );
        counts.record(result.verdict);
        try rows.append(arena, .{ .workload = workload, .result = result });
    }
    if (rows.items.len == 0 and measure != .wall) return;
    std.mem.sort(report.Row, rows.items, {}, rowLessThan);
    try sections.append(arena, .{
        .measure = measure,
        .rows = rows.items,
        .counts = counts,
    });
}

fn comparisonLimits(
    base: *const reader.Dataset,
    candidate: *const reader.Dataset,
    iterations: u32,
) ?stats.ComparisonLimits {
    const max_samples = @max(
        maxComparableSamples(&base.wall, &candidate.wall),
        maxComparableSamples(&base.rss, &candidate.rss),
    );
    if (max_samples == 0) return null;
    return .{
        .max_samples_per_series = max_samples,
        .max_bootstrap_iterations = iterations,
    };
}

fn maxComparableSamples(
    base_series: *const reader.Series,
    candidate_series: *const reader.Series,
) usize {
    var max_samples: usize = 0;
    for (base_series.keys()) |workload| {
        const base_values = reader.seriesValues(base_series, workload);
        const candidate_values = reader.seriesValues(candidate_series, workload);
        if (base_values.len == 0 or candidate_values.len == 0) continue;
        max_samples = @max(max_samples, @max(base_values.len, candidate_values.len));
    }
    return max_samples;
}

fn rowLessThan(_: void, left: report.Row, right: report.Row) bool {
    if (left.result.ratio == right.result.ratio) {
        return std.mem.lessThan(u8, left.workload, right.workload);
    }
    return left.result.ratio < right.result.ratio;
}

fn readInput(arena: std.mem.Allocator, path: []const u8) ![]const u8 {
    const fs_io = sys.fs.debugIo();
    var file = if (std.mem.startsWith(u8, path, "/"))
        try sys.fs.openAbsoluteFile(path, .{})
    else
        try sys.fs.cwd().openFile(fs_io, path, .{});
    defer file.close(fs_io);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    var buffer: [16384]u8 = undefined;
    while (true) {
        const count = try sys.fs.readHandle(file, &buffer);
        if (count == 0) break;
        if (out.items.len + count > max_input_bytes) return error.StreamTooLong;
        try out.appendSlice(arena, buffer[0..count]);
    }
    return out.items;
}

test {
    std.testing.refAllDecls(@This());
}

test "compare run reports verdicts across datasets" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const base = try reader.parse(arena,
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"steady","median_ns":100}
        \\{"event":"summary","workload":"churn","median_ns":1000}
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"steady","median_ns":102}
        \\{"event":"summary","workload":"churn","median_ns":1010}
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"steady","median_ns":98}
        \\{"event":"summary","workload":"churn","median_ns":990}
    );
    const candidate = try reader.parse(arena,
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"steady","median_ns":80}
        \\{"event":"summary","workload":"churn","median_ns":1005}
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"steady","median_ns":81}
        \\{"event":"summary","workload":"churn","median_ns":995}
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"steady","median_ns":79}
        \\{"event":"summary","workload":"churn","median_ns":1000}
    );

    var storage = try stats.ComparisonStorage.init(arena, comparisonLimits(&base, &candidate, 400).?);
    defer storage.deinit(arena);
    storage.activate();
    const steady = try stats.compareSeries(&storage, base.medians("steady"), candidate.medians("steady"), 400, 7);
    try std.testing.expectEqual(stats.Verdict.improved, steady.verdict);
    const churn = try stats.compareSeries(&storage, base.medians("churn"), candidate.medians("churn"), 400, 7);
    try std.testing.expectEqual(stats.Verdict.neutral, churn.verdict);
}

test "sections cover wall always and rss when both sides carry it" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const base = try reader.parse(arena,
        \\{"event":"run_start","allocator":"libc"}
        \\{"event":"summary","workload":"cfrac","median_ns":100,"median_max_rss_kib":4096}
        \\{"event":"run_start","allocator":"libc"}
        \\{"event":"summary","workload":"cfrac","median_ns":101,"median_max_rss_kib":4100}
        \\{"event":"run_start","allocator":"libc"}
        \\{"event":"summary","workload":"cfrac","median_ns":99,"median_max_rss_kib":4090}
    );
    const candidate = try reader.parse(arena,
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"cfrac","median_ns":100,"median_max_rss_kib":8192}
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"cfrac","median_ns":100,"median_max_rss_kib":8200}
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"cfrac","median_ns":101,"median_max_rss_kib":8190}
    );

    var sections: std.ArrayListUnmanaged(report.Section) = .empty;
    const parsed: Options = .{
        .base_path = "base",
        .candidate_path = "candidate",
        .iterations = 400,
        .seed = 7,
    };
    var storage = try stats.ComparisonStorage.init(arena, comparisonLimits(&base, &candidate, parsed.iterations).?);
    defer storage.deinit(arena);
    storage.activate();
    try appendSection(arena, &sections, .wall, &base.wall, &candidate.wall, parsed, &storage);
    try appendSection(arena, &sections, .rss, &base.rss, &candidate.rss, parsed, &storage);

    try std.testing.expectEqual(@as(usize, 2), sections.items.len);
    try std.testing.expectEqual(report.Measure.wall, sections.items[0].measure);
    try std.testing.expectEqual(report.Measure.rss, sections.items[1].measure);
    try std.testing.expectEqual(@as(u32, 1), sections.items[1].counts.regressed);

    var no_rss: std.ArrayListUnmanaged(report.Section) = .empty;
    var empty: reader.Series = .empty;
    try appendSection(arena, &no_rss, .rss, &empty, &empty, parsed, null);
    try std.testing.expectEqual(@as(usize, 0), no_rss.items.len);
}

test "comparison command reuses one comparison region across sections" {
    comptime {
        alloc_phase.capacity.record(
            alloc_phase.capacity.witness(@import("bench").ComparisonStorage, "bench_comparison_command"),
        );
    }

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const base = try reader.parse(arena,
        \\{"event":"run_start","allocator":"libc"}
        \\{"event":"summary","workload":"alpha","median_ns":100,"median_max_rss_kib":4000}
        \\{"event":"summary","workload":"beta","median_ns":200,"median_max_rss_kib":5000}
        \\{"event":"run_start","allocator":"libc"}
        \\{"event":"summary","workload":"alpha","median_ns":101,"median_max_rss_kib":4010}
        \\{"event":"summary","workload":"beta","median_ns":201,"median_max_rss_kib":5010}
        \\{"event":"run_start","allocator":"libc"}
        \\{"event":"summary","workload":"alpha","median_ns":99,"median_max_rss_kib":3990}
        \\{"event":"summary","workload":"beta","median_ns":199,"median_max_rss_kib":4990}
    );
    const candidate = try reader.parse(arena,
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"alpha","median_ns":80,"median_max_rss_kib":6000}
        \\{"event":"summary","workload":"beta","median_ns":190,"median_max_rss_kib":4900}
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"alpha","median_ns":81,"median_max_rss_kib":6010}
        \\{"event":"summary","workload":"beta","median_ns":191,"median_max_rss_kib":4910}
        \\{"event":"run_start","allocator":"gpalloc"}
        \\{"event":"summary","workload":"alpha","median_ns":79,"median_max_rss_kib":5990}
        \\{"event":"summary","workload":"beta","median_ns":189,"median_max_rss_kib":4890}
    );
    const parsed: Options = .{
        .base_path = "base",
        .candidate_path = "candidate",
        .iterations = 400,
        .seed = 7,
    };
    var counting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var storage = try stats.ComparisonStorage.init(
        counting.allocator(),
        comparisonLimits(&base, &candidate, parsed.iterations).?,
    );
    defer storage.deinit(counting.allocator());
    storage.activate();
    const allocations = counting.alloc_index;
    const bytes = counting.allocated_bytes;

    var sections: std.ArrayListUnmanaged(report.Section) = .empty;
    try appendSection(arena, &sections, .wall, &base.wall, &candidate.wall, parsed, &storage);
    try appendSection(arena, &sections, .rss, &base.rss, &candidate.rss, parsed, &storage);

    try std.testing.expectEqual(@as(usize, 1), allocations);
    try std.testing.expectEqual(@as(usize, 3_236), bytes);
    try std.testing.expectEqual(allocations, counting.alloc_index);
    try std.testing.expectEqual(bytes, counting.allocated_bytes);
    try std.testing.expectEqual(@as(usize, 2), sections.items.len);
    try std.testing.expectEqual(@as(usize, 2), sections.items[0].rows.len);
    try std.testing.expectEqual(@as(usize, 2), sections.items[1].rows.len);
    try std.testing.expect(!storage.status().in_use);
}
