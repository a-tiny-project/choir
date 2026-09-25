const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D32 = simd.FixedTag(u32, 8);
const D64 = simd.FixedTag(u64, 4);
const D16 = simd.FixedTag(u16, 16);
const blocks: usize = 2_048;
const raw16_per_block = 16 * D16.lane_count;
const packed16_per_block = 13 * D16.lane_count;
const raw32_per_block = 32 * D32.lane_count;
const packed32_per_block = 11 * D32.lane_count;
const raw64_per_block = 64 * D64.lane_count;
const packed64_per_block = 33 * D64.lane_count;
const frame64: u64 = 0x1020_3040_5060_7080;

var raw32: [blocks * raw32_per_block]u32 = undefined;
var packed32: [blocks * packed32_per_block]u32 = undefined;
var restored32: [blocks * raw32_per_block]u32 = undefined;
var raw64: [blocks * raw64_per_block]u64 = undefined;
var packed64: [blocks * packed64_per_block]u64 = undefined;
var restored64: [blocks * raw64_per_block]u64 = undefined;
var raw16: [blocks * raw16_per_block]u16 = undefined;
var packed16: [blocks * packed16_per_block]u16 = undefined;
var restored16: [blocks * raw16_per_block]u16 = undefined;
var expected16: u64 = 0;
var expected32: u64 = 0;
var expected64: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (&raw16, 0..) |*value, index| {
        value.* = @as(u16, @truncate(index *% 40_503 +% 17_311)) & 0x1FFF;
    }
    for (&raw32, 0..) |*value, index| {
        value.* = @as(u32, @truncate(index *% 2_654_435_761 +% 1_013_904_223)) & 0x7FF;
    }
    for (&raw64, 0..) |*value, index| {
        const delta = (@as(u64, index) *% 0x9E37_79B9_7F4A_7C15) & 0x1_FFFF_FFFF;
        value.* = frame64 +% delta;
    }
    expected16 = checksum16(&raw16);
    expected32 = checksum32(&raw32);
    expected64 = checksum64(&raw64);
}

pub fn pack16RoundTrip(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.bitpack.u16x16.bits13", @src());
        defer phase.end();
        for (0..blocks) |block| {
            const raw_offset = block * raw16_per_block;
            const packed_offset = block * packed16_per_block;
            simd.packBits(D16, 13, raw16[raw_offset..], packed16[packed_offset..]);
            simd.unpackBits(D16, 13, packed16[packed_offset..], restored16[raw_offset..]);
        }
    }
    if (checksum16(&restored16) != expected16) @panic("SIMD Pack16 benchmark witness failed");
    std.mem.doNotOptimizeAway(&restored16);
    bench.coz.progressNamed("simd.bitpack.u16x16.bits13.complete");
}

pub fn pack32RoundTrip(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.bitpack.u32x8.bits11", @src());
        defer phase.end();
        for (0..blocks) |block| {
            const raw_offset = block * raw32_per_block;
            const packed_offset = block * packed32_per_block;
            simd.packBits(D32, 11, raw32[raw_offset..], packed32[packed_offset..]);
            simd.unpackBits(D32, 11, packed32[packed_offset..], restored32[raw_offset..]);
        }
    }
    if (checksum32(&restored32) != expected32) @panic("SIMD Pack32 benchmark witness failed");
    std.mem.doNotOptimizeAway(&restored32);
    bench.coz.progressNamed("simd.bitpack.u32x8.bits11.complete");
}

pub fn pack64FrameRoundTrip(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.bitpack.u64x4.frame.bits33", @src());
        defer phase.end();
        for (0..blocks) |block| {
            const raw_offset = block * raw64_per_block;
            const packed_offset = block * packed64_per_block;
            simd.packBitsFrame(D64, 33, raw64[raw_offset..], packed64[packed_offset..], frame64);
            simd.unpackBitsFrame(
                D64,
                33,
                packed64[packed_offset..],
                restored64[raw_offset..],
                frame64,
            );
        }
    }
    if (checksum64(&restored64) != expected64) @panic("SIMD Pack64 benchmark witness failed");
    std.mem.doNotOptimizeAway(&restored64);
    bench.coz.progressNamed("simd.bitpack.u64x4.frame.bits33.complete");
}

fn checksum32(values: []const u32) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| hash = (hash ^ value) *% 0x0000_0100_0000_01b3;
    return hash;
}

fn checksum16(values: []const u16) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| hash = (hash ^ value) *% 0x0000_0100_0000_01b3;
    return hash;
}

fn checksum64(values: []const u64) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| hash = (hash ^ value) *% 0x0000_0100_0000_01b3;
    return hash;
}
