const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const DF = simd.FixedTag(f32, 8);
const DI = simd.FixedTag(i16, 16);
const DB = simd.BFloat16Tag(16);
const max_values: usize = 257;
const padded_values: usize = 272;

fn close(expected: f32, actual: f32, scale: f32) bool {
    const tolerance = scale * @max(@abs(expected), 1);
    return @abs(expected - actual) <= tolerance;
}

fn drawLength(data: *hypothesis.ConjectureData) !usize {
    return @intCast(try data.drawInteger(0, max_values, 0));
}

fn drawFloat(data: *hypothesis.ConjectureData) !f32 {
    const drawn: i32 = @intCast(try data.drawInteger(0, 1024, 512));
    return @as(f32, @floatFromInt(drawn - 512)) * (1.0 / 64.0);
}

fn expectDot(expected: f32, actual: f32) !void {
    try std.testing.expect(close(expected, actual, 96 * std.math.floatEps(f32)));
}

fn checkAssumptions(a: []const f32, b: []const f32, length: usize, expected: f32) !void {
    try expectDot(expected, simd.dotProduct(DF, a[0..length], b[0..length]));
    try expectDot(expected, simd.dotProductAssume(
        DF,
        a,
        b,
        length,
        .{ .padded_to_vector = true },
    ));
    if (length >= DF.lane_count) {
        try expectDot(expected, simd.dotProductAssume(
            DF,
            a[0..length],
            b[0..length],
            length,
            .{ .at_least_one_vector = true },
        ));
        try expectDot(expected, simd.dotProductAssume(
            DF,
            a,
            b,
            length,
            .{ .at_least_one_vector = true, .padded_to_vector = true },
        ));
    }
    if (length % DF.lane_count == 0) {
        try expectDot(expected, simd.dotProductAssume(
            DF,
            a[0..length],
            b[0..length],
            length,
            .{ .multiple_of_vector = true },
        ));
        try expectDot(expected, simd.dotProductAssume(
            DF,
            a,
            b,
            length,
            .{ .multiple_of_vector = true, .padded_to_vector = true },
        ));
        if (length >= DF.lane_count) {
            try expectDot(expected, simd.dotProductAssume(
                DF,
                a[0..length],
                b[0..length],
                length,
                .{ .at_least_one_vector = true, .multiple_of_vector = true },
            ));
            try expectDot(expected, simd.dotProductAssume(
                DF,
                a,
                b,
                length,
                .{
                    .at_least_one_vector = true,
                    .multiple_of_vector = true,
                    .padded_to_vector = true,
                },
            ));
        }
    }
}

pub const FloatingProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const length = try drawLength(data);
        var a: [padded_values]f32 = @splat(std.math.nan(f32));
        var b: [padded_values]f32 = @splat(std.math.nan(f32));
        var expected: f32 = 0;
        for (a[0..length], b[0..length]) |*av, *bv| {
            av.* = try drawFloat(data);
            bv.* = try drawFloat(data);
            expected = @mulAdd(f32, av.*, bv.*, expected);
        }
        try checkAssumptions(&a, &b, length, expected);
    }
};

pub const IntegerProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const length = try drawLength(data);
        var a: [max_values]i16 = undefined;
        var b: [max_values]i16 = undefined;
        var expected: i32 = 0;
        for (a[0..length], b[0..length]) |*av, *bv| {
            const drawn_a: i32 = @intCast(try data.drawInteger(0, 2048, 1024));
            const drawn_b: i32 = @intCast(try data.drawInteger(0, 2048, 1024));
            av.* = @intCast(drawn_a - 1024);
            bv.* = @intCast(drawn_b - 1024);
            expected += @as(i32, av.*) * @as(i32, bv.*);
        }
        try std.testing.expectEqual(expected, simd.dotProduct(DI, a[0..length], b[0..length]));
    }
};

pub const BFloatProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const length = try drawLength(data);
        var a: [max_values]simd.BFloat16 = undefined;
        var b: [max_values]simd.BFloat16 = undefined;
        var mixed: [max_values]f32 = undefined;
        var expected_same: f32 = 0;
        var expected_mixed: f32 = 0;
        for (a[0..length], b[0..length], mixed[0..length]) |*av, *bv, *mv| {
            av.* = simd.BFloat16.fromF32(try drawFloat(data));
            bv.* = simd.BFloat16.fromF32(try drawFloat(data));
            mv.* = try drawFloat(data);
            expected_same = @mulAdd(f32, av.toF32(), bv.toF32(), expected_same);
            expected_mixed = @mulAdd(f32, mv.*, bv.toF32(), expected_mixed);
        }
        try expectDot(
            expected_same,
            simd.dotBFloat16(DB, a[0..length], b[0..length]),
        );
        try expectDot(
            expected_mixed,
            simd.dotF32BFloat16(DF, mixed[0..length], b[0..length]),
        );
    }
};

test "property: floating dot assumptions preserve scalar products across tails" {
    try hypothesis.checkNamed(FloatingProperty, "simd-dot-floating-assumptions", run.settings());
}

test "property: i16 dot equals the widened scalar product" {
    try hypothesis.checkNamed(IntegerProperty, "simd-dot-i16-model", run.settings());
}

test "property: bfloat dot forms equal widened scalar products" {
    try hypothesis.checkNamed(BFloatProperty, "simd-dot-bfloat-model", run.settings());
}
