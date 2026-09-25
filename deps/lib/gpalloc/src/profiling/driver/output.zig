const std = @import("std");
const builtin = @import("builtin");
const bench = @import("bench");
const gpalloc = @import("gpalloc");
const pretty = @import("pretty");
const pretty_json = pretty.json;
const pretty_usage = @import("pretty_usage");
const profile_build_options = @import("profile_build_options");

const compare = @import("compare/root.zig");
const options = @import("options.zig");

const metric_schema = "tiny.profiling.metric/v1";

pub const Workload = struct {
    id: []const u8,
    name: []const u8,
};

pub const AllocatorStats = struct {
    before: gpalloc.Stats,
    after: gpalloc.Stats,
};

const usage_text =
    \\usage: gpalloc-bench-driver [options]
    \\       gpalloc-bench-driver compare BASE.ndjson CANDIDATE.ndjson [options]
    \\
    \\Options:
    \\  --allocator MODE       Allocator mode.
    \\  --label NAME           Allocator label written to NDJSON events.
    \\  --workload ID          Workload id, or all. Default: all.
    \\  --warmup N             Warmup samples before measurement. Default: 5.
    \\  --samples N            Measured samples per workload. Default: 30.
    \\  --evals N              Workload evaluations per sample. Default: 1.
    \\  --coz-profile PATH     Write Coz profile events to PATH.
    \\  --coz-experiments      Run the Coz experiment worker during the workload.
    \\  --coz-experiment-ms N  Coz experiment duration in milliseconds.
    \\  --coz-source PATTERN   Source path pattern for Coz line attribution.
    \\  --stabilizer           Randomize code and stack layout between samples.
    \\  --stabilizer-seed N    Layout randomization seed. Default: 20260612.
    \\  --allocator-stats      Emit gpalloc allocator memory metrics.
    \\  --list-workloads       Print workload ids and names.
    \\  -h, --help             Print this message.
    \\
    \\Allocator modes:
    \\  gpalloc, gpalloc-os-pages, gpalloc-os-discard, gpalloc-release-empty
    \\  gpalloc-limited-thread-caches, gpalloc-unlimited-thread-caches
    \\  gpalloc-no-large-cache, gpalloc-no-thread-exit-flush, smp, system
    \\
    \\Run `compare --help` for the A/B comparison options.
    \\
    \\The system allocator mode uses the libc-backed allocator from lib/sys.
    \\Preload mimalloc, jemalloc, or TCMalloc with LD_PRELOAD around this
    \\executable to compare their malloc implementations against the same
    \\workloads.
;

pub fn writeUsage(allocator: std.mem.Allocator) !void {
    try pretty_usage.writeStdoutUsageText(allocator, usage_text);
}

pub fn writeParseError(allocator: std.mem.Allocator, err: anyerror) !void {
    const stderr = pretty_usage.Terminal.stderr(allocator, .{});
    try stderr.writeErrorTextFmt("gpalloc-bench-driver", "{s}", .{@errorName(err)});
    try stderr.writeDoc(pretty.hardline);
    try stderr.writeUsageText(usage_text);
}

pub fn writeCompareUsage(allocator: std.mem.Allocator) !void {
    try pretty_usage.writeStdoutUsageText(allocator, compare.usage_text);
}

pub fn writeCompareParseError(allocator: std.mem.Allocator, err: anyerror) !void {
    const stderr = pretty_usage.Terminal.stderr(allocator, .{});
    try stderr.writeErrorTextFmt("gpalloc-bench-driver compare", "{s}", .{@errorName(err)});
    try stderr.writeDoc(pretty.hardline);
    try stderr.writeUsageText(compare.usage_text);
}

pub fn writeRunStart(writer: *std.Io.Writer, parsed: options.Options) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("event");
    try stringify.write("run_start");
    try stringify.objectField("protocol");
    try stringify.write("gpalloc.bench/v1");
    try stringify.objectField("timestamp_ns");
    try stringify.write(bench.realNowNs());
    try stringify.objectField("git_sha");
    try stringify.write(profile_build_options.git_sha);
    try stringify.objectField("git_dirty");
    try stringify.write(profile_build_options.git_dirty);
    try stringify.objectField("optimize");
    try stringify.write(profile_build_options.optimize);
    try stringify.objectField("target");
    try stringify.write(profile_build_options.target);
    try stringify.objectField("zig_version");
    try stringify.write(builtin.zig_version_string);
    try stringify.objectField("allocator");
    try stringify.write(options.label(parsed));
    try stringify.objectField("allocator_mode");
    try stringify.write(options.modeName(parsed.allocator_mode));
    try stringify.objectField("warmup");
    try stringify.write(parsed.warmup);
    try stringify.objectField("samples");
    try stringify.write(parsed.samples);
    try stringify.objectField("evals");
    try stringify.write(parsed.evals);
    try stringify.objectField("stabilizer");
    try stringify.write(parsed.stabilizer);
    if (parsed.stabilizer) {
        try stringify.objectField("stabilizer_seed");
        try stringify.write(parsed.stabilizer_seed);
    }
    if (parsed.workload_id) |id| {
        try stringify.objectField("workload_filter");
        try stringify.write(id);
    }
    try stringify.endObject();
    try writer.writeByte('\n');
}

pub fn writeSample(
    writer: *std.Io.Writer,
    parsed: options.Options,
    workload: Workload,
    sample_index: u32,
    total_ns: u64,
    ns: u64,
) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("event");
    try stringify.write("sample");
    try writeCommonResultFields(&stringify, parsed, workload);
    try stringify.objectField("sample_index");
    try stringify.write(sample_index);
    try stringify.objectField("total_ns");
    try stringify.write(total_ns);
    try stringify.objectField("ns");
    try stringify.write(ns);
    try stringify.endObject();
    try writer.writeByte('\n');
}

pub fn writeSummary(
    writer: *std.Io.Writer,
    parsed: options.Options,
    workload: Workload,
    stats: bench.SampleStats,
) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("event");
    try stringify.write("summary");
    try writeCommonResultFields(&stringify, parsed, workload);
    try stringify.objectField("sample_count");
    try stringify.write(parsed.samples);
    try stringify.objectField("min_ns");
    try stringify.write(stats.min_ns);
    try stringify.objectField("max_ns");
    try stringify.write(stats.max_ns);
    try stringify.objectField("mean_ns");
    try stringify.write(stats.mean_ns);
    try stringify.objectField("median_ns");
    try stringify.write(stats.median_ns);
    try stringify.objectField("p75_ns");
    try stringify.write(stats.p75_ns);
    try stringify.objectField("p95_ns");
    try stringify.write(stats.p95_ns);
    try stringify.objectField("p99_ns");
    try stringify.write(stats.p99_ns);
    try stringify.endObject();
    try writer.writeByte('\n');
}

pub fn writeAllocatorStats(
    writer: *std.Io.Writer,
    parsed: options.Options,
    workload: Workload,
    stats: AllocatorStats,
) !void {
    try writeCountDelta(writer, parsed, workload, "gpalloc.stats.small_allocations", "allocations", stats.before.small_allocations, stats.after.small_allocations);
    try writeCountDelta(writer, parsed, workload, "gpalloc.stats.small_frees", "frees", stats.before.small_frees, stats.after.small_frees);
    try writeCountDelta(writer, parsed, workload, "gpalloc.stats.large_allocations", "allocations", stats.before.large_allocations, stats.after.large_allocations);
    try writeCountDelta(writer, parsed, workload, "gpalloc.stats.large_frees", "frees", stats.before.large_frees, stats.after.large_frees);
    try writeCountDelta(writer, parsed, workload, "gpalloc.stats.pages_allocated", "pages", stats.before.pages_allocated, stats.after.pages_allocated);
    try writeCountDelta(writer, parsed, workload, "gpalloc.stats.pages_freed", "pages", stats.before.pages_freed, stats.after.pages_freed);
    try writeCountDelta(writer, parsed, workload, "gpalloc.stats.empty_page_discards", "pages", stats.before.empty_page_discards, stats.after.empty_page_discards);
    try writeCountGauge(writer, parsed, workload, "gpalloc.stats.retained_empty_pages", "pages", stats.after.retained_empty_pages);
    try writeBytesGauge(writer, parsed, workload, "gpalloc.stats.discarded_small_bytes", stats.after.discarded_small_bytes);
    try writeBytesGauge(writer, parsed, workload, "gpalloc.stats.active_small_bytes", stats.after.active_small_bytes);
    try writeBytesGauge(writer, parsed, workload, "gpalloc.stats.active_large_bytes", stats.after.active_large_bytes);
    try writeBytesGauge(writer, parsed, workload, "gpalloc.stats.mapped_small_bytes", stats.after.mapped_small_bytes);
}

pub fn writeRunEnd(writer: *std.Io.Writer, benches: u32) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("event");
    try stringify.write("run_end");
    try stringify.objectField("benches");
    try stringify.write(benches);
    try stringify.endObject();
    try writer.writeByte('\n');
}

fn writeCommonResultFields(
    stringify: *pretty_json.Writer,
    parsed: options.Options,
    workload: Workload,
) !void {
    try stringify.objectField("allocator");
    try stringify.write(options.label(parsed));
    try stringify.objectField("allocator_mode");
    try stringify.write(options.modeName(parsed.allocator_mode));
    try stringify.objectField("workload");
    try stringify.write(workload.id);
    try stringify.objectField("workload_name");
    try stringify.write(workload.name);
    try stringify.objectField("evals");
    try stringify.write(parsed.evals);
}

fn writeCountDelta(
    writer: *std.Io.Writer,
    parsed: options.Options,
    workload: Workload,
    metric: []const u8,
    count_kind: []const u8,
    before: u64,
    after: u64,
) !void {
    try writeMetric(writer, parsed, workload, .{
        .metric = metric,
        .unit = "count",
        .value = after -| before,
        .stat_kind = "counter_delta",
        .count_kind = count_kind,
    });
}

fn writeCountGauge(
    writer: *std.Io.Writer,
    parsed: options.Options,
    workload: Workload,
    metric: []const u8,
    count_kind: []const u8,
    value: usize,
) !void {
    try writeMetric(writer, parsed, workload, .{
        .metric = metric,
        .unit = "count",
        .value = @intCast(value),
        .stat_kind = "gauge_after",
        .count_kind = count_kind,
    });
}

fn writeBytesGauge(
    writer: *std.Io.Writer,
    parsed: options.Options,
    workload: Workload,
    metric: []const u8,
    value: usize,
) !void {
    try writeMetric(writer, parsed, workload, .{
        .metric = metric,
        .unit = "bytes",
        .value = @intCast(value),
        .stat_kind = "gauge_after",
        .count_kind = null,
    });
}

const MetricRow = struct {
    metric: []const u8,
    unit: []const u8,
    value: u64,
    stat_kind: []const u8,
    count_kind: ?[]const u8,
};

fn writeMetric(
    writer: *std.Io.Writer,
    parsed: options.Options,
    workload: Workload,
    row: MetricRow,
) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("schema");
    try stringify.write(metric_schema);
    try stringify.objectField("event");
    try stringify.write("summary");
    try stringify.objectField("family");
    try stringify.write("memory");
    try stringify.objectField("metric");
    try stringify.write(row.metric);
    try stringify.objectField("name");
    try stringify.write(row.metric);
    try stringify.objectField("unit");
    try stringify.write(row.unit);
    try stringify.objectField("value");
    try stringify.write(row.value);
    try stringify.objectField("suite");
    try stringify.write("gpalloc");
    try stringify.objectField("summary");
    try stringify.write("allocator_stats");
    try stringify.objectField("phase");
    try stringify.write("measured_samples");
    try stringify.objectField("stat_kind");
    try stringify.write(row.stat_kind);
    if (row.count_kind) |count_kind| {
        try stringify.objectField("count_kind");
        try stringify.write(count_kind);
    }
    try writeCommonResultFields(&stringify, parsed, workload);
    try stringify.objectField("samples");
    try stringify.write(parsed.samples);
    try stringify.endObject();
    try writer.writeByte('\n');
}

test "allocator stats emit strict profiling memory metrics" {
    const allocator = std.testing.allocator;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    const parsed: options.Options = .{
        .allocator_mode = .gpalloc_release_empty,
        .samples = 3,
        .evals = 2,
    };
    try writeAllocatorStats(&out.writer, parsed, .{ .id = "small_churn", .name = "Small churn" }, .{
        .before = .{
            .small_allocations = 4,
            .small_frees = 1,
        },
        .after = .{
            .small_allocations = 14,
            .small_frees = 9,
            .retained_empty_pages = 2,
            .mapped_small_bytes = 8192,
        },
    });

    const text = out.written();
    try std.testing.expect(std.mem.indexOf(u8, text, "\"schema\":\"tiny.profiling.metric/v1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"family\":\"memory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"metric\":\"gpalloc.stats.small_allocations\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"value\":10") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"stat_kind\":\"counter_delta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"metric\":\"gpalloc.stats.mapped_small_bytes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"unit\":\"bytes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"allocator_mode\":\"gpalloc-release-empty\"") != null);
}
