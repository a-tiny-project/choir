const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const DI = simd.FixedTag(i32, 4);
const II = simd.FixedTag(i8, 16);
const DF = simd.FixedTag(f32, 4);
const BF = simd.BFloat16Tag(8);
const sample_count: usize = 16_384;

var int_a: [sample_count]II.Vector = undefined;
var int_b: [sample_count]II.Vector = undefined;
var int_c: [sample_count]DI.Vector = undefined;
var bf_a: [sample_count]BF.Vector = undefined;
var bf_b: [sample_count]BF.Vector = undefined;
var bf_c: [sample_count]DF.Vector = undefined;
var expected_int: u64 = 0;
var expected_bfloat: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (&int_a, &int_b, &int_c, 0..) |*a, *b, *c, sample| {
        inline for (0..II.lane_count) |lane| {
            const av = @as(i32, @intCast((sample + lane) % 25)) - 12;
            const bv = @as(i32, @intCast((sample * 3 + lane) % 19)) - 9;
            a.*[lane] = @intCast(av);
            b.*[lane] = @intCast(bv);
        }
        inline for (0..DI.lane_count) |lane| c.*[lane] = @intCast((sample + lane) % 1021);
    }
    for (&bf_a, &bf_b, &bf_c, 0..) |*a, *b, *c, sample| {
        inline for (0..BF.lane_count) |lane| {
            const av = @as(i32, @intCast((sample + lane) % 17)) - 8;
            const bv = @as(i32, @intCast((sample * 5 + lane) % 13)) - 6;
            a.*[lane] = simd.BFloat16.fromF32(@as(f32, @floatFromInt(av)) * 0.25).bits;
            b.*[lane] = simd.BFloat16.fromF32(@as(f32, @floatFromInt(bv)) * 0.125).bits;
        }
        inline for (0..DF.lane_count) |lane| {
            const value = @as(i32, @intCast((sample + lane) % 23)) - 11;
            c.*[lane] = @as(f32, @floatFromInt(value)) * 0.5;
        }
    }
    expected_int = integerWorkload();
    expected_bfloat = bfloatWorkload();
}

pub fn integer(_: std.mem.Allocator) void {
    var witness: u64 = 0;
    {
        const phase = bench.phaseAt("simd.matmul.int8-i32", @src());
        defer phase.end();
        witness = integerWorkload();
    }
    if (witness != expected_int) @panic("SIMD int8 matmul benchmark witness failed");
    std.mem.doNotOptimizeAway(witness);
    bench.coz.progressNamed("simd.matmul.int8-i32.complete");
}

pub fn bfloat(_: std.mem.Allocator) void {
    var witness: u64 = 0;
    {
        const phase = bench.phaseAt("simd.matmul.bfloat-f32", @src());
        defer phase.end();
        witness = bfloatWorkload();
    }
    if (witness != expected_bfloat) @panic("SIMD bfloat matmul benchmark witness failed");
    std.mem.doNotOptimizeAway(witness);
    bench.coz.progressNamed("simd.matmul.bfloat-f32.complete");
}

fn integerWorkload() u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (int_a, int_b, int_c) |a, b, c| {
        const result = simd.perBlock2x2MatMul(DI, a, b, c);
        inline for (0..DI.lane_count) |lane| {
            hash = (hash ^ @as(u32, @bitCast(result[lane]))) *% 0x0000_0100_0000_01b3;
        }
    }
    return hash;
}

fn bfloatWorkload() u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (bf_a, bf_b, bf_c) |a, b, c| {
        const result = simd.perBlock2x2MatMul(DF, a, b, c);
        inline for (0..DF.lane_count) |lane| {
            hash = (hash ^ @as(u32, @bitCast(result[lane]))) *% 0x0000_0100_0000_01b3;
        }
    }
    return hash;
}
