const std = @import("std");
const parameters = @import("parameters.zig");

const weights = [_]u64{
    262144,
    393216,
    245760,
    81920,
    15360,
    1536,
    64,
};

const total: u64 = 1_000_000;
const ranges = buildRanges();
const offsets = buildOffsets();

pub fn paretoSlot(rnum1: u32, rnum2: u32) usize {
    const bucket: usize = if (rnum1 < ranges[0])
        0
    else if (rnum1 < ranges[1])
        1
    else if (rnum1 < ranges[2])
        2
    else if (rnum1 < ranges[3])
        3
    else if (rnum1 < ranges[4])
        4
    else if (rnum1 < ranges[5])
        5
    else
        6;
    const start = offsets[bucket];
    const end = offsets[bucket + 1];
    const range_size = end - start;
    if (range_size == 0) return start;
    return start + @as(usize, rnum2) % range_size;
}

pub fn blockSize(random: u64) usize {
    const class_bits = parameters.alloc_test_max_size_exp - 3;
    const class_mask = (@as(u64, 1) << class_bits) - 1;
    const class_base = (random & class_mask) + 1;
    const class_index = @ctz(class_base) + 2;
    const size_mask = (@as(u64, 1) << @intCast(class_index)) - 1;
    return @intCast(((random >> class_bits) & size_mask) + 1 + (@as(u64, 1) << @intCast(class_index)));
}

pub fn random32(state: *u64) u32 {
    const result = state.* *% 0xd989_bcac_c137_dcd5;
    state.* ^= state.* >> 11;
    state.* ^= state.* << 31;
    state.* ^= state.* >> 18;
    return @truncate(result >> 32);
}

pub fn random64(state: *u64) u64 {
    return (@as(u64, random32(state)) << 32) | random32(state);
}

fn buildRanges() [6]u32 {
    var result: [6]u32 = undefined;
    var cumulative: u64 = 0;
    for (&result, 0..) |*range, index| {
        cumulative += weights[index];
        range.* = @intCast((@as(u64, std.math.maxInt(u32)) * cumulative) / total);
    }
    return result;
}

fn buildOffsets() [8]usize {
    var result: [8]usize = undefined;
    result[0] = 0;
    result[7] = parameters.alloc_test_slot_count;
    var index: usize = 0;
    while (index < 6) : (index += 1) {
        result[index + 1] = result[index] + @as(usize, @intCast((@as(u64, parameters.alloc_test_slot_count) * weights[6 - index]) / total));
    }
    return result;
}
