const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const D = simd.FixedTag(i32, 8);
const Bytes = simd.ScalableTag(u8);
const max_values: usize = 129;

fn drawValues(data: *hypothesis.ConjectureData, values: *[max_values]i32) !usize {
    const length: usize = @intCast(try data.drawInteger(0, max_values, 0));
    for (values[0..length]) |*value| {
        const drawn: i32 = @intCast(try data.drawInteger(0, 512, 256));
        value.* = drawn - 256;
    }
    return length;
}

const LessThan = struct {
    limit: i32,

    pub fn call(self: @This(), comptime Tag: type, value: Tag.Vector) Tag.Mask {
        return value < @as(Tag.Vector, @splat(self.limit));
    }
};

pub const SearchProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var storage: [max_values]i32 = undefined;
        const length = try drawValues(data, &storage);
        const input = storage[0..length];
        const needle_drawn: i32 = @intCast(try data.drawInteger(0, 512, 256));
        const needle = needle_drawn - 256;
        var expected_count: usize = 0;
        var expected_find = length;
        var expected_min: i32 = std.math.maxInt(i32);
        var expected_max: i32 = std.math.minInt(i32);
        var expected_sorted = true;
        for (input, 0..) |value, index| {
            if (value == needle) {
                expected_count += 1;
                if (expected_find == length) expected_find = index;
            }
            expected_min = @min(expected_min, value);
            expected_max = @max(expected_max, value);
            if (index != 0 and value < input[index - 1]) expected_sorted = false;
        }
        try std.testing.expectEqual(expected_count, simd.countValue(D, input, needle));
        try std.testing.expectEqual(expected_find, simd.find(D, input, needle));
        try std.testing.expectEqual(expected_count == length, simd.allEqual(D, input, needle));
        try std.testing.expectEqual(expected_min, simd.minValue(D, input));
        try std.testing.expectEqual(expected_max, simd.maxValue(D, input));
        try std.testing.expectEqual(expected_sorted, simd.isSorted(D, input));
        var copied: [max_values]i32 = undefined;
        simd.copy(D, input, copied[0..length]);
        try std.testing.expectEqualSlices(i32, input, copied[0..length]);
        simd.fill(D, copied[0..length], needle);
        for (copied[0..length]) |value| try std.testing.expectEqual(needle, value);
    }
};

pub const EqualityProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var left_storage: [max_values]i32 = undefined;
        const length = try drawValues(data, &left_storage);
        const left = left_storage[0..length];
        var right_storage: [max_values]i32 = undefined;
        @memcpy(right_storage[0..length], left);
        var right_length = length;
        const change = try data.drawInteger(0, 2, 0);
        if (change == 1 and length != 0) {
            const position: usize = @intCast(try data.drawInteger(0, length - 1, 0));
            const byte: u5 = @intCast(try data.drawInteger(0, 3, 0));
            const flip: u32 = @intCast(try data.drawInteger(1, 255, 1));
            right_storage[position] ^= @bitCast(flip << (8 * byte));
        }
        if (change == 2 and length != 0) right_length -= 1;
        const right = right_storage[0..right_length];
        const expected = std.mem.eql(i32, left, right);
        try std.testing.expect(simd.equal(D, left, left));
        try std.testing.expectEqual(expected, simd.equal(D, left, right));
        const left_bytes = std.mem.sliceAsBytes(left);
        const right_bytes = std.mem.sliceAsBytes(right);
        try std.testing.expectEqual(expected, simd.equal(Bytes, left_bytes, right_bytes));
    }
};

pub const OrderProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var left_storage: [max_values]i32 = undefined;
        const length = try drawValues(data, &left_storage);
        const left = left_storage[0..length];
        var right_storage: [max_values]i32 = undefined;
        @memcpy(right_storage[0..length], left);
        var right_length = length;
        const change = try data.drawInteger(0, 3, 0);
        if (change == 1 and length != 0) {
            const position: usize = @intCast(try data.drawInteger(0, length - 1, 0));
            const byte: u5 = @intCast(try data.drawInteger(0, 3, 0));
            const flip: u32 = @intCast(try data.drawInteger(1, 255, 1));
            right_storage[position] ^= @bitCast(flip << (8 * byte));
        }
        if (change == 2 and length != 0) right_length -= 1;
        if (change == 3 and length != max_values) {
            right_storage[length] = 0;
            right_length += 1;
        }
        const right = right_storage[0..right_length];
        try std.testing.expectEqual(std.mem.order(i32, left, right), simd.order(D, left, right));
        try std.testing.expectEqual(std.mem.order(i32, right, left), simd.order(D, right, left));
        const left_bytes = std.mem.sliceAsBytes(left);
        const right_bytes = std.mem.sliceAsBytes(right);
        const expected_bytes = std.mem.order(u8, left_bytes, right_bytes);
        try std.testing.expectEqual(expected_bytes, simd.order(Bytes, left_bytes, right_bytes));
        const shared = @min(left.len, right.len);
        var expected: usize = 0;
        while (expected < shared and left[expected] == right[expected]) expected += 1;
        try std.testing.expectEqual(expected, simd.mismatch(D, left[0..shared], right[0..shared]));
    }
};

pub const StableFilterProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var storage: [max_values]i32 = undefined;
        const length = try drawValues(data, &storage);
        const input = storage[0..length];
        const limit_drawn: i32 = @intCast(try data.drawInteger(0, 512, 256));
        const predicate = LessThan{ .limit = limit_drawn - 256 };
        var expected: [max_values]i32 = undefined;
        var expected_count: usize = 0;
        for (input) |value| {
            if (value < predicate.limit) {
                expected[expected_count] = value;
                expected_count += 1;
            }
        }
        var output: [max_values]i32 = undefined;
        const actual_count = simd.copyIf(D, input, &output, predicate);
        try std.testing.expectEqual(expected_count, simd.countIf(D, input, predicate));
        try std.testing.expectEqual(expected_count, actual_count);
        try std.testing.expectEqualSlices(
            i32,
            expected[0..expected_count],
            output[0..actual_count],
        );
        const expected_find: usize = for (input, 0..) |value, index| {
            if (value < predicate.limit) break index;
        } else length;
        try std.testing.expectEqual(expected_find, simd.findIf(D, input, predicate));
        var grouped = storage;
        var grouped_expected: [max_values]i32 = undefined;
        var unique_count: usize = 0;
        for (input) |value| {
            if (unique_count == 0 or value != grouped_expected[unique_count - 1]) {
                grouped_expected[unique_count] = value;
                unique_count += 1;
            }
        }
        try std.testing.expectEqual(length == unique_count, simd.allUnique(D, input));
        const actual_unique = simd.unique(D, grouped[0..length]);
        try std.testing.expectEqualSlices(
            i32,
            grouped_expected[0..unique_count],
            grouped[0..actual_unique],
        );
        try std.testing.expect(simd.allUnique(D, grouped[0..actual_unique]));
    }
};

const Affine = struct {
    factor: i32,
    offset: i32,

    pub fn call(self: @This(), comptime Tag: type, value: Tag.Vector) Tag.Vector {
        return value * @as(Tag.Vector, @splat(self.factor)) + @as(Tag.Vector, @splat(self.offset));
    }
};

const Add = struct {
    pub fn call(_: @This(), comptime Tag: type, a: Tag.Vector, b: Tag.Vector) Tag.Vector {
        return a + b;
    }
};

pub const TransformProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var storage: [max_values]i32 = undefined;
        const length = try drawValues(data, &storage);
        var other: [max_values]i32 = undefined;
        for (other[0..length], 0..) |*value, index| value.* = @intCast(index % 17);
        const factor = @as(i32, @intCast(try data.drawInteger(0, 6, 3))) - 3;
        const offset = @as(i32, @intCast(try data.drawInteger(0, 32, 16))) - 16;
        var expected = storage;
        for (expected[0..length]) |*value| value.* = value.* * factor + offset;
        simd.transform(D, storage[0..length], Affine{ .factor = factor, .offset = offset });
        try std.testing.expectEqualSlices(i32, expected[0..length], storage[0..length]);
        for (expected[0..length], other[0..length]) |*value, addend| value.* += addend;
        simd.transform1(D, storage[0..length], other[0..length], Add{});
        try std.testing.expectEqualSlices(i32, expected[0..length], storage[0..length]);
        const old = if (length == 0) @as(i32, 0) else expected[length / 2];
        simd.replace(D, storage[0..length], old, -777);
        for (expected[0..length]) |*value| if (value.* == old) {
            value.* = -777;
        };
        try std.testing.expectEqualSlices(i32, expected[0..length], storage[0..length]);
        simd.replaceIf(D, storage[0..length], 777, LessThan{ .limit = 0 });
        for (expected[0..length]) |*value| if (value.* < 0) {
            value.* = 777;
        };
        try std.testing.expectEqualSlices(i32, expected[0..length], storage[0..length]);
    }
};

test "property: span search and extrema match scalar models across tails" {
    try hypothesis.checkNamed(SearchProperty, "simd-algo-search-model", run.settings());
}

test "property: span equality matches element equality across tails" {
    try hypothesis.checkNamed(EqualityProperty, "simd-algo-equality-model", run.settings());
}

test "property: span order matches element order across tails" {
    try hypothesis.checkNamed(OrderProperty, "simd-algo-order-model", run.settings());
}

test "property: filtering and grouped uniqueness preserve stable order" {
    try hypothesis.checkNamed(StableFilterProperty, "simd-algo-stable-filter", run.settings());
}

test "property: transform and replacement compose with scalar mutation" {
    try hypothesis.checkNamed(TransformProperty, "simd-algo-transform-model", run.settings());
}
