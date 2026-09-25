const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const max_candidates: usize = 129;
const max_cost_values: usize = 64;

pub const SkipListProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(1, max_candidates, 1));
        const removal_count: usize = @intCast(try data.drawInteger(0, count, 0));
        var positions: [max_candidates]usize = undefined;
        var active: [max_candidates]bool = @splat(false);
        for (positions[0..count], active[0..count], 0..) |*position, *is_active, index| {
            position.* = index;
            is_active.* = true;
        }
        var list = simd.NextWithSkip(max_candidates).init(count);
        var active_count = count;
        try verifyList(&list, active[0..count], active_count);
        for (0..removal_count) |removal_index| {
            const selected: usize = @intCast(try data.drawInteger(
                removal_index,
                count - 1,
                removal_index,
            ));
            std.mem.swap(usize, &positions[removal_index], &positions[selected]);
            const position = positions[removal_index];
            list.skip(position);
            if (active_count > 1) {
                active[position] = false;
                active_count -= 1;
            }
            try verifyList(&list, active[0..count], active_count);
        }
    }
};

pub const DistributionScaleProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(1, max_cost_values, 1));
        const scale_exponent: u6 = @intCast(try data.drawInteger(0, 10, 0));
        const scale_integer = @as(u64, 1) << scale_exponent;
        const scale: f64 = @floatFromInt(scale_integer);
        var base = simd.CostDistribution{};
        var scaled = simd.CostDistribution{};
        for (0..count) |_| {
            const integer: u32 = @intCast(try data.drawInteger(0, 1_000_000, 0));
            const value: f64 = @floatFromInt(integer);
            base.notify(value);
            scaled.notify(value * scale);
        }
        try std.testing.expectEqual(base.estimateCost() * scale, scaled.estimateCost());
        try std.testing.expectEqual(base.m1() * scale, scaled.m1());
        try std.testing.expectEqual(base.m2() * scale * scale, scaled.m2());
        try std.testing.expectEqual(base.mean() * scale, scaled.mean());
        try std.testing.expectEqual(
            base.standardDeviation() * scale,
            scaled.standardDeviation(),
        );
        try std.testing.expectEqual(base.lower() * scale, scaled.lower());
        try std.testing.expectEqual(base.upper() * scale, scaled.upper());
        try std.testing.expectEqual(base.onlineCount(), scaled.onlineCount());
        try std.testing.expectEqual(base.bufferedCount(), scaled.bufferedCount());
    }
};

pub const ExhaustiveTuningProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const candidate_count: usize = @intCast(try data.drawInteger(1, max_candidates, 1));
        var candidates: [max_candidates]u16 = undefined;
        var fixed_costs: [max_candidates]u64 = undefined;
        var expected_index: usize = 0;
        for (
            candidates[0..candidate_count],
            fixed_costs[0..candidate_count],
            0..,
        ) |*candidate, *cost, index| {
            candidate.* = @intCast(index);
            cost.* = @intCast(try data.drawInteger(0, 1_000_000, 0));
            if (cost.* < fixed_costs[expected_index]) expected_index = index;
        }

        const Tuner = simd.AutoTune(u16, max_candidates, 3);
        var tuner = Tuner{};
        try tuner.setCandidates(candidates[0..candidate_count]);
        var measurements: [max_candidates]usize = @splat(0);
        var calls: usize = 0;
        while (tuner.best() == null) : (calls += 1) {
            try std.testing.expect(calls < 5 * candidate_count);
            const index = tuner.currentIndex();
            try std.testing.expect(index < candidate_count);
            try std.testing.expectEqual(candidates[index], tuner.nextConfig().*);
            measurements[index] += 1;
            tuner.notifyCost(fixed_costs[index]);
        }
        try std.testing.expectEqual(candidates[expected_index], tuner.best().?.*);
        try std.testing.expectEqual(@as(usize, 5), tuner.completedRounds());
        for (measurements[0..candidate_count]) |measurement_count| {
            try std.testing.expect(measurement_count >= 4);
        }
    }
};

fn verifyList(list: anytype, active: []const bool, active_count: usize) !void {
    var first: ?usize = null;
    for (active, 0..) |is_active, position| {
        if (!is_active) continue;
        if (first == null) first = position;
        var expected = position;
        while (true) {
            expected = if (expected + 1 == active.len) 0 else expected + 1;
            if (active[expected]) break;
        }
        try std.testing.expectEqual(expected, list.next(position));
    }
    var observed = first.?;
    for (0..active_count) |_| observed = list.next(observed);
    try std.testing.expectEqual(first.?, observed);
}

test "property: packed next-with-skip matches a scalar circular set" {
    try hypothesis.checkNamed(SkipListProperty, "simd-autotune-skip-list-model", run.settings());
}

test "property: robust cost estimates are homogeneous under binary scaling" {
    try hypothesis.checkNamed(
        DistributionScaleProperty,
        "simd-autotune-cost-binary-scale",
        run.settings(),
    );
}

test "property: exhaustive auto-tuning selects the first minimum fixed cost" {
    try hypothesis.checkNamed(
        ExhaustiveTuningProperty,
        "simd-autotune-exhaustive-minimum",
        run.settings(),
    );
}
