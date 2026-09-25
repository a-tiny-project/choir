const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;

fn next(state: *u64) u64 {
    state.* +%= 0x9E37_79B9_7F4A_7C15;
    var value = state.*;
    value = (value ^ (value >> 30)) *% 0xBF58_476D_1CE4_E5B9;
    value = (value ^ (value >> 27)) *% 0x94D0_49BB_1331_11EB;
    return value ^ (value >> 31);
}

fn widthMask(comptime T: type, comptime bits: usize) T {
    return if (bits == @bitSizeOf(T))
        std.math.maxInt(T)
    else
        (@as(T, 1) << @intCast(bits)) - 1;
}

fn checkRoundTrip(
    comptime T: type,
    comptime bits: usize,
    comptime frame_mode: bool,
    seed: u64,
) !void {
    const D = simd.FixedTag(T, 4);
    const raw_count = @bitSizeOf(T) * D.lane_count;
    const packed_count = bits * D.lane_count;
    const mask = widthMask(T, bits);
    const frame: T = @truncate(0x1020_3040_5060_7080);
    var state = seed;
    var raw: [raw_count]T = undefined;
    var restored: [raw_count]T = undefined;
    var packed_values: [packed_count]T = undefined;
    var repacked: [packed_count]T = undefined;
    for (&raw) |*value| {
        const delta = @as(T, @truncate(next(&state))) & mask;
        value.* = if (frame_mode) frame +% delta else delta;
    }
    if (frame_mode) {
        simd.packBitsFrame(D, bits, &raw, &packed_values, frame);
        simd.unpackBitsFrame(D, bits, &packed_values, &restored, frame);
        simd.packBitsFrame(D, bits, &restored, &repacked, frame);
    } else {
        simd.packBits(D, bits, &raw, &packed_values);
        simd.unpackBits(D, bits, &packed_values, &restored);
        simd.packBits(D, bits, &restored, &repacked);
    }
    try std.testing.expectEqualSlices(T, &raw, &restored);
    try std.testing.expectEqualSlices(T, &packed_values, &repacked);
}

fn checkLaneIsolation(comptime T: type, comptime bits: usize, seed: u64) !void {
    const D = simd.FixedTag(T, 4);
    const raw_count = @bitSizeOf(T) * D.lane_count;
    const packed_count = bits * D.lane_count;
    const mask = widthMask(T, bits);
    var state = seed;
    var raw: [raw_count]T = undefined;
    var before: [packed_count]T = undefined;
    var after: [packed_count]T = undefined;
    for (&raw) |*value| value.* = @as(T, @truncate(next(&state))) & mask;
    simd.packBits(D, bits, &raw, &before);
    inline for (0..@bitSizeOf(T)) |position| raw[position * D.lane_count] ^= 1;
    simd.packBits(D, bits, &raw, &after);
    var changed = false;
    inline for (0..bits) |position| {
        changed = changed or before[position * D.lane_count] != after[position * D.lane_count];
        inline for (1..D.lane_count) |lane| {
            try std.testing.expectEqual(
                before[position * D.lane_count + lane],
                after[position * D.lane_count + lane],
            );
        }
    }
    try std.testing.expect(changed);
}

pub const RoundTripProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        try checkRoundTrip(u8, 3, false, seed);
        try checkRoundTrip(u8, 5, false, seed);
        try checkRoundTrip(u16, 6, false, seed);
        try checkRoundTrip(u16, 13, false, seed);
        try checkRoundTrip(u32, 11, false, seed);
        try checkRoundTrip(u32, 31, true, seed);
        try checkRoundTrip(u64, 33, false, seed);
        try checkRoundTrip(u64, 61, true, seed);
    }
};

pub const LaneIsolationProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        try checkLaneIsolation(u8, 3, seed);
        try checkLaneIsolation(u16, 11, seed);
        try checkLaneIsolation(u32, 11, seed);
        try checkLaneIsolation(u64, 33, seed);
    }
};

test "property: bit packing round trips and re-packs canonically" {
    try hypothesis.checkNamed(RoundTripProperty, "simd-bitpack-roundtrip", run.settings());
}

test "property: packed lanes remain independent" {
    try hypothesis.checkNamed(LaneIsolationProperty, "simd-bitpack-lane-isolation", run.settings());
}
