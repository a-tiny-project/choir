const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const cost_count: usize = 4096;
const skip_count: usize = 4096;
const candidate_count: usize = 256;
const Tuner = simd.AutoTune(u16, candidate_count, 2);

var cost_source: [cost_count]f64 = undefined;
var skip_order: [skip_count]usize = undefined;
var candidates: [candidate_count]u16 = undefined;
var fixed_costs: [candidate_count]u64 = undefined;
var expected_cost: f64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    var expected = simd.CostDistribution{};
    for (&cost_source, 0..) |*value, index| {
        const offset: i32 = @intCast(((index * 37) ^ (index >> 3)) % 101);
        value.* = @floatFromInt(450 + offset);
        if (index % 32 == 0) value.* += 10_000;
        if (index % 64 == 1) value.* *= 0.75;
        expected.notify(value.*);
    }
    expected_cost = expected.estimateCost();
    for (&skip_order, 0..) |*position, index| position.* = index * 4051 % skip_count;
    for (&candidates, &fixed_costs, 0..) |*candidate, *cost, index| {
        candidate.* = @intCast(index);
        const distance = if (index < 73) 73 - index else index - 73;
        cost.* = 1_000 + 17 * distance;
    }
}

pub fn costDistribution(_: std.mem.Allocator) void {
    var distribution = simd.CostDistribution{};
    const observed = blk: {
        const phase = bench.phaseAt("simd.autotune.cost-distribution", @src());
        defer phase.end();
        for (cost_source) |cost| distribution.notify(cost);
        break :blk distribution.estimateCost();
    };
    if (observed != expected_cost) @panic("auto-tune cost distribution witness failed");
    std.mem.doNotOptimizeAway(&distribution);
    bench.coz.progressNamed("simd.autotune.cost-distribution.complete");
}

pub fn skipList(_: std.mem.Allocator) void {
    var list = simd.NextWithSkip(skip_count).init(skip_count);
    const survivor = blk: {
        const phase = bench.phaseAt("simd.autotune.skip-list", @src());
        defer phase.end();
        for (skip_order[0 .. skip_count - 1]) |position| list.skip(position);
        break :blk skip_order[skip_count - 1];
    };
    if (list.next(survivor) != survivor) @panic("auto-tune skip list witness failed");
    std.mem.doNotOptimizeAway(&list);
    bench.coz.progressNamed("simd.autotune.skip-list.complete");
}

pub fn exhaustiveTuning(_: std.mem.Allocator) void {
    var tuner = Tuner{};
    var calls: usize = 0;
    {
        const phase = bench.phaseAt("simd.autotune.exhaustive", @src());
        defer phase.end();
        tuner.setCandidates(&candidates) catch unreachable;
        while (tuner.best() == null) : (calls += 1) {
            const index = tuner.currentIndex();
            tuner.notifyCost(fixed_costs[index]);
        }
    }
    if (tuner.best().?.* != 73 or calls == 0 or calls > candidate_count * 4) {
        @panic("auto-tune exhaustive search witness failed");
    }
    std.mem.doNotOptimizeAway(&tuner);
    std.mem.doNotOptimizeAway(&calls);
    bench.coz.progressNamed("simd.autotune.exhaustive.complete");
}
