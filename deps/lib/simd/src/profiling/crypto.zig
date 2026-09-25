const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D = simd.FixedTag(u8, 16);
const block_count: usize = 65_536 + 3;

var input: [block_count * D.lane_count]u8 = undefined;
var output: [block_count * D.lane_count]u8 = undefined;
var round_key: D.Vector = undefined;
var expected_checksum: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    inline for (0..D.lane_count) |index| round_key[index] = @truncate(index * 17 + 3);
    for (0..input.len) |index| {
        input[index] = @truncate(index *% 29 +% 11);
        output[index] = 0;
    }
    expected_checksum = checksumSeed();
    var index: usize = 0;
    while (index < input.len) : (index += D.lane_count) {
        var state = simd.load(D, input[index..]);
        inline for (0..4) |_| state = simd.aesRound(D, state, round_key);
        const lanes: [D.lane_count]u8 = state;
        for (lanes) |lane_value| expected_checksum = checksumStep(expected_checksum, lane_value);
    }
}

pub fn vectorAesRounds(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.crypto.aes.rounds", @src());
        defer phase.end();
        var index: usize = 0;
        while (index < input.len) : (index += D.lane_count) {
            var state = simd.load(D, input[index..]);
            inline for (0..4) |_| state = simd.aesRound(D, state, round_key);
            simd.store(D, state, output[index..]);
        }
    }
    witness("simd.crypto.aes.rounds.complete");
}

fn witness(comptime progress_name: []const u8) void {
    var checksum = checksumSeed();
    for (output) |value| checksum = checksumStep(checksum, value);
    if (checksum != expected_checksum) @panic("SIMD crypto benchmark witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed(progress_name);
}

fn checksumSeed() u64 {
    return 0xcbf2_9ce4_8422_2325;
}

fn checksumStep(checksum: u64, value: u8) u64 {
    return (checksum ^ value) *% 0x0000_0100_0000_01b3;
}
