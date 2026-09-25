const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const I = simd.FixedTag(i16, 8);
const F = simd.FixedTag(f32, 8);
const A = simd.FixedTag(u8, 16);
const C = simd.FixedTag(u64, 4);
const B = simd.BFloat16Tag(8);

fn drawI16(data: *hypothesis.ConjectureData) !I.Vector {
    var result: I.Vector = undefined;
    inline for (0..I.lane_count) |index| {
        const bits: u16 = @intCast(try data.drawInteger(0, std.math.maxInt(u16), 0));
        result[index] = @bitCast(bits);
    }
    return result;
}

fn drawFiniteF32(data: *hypothesis.ConjectureData) !F.Vector {
    var result: F.Vector = undefined;
    inline for (0..F.lane_count) |index| {
        const drawn: i64 = @intCast(try data.drawInteger(0, 2_000_000, 1_000_000));
        const numerator: i32 = @intCast(drawn - 1_000_000);
        result[index] = @as(f32, @floatFromInt(numerator)) * 0.03125;
    }
    return result;
}

fn drawBytes(data: *hypothesis.ConjectureData) !A.Vector {
    var result: A.Vector = undefined;
    inline for (0..A.lane_count) |index| {
        result[index] = @intCast(try data.drawInteger(0, 255, 0));
    }
    return result;
}

fn drawU64(data: *hypothesis.ConjectureData) !C.Vector {
    var result: C.Vector = undefined;
    inline for (0..C.lane_count) |index| {
        result[index] = try data.drawInteger(0, std.math.maxInt(u64), 0);
    }
    return result;
}

pub const SaturatingProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const a = try drawI16(data);
        const b = try drawI16(data);
        const sum = simd.saturatedAdd(I, a, b);
        const difference = simd.saturatedSub(I, a, b);
        try std.testing.expect(@reduce(.And, sum == simd.saturatedAdd(I, b, a)));
        try std.testing.expect(@reduce(.And, simd.absDiff(I, a, b) == simd.absDiff(I, b, a)));
        inline for (0..I.lane_count) |index| {
            const expected_sum: i16 = @intCast(std.math.clamp(
                @as(i32, a[index]) + @as(i32, b[index]),
                std.math.minInt(i16),
                std.math.maxInt(i16),
            ));
            const expected_difference: i16 = @intCast(std.math.clamp(
                @as(i32, a[index]) - @as(i32, b[index]),
                std.math.minInt(i16),
                std.math.maxInt(i16),
            ));
            try std.testing.expectEqual(expected_sum, sum[index]);
            try std.testing.expectEqual(expected_difference, difference[index]);
        }
    }
};

pub const FloatingProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawFiniteF32(data);
        const rounded = simd.round(F, value);
        try std.testing.expect(@reduce(.And, simd.round(F, rounded) == rounded));
        try std.testing.expect(@reduce(.And, simd.trunc(F, simd.trunc(F, value)) == simd.trunc(F, value)));
        try std.testing.expect(@reduce(.And, simd.complexConj(F, simd.complexConj(F, value)) == value));
    }
};

pub const CryptoProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const state = try drawBytes(data);
        const zero: A.Vector = @splat(0);
        try std.testing.expect(@reduce(.And, simd.aesLastRoundInv(
            A,
            simd.aesLastRound(A, state, zero),
            zero,
        ) == state));
        const a = try drawU64(data);
        const b = try drawU64(data);
        const c = try drawU64(data);
        try std.testing.expect(@reduce(.And, simd.clMulLower(C, a, b ^ c) ==
            (simd.clMulLower(C, a, b) ^ simd.clMulLower(C, a, c))));
        try std.testing.expect(@reduce(.And, simd.clMulUpper(C, a, b ^ c) ==
            (simd.clMulUpper(C, a, b) ^ simd.clMulUpper(C, a, c))));
    }
};

pub const BFloatProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var bits: B.Vector = undefined;
        inline for (0..B.lane_count) |index| {
            const sign: u16 = @intCast((try data.drawInteger(0, 1, 0)) << 15);
            const finite: u16 = @intCast(try data.drawInteger(0, 0x7f7f, 0));
            bits[index] = sign | finite;
        }
        const promoted = simd.promoteTo(F, bits);
        try std.testing.expect(@reduce(.And, simd.demoteTo(B, promoted) == bits));
        try std.testing.expect(@reduce(.And, simd.demoteTo(B, simd.promoteTo(F, simd.demoteTo(B, promoted))) == bits));
    }
};

test "property: saturating arithmetic matches widened scalar bounds" {
    try hypothesis.checkNamed(SaturatingProperty, "simd-saturating-scalar-model", run.settings());
}

test "property: rounding and complex conjugation are idempotent or involutive" {
    try hypothesis.checkNamed(FloatingProperty, "simd-floating-idempotence", run.settings());
}

test "property: AES last rounds invert and CLMUL distributes over xor" {
    try hypothesis.checkNamed(CryptoProperty, "simd-crypto-algebra", run.settings());
}

test "property: finite bfloat16 values survive f32 round trips" {
    try hypothesis.checkNamed(BFloatProperty, "simd-bfloat16-roundtrip", run.settings());
}
