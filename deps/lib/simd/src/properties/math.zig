const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const I = simd.FixedTag(i32, 8);
const F = simd.FixedTag(f32, 8);

fn drawI32(data: *hypothesis.ConjectureData) !i32 {
    const bits: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
    return @bitCast(bits);
}

fn drawDivisor(data: *hypothesis.ConjectureData) !i32 {
    const magnitude: i32 = @intCast(try data.drawInteger(1, std.math.maxInt(i32), 1));
    return if (try data.drawBoolean()) magnitude else -magnitude;
}

fn drawMathVector(data: *hypothesis.ConjectureData) !F.Vector {
    var result: F.Vector = undefined;
    inline for (0..F.lane_count) |index| {
        const drawn: i32 = @intCast(try data.drawInteger(1, 32_768, 128));
        result[index] = @as(f32, @floatFromInt(drawn)) / 1024.0;
    }
    return result;
}

pub const IntDivisionProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const divisor = try drawDivisor(data);
        var dividends: I.Vector = undefined;
        inline for (0..I.lane_count) |index| dividends[index] = try drawI32(data);
        const params = simd.computeDivisorParams(i32, divisor);
        const trunc_result = simd.intDiv(I, dividends, params);
        const floor_result = simd.intDivFloor(I, dividends, params);
        inline for (0..I.lane_count) |index| {
            const dividend = dividends[index];
            if (dividend == std.math.minInt(i32) and divisor == -1) {
                try std.testing.expectEqual(std.math.minInt(i32), trunc_result[index]);
                try std.testing.expectEqual(@as(i32, 0), floor_result[index]);
            } else {
                const quotient = @divTrunc(dividend, divisor);
                const remainder = @rem(dividend, divisor);
                const floor_adjust: i32 = if (remainder != 0 and (dividend < 0) != (divisor < 0)) 1 else 0;
                try std.testing.expectEqual(quotient, trunc_result[index]);
                try std.testing.expectEqual(quotient - floor_adjust, floor_result[index]);
            }
        }
    }
};

pub const ScalarDivisorProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const divisor = try data.drawInteger(1, std.math.maxInt(u64), 1);
        const dividend = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const scalar = simd.Divisor64.init(divisor);
        const quotient = scalar.divide(dividend);
        const remainder = scalar.remainder(dividend);
        try std.testing.expectEqual(dividend / divisor, quotient);
        try std.testing.expectEqual(dividend % divisor, remainder);
        try std.testing.expect(remainder < divisor);
        try std.testing.expectEqual(dividend, quotient * divisor + remainder);
    }
};

pub const MathIdentityProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const positive = try drawMathVector(data);
        const logarithm = simd.log(F, positive);
        const roundtrip = simd.exp(F, logarithm);
        const angles = positive - @as(F.Vector, @splat(16));
        const sine = simd.sin(F, angles);
        const cosine = simd.cos(F, angles);
        const odd_error = simd.erf(F, -angles) + simd.erf(F, angles);
        inline for (0..F.lane_count) |index| {
            try std.testing.expectApproxEqRel(positive[index], roundtrip[index], 0.000002);
            try std.testing.expectApproxEqAbs(@as(f32, 1), sine[index] * sine[index] + cosine[index] * cosine[index], 0.000002);
            try std.testing.expectApproxEqAbs(@as(f32, 0), odd_error[index], 0.000002);
        }
    }
};

pub const PrecisionProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var a: F.Vector = undefined;
        var b: F.Vector = undefined;
        inline for (0..F.lane_count) |index| {
            const a_int: i32 = @intCast(try data.drawInteger(0, 2_000_000, 1_000_000));
            const b_int: i32 = @intCast(try data.drawInteger(0, 2_000_000, 1_000_000));
            a[index] = @as(f32, @floatFromInt(a_int - 1_000_000)) * 0.03125;
            b[index] = @as(f32, @floatFromInt(b_int - 1_000_000)) * 0.03125;
        }
        var sum_error: F.Vector = undefined;
        const sum = simd.twoSums(F, a, b, &sum_error);
        var product_error: F.Vector = undefined;
        const product = simd.twoProducts(F, a, b, &product_error);
        inline for (0..F.lane_count) |index| {
            try std.testing.expectEqual(
                @as(f64, a[index]) + @as(f64, b[index]),
                @as(f64, sum[index]) + @as(f64, sum_error[index]),
            );
            try std.testing.expectEqual(
                @as(f64, a[index]) * @as(f64, b[index]),
                @as(f64, product[index]) + @as(f64, product_error[index]),
            );
        }
    }
};

test "property: integer division matches truncating and floor scalar models" {
    try hypothesis.checkNamed(IntDivisionProperty, "simd-intdiv-scalar-model", run.settings());
}

test "property: scalar divisor quotient and remainder reconstruct the dividend" {
    try hypothesis.checkNamed(ScalarDivisorProperty, "simd-scalar-divisor-model", run.settings());
}

test "property: contributed math preserves roundtrip parity and oddness" {
    try hypothesis.checkNamed(MathIdentityProperty, "simd-contrib-math-identities", run.settings());
}

test "property: compensated arithmetic reconstructs f32 operations in f64" {
    try hypothesis.checkNamed(PrecisionProperty, "simd-compensated-arithmetic", run.settings());
}
