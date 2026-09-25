const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D = simd.FixedTag(u32, 8);
const element_count: usize = 131_072 + 3;

var left: [element_count]u32 = undefined;
var right: [element_count]u32 = undefined;
var output: [element_count * 2]u32 = undefined;
var expected_checksum: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    expected_checksum = checksumSeed();
    for (0..element_count) |index| {
        left[index] = @truncate(index *% 0x9e37_79b9 +% 0x85eb_ca6b);
        right[index] = @truncate(index *% 0xc2b2_ae35 +% 0x27d4_eb2f);
        output[index * 2] = 0;
        output[index * 2 + 1] = 0;
        expected_checksum = checksumStep(expected_checksum, left[index]);
        expected_checksum = checksumStep(expected_checksum, right[index]);
    }
}

pub fn scalarInterleave(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.layout.scalar.u32", @src());
        defer phase.end();
        for (0..element_count) |index| {
            output[index * 2] = left[index];
            output[index * 2 + 1] = right[index];
        }
    }
    witness("simd.layout.scalar.u32.complete");
}

pub fn vectorInterleave(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.layout.vector.u32x8", @src());
        defer phase.end();
        var index: usize = 0;
        while (index + D.lane_count <= element_count) : (index += D.lane_count) {
            const a = simd.load(D, left[index..]);
            const b = simd.load(D, right[index..]);
            simd.store(D, simd.interleaveWholeLower(D, a, b), output[index * 2 ..]);
            simd.store(D, simd.interleaveWholeUpper(D, a, b), output[index * 2 + D.lane_count ..]);
        }
        while (index < element_count) : (index += 1) {
            output[index * 2] = left[index];
            output[index * 2 + 1] = right[index];
        }
    }
    witness("simd.layout.vector.u32x8.complete");
}

fn witness(comptime progress_name: []const u8) void {
    var checksum = checksumSeed();
    for (output) |value| checksum = checksumStep(checksum, value);
    if (checksum != expected_checksum) @panic("SIMD layout benchmark witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed(progress_name);
}

fn checksumSeed() u64 {
    return 0xcbf2_9ce4_8422_2325;
}

fn checksumStep(checksum: u64, value: u32) u64 {
    return (checksum ^ value) *% 0x0000_0100_0000_01b3;
}
