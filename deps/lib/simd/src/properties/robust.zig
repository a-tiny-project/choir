const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const max_values: usize = 64;

pub const OrderProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(1, max_values, 0));
        var original: [max_values]u16 = undefined;
        for (original[0..count]) |*value| {
            value.* = @intCast(try data.drawInteger(0, 1023, 0));
        }

        var expected_sorted = original;
        std.mem.sort(u16, expected_sorted[0..count], {}, std.sort.asc(u16));
        var counted = original;
        var counting_scratch: [max_values]simd.CountingSortEntry(u16) = undefined;
        try simd.countingSort(u16, counted[0..count], &counting_scratch);
        try std.testing.expectEqualSlices(u16, expected_sorted[0..count], counted[0..count]);

        var mode_values = original;
        const observed_mode = try simd.mode(u16, mode_values[0..count], &counting_scratch);
        try std.testing.expectEqual(referenceMode(expected_sorted[0..count]), observed_mode);

        var reversed = original;
        std.mem.reverse(u16, reversed[0..count]);
        const reversed_mode = try simd.mode(u16, reversed[0..count], &counting_scratch);
        try std.testing.expectEqual(observed_mode, reversed_mode);

        var median_values = original;
        const observed_median = simd.median(u16, median_values[0..count]);
        const expected_median = referenceMedian(expected_sorted[0..count]);
        try std.testing.expectEqual(expected_median, observed_median);
        try std.testing.expect(observed_median >= expected_sorted[0]);
        try std.testing.expect(observed_median <= expected_sorted[count - 1]);

        var deviation_scratch: [max_values]u16 = undefined;
        const observed_mad = try simd.medianAbsoluteDeviation(
            u16,
            original[0..count],
            observed_median,
            &deviation_scratch,
        );
        try std.testing.expectEqual(
            referenceMad(original[0..count], observed_median),
            observed_mad,
        );
    }
};

pub const TranslationProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(1, max_values, 0));
        const offset: u32 = @intCast(try data.drawInteger(0, 1000, 0));
        var base: [max_values]u32 = undefined;
        var translated: [max_values]u32 = undefined;
        for (base[0..count], translated[0..count]) |*value, *shifted| {
            value.* = @intCast(try data.drawInteger(0, 50_000, 0));
            shifted.* = value.* + offset;
        }

        var base_mode_values = base;
        var translated_mode_values = translated;
        var base_mode_scratch: [max_values]simd.CountingSortEntry(u32) = undefined;
        var translated_mode_scratch: [max_values]simd.CountingSortEntry(u32) = undefined;
        const base_mode = try simd.mode(
            u32,
            base_mode_values[0..count],
            &base_mode_scratch,
        );
        const translated_mode = try simd.mode(
            u32,
            translated_mode_values[0..count],
            &translated_mode_scratch,
        );
        try std.testing.expectEqual(base_mode + offset, translated_mode);

        var base_median_values = base;
        var translated_median_values = translated;
        const base_median = simd.median(u32, base_median_values[0..count]);
        const translated_median = simd.median(u32, translated_median_values[0..count]);
        try std.testing.expectEqual(base_median + offset, translated_median);

        var base_deviations: [max_values]u32 = undefined;
        var translated_deviations: [max_values]u32 = undefined;
        const base_mad = try simd.medianAbsoluteDeviation(
            u32,
            base[0..count],
            base_median,
            &base_deviations,
        );
        const translated_mad = try simd.medianAbsoluteDeviation(
            u32,
            translated[0..count],
            translated_median,
            &translated_deviations,
        );
        try std.testing.expectEqual(base_mad, translated_mad);
    }
};

fn referenceMode(sorted: []const u16) u16 {
    var index_begin: usize = 0;
    var half_count = sorted.len / 2;
    while (half_count > 1) {
        var best_index = index_begin;
        var best_range: u32 = std.math.maxInt(u32);
        for (index_begin..index_begin + half_count) |index| {
            const range = @as(u32, sorted[index + half_count]) - sorted[index];
            if (range < best_range) {
                best_range = range;
                best_index = index;
            }
        }
        index_begin = best_index;
        half_count /= 2;
    }
    if (half_count == 0) return sorted[index_begin];
    return @intCast(
        (@as(u32, sorted[index_begin]) + sorted[index_begin + 1] + 1) / 2,
    );
}

fn referenceMedian(sorted: []const u16) u16 {
    const half = sorted.len / 2;
    if (sorted.len % 2 != 0) return sorted[half];
    return @intCast((@as(u32, sorted[half - 1]) + sorted[half] + 1) / 2);
}

fn referenceMad(values: []const u16, median_value: u16) u16 {
    var deviations: [max_values]u16 = undefined;
    for (values, deviations[0..values.len]) |value, *deviation| {
        deviation.* = if (value < median_value)
            median_value - value
        else
            value - median_value;
    }
    std.mem.sort(u16, deviations[0..values.len], {}, std.sort.asc(u16));
    return referenceMedian(deviations[0..values.len]);
}

test "property: robust order statistics match independent scalar models" {
    try hypothesis.checkNamed(OrderProperty, "simd-robust-order-model", run.settings());
}

test "property: robust locations translate while deviations remain invariant" {
    try hypothesis.checkNamed(TranslationProperty, "simd-robust-translation", run.settings());
}
