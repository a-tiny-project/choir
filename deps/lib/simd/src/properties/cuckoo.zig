const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const Family = simd.CuckooFamily(simd.WeakTwoMul, 16, 16);
const D = simd.FixedTag(u32, 8);
const max_keys: usize = 129;
const max_slots: usize = 256;
const max_scratch: usize = max_keys * 6 + max_slots + Family.minimum_bucket_count;

var property_slots: [max_slots]u32 = undefined;
var property_scratch: [max_scratch]u32 = undefined;

pub const CuckooTableProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const key_count: usize = @intCast(try data.drawInteger(0, max_keys, 0));
        const permutation = simd.Triple32.initKey(seed);
        var keys: [max_keys]u32 = undefined;
        var absent: [max_keys]u32 = undefined;
        var source_index: u32 = 0;
        fillDistinct(permutation, &source_index, keys[0..key_count]);
        fillDistinct(permutation, &source_index, absent[0..key_count]);

        const built = try buildTable(keys[0..key_count]);
        const first_digest = digest(built.table.slots());
        const replayed = try buildTable(keys[0..key_count]);
        try std.testing.expectEqual(first_digest, digest(replayed.table.slots()));
        try std.testing.expectEqual(built.stats, replayed.stats);
        try std.testing.expectEqual(key_count == 0, replayed.table.isEmpty());
        try std.testing.expect(std.math.isPowerOfTwo(replayed.table.config.num_buckets));
        try std.testing.expectEqual(
            replayed.table.config.num_buckets * Family.bucket_size,
            replayed.table.config.num_slots,
        );
        try std.testing.expect(replayed.stats.success);
        try std.testing.expect(replayed.stats.attempts >= 1);
        try std.testing.expect(replayed.stats.attempts <= 100);
        try std.testing.expectEqual(replayed.table.num_primary, replayed.stats.num_primary);

        var occupied: usize = 0;
        for (replayed.table.slots(), 0..) |slot, slot_index| {
            if (slot == Family.empty_key) continue;
            occupied += 1;
            const lookup = replayed.table.lookupOneSlot(slot);
            const bucket_offset = slot_index / Family.bucket_size * Family.bucket_size;
            try std.testing.expect(
                bucket_offset == lookup.primary_slot or bucket_offset == lookup.secondary_slot,
            );
        }
        try std.testing.expectEqual(key_count, occupied);
        for (keys[0..key_count]) |key| try std.testing.expect(replayed.table.queryOne(key));
        for (absent[0..key_count]) |key| try std.testing.expect(!replayed.table.queryOne(key));

        var offset: usize = 0;
        while (offset + D.lane_count <= key_count) : (offset += D.lane_count) {
            const present: D.Vector = keys[offset..][0..D.lane_count].*;
            const missing: D.Vector = absent[offset..][0..D.lane_count].*;
            try std.testing.expect(!@reduce(.Or, replayed.table.queryBatch(false, D, present)));
            try std.testing.expect(!@reduce(.Or, replayed.table.queryBatch(true, D, present)));
            try std.testing.expect(@reduce(.And, replayed.table.queryBatch(false, D, missing)));
            try std.testing.expect(@reduce(.And, replayed.table.queryBatch(true, D, missing)));
            const vector = replayed.table.lookupSlotsAndHash(D, present);
            inline for (0..D.lane_count) |lane| {
                const scalar = replayed.table.lookupOneSlot(present[lane]);
                try std.testing.expectEqual(scalar.primary_hash, vector.primary_hashes[lane]);
                try std.testing.expectEqual(scalar.primary_slot, vector.primary_slots[lane]);
                try std.testing.expectEqual(scalar.secondary_slot, vector.secondary_slots[lane]);
            }
        }
    }
};

fn fillDistinct(permutation: simd.Triple32, source_index: *u32, output: []u32) void {
    for (output) |*key| {
        while (true) {
            const candidate = permutation.hash(source_index.*);
            source_index.* +%= 1;
            if (candidate != Family.empty_key) {
                key.* = candidate;
                break;
            }
        }
    }
}

const BuildResult = struct {
    table: Family.Table,
    stats: simd.CuckooBuildStats,
};

fn buildTable(keys: []const u32) !BuildResult {
    const plan = try Family.BuildPlan.inspect(keys.len, 0.25);
    try std.testing.expect(plan.slots_len <= property_slots.len);
    try std.testing.expect(plan.scratch_len <= property_scratch.len);
    var stats: simd.CuckooBuildStats = .{};
    const table = try plan.build(&property_scratch, &property_slots, keys, 100, &stats);
    return .{ .table = table, .stats = stats };
}

fn digest(slots: []const u32) u64 {
    var result: u64 = 1_469_598_103_934_665_603;
    for (slots) |slot| result = (result ^ slot) *% 1_099_511_628_211;
    return result;
}

test "property: generic Cuckoo tables preserve exact scalar and batch membership" {
    try hypothesis.checkNamed(CuckooTableProperty, "simd-cuckoo-table", run.settings());
}

const MatchFamily = simd.CuckooFamily(simd.WeakTwoMul, 2, 1);
const match_max_keys: usize = 8;
const match_max_slots: usize = 16;
const match_max_scratch: usize = match_max_keys * 6 + match_max_slots + 8;
const local_max_scratch: usize = match_max_keys * 3 + match_max_slots + 16;
const match_max_states: usize = 1 << match_max_slots;

var match_scratch: [match_max_scratch]u32 = undefined;
var local_scratch: [local_max_scratch]u32 = undefined;
var match_slots: [match_max_slots]u32 = undefined;
var match_states_first: [match_max_states]bool = undefined;
var match_states_second: [match_max_states]bool = undefined;
var match_costs_first: [match_max_states]u8 = undefined;
var match_costs_second: [match_max_states]u8 = undefined;
var optimized_scratch: [256]u32 = undefined;

pub const CuckooMaximumMatchingProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const key_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const primary_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const secondary_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const key_count: usize = @intCast(try data.drawInteger(0, match_max_keys, 0));
        const permutation = simd.Triple32.initKey(key_seed);
        var keys: [match_max_keys]u32 = undefined;
        var source_index: u32 = 0;
        fillDistinct(permutation, &source_index, keys[0..key_count]);
        const config = try MatchFamily.Config.init(key_count, 0);
        const primary = MatchFamily.Hash.initKey(primary_seed);
        const secondary = MatchFamily.Hash.initKey(secondary_seed);
        var cuckoo_builder = try MatchFamily.Builder.init(config, &match_scratch);
        const matched = try cuckoo_builder.build(keys[0..key_count], primary, secondary, null);
        const expected = exhaustiveMatching(keys[0..key_count], config, primary, secondary);
        try std.testing.expectEqual(expected, matched);
        if (!matched) return;
        const table = try cuckoo_builder.take(keys[0..key_count], &match_slots);
        var occupied: usize = 0;
        for (table.slots()) |slot| occupied += @intFromBool(slot != MatchFamily.empty_key);
        try std.testing.expectEqual(key_count, occupied);
        for (keys[0..key_count]) |key| try std.testing.expect(table.queryOne(key));
    }
};

fn exhaustiveMatching(
    keys: []const u32,
    config: MatchFamily.Config,
    primary: MatchFamily.Hash,
    secondary: MatchFamily.Hash,
) bool {
    const state_count = @as(usize, 1) << @intCast(config.num_slots);
    var current = match_states_first[0..state_count];
    var next = match_states_second[0..state_count];
    @memset(current, false);
    current[0] = true;
    for (keys) |key| {
        @memset(next, false);
        for (current, 0..) |reachable, occupied| {
            if (!reachable) continue;
            addCandidateStates(key, occupied, next, config, primary, secondary);
        }
        const previous = current;
        current = next;
        next = previous;
    }
    for (current) |reachable| if (reachable) return true;
    return false;
}

fn addCandidateStates(
    key: u32,
    occupied: usize,
    next: []bool,
    config: MatchFamily.Config,
    primary: MatchFamily.Hash,
    secondary: MatchFamily.Hash,
) void {
    const buckets = [2]u32{
        primary.hash(key) & config.bucket_mask,
        secondary.hash(key) & config.bucket_mask,
    };
    for (buckets) |bucket| {
        for (0..MatchFamily.bucket_size) |within_bucket| {
            const slot = @as(usize, bucket) * MatchFamily.bucket_size + within_bucket;
            const bit = @as(usize, 1) << @intCast(slot);
            if (occupied & bit == 0) next[occupied | bit] = true;
        }
    }
}

test "property: generic Cuckoo builder agrees with exhaustive maximum matching" {
    try hypothesis.checkNamed(
        CuckooMaximumMatchingProperty,
        "simd-cuckoo-maximum-matching",
        run.settings(),
    );
}

const LocalSearchResult = struct {
    matched: bool,
    digest: u64,
    moves_used: usize,
    move_limit: usize,
    num_unmatched_after_greedy: u32,
    num_primary: u32,
};

pub const CuckooLocalSearchProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const key_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const primary_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const secondary_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const key_count: usize = @intCast(try data.drawInteger(0, match_max_keys, 0));
        const permutation = simd.Triple32.initKey(key_seed);
        var keys: [match_max_keys]u32 = undefined;
        var source_index: u32 = 0;
        fillDistinct(permutation, &source_index, keys[0..key_count]);
        const config = try MatchFamily.Config.init(key_count, 0);
        const primary = MatchFamily.Hash.initKey(primary_seed);
        const secondary = MatchFamily.Hash.initKey(secondary_seed);
        const expected = exhaustiveMatching(keys[0..key_count], config, primary, secondary);
        const first = try runLocalSearch(keys[0..key_count], config, primary, secondary);
        const replayed = try runLocalSearch(keys[0..key_count], config, primary, secondary);
        try std.testing.expectEqual(first, replayed);
        try std.testing.expect(first.moves_used <= first.move_limit);
        if (!expected) try std.testing.expect(!first.matched);
        if (first.matched) {
            try std.testing.expect(expected);
            try std.testing.expect(first.moves_used < first.move_limit);
        }
    }
};

fn runLocalSearch(
    keys: []const u32,
    config: MatchFamily.Config,
    primary: MatchFamily.Hash,
    secondary: MatchFamily.Hash,
) !LocalSearchResult {
    var search = try MatchFamily.LocalSearch.init(config, &local_scratch);
    var stats: simd.CuckooBuildStats = .{};
    const matched = try search.build(keys, primary, secondary, &stats);
    if (!matched) {
        return .{
            .matched = false,
            .digest = 0,
            .moves_used = search.moves_used,
            .move_limit = search.move_limit,
            .num_unmatched_after_greedy = stats.num_unmatched_after_greedy,
            .num_primary = 0,
        };
    }
    const table = try search.take(keys, &match_slots);
    var occupied: usize = 0;
    for (table.slots(), 0..) |slot, slot_index| {
        if (slot == MatchFamily.empty_key) continue;
        occupied += 1;
        const lookup = table.lookupOneSlot(slot);
        const bucket_offset = slot_index / MatchFamily.bucket_size * MatchFamily.bucket_size;
        try std.testing.expect(
            bucket_offset == lookup.primary_slot or bucket_offset == lookup.secondary_slot,
        );
    }
    try std.testing.expectEqual(keys.len, occupied);
    for (keys) |key| try std.testing.expect(table.queryOne(key));
    return .{
        .matched = true,
        .digest = digest(table.slots()),
        .moves_used = search.moves_used,
        .move_limit = search.move_limit,
        .num_unmatched_after_greedy = stats.num_unmatched_after_greedy,
        .num_primary = table.num_primary,
    };
}

test "property: Cuckoo local search emits deterministic bounded valid matchings" {
    try hypothesis.checkNamed(
        CuckooLocalSearchProperty,
        "simd-cuckoo-local-search",
        run.settings(),
    );
}

pub const CuckooMinimumCostProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const key_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const primary_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const secondary_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const key_count: usize = @intCast(try data.drawInteger(0, match_max_keys, 0));
        const permutation = simd.Triple32.initKey(key_seed);
        var keys: [match_max_keys]u32 = undefined;
        var source_index: u32 = 0;
        fillDistinct(permutation, &source_index, keys[0..key_count]);
        const config = try MatchFamily.Config.init(key_count, 0);
        const primary = MatchFamily.Hash.initKey(primary_seed);
        const secondary = MatchFamily.Hash.initKey(secondary_seed);
        const expected = exhaustiveMinimumSecondary(
            keys[0..key_count],
            config,
            primary,
            secondary,
        );
        const plan = try MatchFamily.OptimizedBuildPlan.inspect(key_count, 0);
        try std.testing.expect(plan.scratch_len <= optimized_scratch.len);
        var stats: simd.CuckooBuildStats = .{ .collect_path_cost_stats = true };
        const result = plan.buildWithHashes(
            &optimized_scratch,
            &match_slots,
            keys[0..key_count],
            primary,
            secondary,
            &stats,
        );
        if (expected == null) {
            try std.testing.expectError(error.BuildFailed, result);
            return;
        }
        const table = try result;
        const minimum_secondary: u32 = expected.?;
        try std.testing.expect(stats.success);
        try std.testing.expectEqual(
            @as(u32, @intCast(key_count)) - minimum_secondary,
            stats.num_primary,
        );
        var paths_found: u32 = 0;
        var added_secondary: u32 = 0;
        for (stats.paths_per_path_cost, 0..) |count, cost| {
            paths_found += count;
            added_secondary += @as(u32, @intCast(cost)) * count;
        }
        try std.testing.expectEqual(stats.num_unmatched_after_greedy, paths_found);
        try std.testing.expectEqual(
            minimum_secondary,
            greedySecondaryCount(keys[0..key_count], config, primary, secondary) +
                added_secondary,
        );
        for (keys[0..key_count]) |key| try std.testing.expect(table.queryOne(key));
    }
};

fn exhaustiveMinimumSecondary(
    keys: []const u32,
    config: MatchFamily.Config,
    primary: MatchFamily.Hash,
    secondary: MatchFamily.Hash,
) ?u8 {
    const invalid: u8 = std.math.maxInt(u8);
    const state_count = @as(usize, 1) << @intCast(config.num_slots);
    var current = match_costs_first[0..state_count];
    var next = match_costs_second[0..state_count];
    @memset(current, invalid);
    current[0] = 0;
    for (keys) |key| {
        @memset(next, invalid);
        for (current, 0..) |cost, occupied| {
            if (cost == invalid) continue;
            addMinimumCostStates(key, occupied, cost, next, config, primary, secondary);
        }
        const previous = current;
        current = next;
        next = previous;
    }
    var minimum: u8 = invalid;
    for (current) |cost| minimum = @min(minimum, cost);
    return if (minimum == invalid) null else minimum;
}

fn addMinimumCostStates(
    key: u32,
    occupied: usize,
    cost: u8,
    next: []u8,
    config: MatchFamily.Config,
    primary: MatchFamily.Hash,
    secondary: MatchFamily.Hash,
) void {
    const primary_bucket = primary.hash(key) & config.bucket_mask;
    const secondary_bucket = secondary.hash(key) & config.bucket_mask;
    const buckets = [2]u32{ primary_bucket, secondary_bucket };
    for (buckets, 0..) |bucket, choice| {
        const added_cost: u8 = @intFromBool(choice == 1 and bucket != primary_bucket);
        for (0..MatchFamily.bucket_size) |within_bucket| {
            const slot = @as(usize, bucket) * MatchFamily.bucket_size + within_bucket;
            const bit = @as(usize, 1) << @intCast(slot);
            if (occupied & bit != 0) continue;
            const state = occupied | bit;
            next[state] = @min(next[state], cost + added_cost);
        }
    }
}

fn greedySecondaryCount(
    keys: []const u32,
    config: MatchFamily.Config,
    primary: MatchFamily.Hash,
    secondary: MatchFamily.Hash,
) u32 {
    var fills: [match_max_slots / MatchFamily.bucket_size]u8 = @splat(0);
    var matched: [match_max_keys]bool = @splat(false);
    for (keys, 0..) |key, key_index| {
        const bucket: usize = @intCast(primary.hash(key) & config.bucket_mask);
        if (fills[bucket] == MatchFamily.bucket_size) continue;
        fills[bucket] += 1;
        matched[key_index] = true;
    }
    var secondary_count: u32 = 0;
    for (keys, matched[0..keys.len]) |key, placed| {
        if (placed) continue;
        const bucket: usize = @intCast(secondary.hash(key) & config.bucket_mask);
        if (fills[bucket] == MatchFamily.bucket_size) continue;
        fills[bucket] += 1;
        secondary_count += 1;
    }
    return secondary_count;
}

test "property: optimized Cuckoo builder reaches exhaustive minimum cost" {
    try hypothesis.checkNamed(
        CuckooMinimumCostProperty,
        "simd-cuckoo-minimum-cost",
        run.settings(),
    );
}
