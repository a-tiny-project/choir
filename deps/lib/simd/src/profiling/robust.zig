const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const value_count: usize = 1024;
const T = u64;
const Entry = simd.CountingSortEntry(T);

var source: [value_count]T = undefined;
var working: [value_count]T = undefined;
var counting_scratch: [value_count]Entry = undefined;
var deviation_scratch: [value_count]T = undefined;
var expected_mode: T = 0;
var expected_median: T = 0;
var expected_mad: T = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (&source, 0..) |*value, index| {
        value.* = ((index * 37) ^ (index >> 3)) % 8;
    }
    working = source;
    std.mem.sort(T, &working, {}, std.sort.asc(T));
    expected_mode = simd.modeOfSorted(T, &working);
    expected_median = simd.median(T, &working);
    expected_mad = simd.medianAbsoluteDeviation(
        T,
        &source,
        expected_median,
        &deviation_scratch,
    ) catch unreachable;
}

pub fn countingMode(_: std.mem.Allocator) void {
    working = source;
    const observed = blk: {
        const phase = bench.phaseAt("simd.robust.counting-mode", @src());
        defer phase.end();
        break :blk simd.mode(T, &working, &counting_scratch) catch unreachable;
    };
    if (observed != expected_mode) @panic("robust counting mode witness failed");
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.robust.counting-mode.complete");
}

pub fn comparisonMode(_: std.mem.Allocator) void {
    working = source;
    const observed = blk: {
        const phase = bench.phaseAt("simd.robust.comparison-mode", @src());
        defer phase.end();
        std.mem.sort(T, &working, {}, std.sort.asc(T));
        break :blk simd.modeOfSorted(T, &working);
    };
    if (observed != expected_mode) @panic("robust comparison mode witness failed");
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.robust.comparison-mode.complete");
}

pub fn medianAbsoluteDeviation(_: std.mem.Allocator) void {
    const observed = blk: {
        const phase = bench.phaseAt("simd.robust.mad", @src());
        defer phase.end();
        break :blk simd.medianAbsoluteDeviation(
            T,
            &source,
            expected_median,
            &deviation_scratch,
        ) catch unreachable;
    };
    if (observed != expected_mad) @panic("robust MAD witness failed");
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.robust.mad.complete");
}
