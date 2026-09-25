const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const value_count: usize = 4096;
const shard_count: usize = 64;
const shard_size = value_count / shard_count;
const histogram_capacity: usize = 64;
const Histogram = simd.Bins(histogram_capacity);

var source: [value_count]f32 = undefined;
var histogram_source: [value_count]u8 = undefined;
var shards: [shard_count]simd.Stats = undefined;
var expected_stats = simd.Stats{};
var expected_histogram = Histogram{};

pub fn prepare(_: std.mem.Allocator) void {
    expected_stats.reset();
    expected_histogram.reset();
    for (&shards) |*shard| shard.reset();
    for (&source, &histogram_source, 0..) |*value, *bin_index, index| {
        value.* = @floatFromInt(1 + ((index * 37) ^ (index >> 3)) % 10_000);
        bin_index.* = @intCast(((index * 29) ^ (index >> 2)) % histogram_capacity);
        expected_stats.notify(value.*);
        expected_histogram.notify(bin_index.*);
        shards[index / shard_size].notify(value.*);
    }
}

pub fn onlineMoments(_: std.mem.Allocator) void {
    var observed = simd.Stats{};
    {
        const phase = bench.phaseAt("simd.stats.online", @src());
        defer phase.end();
        for (source) |value| observed.notify(value);
    }
    verifyStats(&observed);
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.stats.online.complete");
}

pub fn assimilatedMoments(_: std.mem.Allocator) void {
    var observed = simd.Stats{};
    {
        const phase = bench.phaseAt("simd.stats.assimilate", @src());
        defer phase.end();
        for (&shards) |*shard| observed.assimilate(shard);
    }
    verifyStats(&observed);
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.stats.assimilate.complete");
}

pub fn histogram(_: std.mem.Allocator) void {
    var observed = Histogram{};
    {
        const phase = bench.phaseAt("simd.stats.bins", @src());
        defer phase.end();
        for (histogram_source) |bin_index| observed.notify(bin_index);
    }
    if (observed.modalBinIndex() != expected_histogram.modalBinIndex() or
        observed.numNonzero() != expected_histogram.numNonzero())
    {
        @panic("statistics histogram witness failed");
    }
    for (0..histogram_capacity) |bin_index| {
        if (observed.bin(bin_index) != expected_histogram.bin(bin_index)) {
            @panic("statistics histogram witness failed");
        }
    }
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.stats.bins.complete");
}

fn verifyStats(observed: *const simd.Stats) void {
    if (observed.count() != expected_stats.count() or
        observed.min() != expected_stats.min() or
        observed.max() != expected_stats.max() or
        @abs(observed.mean() - expected_stats.mean()) > 1e-9 or
        @abs(observed.variance() - expected_stats.variance()) > 1e-5)
    {
        @panic("online statistics witness failed");
    }
}
