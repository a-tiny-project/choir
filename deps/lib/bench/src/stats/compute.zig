const std = @import("std");
const model = @import("model.zig");
const storage_mod = @import("storage.zig");

pub fn sample(
    storage: *storage_mod.Storage,
    samples: []const u64,
) model.ComputeError!model.SampleStats {
    return sampleWithBootstrap(storage, samples, .{});
}

pub fn sampleWithBootstrap(
    storage: *storage_mod.Storage,
    samples: []const u64,
    bootstrap: model.BootstrapConfig,
) model.ComputeError!model.SampleStats {
    const regions = try storage.acquire(samples.len, bootstrap);
    defer storage.reset();
    @memcpy(regions.sorted, samples);
    std.mem.sort(u64, regions.sorted, {}, lessThanU64);

    var total: u128 = 0;
    for (samples) |value| total += value;
    return .{
        .min_ns = regions.sorted[0],
        .max_ns = regions.sorted[regions.sorted.len - 1],
        .mean_ns = @as(f64, @floatFromInt(total)) /
            @as(f64, @floatFromInt(samples.len)),
        .median_ns = percentile(regions.sorted, 50),
        .p75_ns = percentile(regions.sorted, 75),
        .p95_ns = percentile(regions.sorted, 95),
        .p99_ns = percentile(regions.sorted, 99),
        .total_ns = if (total > std.math.maxInt(u64)) std.math.maxInt(u64) else @intCast(total),
        .confidence_intervals = bootstrapConfidenceIntervals(regions, bootstrap),
    };
}

pub fn percentile(sorted: []const u64, pct: u8) u64 {
    if (sorted.len == 0) return 0;
    return sorted[scaledIndex(sorted.len, pct, 100)];
}

fn lessThanU64(_: void, left: u64, right: u64) bool {
    return left < right;
}

fn bootstrapConfidenceIntervals(
    regions: storage_mod.Regions,
    config: model.BootstrapConfig,
) ?model.BootstrapConfidenceIntervals {
    if (config.iterations == 0) return null;
    var prng = std.Random.DefaultPrng.init(config.seed);
    const random = prng.random();
    for (0..config.iterations) |index| {
        @memset(regions.counts, 0);
        var total: u128 = 0;
        for (0..regions.sorted.len) |_| {
            const sample_index = random.intRangeLessThan(usize, 0, regions.sorted.len);
            regions.counts[sample_index] += 1;
            total += regions.sorted[sample_index];
        }
        regions.means[index] = @as(f64, @floatFromInt(total)) /
            @as(f64, @floatFromInt(regions.sorted.len));
        regions.medians[index] = @floatFromInt(weightedPercentile(
            regions.sorted,
            regions.counts,
            50,
        ));
        regions.p75s[index] = @floatFromInt(weightedPercentile(
            regions.sorted,
            regions.counts,
            75,
        ));
        regions.p95s[index] = @floatFromInt(weightedPercentile(
            regions.sorted,
            regions.counts,
            95,
        ));
        regions.p99s[index] = @floatFromInt(weightedPercentile(
            regions.sorted,
            regions.counts,
            99,
        ));
    }

    std.mem.sort(f64, regions.means, {}, std.sort.asc(f64));
    std.mem.sort(f64, regions.medians, {}, std.sort.asc(f64));
    std.mem.sort(f64, regions.p75s, {}, std.sort.asc(f64));
    std.mem.sort(f64, regions.p95s, {}, std.sort.asc(f64));
    std.mem.sort(f64, regions.p99s, {}, std.sort.asc(f64));
    return .{
        .confidence = @as(f64, @floatFromInt(config.confidence_per_mille)) / 1000.0,
        .iterations = config.iterations,
        .seed = config.seed,
        .mean_ns = interval(regions.means, config.confidence_per_mille),
        .median_ns = interval(regions.medians, config.confidence_per_mille),
        .p75_ns = interval(regions.p75s, config.confidence_per_mille),
        .p95_ns = interval(regions.p95s, config.confidence_per_mille),
        .p99_ns = interval(regions.p99s, config.confidence_per_mille),
    };
}

fn interval(sorted: []const f64, confidence_per_mille: u16) model.ConfidenceInterval {
    const tail = (1000 - @as(usize, confidence_per_mille)) / 2;
    return .{
        .low_ns = quantilePerMille(sorted, @intCast(tail)),
        .high_ns = quantilePerMille(sorted, @intCast(1000 - tail)),
    };
}

fn quantilePerMille(sorted: []const f64, per_mille: u16) f64 {
    if (sorted.len == 0) return 0;
    return sorted[scaledIndex(sorted.len, per_mille, 1000)];
}

fn weightedPercentile(sorted: []const u64, counts: []const u32, pct: u8) u64 {
    std.debug.assert(sorted.len == counts.len);
    const target = scaledIndex(sorted.len, pct, 100);
    var seen: usize = 0;
    for (sorted, counts) |value, count| {
        seen += count;
        if (seen > target) return value;
    }
    return sorted[sorted.len - 1];
}

fn scaledIndex(len: usize, numerator: usize, denominator: usize) usize {
    std.debug.assert(len > 0);
    std.debug.assert(denominator > 0);
    const product = @as(u128, len - 1) * numerator;
    return @intCast((product + denominator - 1) / denominator);
}
