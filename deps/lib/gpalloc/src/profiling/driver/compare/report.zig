const std = @import("std");
const bench = @import("bench");
const pretty = @import("pretty");
const pretty_json = pretty.json;

const stats = @import("stats/root.zig");

pub const Measure = enum {
    wall,
    rss,

    pub fn label(self: Measure) []const u8 {
        return switch (self) {
            .wall => "wall_ns",
            .rss => "max_rss_kib",
        };
    }

    pub fn baseColumn(self: Measure) []const u8 {
        return switch (self) {
            .wall => "base_ns",
            .rss => "base_kib",
        };
    }

    pub fn candidateColumn(self: Measure) []const u8 {
        return switch (self) {
            .wall => "candidate_ns",
            .rss => "candidate_kib",
        };
    }
};

pub const Row = struct {
    workload: []const u8,
    result: stats.Result,
};

pub const Section = struct {
    measure: Measure,
    rows: []const Row,
    counts: Counts,
};

pub const Header = struct {
    base_path: []const u8,
    candidate_path: []const u8,
    base_runs: u32,
    candidate_runs: u32,
    iterations: u32,
    seed: u64,
};

pub const Counts = struct {
    improved: u32 = 0,
    regressed: u32 = 0,
    neutral: u32 = 0,

    pub fn record(self: *Counts, verdict: stats.Verdict) void {
        switch (verdict) {
            .improved => self.improved += 1,
            .regressed => self.regressed += 1,
            .neutral => self.neutral += 1,
        }
    }
};

pub fn writeText(writer: *std.Io.Writer, header: Header, sections: []const Section) !void {
    var line_buffer: [256]u8 = undefined;
    try writeLine(writer, &line_buffer, "base: {s} ({d} runs)  candidate: {s} ({d} runs)  bootstrap: {d}x seed {d}\n", .{
        header.base_path,
        header.base_runs,
        header.candidate_path,
        header.candidate_runs,
        header.iterations,
        header.seed,
    });
    for (sections) |section| {
        try writeLine(writer, &line_buffer, "{s}\n", .{section.measure.label()});
        try writeLine(writer, &line_buffer, "{s:<36} {s:>12} {s:>13} {s:>7}  {s:<15} {s}\n", .{
            "workload",
            section.measure.baseColumn(),
            section.measure.candidateColumn(),
            "ratio",
            "95% CI",
            "verdict",
        });
        for (section.rows) |row| {
            var interval_buffer: [48]u8 = undefined;
            const interval = try std.fmt.bufPrint(&interval_buffer, "[{d:.3},{d:.3}]", .{
                row.result.ci_low,
                row.result.ci_high,
            });
            try writeLine(writer, &line_buffer, "{s:<36} {d:>12} {d:>13} {d:>7.3}  {s:<15} {s}\n", .{
                row.workload,
                row.result.base_median,
                row.result.candidate_median,
                row.result.ratio,
                interval,
                row.result.verdict.name(),
            });
        }
        try writeLine(writer, &line_buffer, "improved {d}, regressed {d}, neutral {d}\n", .{
            section.counts.improved,
            section.counts.regressed,
            section.counts.neutral,
        });
    }
}

pub fn writeJson(writer: *std.Io.Writer, header: Header, sections: []const Section) !void {
    {
        var stringify = pretty_json.Writer.init(writer, .minified);
        try stringify.beginObject();
        try stringify.objectField("event");
        try stringify.write("compare_start");
        try stringify.objectField("protocol");
        try stringify.write("gpalloc.bench.compare/v2");
        try stringify.objectField("base");
        try stringify.write(header.base_path);
        try stringify.objectField("base_runs");
        try stringify.write(header.base_runs);
        try stringify.objectField("candidate");
        try stringify.write(header.candidate_path);
        try stringify.objectField("candidate_runs");
        try stringify.write(header.candidate_runs);
        try stringify.objectField("iterations");
        try stringify.write(header.iterations);
        try stringify.objectField("seed");
        try stringify.write(header.seed);
        try stringify.endObject();
        try writer.writeByte('\n');
    }
    for (sections) |section| {
        for (section.rows) |row| {
            var stringify = pretty_json.Writer.init(writer, .minified);
            try stringify.beginObject();
            try stringify.objectField("event");
            try stringify.write("comparison");
            try stringify.objectField("measure");
            try stringify.write(section.measure.label());
            try stringify.objectField("workload");
            try stringify.write(row.workload);
            try stringify.objectField("base_median");
            try stringify.write(row.result.base_median);
            try stringify.objectField("candidate_median");
            try stringify.write(row.result.candidate_median);
            try stringify.objectField("ratio");
            try stringify.write(row.result.ratio);
            try stringify.objectField("ci_low");
            try stringify.write(row.result.ci_low);
            try stringify.objectField("ci_high");
            try stringify.write(row.result.ci_high);
            try stringify.objectField("verdict");
            try stringify.write(row.result.verdict.name());
            try stringify.endObject();
            try writer.writeByte('\n');
        }
        var stringify = pretty_json.Writer.init(writer, .minified);
        try stringify.beginObject();
        try stringify.objectField("event");
        try stringify.write("compare_counts");
        try stringify.objectField("measure");
        try stringify.write(section.measure.label());
        try stringify.objectField("improved");
        try stringify.write(section.counts.improved);
        try stringify.objectField("regressed");
        try stringify.write(section.counts.regressed);
        try stringify.objectField("neutral");
        try stringify.write(section.counts.neutral);
        try stringify.endObject();
        try writer.writeByte('\n');
    }
    {
        var totals: Counts = .{};
        for (sections) |section| {
            totals.improved += section.counts.improved;
            totals.regressed += section.counts.regressed;
            totals.neutral += section.counts.neutral;
        }
        var stringify = pretty_json.Writer.init(writer, .minified);
        try stringify.beginObject();
        try stringify.objectField("event");
        try stringify.write("compare_end");
        try stringify.objectField("improved");
        try stringify.write(totals.improved);
        try stringify.objectField("regressed");
        try stringify.write(totals.regressed);
        try stringify.objectField("neutral");
        try stringify.write(totals.neutral);
        try stringify.endObject();
        try writer.writeByte('\n');
    }
}

fn writeLine(
    writer: *std.Io.Writer,
    line_buffer: []u8,
    comptime format: []const u8,
    args: anytype,
) !void {
    try bench.pretty.write(
        writer,
        .{ .text = try std.fmt.bufPrint(line_buffer, format, args) },
        .{},
    );
}

test "text report renders one section per measure" {
    const allocator = std.testing.allocator;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    const wall_rows = [_]Row{.{
        .workload = "cfrac",
        .result = .{
            .base_median = 1653,
            .candidate_median = 1623,
            .ratio = 0.982,
            .ci_low = 0.958,
            .ci_high = 0.996,
            .verdict = .improved,
        },
    }};
    const rss_rows = [_]Row{.{
        .workload = "cfrac",
        .result = .{
            .base_median = 4096,
            .candidate_median = 5000,
            .ratio = 1.22,
            .ci_low = 1.1,
            .ci_high = 1.3,
            .verdict = .regressed,
        },
    }};
    const sections = [_]Section{
        .{ .measure = .wall, .rows = &wall_rows, .counts = .{ .improved = 1 } },
        .{ .measure = .rss, .rows = &rss_rows, .counts = .{ .regressed = 1 } },
    };
    try writeText(&out.writer, .{
        .base_path = "base.ndjson",
        .candidate_path = "cand.ndjson",
        .base_runs = 3,
        .candidate_runs = 3,
        .iterations = 4000,
        .seed = 20260612,
    }, &sections);

    const text = out.written();
    try std.testing.expect(std.mem.indexOf(u8, text, "wall_ns") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "max_rss_kib") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "base_kib") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "[0.958,0.996]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "improved 1, regressed 0, neutral 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "improved 0, regressed 1, neutral 0") != null);
}

test "json report emits protocol v2 with measure fields and counts" {
    const allocator = std.testing.allocator;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    const rows = [_]Row{.{
        .workload = "redis_trace",
        .result = .{
            .base_median = 900,
            .candidate_median = 940,
            .ratio = 1.044,
            .ci_low = 1.01,
            .ci_high = 1.08,
            .verdict = .regressed,
        },
    }};
    const sections = [_]Section{
        .{ .measure = .wall, .rows = &rows, .counts = .{ .regressed = 1 } },
    };
    try writeJson(&out.writer, .{
        .base_path = "base.ndjson",
        .candidate_path = "cand.ndjson",
        .base_runs = 1,
        .candidate_runs = 1,
        .iterations = 100,
        .seed = 7,
    }, &sections);

    const text = out.written();
    try std.testing.expect(std.mem.indexOf(u8, text, "\"protocol\":\"gpalloc.bench.compare/v2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"measure\":\"wall_ns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"base_median\":900") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"verdict\":\"regressed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"event\":\"compare_counts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"event\":\"compare_end\"") != null);
}
