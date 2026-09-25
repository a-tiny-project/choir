const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const DF = simd.FixedTag(f32, 8);
const DB = simd.BFloat16Tag(16);
const rows: usize = 257;
const columns: usize = 1_027;
const area: usize = rows * columns;

var matrix: [area]f32 = undefined;
var matrix_bf: [area]simd.BFloat16 = undefined;
var vector: [columns]f32 = undefined;
var vector_bf: [columns]simd.BFloat16 = undefined;
var output: [rows]f32 = undefined;
var expected_f32: u64 = 0;
var expected_mixed: u64 = 0;
var expected_bf: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (&matrix, &matrix_bf, 0..) |*value, *bf, index| {
        const integer = @as(i32, @intCast(index % 1021)) - 510;
        value.* = @as(f32, @floatFromInt(integer)) * (1.0 / 128.0);
        bf.* = simd.BFloat16.fromF32(value.*);
    }
    for (&vector, &vector_bf, 0..) |*value, *bf, index| {
        const integer = @as(i32, @intCast(index % 251)) - 125;
        value.* = @as(f32, @floatFromInt(integer)) * (1.0 / 64.0);
        bf.* = simd.BFloat16.fromF32(value.*);
    }
    simd.matVec(DF, &matrix, &vector, &output);
    expected_f32 = checksum(&output);
    simd.matVecBFloatF32(DF, &matrix_bf, &vector, &output);
    expected_mixed = checksum(&output);
    simd.matVecBFloat16(DB, &matrix_bf, &vector_bf, &output);
    expected_bf = checksum(&output);
}

pub fn floating(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.matvec.f32x8", @src());
        defer phase.end();
        simd.matVec(DF, &matrix, &vector, &output);
    }
    if (checksum(&output) != expected_f32) @panic("SIMD f32 matvec benchmark witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed("simd.matvec.f32x8.complete");
}

pub fn mixed(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.matvec.bf16-f32", @src());
        defer phase.end();
        simd.matVecBFloatF32(DF, &matrix_bf, &vector, &output);
    }
    if (checksum(&output) != expected_mixed) @panic("SIMD mixed matvec benchmark witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed("simd.matvec.bf16-f32.complete");
}

pub fn bfloat(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.matvec.bf16x16", @src());
        defer phase.end();
        simd.matVecBFloat16(DB, &matrix_bf, &vector_bf, &output);
    }
    if (checksum(&output) != expected_bf) @panic("SIMD bfloat matvec benchmark witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed("simd.matvec.bf16x16.complete");
}

fn checksum(values: []const f32) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| {
        hash = (hash ^ @as(u32, @bitCast(value))) *% 0x0000_0100_0000_01b3;
    }
    return hash;
}
