const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D32 = simd.FixedTag(u32, 8);
const D64 = simd.FixedTag(u64, 4);
const value_count: usize = 262_157;
const key32: u32 = 0x5349_4d44;
const key64: u64 = 0x4841_5348_3634_2121;
const lemire_range: u32 = 1_000_003;

var input32: [value_count]u32 = undefined;
var output32: [value_count]u32 = undefined;
var input64: [value_count]u64 = undefined;
var output64: [value_count]u64 = undefined;
var expected32: u64 = 0;
var expected64: u64 = 0;
var expected_lemire: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (&input32, 0..) |*value, index| value.* = @truncate(index *% 0x9e37_79b9 +% 17);
    for (&input64, 0..) |*value, index| value.* = index *% 0x9e37_79b9_7f4a_7c15 +% 29;
    vector32Pipeline();
    expected32 = checksum(u32, &output32);
    vector64Pipeline();
    expected64 = checksum(u64, &output64);
    lemirePipeline();
    expected_lemire = checksum(u32, &output32);
}

pub fn scalar32(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.hash.triple32.scalar", @src());
        defer phase.end();
        scalar32Pipeline();
    }
    if (checksum(u32, &output32) != expected32) @panic("scalar Triple32 benchmark witness failed");
    std.mem.doNotOptimizeAway(&output32);
    bench.coz.progressNamed("simd.hash.triple32.scalar.complete");
}

pub fn lemire32(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.hash.lemire.scalar", @src());
        defer phase.end();
        lemirePipeline();
    }
    if (checksum(u32, &output32) != expected_lemire) @panic("Lemire reduction benchmark witness failed");
    std.mem.doNotOptimizeAway(&output32);
    bench.coz.progressNamed("simd.hash.lemire.scalar.complete");
}

pub fn vector32(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.hash.triple32.u32x8", @src());
        defer phase.end();
        vector32Pipeline();
    }
    if (checksum(u32, &output32) != expected32) @panic("vector Triple32 benchmark witness failed");
    std.mem.doNotOptimizeAway(&output32);
    bench.coz.progressNamed("simd.hash.triple32.u32x8.complete");
}

pub fn scalar64(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.hash.moremur.scalar", @src());
        defer phase.end();
        scalar64Pipeline();
    }
    if (checksum(u64, &output64) != expected64) @panic("scalar Moremur benchmark witness failed");
    std.mem.doNotOptimizeAway(&output64);
    bench.coz.progressNamed("simd.hash.moremur.scalar.complete");
}

pub fn vector64(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.hash.moremur.u64x4", @src());
        defer phase.end();
        vector64Pipeline();
    }
    if (checksum(u64, &output64) != expected64) @panic("vector Moremur benchmark witness failed");
    std.mem.doNotOptimizeAway(&output64);
    bench.coz.progressNamed("simd.hash.moremur.u64x4.complete");
}

fn scalar32Pipeline() void {
    const hash = simd.Triple32.initKey(key32);
    for (input32, &output32) |input, *output| output.* = hash.hash(input);
}

fn lemirePipeline() void {
    for (input32, &output32) |input, *output| output.* = simd.lemireMod(input, lemire_range);
}

fn vector32Pipeline() void {
    const hash = simd.Triple32.initKey(key32);
    simd.hashArray(D32, hash, &input32, &output32);
}

fn scalar64Pipeline() void {
    const hash = simd.Moremur.initKey(key64);
    for (input64, &output64) |input, *output| output.* = hash.hash(input);
}

fn vector64Pipeline() void {
    const hash = simd.Moremur.initKey(key64);
    simd.hashArray(D64, hash, &input64, &output64);
}

fn checksum(comptime T: type, values: []const T) u64 {
    var result: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| result = (result ^ @as(u64, value)) *% 0x0000_0100_0000_01b3;
    return result;
}
