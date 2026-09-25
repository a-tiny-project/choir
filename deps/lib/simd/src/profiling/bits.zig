const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D = simd.FixedTag(u64, 4);
const element_count: usize = 131_072 + 5;

var input: [element_count]u64 = undefined;
var output: [element_count]u64 = undefined;
var expected_checksum: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    expected_checksum = checksumSeed();
    for (0..element_count) |index| {
        input[index] = index *% 0x9e37_79b9_7f4a_7c15 +% 0xd1b5_4a32_d192_ed03;
        output[index] = 0;
        expected_checksum = checksumStep(expected_checksum, mixScalar(input[index]));
    }
}

pub fn scalarMix(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.bits.scalar.u64", @src());
        defer phase.end();
        for (0..element_count) |index| output[index] = mixScalar(input[index]);
    }
    witness("simd.bits.scalar.u64.complete");
}

pub fn vectorMix(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.bits.vector.u64x4", @src());
        defer phase.end();
        var index: usize = 0;
        while (index + D.lane_count <= element_count) : (index += D.lane_count) {
            const value = simd.load(D, input[index..]);
            const mixed = simd.bitXor(
                D,
                simd.rotateLeft(D, 13, value),
                simd.populationCount(D, value),
            );
            simd.store(D, mixed, output[index..]);
        }
        while (index < element_count) : (index += 1) {
            output[index] = mixScalar(input[index]);
        }
    }
    witness("simd.bits.vector.u64x4.complete");
}

fn mixScalar(value: u64) u64 {
    return std.math.rotl(u64, value, 13) ^ @as(u64, @popCount(value));
}

fn witness(comptime progress_name: []const u8) void {
    var checksum = checksumSeed();
    for (output) |value| checksum = checksumStep(checksum, value);
    if (checksum != expected_checksum) @panic("SIMD bit benchmark witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed(progress_name);
}

fn checksumSeed() u64 {
    return 0xcbf2_9ce4_8422_2325;
}

fn checksumStep(checksum: u64, value: u64) u64 {
    return (checksum ^ value) *% 0x0000_0100_0000_01b3;
}
