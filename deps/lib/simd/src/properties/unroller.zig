const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const max_values: usize = 257;

const AffineUnit = struct {
    factor: i32,
    offset: i32,

    pub const Base: type = simd.UnrollerUnit(i32, i32);

    pub fn func(
        self: *@This(),
        _: isize,
        value: Base.InputVector,
        _: Base.OutputVector,
    ) Base.OutputVector {
        return value *% @as(Base.OutputVector, @splat(self.factor)) +%
            @as(Base.OutputVector, @splat(self.offset));
    }
};

const PairUnit = struct {
    pub const Base: type = simd.UnrollerUnit2D(i32, i32, i32);

    pub fn func(
        _: *@This(),
        _: isize,
        first: Base.Input0Vector,
        second: Base.Input1Vector,
        _: Base.OutputVector,
    ) Base.OutputVector {
        return first *% @as(Base.OutputVector, @splat(3)) +%
            second *% @as(Base.OutputVector, @splat(5));
    }
};

const SumUnit = struct {
    pub const Base: type = simd.UnrollerUnit(i32, i32);

    pub fn func(
        _: *@This(),
        _: isize,
        value: Base.InputVector,
        sum: Base.OutputVector,
    ) Base.OutputVector {
        return value +% sum;
    }

    pub fn storeAndShortCircuit(
        _: *@This(),
        _: isize,
        _: []i32,
        _: Base.OutputVector,
    ) bool {
        return true;
    }

    pub fn maskStore(
        _: *@This(),
        _: isize,
        _: []i32,
        _: Base.OutputVector,
        _: isize,
    ) usize {
        return 0;
    }

    pub fn reduceUnrolled(
        _: *@This(),
        x0: Base.OutputVector,
        x1: Base.OutputVector,
        x2: Base.OutputVector,
        value: Base.OutputVector,
    ) Base.OutputVector {
        return x0 +% x1 +% x2 +% value;
    }

    pub fn reduceFinal(
        _: *@This(),
        value: Base.OutputVector,
        output: []i32,
    ) usize {
        std.debug.assert(output.len >= 1);
        var total: i32 = 0;
        inline for (0..Base.actual_lanes) |lane_index| total +%= value[lane_index];
        output[0] = total;
        return 1;
    }
};

fn drawValues(data: *hypothesis.ConjectureData, values: *[max_values]i32) !usize {
    const length: usize = @intCast(try data.drawInteger(0, max_values, 0));
    for (values[0..length]) |*value| {
        const drawn: i32 = @intCast(try data.drawInteger(0, 2_000_000, 1_000_000));
        value.* = drawn - 1_000_000;
    }
    return length;
}

pub const ElementwiseProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var input: [max_values]i32 = undefined;
        const length = try drawValues(data, &input);
        const factor = @as(i32, @intCast(try data.drawInteger(0, 8, 4))) - 4;
        const offset = @as(i32, @intCast(try data.drawInteger(0, 2_000, 1_000))) - 1_000;
        var expected: [max_values]i32 = undefined;
        for (input[0..length], expected[0..length]) |value, *result| {
            result.* = value *% factor +% offset;
        }
        var output: [max_values]i32 = undefined;
        var unit = AffineUnit{ .factor = factor, .offset = offset };
        simd.unroll(&unit, input[0..length], output[0..length]);
        try std.testing.expectEqualSlices(i32, expected[0..length], output[0..length]);
    }
};

pub const PairProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var first: [max_values]i32 = undefined;
        var second: [max_values]i32 = undefined;
        const length = try drawValues(data, &first);
        for (second[0..length]) |*value| {
            const drawn: i32 = @intCast(try data.drawInteger(0, 2_000_000, 1_000_000));
            value.* = drawn - 1_000_000;
        }
        var expected: [max_values]i32 = undefined;
        for (first[0..length], second[0..length], expected[0..length]) |a, b, *result| {
            result.* = a *% 3 +% b *% 5;
        }
        var output: [max_values]i32 = undefined;
        var unit = PairUnit{};
        simd.unroll2(&unit, first[0..length], second[0..length], output[0..length]);
        try std.testing.expectEqualSlices(i32, expected[0..length], output[0..length]);
    }
};

pub const ReductionProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var input: [max_values]i32 = undefined;
        const length = try drawValues(data, &input);
        var expected: i32 = 0;
        for (input[0..length]) |value| expected +%= value;
        var output: [1]i32 = undefined;
        var unit = SumUnit{};
        simd.unroll(&unit, input[0..length], &output);
        try std.testing.expectEqual(expected, output[0]);
    }
};

test "property: unroller elementwise hooks match scalar tails and four-way bodies" {
    try hypothesis.checkNamed(ElementwiseProperty, "simd-unroller-elementwise", run.settings());
}

test "property: two-input unroller matches scalar pairwise composition" {
    try hypothesis.checkNamed(PairProperty, "simd-unroller-pair", run.settings());
}

test "property: unroller associative reduction matches scalar folding" {
    try hypothesis.checkNamed(ReductionProperty, "simd-unroller-reduction", run.settings());
}
