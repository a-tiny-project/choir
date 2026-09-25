const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const U32 = simd.FixedTag(u32, 8);
const I32 = simd.FixedTag(i32, 8);
const F32 = simd.FixedTag(f32, 8);
const U16 = simd.FixedTag(u16, 8);
const I16 = simd.FixedTag(i16, 8);
const F16 = simd.FixedTag(f16, 8);
const U8 = simd.FixedTag(u8, 8);

fn drawU32(data: *hypothesis.ConjectureData) !U32.Vector {
    var result: U32.Vector = undefined;
    inline for (0..U32.lane_count) |index| {
        result[index] = @truncate(try data.drawInteger(0, std.math.maxInt(u32), 0));
    }
    return result;
}

fn drawU16(data: *hypothesis.ConjectureData) !U16.Vector {
    var result: U16.Vector = undefined;
    inline for (0..U16.lane_count) |index| {
        result[index] = @truncate(try data.drawInteger(0, std.math.maxInt(u16), 0));
    }
    return result;
}

pub const PromotionDemotionProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const unsigned = try drawU16(data);
        const signed: I16.Vector = @bitCast(try drawU16(data));
        try std.testing.expect(@reduce(.And, simd.demoteTo(U16, simd.promoteTo(U32, unsigned)) == unsigned));
        try std.testing.expect(@reduce(.And, simd.demoteTo(I16, simd.promoteTo(I32, signed)) == signed));

        const halves: F16.Vector = @bitCast(try drawU16(data));
        const restored = simd.demoteTo(F16, simd.promoteTo(F32, halves));
        inline for (0..F16.lane_count) |index| {
            if (!std.math.isNan(halves[index])) {
                try std.testing.expectEqual(@as(u16, @bitCast(halves[index])), @as(u16, @bitCast(restored[index])));
            }
        }
    }
};

pub const SaturatingDemotionProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const a: I32.Vector = @bitCast(try drawU32(data));
        const b: I32.Vector = @bitCast(try drawU32(data));
        const low = simd.min(I32, a, b);
        const high = simd.max(I32, a, b);
        const low_signed = simd.demoteTo(I16, low);
        const high_signed = simd.demoteTo(I16, high);
        const low_unsigned = simd.demoteTo(U16, low);
        const high_unsigned = simd.demoteTo(U16, high);
        const actual_signed = simd.demoteTo(I16, a);
        const actual_unsigned = simd.demoteTo(U16, a);
        try std.testing.expect(@reduce(.And, low_signed <= high_signed));
        try std.testing.expect(@reduce(.And, low_unsigned <= high_unsigned));

        inline for (0..I32.lane_count) |index| {
            const value = a[index];
            const expected_signed: i16 = if (value < std.math.minInt(i16))
                std.math.minInt(i16)
            else if (value > std.math.maxInt(i16))
                std.math.maxInt(i16)
            else
                @intCast(value);
            const expected_unsigned: u16 = if (value <= 0)
                0
            else if (value > std.math.maxInt(u16))
                std.math.maxInt(u16)
            else
                @intCast(value);
            try std.testing.expectEqual(expected_signed, actual_signed[index]);
            try std.testing.expectEqual(expected_unsigned, actual_unsigned[index]);
        }
    }
};

pub const TruncationPackingProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawU32(data);
        try std.testing.expect(@reduce(.And, simd.truncateTo(U8, value) == @as(U8.Vector, @truncate(value))));

        const A = simd.FixedTag(u16, 4);
        const a_source = try drawU16(data);
        const b_source = try drawU16(data);
        var a: A.Vector = undefined;
        var b: A.Vector = undefined;
        inline for (0..A.lane_count) |index| {
            a[index] = a_source[index];
            b[index] = b_source[index];
        }
        const result = simd.orderedTruncate2To(U8, a, b);
        inline for (0..A.lane_count) |index| {
            try std.testing.expectEqual(@as(u8, @truncate(a[index])), result[index]);
            try std.testing.expectEqual(@as(u8, @truncate(b[index])), result[A.lane_count + index]);
        }
    }
};

pub const FloatIntegerProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const bits = try drawU32(data);
        const value: F32.Vector = @bitCast(bits);
        const signed = simd.convertTo(I32, value);
        const unsigned = simd.convertTo(U32, value);
        inline for (0..F32.lane_count) |index| {
            try std.testing.expectEqual(modelI32(value[index]), signed[index]);
            try std.testing.expectEqual(modelU32(value[index]), unsigned[index]);
        }
    }
};

pub const MaskConversionProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const B = simd.FixedTag(u8, 4);
        const W = simd.FixedTag(i32, 4);
        const N = simd.FixedTag(u16, 8);
        var a: B.Mask = undefined;
        var b: B.Mask = undefined;
        inline for (0..B.lane_count) |index| {
            a[index] = try data.drawBoolean();
            b[index] = try data.drawBoolean();
        }
        try std.testing.expect(@reduce(.And, simd.promoteMaskTo(W, B, a) == a));
        try std.testing.expect(@reduce(.And, simd.demoteMaskTo(B, W, a) == a));
        const result = simd.orderedDemote2MasksTo(N, W, a, b);
        inline for (0..B.lane_count) |index| {
            try std.testing.expectEqual(a[index], result[index]);
            try std.testing.expectEqual(b[index], result[B.lane_count + index]);
        }
    }
};

fn modelI32(value: f32) i32 {
    const bits: u32 = @bitCast(value);
    if (std.math.isNan(value)) {
        return if (bits & 0x8000_0000 != 0) std.math.minInt(i32) else std.math.maxInt(i32);
    }
    if (value >= 0x1p31) return std.math.maxInt(i32);
    if (value <= -0x1p31) return std.math.minInt(i32);
    return @intFromFloat(value);
}

fn modelU32(value: f32) u32 {
    const bits: u32 = @bitCast(value);
    if (std.math.isNan(value)) {
        return if (bits & 0x8000_0000 != 0) 0 else std.math.maxInt(u32);
    }
    if (value >= 0x1p32) return std.math.maxInt(u32);
    if (value <= 0) return 0;
    return @intFromFloat(value);
}

test "property: exact promotion and demotion round trips preserve representable lanes" {
    try hypothesis.checkNamed(PromotionDemotionProperty, "simd-convert-roundtrip", run.settings());
}

test "property: saturating demotion is monotone and matches scalar bounds" {
    try hypothesis.checkNamed(SaturatingDemotionProperty, "simd-demote-saturation", run.settings());
}

test "property: truncation keeps low bits and ordered packing keeps source order" {
    try hypothesis.checkNamed(TruncationPackingProperty, "simd-truncate-packing", run.settings());
}

test "property: floating conversion matches the saturating scalar model" {
    try hypothesis.checkNamed(FloatIntegerProperty, "simd-float-integer-saturation", run.settings());
}

test "property: mask conversion preserves truth and ordered source lanes" {
    try hypothesis.checkNamed(MaskConversionProperty, "simd-mask-conversion", run.settings());
}
