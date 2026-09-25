const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const F = simd.FixedTag(f32, 8);
const I = simd.FixedTag(i32, 8);
const element_count: usize = 262_144 + 13;

var input: [element_count]f32 = undefined;
var output: [element_count]i32 = undefined;
var expected_checksum: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    expected_checksum = checksumSeed();
    for (0..element_count) |index| {
        const centered: i32 = @as(i32, @intCast(index % 2_000_001)) - 1_000_000;
        input[index] = @floatFromInt(centered);
        switch (index & 1023) {
            0 => input[index] = std.math.inf(f32),
            1 => input[index] = -std.math.inf(f32),
            2 => input[index] = @bitCast(@as(u32, 0x7fc0_1234)),
            3 => input[index] = @bitCast(@as(u32, 0xffc0_1234)),
            4 => input[index] = 0x1p31,
            5 => input[index] = -0x1p31,
            else => {},
        }
        output[index] = 0;
        expected_checksum = checksumStep(expected_checksum, scalarLane(input[index]));
    }
}

pub fn scalarConvert(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.convert.scalar.f32.i32", @src());
        defer phase.end();
        for (input, 0..) |value, index| output[index] = scalarLane(value);
    }
    witness("simd.convert.scalar.f32.i32.complete");
}

pub fn vectorConvert(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.convert.vector.f32x8.i32x8", @src());
        defer phase.end();
        var index: usize = 0;
        while (index + F.lane_count <= element_count) : (index += F.lane_count) {
            simd.store(I, simd.convertTo(I, simd.load(F, input[index..])), output[index..]);
        }
        while (index < element_count) : (index += 1) output[index] = scalarLane(input[index]);
    }
    witness("simd.convert.vector.f32x8.i32x8.complete");
}

fn scalarLane(value: f32) i32 {
    const bits: u32 = @bitCast(value);
    if (std.math.isNan(value)) {
        return if (bits & 0x8000_0000 != 0) std.math.minInt(i32) else std.math.maxInt(i32);
    }
    if (value >= 0x1p31) return std.math.maxInt(i32);
    if (value <= -0x1p31) return std.math.minInt(i32);
    return @intFromFloat(value);
}

fn witness(comptime progress_name: []const u8) void {
    var checksum = checksumSeed();
    for (output) |value| checksum = checksumStep(checksum, value);
    if (checksum != expected_checksum) @panic("SIMD conversion benchmark witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed(progress_name);
}

fn checksumSeed() u64 {
    return 0xcbf2_9ce4_8422_2325;
}

fn checksumStep(checksum: u64, value: i32) u64 {
    return (checksum ^ @as(u32, @bitCast(value))) *% 0x0000_0100_0000_01b3;
}
