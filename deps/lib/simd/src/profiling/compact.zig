const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D = simd.FixedTag(u32, 8);
const element_count: usize = 262_144 + 13;

var input: [element_count]u32 = undefined;
var masks: [element_count]bool = undefined;
var output: [element_count]u32 = undefined;
var expected_checksum: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (0..element_count) |index| {
        input[index] = @truncate(index *% 0x9e37_79b1 +% 0x85eb_ca6b);
        masks[index] = ((index *% 17 +% index / 7) & 7) < 3;
        output[index] = 0;
    }
    scalarBody();
    expected_checksum = checksum();
    @memset(&output, 0);
}

pub fn scalarCompact(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.compact.scalar.u32", @src());
        defer phase.end();
        scalarBody();
    }
    witness("simd.compact.scalar.u32.complete");
}

pub fn vectorCompact(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.compact.vector.u32x8", @src());
        defer phase.end();
        var index: usize = 0;
        while (index + D.lane_count <= element_count) : (index += D.lane_count) {
            var mask: D.Mask = undefined;
            inline for (0..D.lane_count) |lane_index| mask[lane_index] = masks[index + lane_index];
            simd.store(D, simd.compress(D, simd.load(D, input[index..]), mask), output[index..]);
        }
        while (index < element_count) : (index += 1) output[index] = input[index];
    }
    witness("simd.compact.vector.u32x8.complete");
}

fn scalarBody() void {
    var index: usize = 0;
    while (index + D.lane_count <= element_count) : (index += D.lane_count) {
        var compacted: [D.lane_count]u32 = undefined;
        var position: usize = 0;
        for (0..D.lane_count) |lane_index| {
            if (masks[index + lane_index]) {
                compacted[position] = input[index + lane_index];
                position += 1;
            }
        }
        for (0..D.lane_count) |lane_index| {
            if (!masks[index + lane_index]) {
                compacted[position] = input[index + lane_index];
                position += 1;
            }
        }
        output[index..][0..D.lane_count].* = compacted;
    }
    while (index < element_count) : (index += 1) output[index] = input[index];
}

fn witness(comptime progress_name: []const u8) void {
    if (checksum() != expected_checksum) @panic("SIMD compaction benchmark witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed(progress_name);
}

fn checksum() u64 {
    var result: u64 = 0xcbf2_9ce4_8422_2325;
    for (output) |value| result = (result ^ value) *% 0x0000_0100_0000_01b3;
    return result;
}
