const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const D = simd.FixedTag(u64, 4);
const F = simd.FixedTag(f32, 8);
const U = simd.FixedTag(u32, 8);

fn drawU64(data: *hypothesis.ConjectureData) !D.Vector {
    var result: D.Vector = undefined;
    inline for (0..D.lane_count) |index| {
        result[index] = try data.drawInteger(0, std.math.maxInt(u64), 0);
    }
    return result;
}

fn drawAmounts(data: *hypothesis.ConjectureData) !D.Vector {
    var result: D.Vector = undefined;
    inline for (0..D.lane_count) |index| {
        result[index] = try data.drawInteger(0, 63, 0);
    }
    return result;
}

fn drawU32(data: *hypothesis.ConjectureData) !U.Vector {
    var result: U.Vector = undefined;
    inline for (0..U.lane_count) |index| {
        result[index] = @truncate(try data.drawInteger(0, std.math.maxInt(u32), 0));
    }
    return result;
}

pub const RotationProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawU64(data);
        const amounts = try drawAmounts(data);
        const rotated = simd.rol(D, value, amounts);
        try std.testing.expect(@reduce(.And, simd.ror(D, rotated, amounts) == value));
        const same: i32 = @intCast(try data.drawInteger(0, 63, 0));
        try std.testing.expect(@reduce(.And, simd.rotateRightSame(D, simd.rotateLeftSame(D, value, same), same) == value));
    }
};

pub const ShiftProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawU64(data);
        const amounts = try drawAmounts(data);
        const left = simd.shl(D, value, amounts);
        const right = simd.shr(D, value, amounts);
        const rounded = simd.roundingShr(D, value, amounts);
        inline for (0..D.lane_count) |index| {
            const amount: u6 = @intCast(amounts[index]);
            try std.testing.expectEqual(value[index] << amount, left[index]);
            try std.testing.expectEqual(value[index] >> amount, right[index]);
            const expected = if (amount == 0)
                value[index]
            else
                (value[index] >> amount) +
                    ((value[index] >> (amount - 1)) & 1);
            try std.testing.expectEqual(expected, rounded[index]);
        }
    }
};

pub const CountProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawU64(data);
        const amounts = try drawAmounts(data);
        const population = simd.populationCount(D, value);
        const complement = simd.populationCount(D, simd.bitNot(D, value));
        const rotated = simd.populationCount(D, simd.rol(D, value, amounts));
        const leading = simd.leadingZeroCount(D, value);
        const trailing = simd.trailingZeroCount(D, value);
        const highest = simd.highestSetBitIndex(D, value);
        inline for (0..D.lane_count) |index| {
            try std.testing.expectEqual(@as(u64, 64), population[index] + complement[index]);
            try std.testing.expectEqual(population[index], rotated[index]);
            if (value[index] == 0) {
                try std.testing.expectEqual(@as(u64, 64), leading[index]);
                try std.testing.expectEqual(@as(u64, 64), trailing[index]);
                try std.testing.expectEqual(std.math.maxInt(u64), highest[index]);
            } else {
                try std.testing.expectEqual(@as(u64, 63), leading[index] + highest[index]);
                try std.testing.expect(trailing[index] <= highest[index]);
            }
        }
    }
};

pub const CopySignProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const magnitude_bits = try drawU32(data);
        const sign_bits = try drawU32(data);
        const actual: U.Vector = @bitCast(simd.copySign(
            F,
            @as(F.Vector, @bitCast(magnitude_bits)),
            @as(F.Vector, @bitCast(sign_bits)),
        ));
        const expected = (magnitude_bits & @as(U.Vector, @splat(0x7fff_ffff))) |
            (sign_bits & @as(U.Vector, @splat(0x8000_0000)));
        try std.testing.expect(@reduce(.And, actual == expected));
    }
};

test "property: rotations are invertible modulo lane width" {
    try hypothesis.checkNamed(RotationProperty, "simd-rotation-inverse", run.settings());
}

test "property: variable and rounded shifts match scalar lanes" {
    try hypothesis.checkNamed(ShiftProperty, "simd-shift-scalar-model", run.settings());
}

test "property: bit counts partition and survive rotation" {
    try hypothesis.checkNamed(CountProperty, "simd-bit-count-laws", run.settings());
}

test "property: copy sign changes only the sign bit" {
    try hypothesis.checkNamed(CopySignProperty, "simd-copy-sign-bits", run.settings());
}
