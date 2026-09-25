const bench = @import("bench");
const model = @import("model.zig");

pub fn compareSeries(
    storage: *bench.ComparisonStorage,
    base: []const u64,
    candidate: []const u64,
    iterations: u32,
    seed: u64,
) bench.ComparisonError!model.Result {
    const comparison = try bench.compare.analyzeU64Medians(
        storage,
        base,
        candidate,
        iterations,
        seed,
    );
    return .{
        .base_median = comparison.baseline_median,
        .candidate_median = comparison.candidate_median,
        .ratio = comparison.ratio,
        .ci_low = comparison.low_ratio,
        .ci_high = comparison.high_ratio,
        .verdict = verdict(comparison.low_ratio, comparison.high_ratio),
    };
}

fn verdict(low_ratio: f64, high_ratio: f64) model.Verdict {
    if (high_ratio < 1.0) return .improved;
    if (low_ratio > 1.0) return .regressed;
    return .neutral;
}
