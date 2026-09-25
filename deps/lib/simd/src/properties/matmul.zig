const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const DI = simd.FixedTag(i32, 8);
const II = simd.FixedTag(i8, 32);
const DF = simd.FixedTag(f32, 8);
const BF = simd.BFloat16Tag(16);

pub const Int8ModelProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var a: II.Vector = undefined;
        var b: II.Vector = undefined;
        var c: DI.Vector = undefined;
        inline for (0..II.lane_count) |index| {
            a[index] = @bitCast(@as(u8, @intCast(try data.drawInteger(0, 255, 128))));
            b[index] = @bitCast(@as(u8, @intCast(try data.drawInteger(0, 255, 128))));
        }
        inline for (0..DI.lane_count) |index| {
            c[index] = @bitCast(@as(u32, @intCast(
                try data.drawInteger(0, std.math.maxInt(u32), 0),
            )));
        }
        const actual = simd.perBlock2x2MatMul(DI, a, b, c);
        const input_a: [II.lane_count]i8 = @bitCast(a);
        const input_b: [II.lane_count]i8 = @bitCast(b);
        var expected: [DI.lane_count]i32 = @bitCast(c);
        for (0..DI.lane_count / 4) |block| {
            for (0..2) |row| {
                for (0..2) |column| {
                    var sum: i32 = 0;
                    for (0..8) |inner| {
                        sum += @as(i32, input_a[block * 16 + row * 8 + inner]) *
                            @as(i32, input_b[block * 16 + column * 8 + inner]);
                    }
                    const output = block * 4 + row * 2 + column;
                    expected[output] = expected[output] +% sum;
                }
            }
        }
        try std.testing.expect(@reduce(.And, actual == @as(DI.Vector, @bitCast(expected))));
    }
};

pub const BFloatModelProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var a: BF.Vector = undefined;
        var b: BF.Vector = undefined;
        var c: DF.Vector = undefined;
        inline for (0..BF.lane_count) |index| {
            const av = @as(i32, @intCast(try data.drawInteger(0, 64, 32))) - 32;
            const bv = @as(i32, @intCast(try data.drawInteger(0, 64, 32))) - 32;
            a[index] = simd.BFloat16.fromF32(@as(f32, @floatFromInt(av)) * 0.125).bits;
            b[index] = simd.BFloat16.fromF32(@as(f32, @floatFromInt(bv)) * 0.125).bits;
        }
        inline for (0..DF.lane_count) |index| {
            const value = @as(i32, @intCast(try data.drawInteger(0, 64, 32))) - 32;
            c[index] = @as(f32, @floatFromInt(value)) * 0.25;
        }
        const actual = simd.perBlock2x2MatMul(DF, a, b, c);
        const input_a: [BF.lane_count]u16 = @bitCast(a);
        const input_b: [BF.lane_count]u16 = @bitCast(b);
        var expected: [DF.lane_count]f32 = @bitCast(c);
        for (0..DF.lane_count / 4) |block| {
            for (0..2) |row| {
                for (0..2) |column| {
                    var sum: f32 = 0;
                    for (0..4) |inner| {
                        sum += simd.BFloat16.fromBits(
                            input_a[block * 8 + row * 4 + inner],
                        ).toF32() * simd.BFloat16.fromBits(
                            input_b[block * 8 + column * 4 + inner],
                        ).toF32();
                    }
                    expected[block * 4 + row * 2 + column] += sum;
                }
            }
        }
        try std.testing.expect(@reduce(.And, actual == @as(DF.Vector, @bitCast(expected))));
    }
};

test "property: int8 per-block 2x2 matmul equals wrapping scalar blocks" {
    try hypothesis.checkNamed(Int8ModelProperty, "simd-matmul-int8-block-model", run.settings());
}

test "property: bfloat per-block 2x2 matmul equals widened scalar blocks" {
    try hypothesis.checkNamed(BFloatModelProperty, "simd-matmul-bfloat-block-model", run.settings());
}
