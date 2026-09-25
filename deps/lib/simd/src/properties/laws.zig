const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const D = simd.FixedTag(u32, 8);

fn drawVector(data: *hypothesis.ConjectureData) !D.Vector {
    var result: D.Vector = undefined;
    inline for (0..D.lane_count) |index| {
        result[index] = @truncate(try data.drawInteger(0, std.math.maxInt(u32), 0));
    }
    return result;
}

fn drawMask(data: *hypothesis.ConjectureData) !D.Mask {
    var result: D.Mask = @splat(false);
    inline for (0..D.lane_count) |index| {
        result[index] = try data.drawBoolean();
    }
    return result;
}

fn expectVectorEqual(expected: D.Vector, actual: D.Vector) !void {
    try std.testing.expect(@reduce(.And, expected == actual));
}

pub const ArithmeticRingProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const a = try drawVector(data);
        const b = try drawVector(data);
        const c = try drawVector(data);
        const zero: D.Vector = @splat(0);

        try expectVectorEqual(a, simd.sub(D, simd.add(D, a, b), b));
        try expectVectorEqual(
            simd.add(D, simd.add(D, a, b), c),
            simd.add(D, a, simd.add(D, b, c)),
        );
        try expectVectorEqual(zero, simd.sub(D, a, a));
        try std.testing.expectEqual(
            simd.reduceSum(D, simd.add(D, a, b)),
            simd.reduceSum(D, a) +% simd.reduceSum(D, b),
        );
    }
};

pub const LogicalMaskProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawVector(data);
        const other = try drawVector(data);
        const mask = try drawMask(data);
        const zero: D.Vector = @splat(0);

        try expectVectorEqual(zero, simd.bitXor(D, value, value));
        try std.testing.expect(simd.allBitsZero(
            D,
            simd.bitAnd(D, value, simd.bitNot(D, value)),
        ));
        try std.testing.expect(simd.allBitsOne(
            D,
            simd.bitOr(D, value, simd.bitNot(D, value)),
        ));

        const selected = simd.select(D, mask, value, other);
        inline for (0..D.lane_count) |index| {
            try std.testing.expectEqual(
                if (mask[index]) value[index] else other[index],
                selected[index],
            );
        }
    }
};

pub const PartialMemoryProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var input: [D.lane_count]u32 = undefined;
        for (&input) |*value| {
            value.* = @truncate(try data.drawInteger(0, std.math.maxInt(u32), 0));
        }
        const count: usize = @intCast(try data.drawInteger(0, D.lane_count, 0));
        const loaded = simd.loadN(D, input[0..count], count);
        var output: [D.lane_count]u32 = @splat(0xa5a5_a5a5);
        simd.storeN(D, loaded, &output, count);

        inline for (0..D.lane_count) |index| {
            if (index < count) {
                try std.testing.expectEqual(input[index], loaded[index]);
                try std.testing.expectEqual(input[index], output[index]);
            } else {
                try std.testing.expectEqual(@as(u32, 0), loaded[index]);
                try std.testing.expectEqual(@as(u32, 0xa5a5_a5a5), output[index]);
            }
        }
    }
};

test "property: wrapping arithmetic forms a lane-wise modular ring" {
    try hypothesis.checkNamed(ArithmeticRingProperty, "simd-arithmetic-ring", run.settings());
}

test "property: logical complements and mask selection retain every lane" {
    try hypothesis.checkNamed(LogicalMaskProperty, "simd-logical-mask", run.settings());
}

test "property: partial memory operations preserve exact tail boundaries" {
    try hypothesis.checkNamed(PartialMemoryProperty, "simd-partial-memory", run.settings());
}
