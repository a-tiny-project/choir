const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const line_count: usize = 4096;
const words_per_line = simd.cache.words_per_line;

var source: [line_count][words_per_line]u64 align(simd.alignment) = undefined;
var destination: [line_count][words_per_line]u64 align(simd.alignment) = undefined;
var expected_digest: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    expected_digest = 0;
    for (&source, &destination, 0..) |*source_line, *destination_line, line_index| {
        destination_line.* = @splat(0);
        for (source_line, 0..) |*value, word_index| {
            value.* = @as(u64, @intCast(line_index)) *% 0x9e37_79b9_7f4a_7c15 +%
                @as(u64, @intCast(word_index));
            expected_digest +%= value.*;
        }
    }
}

pub fn streamLines(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.cache.stream-lines", @src());
        defer phase.end();
        for (&source, &destination) |*source_line, *destination_line| {
            simd.streamCacheLine(source_line, destination_line);
        }
        simd.flushStream();
    }
    if (digest(&destination) != expected_digest) @panic("cache stream witness failed");
    std.mem.doNotOptimizeAway(&destination);
    bench.coz.progressNamed("simd.cache.stream-lines.complete");
}

pub fn controlCycle(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.cache.control-cycle", @src());
        defer phase.end();
        for (&source) |*line| {
            simd.loadFence();
            simd.prefetch(line);
            simd.flushCacheline(line);
            simd.pause();
            simd.flushStream();
        }
    }
    if (digest(&source) != expected_digest) @panic("cache control witness failed");
    std.mem.doNotOptimizeAway(&source);
    bench.coz.progressNamed("simd.cache.control-cycle.complete");
}

fn digest(lines: *const [line_count][words_per_line]u64) u64 {
    var value: u64 = 0;
    for (lines) |line| {
        for (line) |word| value +%= word;
    }
    return value;
}
