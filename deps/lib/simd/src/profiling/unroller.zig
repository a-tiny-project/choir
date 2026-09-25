const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const value_count: usize = 262_157;

var input: [value_count]i32 = undefined;
var output: [value_count]i32 = undefined;
var expected_checksum: u64 = 0;
var expected_sum: i32 = 0;

const TransformUnit = struct {
    pub const Base: type = simd.UnrollerUnit(i32, i32);

    pub fn func(
        _: *@This(),
        _: isize,
        value: Base.InputVector,
        _: Base.OutputVector,
    ) Base.OutputVector {
        return value *% @as(Base.OutputVector, @splat(1_664_525)) +%
            @as(Base.OutputVector, @splat(1_013_904_223));
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
        result: []i32,
    ) usize {
        std.debug.assert(result.len >= 1);
        var sum: i32 = 0;
        inline for (0..Base.actual_lanes) |lane_index| sum +%= value[lane_index];
        result[0] = sum;
        return 1;
    }
};

pub fn prepare(_: std.mem.Allocator) void {
    for (&input, 0..) |*value, index| {
        const bits: u32 = @truncate(index *% 2_654_435_761 +% 1_013_904_223);
        value.* = @bitCast(bits);
    }
    scalarTransform();
    expected_checksum = checksum(&output);
    expected_sum = scalarReduction();
}

pub fn scalar(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.unroller.scalar", @src());
        defer phase.end();
        scalarTransform();
    }
    if (checksum(&output) != expected_checksum) @panic("unroller scalar witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed("simd.unroller.scalar.complete");
}

pub fn vector(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.unroller.vector", @src());
        defer phase.end();
        var unit = TransformUnit{};
        simd.unroll(&unit, &input, &output);
    }
    if (checksum(&output) != expected_checksum) @panic("unroller vector witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed("simd.unroller.vector.complete");
}

pub fn reduction(_: std.mem.Allocator) void {
    var result: [1]i32 = undefined;
    {
        const phase = bench.phaseAt("simd.unroller.reduction", @src());
        defer phase.end();
        var unit = SumUnit{};
        simd.unroll(&unit, &input, &result);
    }
    if (result[0] != expected_sum) @panic("unroller reduction witness failed");
    std.mem.doNotOptimizeAway(&result);
    bench.coz.progressNamed("simd.unroller.reduction.complete");
}

fn scalarTransform() void {
    for (&input, &output) |value, *result| {
        result.* = value *% 1_664_525 +% 1_013_904_223;
    }
}

fn scalarReduction() i32 {
    var sum: i32 = 0;
    for (&input) |value| sum +%= value;
    return sum;
}

fn checksum(values: []const i32) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| {
        hash = (hash ^ @as(u32, @bitCast(value))) *% 0x0000_0100_0000_01b3;
    }
    return hash;
}
