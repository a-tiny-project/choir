const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const bin_capacity: usize = 17;
const max_operations: usize = 128;
const max_values: usize = 64;

pub const BinsProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const Histogram = simd.TypedBins(bin_capacity, u64);
        const operation_count: usize = @intCast(try data.drawInteger(0, max_operations, 0));
        const split: usize = @intCast(try data.drawInteger(0, operation_count, 0));
        var bins = Histogram{};
        var left = Histogram{};
        var right = Histogram{};
        var model: [bin_capacity]u64 = @splat(0);

        for (0..operation_count) |operation_index| {
            const bin_index: usize = @intCast(try data.drawInteger(0, bin_capacity - 1, 0));
            const count: u32 = @intCast(try data.drawInteger(0, 1000, 0));
            bins.incrementBy(bin_index, count);
            if (operation_index < split) {
                left.incrementBy(bin_index, count);
            } else {
                right.incrementBy(bin_index, count);
            }
            model[bin_index] += count;
        }
        left.assimilate(&right);
        try verifyBins(&bins, &model);
        try verifyBins(&left, &model);
    }
};

pub const MomentsProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value_count: usize = @intCast(try data.drawInteger(1, max_values, 1));
        const split: usize = @intCast(try data.drawInteger(0, value_count, 0));
        var values: [max_values]f32 = undefined;
        var sequential = simd.Stats{};
        var left = simd.Stats{};
        var right = simd.Stats{};
        var shards: [4]simd.Stats = @splat(.{});
        for (values[0..value_count], 0..) |*value, index| {
            const integer = try data.drawInteger(1, 10_000, 1);
            value.* = @floatFromInt(integer);
            sequential.notify(value.*);
            if (index < split) {
                left.notify(value.*);
            } else {
                right.notify(value.*);
            }
            shards[index % shards.len].notify(value.*);
        }
        left.assimilate(&right);
        shards[0].assimilate(&shards[1]);
        shards[2].assimilate(&shards[3]);
        shards[0].assimilate(&shards[2]);

        const reference = referenceStats(values[0..value_count]);
        try verifyReference(&sequential, reference);
        try verifyReference(&left, reference);
        try verifyReference(&shards[0], reference);
        try verifyEquivalent(&sequential, &left);
        try verifyEquivalent(&sequential, &shards[0]);
    }
};

const Reference = struct {
    count: i64,
    minimum: f32,
    maximum: f32,
    geometric_mean: f64,
    mean: f64,
    sample_variance: f64,
    variance: f64,
    sample_skewness: f64,
    skewness: f64,
    sample_kurtosis: f64,
    kurtosis: f64,
    mu3: f64,
    mu4: f64,
};

fn verifyBins(
    bins: *const simd.TypedBins(bin_capacity, u64),
    model: *const [bin_capacity]u64,
) !void {
    var first = bin_capacity;
    var last: usize = 0;
    var nonzero: usize = 0;
    var maximum: u64 = 0;
    var modal: usize = 0;
    for (model, 0..) |count, bin_index| {
        try std.testing.expectEqual(count, bins.bin(bin_index));
        if (count != 0) {
            if (first == bin_capacity) first = bin_index;
            last = bin_index;
            nonzero += 1;
        }
        if (count > maximum) {
            maximum = count;
            modal = bin_index;
        }
    }
    try std.testing.expectEqual(first, bins.firstNonzero());
    try std.testing.expectEqual(last, bins.lastNonzero());
    try std.testing.expectEqual(nonzero, bins.numNonzero());
    try std.testing.expectEqual(modal, bins.modalBinIndex());
}

fn referenceStats(values: []const f32) Reference {
    var minimum = std.math.floatMax(f32);
    var maximum = -std.math.floatMax(f32);
    var sum: f64 = 0;
    var sum_log: f64 = 0;
    for (values) |value| {
        minimum = @min(minimum, value);
        maximum = @max(maximum, value);
        sum += value;
        sum_log += @log(@as(f64, value));
    }
    const count: f64 = @floatFromInt(values.len);
    const mean = sum / count;
    var moment_2: f64 = 0;
    var moment_3: f64 = 0;
    var moment_4: f64 = 0;
    for (values) |value| {
        const delta = @as(f64, value) - mean;
        const delta_squared = delta * delta;
        moment_2 += delta_squared;
        moment_3 += delta_squared * delta;
        moment_4 += delta_squared * delta_squared;
    }
    const mu2 = moment_2 / count;
    const mu3 = moment_3 / count;
    const mu4 = moment_4 / count;
    const sample_skewness = if (@abs(moment_2) < 1e-7)
        0
    else
        mu3 / std.math.pow(f64, mu2, 1.5);
    const sample_kurtosis = if (@abs(moment_2) < 1e-7)
        0
    else
        mu4 / (mu2 * mu2);
    const ratio = (count - 1) / count;
    return .{
        .count = @intCast(values.len),
        .minimum = minimum,
        .maximum = maximum,
        .geometric_mean = @exp(sum_log / count),
        .mean = mean,
        .sample_variance = mu2,
        .variance = if (values.len == 1) moment_2 else moment_2 / (count - 1),
        .sample_skewness = sample_skewness,
        .skewness = sample_skewness * std.math.pow(f64, ratio, 1.5),
        .sample_kurtosis = sample_kurtosis,
        .kurtosis = sample_kurtosis * ratio * ratio,
        .mu3 = mu3,
        .mu4 = mu4,
    };
}

fn verifyReference(stats: *const simd.Stats, reference: Reference) !void {
    try std.testing.expectEqual(reference.count, stats.count());
    try std.testing.expectEqual(reference.minimum, stats.min());
    try std.testing.expectEqual(reference.maximum, stats.max());
    try expectClose(reference.geometric_mean, stats.geometricMean(), 2e-13);
    try expectClose(reference.mean, stats.mean(), 2e-13);
    try expectClose(reference.sample_variance, stats.sampleVariance(), 2e-12);
    try expectClose(reference.variance, stats.variance(), 2e-12);
    try expectClose(@sqrt(reference.variance), stats.standardDeviation(), 2e-12);
    try expectClose(reference.sample_skewness, stats.sampleSkewness(), 2e-11);
    try expectClose(reference.skewness, stats.skewness(), 2e-11);
    try expectClose(reference.sample_kurtosis, stats.sampleKurtosis(), 2e-11);
    try expectClose(reference.kurtosis, stats.kurtosis(), 2e-11);
    try expectClose(reference.mean, stats.mu1(), 2e-13);
    try expectClose(reference.sample_variance, stats.mu2(), 2e-12);
    try expectClose(reference.mu3, stats.mu3(), 2e-11);
    try expectClose(reference.mu4, stats.mu4(), 2e-11);
}

fn verifyEquivalent(expected: *const simd.Stats, actual: *const simd.Stats) !void {
    try std.testing.expectEqual(expected.count(), actual.count());
    try std.testing.expectEqual(expected.min(), actual.min());
    try std.testing.expectEqual(expected.max(), actual.max());
    try expectClose(expected.geometricMean(), actual.geometricMean(), 2e-13);
    try expectClose(expected.mean(), actual.mean(), 2e-13);
    try expectClose(expected.sampleVariance(), actual.sampleVariance(), 2e-12);
    try expectClose(expected.variance(), actual.variance(), 2e-12);
    try expectClose(expected.sampleSkewness(), actual.sampleSkewness(), 2e-11);
    try expectClose(expected.skewness(), actual.skewness(), 2e-11);
    try expectClose(expected.sampleKurtosis(), actual.sampleKurtosis(), 2e-11);
    try expectClose(expected.kurtosis(), actual.kurtosis(), 2e-11);
}

fn expectClose(expected: f64, actual: f64, relative_tolerance: f64) !void {
    const scale = @max(@abs(expected), 1);
    try std.testing.expect(@abs(expected - actual) <= relative_tolerance * scale);
}

test "property: fixed bins match a scalar model across assimilation" {
    try hypothesis.checkNamed(BinsProperty, "simd-stats-bins-model", run.settings());
}

test "property: online moments match two-pass moments across assimilation" {
    try hypothesis.checkNamed(MomentsProperty, "simd-stats-moments-model", run.settings());
}
