const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const scalar_count: usize = 4096;
const vector_count: usize = 1024;
const D = simd.FixedTag(u32, 8);

var scalar_values: [scalar_count]f64 = undefined;
var vector_values: [vector_count][8]u32 = undefined;
var expected_scalar_digest: u64 = 0;
var expected_vector_digest: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (&scalar_values, 0..) |*value, index| {
        const bits = @as(u64, @intCast(index)) *% 0x9e37_79b9_7f4a_7c15 +%
            0x3f84_7ae1_47ae_147b;
        value.* = @bitCast(bits);
    }
    for (&vector_values, 0..) |*lanes, vector_index| {
        for (lanes, 0..) |*value, lane_index| {
            value.* = @truncate(
                @as(u64, @intCast(vector_index * lanes.len + lane_index)) *%
                    0x9e37_79b9 +% 0x1000_0001,
            );
        }
    }
    expected_scalar_digest = formatScalars();
    expected_vector_digest = formatVectors();
}

pub fn scalarValues(_: std.mem.Allocator) void {
    const phase = bench.phaseAt("simd.print.scalars", @src());
    const digest = formatScalars();
    phase.end();
    if (digest != expected_scalar_digest) @panic("scalar diagnostic benchmark witness failed");
    std.mem.doNotOptimizeAway(&digest);
    bench.coz.progressNamed("simd.print.scalars.complete");
}

pub fn vectorWindows(_: std.mem.Allocator) void {
    const phase = bench.phaseAt("simd.print.vectors", @src());
    const digest = formatVectors();
    phase.end();
    if (digest != expected_vector_digest) @panic("vector diagnostic benchmark witness failed");
    std.mem.doNotOptimizeAway(&digest);
    bench.coz.progressNamed("simd.print.vectors.complete");
}

fn formatScalars() u64 {
    var digest: u64 = 0xcbf2_9ce4_8422_2325;
    for (scalar_values) |value| {
        var buffer: [128]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        simd.writeLaneValue(&writer, value) catch @panic("scalar diagnostic buffer exhausted");
        digest = mix(digest, writer.buffered());
    }
    return digest;
}

fn formatVectors() u64 {
    var digest: u64 = 0xcbf2_9ce4_8422_2325;
    for (vector_values, 0..) |lanes, index| {
        const vector: D.Vector = lanes;
        var buffer: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        simd.writeVector(
            &writer,
            D,
            "profile",
            vector,
            .{ .lane = index % 10, .max_lanes = 7 },
        ) catch @panic("vector diagnostic buffer exhausted");
        digest = mix(digest, writer.buffered());
    }
    return digest;
}

fn mix(initial: u64, bytes: []const u8) u64 {
    var digest = initial;
    for (bytes) |byte| {
        digest ^= byte;
        digest *%= 0x0000_0100_0000_01b3;
    }
    return digest;
}
