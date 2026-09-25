const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const max_u32_keys = 256;
const max_kv_keys = 128;
const max_public_keys = 1024;
const max_float_keys = 512;

fn Order(comptime Key: type, comptime direction: simd.SortDirection) type {
    return struct {
        fn lessThan(_: void, a: Key, b: Key) bool {
            return simd.sort.testing.networkBefore(Key, direction, a, b);
        }
    };
}

fn mix(value: u64) u64 {
    var result = value;
    result = (result ^ (result >> 30)) *% 0xbf58_476d_1ce4_e5b9;
    result = (result ^ (result >> 27)) *% 0x94d0_49bb_1331_11eb;
    return result ^ (result >> 31);
}

fn u32Ascending(_: void, a: u32, b: u32) bool {
    return a < b;
}

fn u32Descending(_: void, a: u32, b: u32) bool {
    return a > b;
}

fn f32Ascending(_: void, a: f32, b: f32) bool {
    return a < b;
}

fn f32Descending(_: void, a: f32, b: f32) bool {
    return a > b;
}

pub const IntegerNetworkProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(0, max_u32_keys, 0));
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const descending = try data.drawBoolean();
        var storage: [max_u32_keys + 2]u32 = undefined;
        storage[0] = 0xa55a_5aa5;
        storage[count + 1] = 0x5aa5_a55a;
        for (storage[1 .. count + 1], 0..) |*value, index| {
            value.* = @truncate(mix(seed +% index) & 0xffff);
        }
        var expected: [max_u32_keys]u32 = undefined;
        @memcpy(expected[0..count], storage[1 .. count + 1]);
        var scratch = simd.sort.testing.Scratch{};
        if (descending) {
            std.mem.sort(u32, expected[0..count], {}, Order(u32, .descending).lessThan);
            try simd.sort.testing.networkSort(
                u32,
                .descending,
                storage[1 .. count + 1],
                &scratch,
            );
        } else {
            std.mem.sort(u32, expected[0..count], {}, Order(u32, .ascending).lessThan);
            try simd.sort.testing.networkSort(
                u32,
                .ascending,
                storage[1 .. count + 1],
                &scratch,
            );
        }
        try std.testing.expectEqualSlices(u32, expected[0..count], storage[1 .. count + 1]);
        try std.testing.expectEqual(@as(u32, 0xa55a_5aa5), storage[0]);
        try std.testing.expectEqual(@as(u32, 0x5aa5_a55a), storage[count + 1]);
    }
};

pub const KeyValueNetworkProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(0, max_kv_keys, 0));
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        var values: [max_kv_keys]simd.K32V32 = undefined;
        for (values[0..count], 0..) |*value, index| {
            const bits = mix(seed +% index);
            value.* = simd.K32V32.init(@truncate(bits & 31), @truncate(bits >> 32));
        }
        var expected = values;
        std.mem.sort(
            simd.K32V32,
            expected[0..count],
            {},
            Order(simd.K32V32, .ascending).lessThan,
        );
        var scratch = simd.sort.testing.Scratch{};
        try simd.sort.testing.networkSort(
            simd.K32V32,
            .ascending,
            values[0..count],
            &scratch,
        );
        try std.testing.expectEqualSlices(
            simd.K32V32,
            expected[0..count],
            values[0..count],
        );
        for (values[0..count], 0..) |value, index| {
            if (index != 0) try std.testing.expect(values[index - 1].key <= value.key);
        }
    }
};

pub const ChunkMappingProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: u32 = @intCast(try data.drawInteger(1, std.math.maxInt(u32), 1));
        const bits: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const expected: usize = @intCast((@as(u64, bits) * count) >> 32);
        const actual = simd.sort.testing.randomChunkIndex(count, bits);
        try std.testing.expectEqual(expected, actual);
        try std.testing.expect(actual < count);
    }
};

pub const MedianProperty = struct {
    fn ascendingU64(_: void, a: u64, b: u64) bool {
        return a < b;
    }

    fn descendingU64(_: void, a: u64, b: u64) bool {
        return a > b;
    }

    fn ascendingK32V32(_: void, a: simd.K32V32, b: simd.K32V32) bool {
        return a.key < b.key or (a.key == b.key and a.value < b.value);
    }

    fn descendingK32V32(_: void, a: simd.K32V32, b: simd.K32V32) bool {
        return a.key > b.key or (a.key == b.key and a.value > b.value);
    }

    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const integers = [_]u64{
            mix(seed) & 15,
            mix(seed +% 1) & 15,
            mix(seed +% 2) & 15,
        };
        var expected_integers = integers;
        std.mem.sort(u64, &expected_integers, {}, ascendingU64);
        try std.testing.expectEqual(
            expected_integers[1],
            simd.sort.testing.medianOf3(
                u64,
                .ascending,
                integers[0],
                integers[1],
                integers[2],
            ),
        );
        std.mem.sort(u64, &expected_integers, {}, descendingU64);
        try std.testing.expectEqual(
            expected_integers[1],
            simd.sort.testing.medianOf3(
                u64,
                .descending,
                integers[0],
                integers[1],
                integers[2],
            ),
        );

        var records: [3]simd.K32V32 = undefined;
        for (&records, 0..) |*record, index| {
            const bits = mix(seed +% index +% 3);
            record.* = simd.K32V32.init(@truncate(bits & 3), @truncate(bits >> 32));
        }
        var expected_records = records;
        std.mem.sort(simd.K32V32, &expected_records, {}, ascendingK32V32);
        try std.testing.expectEqual(
            expected_records[1],
            simd.sort.testing.medianOf3(
                simd.K32V32,
                .ascending,
                records[0],
                records[1],
                records[2],
            ),
        );
        std.mem.sort(simd.K32V32, &expected_records, {}, descendingK32V32);
        try std.testing.expectEqual(
            expected_records[1],
            simd.sort.testing.medianOf3(
                simd.K32V32,
                .descending,
                records[0],
                records[1],
                records[2],
            ),
        );
    }
};

pub const PublicSortProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(0, max_public_keys, 0));
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const descending = try data.drawBoolean();
        var values: [max_public_keys]u32 = undefined;
        for (values[0..count], 0..) |*value, index| value.* = @truncate(mix(seed +% index) & 0xffff);
        var expected = values;
        if (descending) {
            std.mem.sort(u32, expected[0..count], {}, u32Descending);
            simd.vqSort(u32, .descending, values[0..count]);
        } else {
            std.mem.sort(u32, expected[0..count], {}, u32Ascending);
            simd.vqSort(u32, .ascending, values[0..count]);
        }
        try std.testing.expectEqualSlices(u32, expected[0..count], values[0..count]);
    }
};

pub const PartitionProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(0, max_public_keys, 0));
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const pivot: u32 = @truncate(try data.drawInteger(0, 255, 0));
        const descending = try data.drawBoolean();
        var storage: [max_public_keys + 2]u32 = undefined;
        storage[0] = 0xa55a_5aa5;
        storage[count + 1] = 0x5aa5_a55a;
        for (storage[1 .. count + 1], 0..) |*value, index| value.* = @truncate(mix(seed +% index) & 255);
        var expected: [max_public_keys]u32 = undefined;
        @memcpy(expected[0..count], storage[1 .. count + 1]);
        const bounds = if (descending)
            simd.sort.testing.partitionAround(u32, .descending, storage[1 .. count + 1], pivot)
        else
            simd.sort.testing.partitionAround(u32, .ascending, storage[1 .. count + 1], pivot);
        for (storage[1 .. bounds.before + 1]) |value| {
            try std.testing.expect(if (descending) value > pivot else value < pivot);
        }
        for (storage[bounds.before + 1 .. bounds.after + 1]) |value| try std.testing.expectEqual(pivot, value);
        for (storage[bounds.after + 1 .. count + 1]) |value| {
            try std.testing.expect(if (descending) value < pivot else value > pivot);
        }
        var actual: [max_public_keys]u32 = undefined;
        @memcpy(actual[0..count], storage[1 .. count + 1]);
        std.mem.sort(u32, expected[0..count], {}, u32Ascending);
        std.mem.sort(u32, actual[0..count], {}, u32Ascending);
        try std.testing.expectEqualSlices(u32, expected[0..count], actual[0..count]);
        try std.testing.expectEqual(@as(u32, 0xa55a_5aa5), storage[0]);
        try std.testing.expectEqual(@as(u32, 0x5aa5_a55a), storage[count + 1]);
    }
};

pub const PartialSelectProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(1, max_public_keys, 1));
        const prefix: usize = @intCast(try data.drawInteger(0, count, 0));
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const descending = try data.drawBoolean();
        var source: [max_public_keys]u32 = undefined;
        for (source[0..count], 0..) |*value, index| value.* = @truncate(mix(seed +% index) & 0xffff);
        var expected = source;
        var partial = source;
        if (descending) {
            std.mem.sort(u32, expected[0..count], {}, u32Descending);
            try simd.vqPartialSort(u32, .descending, partial[0..count], prefix);
        } else {
            std.mem.sort(u32, expected[0..count], {}, u32Ascending);
            try simd.vqPartialSort(u32, .ascending, partial[0..count], prefix);
        }
        try std.testing.expectEqualSlices(u32, expected[0..prefix], partial[0..prefix]);
        var expected_multiset = source;
        var partial_multiset = partial;
        std.mem.sort(u32, expected_multiset[0..count], {}, u32Ascending);
        std.mem.sort(u32, partial_multiset[0..count], {}, u32Ascending);
        try std.testing.expectEqualSlices(u32, expected_multiset[0..count], partial_multiset[0..count]);

        const kth: usize = @intCast(mix(seed ^ 0x517c_c1b7_2722_0a95) % count);
        var selected = source;
        if (descending) {
            try simd.vqSelect(u32, .descending, selected[0..count], kth);
        } else {
            try simd.vqSelect(u32, .ascending, selected[0..count], kth);
        }
        try std.testing.expectEqual(expected[kth], selected[kth]);
        for (selected[0..kth]) |value| {
            try std.testing.expect(if (descending) value >= selected[kth] else value <= selected[kth]);
        }
        for (selected[kth + 1 .. count]) |value| {
            try std.testing.expect(if (descending) value <= selected[kth] else value >= selected[kth]);
        }
    }
};

pub const FloatNaNProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(3, max_float_keys, 3));
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const descending = try data.drawBoolean();
        var values: [max_float_keys]f32 = undefined;
        for (values[0..count], 0..) |*value, index| {
            const integer: i32 = @intCast(mix(seed +% index) % 2001);
            value.* = @floatFromInt(integer - 1000);
        }
        const nan_index: usize = @intCast(seed % count);
        values[(nan_index + 1) % count] = std.math.inf(f32);
        values[(nan_index + 2) % count] = -std.math.inf(f32);
        values[nan_index] = std.math.nan(f32);
        var expected: [max_float_keys]f32 = undefined;
        var valid: usize = 0;
        for (values[0..count]) |value| {
            if (!std.math.isNan(value)) {
                expected[valid] = value;
                valid += 1;
            }
        }
        if (descending) {
            std.mem.sort(f32, expected[0..valid], {}, f32Descending);
            simd.vqSort(f32, .descending, values[0..count]);
        } else {
            std.mem.sort(f32, expected[0..valid], {}, f32Ascending);
            simd.vqSort(f32, .ascending, values[0..count]);
        }
        try std.testing.expectEqualSlices(f32, expected[0..valid], values[0..valid]);
        const canonical: u32 = @bitCast(simd.sort.testing.canonicalNaN(f32));
        for (values[valid..count]) |value| try std.testing.expectEqual(canonical, @as(u32, @bitCast(value)));
    }
};

test "property: VQSort base network matches an independent integer order" {
    try hypothesis.checkNamed(IntegerNetworkProperty, "simd-vqsort-network-u32", run.settings());
}

test "property: VQSort key value network preserves full-record ties" {
    try hypothesis.checkNamed(KeyValueNetworkProperty, "simd-vqsort-network-kv", run.settings());
}

test "property: VQSort random chunk mapping is multiply-high bounded" {
    try hypothesis.checkNamed(ChunkMappingProperty, "simd-vqsort-chunk-index", run.settings());
}

test "property: VQSort median follows scalar and full-record order" {
    try hypothesis.checkNamed(MedianProperty, "simd-vqsort-median", run.settings());
}

test "property: VQSort public full sort matches an independent order" {
    try hypothesis.checkNamed(PublicSortProperty, "simd-vqsort-public-sort", run.settings());
}

test "property: VQSort partition preserves permutation red zones and three regions" {
    try hypothesis.checkNamed(PartitionProperty, "simd-vqsort-partition", run.settings());
}

test "property: VQSort partial and select match sorted-order boundaries" {
    try hypothesis.checkNamed(PartialSelectProperty, "simd-vqsort-partial-select", run.settings());
}

test "property: VQSort canonicalizes NaN behind retained infinities" {
    try hypothesis.checkNamed(FloatNaNProperty, "simd-vqsort-nan", run.settings());
}
