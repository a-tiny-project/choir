const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const words_per_line = simd.cache.words_per_line;

pub const StreamProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var source: [words_per_line]u64 align(simd.alignment) = undefined;
        for (&source) |*value| value.* = try drawU64(data);
        const original = source;
        const sentinel = try drawU64(data);
        var blocks: [3][words_per_line]u64 align(simd.alignment) = @splat(@splat(sentinel));
        simd.streamCacheLine(&source, &blocks[1]);
        simd.flushStream();
        try std.testing.expectEqualSlices(u64, &original, &source);
        try std.testing.expectEqualSlices(u64, &original, &blocks[1]);
        try std.testing.expectEqualSlices(
            u64,
            &@as([words_per_line]u64, @splat(sentinel)),
            &blocks[0],
        );
        try std.testing.expectEqualSlices(
            u64,
            &@as([words_per_line]u64, @splat(sentinel)),
            &blocks[2],
        );
    }
};

fn drawU64(data: *hypothesis.ConjectureData) !u64 {
    const low: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
    const high: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
    return @as(u64, high) << 32 | low;
}

test "property: streamed cache lines match an exact bounded copy model" {
    try hypothesis.checkNamed(StreamProperty, "simd-cache-stream-copy", run.settings());
}
