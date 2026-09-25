const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const DF = simd.FixedTag(f32, 8);
const DB = simd.BFloat16Tag(16);
const value_count: usize = 262_157;

var a: [value_count]f32 = undefined;
var b: [value_count]f32 = undefined;
var abf: [value_count]simd.BFloat16 = undefined;
var bbf: [value_count]simd.BFloat16 = undefined;
var expected_f32: f32 = 0;
var expected_bf: f32 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (&a, &b, &abf, &bbf, 0..) |*av, *bv, *abv, *bbv, index| {
        const ai = @as(i32, @intCast(index % 1021)) - 510;
        const bi = @as(i32, @intCast(index % 1013)) - 506;
        av.* = @as(f32, @floatFromInt(ai)) * (1.0 / 64.0);
        bv.* = @as(f32, @floatFromInt(bi)) * (1.0 / 64.0);
        abv.* = simd.BFloat16.fromF32(av.*);
        bbv.* = simd.BFloat16.fromF32(bv.*);
    }
    expected_f32 = simd.dotProduct(DF, &a, &b);
    expected_bf = simd.dotBFloat16(DB, &abf, &bbf);
}

pub fn floating(_: std.mem.Allocator) void {
    var actual: f32 = 0;
    {
        const phase = bench.phaseAt("simd.dot.f32x8", @src());
        defer phase.end();
        actual = simd.dotProduct(DF, &a, &b);
    }
    if (actual != expected_f32) @panic("SIMD f32 dot benchmark witness failed");
    std.mem.doNotOptimizeAway(actual);
    bench.coz.progressNamed("simd.dot.f32x8.complete");
}

pub fn bfloat(_: std.mem.Allocator) void {
    var actual: f32 = 0;
    {
        const phase = bench.phaseAt("simd.dot.bf16x16", @src());
        defer phase.end();
        actual = simd.dotBFloat16(DB, &abf, &bbf);
    }
    if (actual != expected_bf) @panic("SIMD bfloat dot benchmark witness failed");
    std.mem.doNotOptimizeAway(actual);
    bench.coz.progressNamed("simd.dot.bf16x16.complete");
}
