const std = @import("std");
const builtin = @import("builtin");
const bench = @import("bench");
const pretty = @import("pretty");
const pretty_json = pretty.json;
const pretty_usage = @import("pretty_usage");
const profile_build_options = @import("profile_build_options");

const catalog = @import("catalog.zig");
const options = @import("options.zig");

pub const usage_text =
    \\usage: gpalloc-external-bench [options]
    \\
    \\Options:
    \\  --suite-dir PATH    mimalloc-bench checkout. Default: zig-out/external/mimalloc-bench.
    \\  --allocator MODE    libc, gpalloc, mimalloc, jemalloc, tcmalloc, or preload:PATH.
    \\  --label NAME        Allocator label written to NDJSON events.
    \\  --benchmark ID      Benchmark id, or all. Default: all.
    \\  --full              Use the full workload sizes instead of smoke sizes.
    \\  --samples N         Measured executions per benchmark. Default: 5.
    \\  --warmup N          Warmup executions before measurement. Default: 1.
    \\  --procs N           Worker count for threaded benchmarks. Default: host CPUs.
    \\  --list-benchmarks   Print benchmark ids and names.
    \\  -h, --help          Print this message.
    \\
    \\Install the suite first with `zig build allocator-suite -- <dir> bench mi je tc`
    \\and build the gpalloc preload library with `zig build preload`. Each measured
    \\execution is one sample; wall time and peak RSS come from wait4 rusage.
    \\Fixed-duration benchmarks (larson, larson-sized, xmalloc-test, rptest) report
    \\their stdout-derived relative time as the sample ns, following the
    \\mimalloc-bench normalization; wall time stays in wall_ns. The NDJSON stream
    \\feeds `gpalloc-bench-driver compare` directly.
;

pub fn writeUsage(allocator: std.mem.Allocator) !void {
    try pretty_usage.writeStdoutUsageText(allocator, usage_text);
}

pub fn writeParseError(allocator: std.mem.Allocator, err: anyerror) !void {
    const stderr = pretty_usage.Terminal.stderr(allocator, .{});
    try stderr.writeErrorTextFmt("gpalloc-external-bench", "{s}", .{@errorName(err)});
    try stderr.writeDoc(pretty.hardline);
    try stderr.writeUsageText(usage_text);
}

pub fn writeRunStart(writer: *std.Io.Writer, parsed: options.Options) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("event");
    try stringify.write("run_start");
    try stringify.objectField("protocol");
    try stringify.write("gpalloc.bench.external/v1");
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
    try stringify.write(parsed.allocator_mode.label());
    try stringify.objectField("suite_dir");
    try stringify.write(parsed.suite_dir);
    try stringify.objectField("profile");
    try stringify.write(@tagName(parsed.profile));
    try stringify.objectField("warmup");
    try stringify.write(parsed.warmup);
    try stringify.objectField("samples");
    try stringify.write(parsed.samples);
    if (parsed.benchmark_id) |id| {
        try stringify.objectField("benchmark_filter");
        try stringify.write(id);
    }
    try stringify.endObject();
    try writer.writeByte('\n');
}

pub fn writeSample(
    writer: *std.Io.Writer,
    parsed: options.Options,
    benchmark: catalog.Benchmark,
    sample_index: u32,
    metric_ns: u64,
    wall_ns: u64,
    max_rss_kib: u64,
) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("event");
    try stringify.write("sample");
    try writeCommonFields(&stringify, parsed, benchmark);
    try stringify.objectField("sample_index");
    try stringify.write(sample_index);
    try stringify.objectField("ns");
    try stringify.write(metric_ns);
    try stringify.objectField("wall_ns");
    try stringify.write(wall_ns);
    try stringify.objectField("max_rss_kib");
    try stringify.write(max_rss_kib);
    try stringify.endObject();
    try writer.writeByte('\n');
}

pub fn writeSummary(
    writer: *std.Io.Writer,
    parsed: options.Options,
    benchmark: catalog.Benchmark,
    wall_stats: bench.SampleStats,
    median_max_rss_kib: u64,
) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("event");
    try stringify.write("summary");
    try writeCommonFields(&stringify, parsed, benchmark);
    try stringify.objectField("sample_count");
    try stringify.write(parsed.samples);
    try stringify.objectField("min_ns");
    try stringify.write(wall_stats.min_ns);
    try stringify.objectField("max_ns");
    try stringify.write(wall_stats.max_ns);
    try stringify.objectField("mean_ns");
    try stringify.write(wall_stats.mean_ns);
    try stringify.objectField("median_ns");
    try stringify.write(wall_stats.median_ns);
    try stringify.objectField("p75_ns");
    try stringify.write(wall_stats.p75_ns);
    try stringify.objectField("p95_ns");
    try stringify.write(wall_stats.p95_ns);
    try stringify.objectField("p99_ns");
    try stringify.write(wall_stats.p99_ns);
    try stringify.objectField("median_max_rss_kib");
    try stringify.write(median_max_rss_kib);
    try stringify.endObject();
    try writer.writeByte('\n');
}

pub fn writeBenchmarkError(
    writer: *std.Io.Writer,
    parsed: options.Options,
    benchmark: catalog.Benchmark,
    detail: []const u8,
) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("event");
    try stringify.write("benchmark_error");
    try writeCommonFields(&stringify, parsed, benchmark);
    try stringify.objectField("detail");
    try stringify.write(detail);
    try stringify.endObject();
    try writer.writeByte('\n');
}

pub fn writeSuiteMissing(writer: *std.Io.Writer, suite_dir: []const u8) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("event");
    try stringify.write("suite_missing");
    try stringify.objectField("suite_dir");
    try stringify.write(suite_dir);
    try stringify.objectField("hint");
    try stringify.write("install the external allocator comparison suite with `zig build allocator-suite`");
    try stringify.endObject();
    try writer.writeByte('\n');
}

pub fn writeRunEnd(writer: *std.Io.Writer, benches: u32, errors: u32) !void {
    var stringify = pretty_json.Writer.init(writer, .minified);
    try stringify.beginObject();
    try stringify.objectField("event");
    try stringify.write("run_end");
    try stringify.objectField("benches");
    try stringify.write(benches);
    try stringify.objectField("errors");
    try stringify.write(errors);
    try stringify.endObject();
    try writer.writeByte('\n');
}

fn writeCommonFields(
    stringify: *pretty_json.Writer,
    parsed: options.Options,
    benchmark: catalog.Benchmark,
) !void {
    try stringify.objectField("allocator");
    try stringify.write(options.label(parsed));
    try stringify.objectField("workload");
    try stringify.write(benchmark.id);
    try stringify.objectField("workload_name");
    try stringify.write(benchmark.name);
    try stringify.objectField("metric");
    try stringify.write(benchmark.metric.label());
}

test "run events carry provenance and compare-compatible fields" {
    const allocator = std.testing.allocator;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    const parsed: options.Options = .{ .allocator_mode = .gpalloc, .samples = 3 };
    try writeRunStart(&out.writer, parsed);
    const benchmark = catalog.byId("cfrac").?;
    try writeSample(&out.writer, parsed, benchmark, 0, 1200, 1250, 4096);
    try writeSummary(&out.writer, parsed, benchmark, .{
        .min_ns = 1100,
        .max_ns = 1300,
        .mean_ns = 1200,
        .median_ns = 1200,
        .p75_ns = 1250,
        .p95_ns = 1300,
        .p99_ns = 1300,
        .total_ns = 3600,
    }, 4096);
    try writeRunEnd(&out.writer, 1, 0);

    const text = out.written();
    try std.testing.expect(std.mem.indexOf(u8, text, "\"protocol\":\"gpalloc.bench.external/v1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"git_sha\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"workload\":\"cfrac\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"metric\":\"wall\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"ns\":1200") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"wall_ns\":1250") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"median_ns\":1200") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"median_max_rss_kib\":4096") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"allocator\":\"gpalloc\"") != null);
}
