const std = @import("std");
const bench = @import("bench");
const memtrace = @import("memtrace");
const corpus = @import("corpus.zig");

const coz = bench.coz;

pub fn small(allocator: std.mem.Allocator) void {
    const phase = bench.phaseAt("memtrace.replay.small", @src());
    defer phase.end();
    replay(allocator, corpus.get().small, false);
    coz.progressNamed("memtrace.replay.small.complete");
}

pub fn large(allocator: std.mem.Allocator) void {
    const phase = bench.phaseAt("memtrace.replay.large", @src());
    defer phase.end();
    replay(allocator, corpus.get().large, false);
    coz.progressNamed("memtrace.replay.large.complete");
}

pub fn summary(allocator: std.mem.Allocator) void {
    const phase = bench.phaseAt("memtrace.replay.summary", @src());
    defer phase.end();
    replay(allocator, corpus.get().large, true);
    coz.progressNamed("memtrace.replay.summary.complete");
}

fn replay(allocator: std.mem.Allocator, bytes: []const u8, write_summary: bool) void {
    var analyzer = memtrace.Analyzer.init(allocator);
    defer analyzer.deinit();
    analyzer.ingestJsonlBytes(bytes) catch @panic("memtrace replay failed");
    if (write_summary) {
        var scratch: [4096]u8 = undefined;
        var sink = std.Io.Writer.Discarding.init(&scratch);
        analyzer.writeSummary(&sink.writer, .{ .include_sites = true }) catch @panic("memtrace summary failed");
        std.mem.doNotOptimizeAway(sink.fullCount());
    }
    std.mem.doNotOptimizeAway(&analyzer);
}
