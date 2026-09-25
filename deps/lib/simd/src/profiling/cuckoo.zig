const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const Family = simd.DefaultCuckoo;
const U16Family = simd.CuckooFamily(simd.WeakTwoMul, 16, 262_144);
const D = simd.FixedTag(u32, 8);
const query_count: usize = 262_157;
const key_count: usize = 60_000;
const optimized_key_count: usize = 63_000;
const slot_count: usize = 131_072;
const build_scratch_count: usize = 923_355;
const u16_slot_count: usize = 4_194_304;
const u16_build_scratch_count: usize = 4_816_448;

var keys: [optimized_key_count]u32 = undefined;
var query_input: [query_count]u32 = undefined;
var query_output: [query_count]u8 = undefined;
var query_slots: [slot_count]u32 = undefined;
var build_slots: [slot_count]u32 = undefined;
var build_scratch: [build_scratch_count]u32 = undefined;
var u16_source_slots: [u16_slot_count]u32 = undefined;
var u16_build_scratch: [u16_build_scratch_count]u32 = undefined;
var fingerprint_slots: [u16_slot_count]u16 = undefined;
var table: Family.Table = undefined;
var build_plan: Family.BuildPlan = undefined;
var matching_builder: Family.Builder = undefined;
var optimized_builder: Family.Optimizer = undefined;
var local_search: Family.LocalSearch = undefined;
var matching_primary: Family.Hash = undefined;
var matching_secondary: Family.Hash = undefined;
var local_primary: Family.Hash = undefined;
var local_secondary: Family.Hash = undefined;
var u16_source: U16Family.Table = undefined;
var u16_table: U16Family.Table = undefined;
var expected_build: u64 = 0;
var expected_matching: u64 = 0;
var expected_optimized: u64 = 0;
var expected_local: u64 = 0;
var expected_query: u64 = 0;
var expected_u16_query: u64 = 0;
var expected_fingerprints: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    const permutation = simd.Triple32.initKey(0x4355_434b);
    for (&keys, 0..) |*key, index| key.* = permutation.hash(@intCast(index));
    for (&query_input, 0..) |*key, index| {
        key.* = if (index & 1 == 0)
            keys[index % key_count]
        else
            permutation.hash(@intCast(key_count + index));
    }
    build_plan = Family.BuildPlan.inspect(key_count, 0.25) catch
        @panic("Cuckoo build plan failed");
    var query_stats: simd.CuckooBuildStats = .{};
    table = build_plan.build(
        &build_scratch,
        &query_slots,
        keys[0..key_count],
        200,
        &query_stats,
    ) catch
        @panic("Cuckoo query table build failed");
    const u16_plan = U16Family.BuildPlan.inspect(key_count, 0.25) catch
        @panic("Cuckoo u16 build plan failed");
    var u16_stats: simd.CuckooBuildStats = .{};
    u16_source = u16_plan.build(
        &u16_build_scratch,
        &u16_source_slots,
        keys[0..key_count],
        200,
        &u16_stats,
    ) catch @panic("Cuckoo u16 table build failed");
    u16_table = u16_source.buildU16Slots(&fingerprint_slots) catch
        @panic("Cuckoo u16 conversion failed");
    batchPipeline(false);
    expected_query = checksum(u8, &query_output);
    batchU16Pipeline(false);
    expected_u16_query = checksum(u8, &query_output);
    expected_fingerprints = checksum(u16, &fingerprint_slots);
    prepareBuildWitnesses();
}

fn prepareBuildWitnesses() void {
    var build_stats: simd.CuckooBuildStats = .{};
    const built = build_plan.build(
        &build_scratch,
        &build_slots,
        keys[0..key_count],
        200,
        &build_stats,
    ) catch
        @panic("Cuckoo build benchmark setup failed");
    expected_build = buildChecksum(built, build_stats);
    const matching_config = Family.Config.init(key_count, 0.01) catch
        @panic("Cuckoo matching config failed");
    const optimized_plan = Family.OptimizedBuildPlan.inspect(optimized_key_count, 0.01) catch
        @panic("Cuckoo optimized plan failed");
    if (optimized_plan.scratch_len != build_scratch.len) {
        @panic("Cuckoo optimized scratch capacity drifted");
    }
    matching_builder = Family.Builder.init(matching_config, &build_scratch) catch
        @panic("Cuckoo matching scratch failed");
    const engine = simd.AesCtrEngine.initDeterministic();
    matching_primary = Family.Hash.initSeed(&engine, 0);
    matching_secondary = Family.Hash.initSeed(&engine, 1);
    var matching_stats: simd.CuckooBuildStats = .{};
    if (!(matching_builder.build(
        keys[0..key_count],
        matching_primary,
        matching_secondary,
        &matching_stats,
    ) catch @panic("Cuckoo matching setup failed"))) @panic("Cuckoo matching failed");
    if (matching_stats.num_unmatched_after_greedy == 0) @panic("Cuckoo matching not exercised");
    const matched = matching_builder.take(keys[0..key_count], &build_slots) catch
        @panic("Cuckoo matching table setup failed");
    expected_matching = buildChecksum(matched, matching_stats);
    optimized_builder = Family.Optimizer.init(optimized_plan.config, &build_scratch) catch
        @panic("Cuckoo optimized scratch failed");
    var optimized_stats: simd.CuckooBuildStats = .{ .collect_path_cost_stats = true };
    if (!(optimized_builder.build(
        keys[0..optimized_key_count],
        matching_primary,
        matching_secondary,
        &optimized_stats,
    ) catch @panic("Cuckoo optimized setup failed"))) @panic("Cuckoo optimized failed");
    if (optimized_stats.paths_per_path_cost.len < 3) {
        @panic("Cuckoo optimized path costs not exercised");
    }
    const optimized = optimized_builder.take(keys[0..optimized_key_count], &build_slots) catch
        @panic("Cuckoo optimized table setup failed");
    expected_optimized = buildChecksum(optimized, optimized_stats);
    const local_plan = Family.LocalBuildPlan.inspect(key_count, 0.01) catch
        @panic("Cuckoo local search plan failed");
    if (local_plan.scratch_len > build_scratch.len) {
        @panic("Cuckoo local search scratch capacity drifted");
    }
    var seed_stats: simd.CuckooBuildStats = .{};
    _ = local_plan.build(
        &build_scratch,
        &build_slots,
        keys[0..key_count],
        200,
        &seed_stats,
    ) catch @panic("Cuckoo local search seed failed");
    local_search = Family.LocalSearch.init(local_plan.config, &build_scratch) catch
        @panic("Cuckoo local search scratch failed");
    local_primary = Family.Hash.initSeed(&engine, @as(u64, seed_stats.global_seed) * 2);
    local_secondary = Family.Hash.initSeed(&engine, @as(u64, seed_stats.global_seed) * 2 + 1);
    var local_stats: simd.CuckooBuildStats = .{};
    if (!(local_search.build(
        keys[0..key_count],
        local_primary,
        local_secondary,
        &local_stats,
    ) catch @panic("Cuckoo local search setup failed"))) {
        @panic("Cuckoo local search found no matching");
    }
    if (local_stats.num_unmatched_after_greedy == 0 or local_search.moves_used == 0) {
        @panic("Cuckoo local search not exercised");
    }
    const local = local_search.take(keys[0..key_count], &build_slots) catch
        @panic("Cuckoo local search table setup failed");
    expected_local = buildChecksum(local, local_stats);
}

pub fn buildDefault(_: std.mem.Allocator) void {
    var stats: simd.CuckooBuildStats = .{};
    const built = blk: {
        const phase = bench.phaseAt("simd.cuckoo.build", @src());
        defer phase.end();
        break :blk build_plan.build(
            &build_scratch,
            &build_slots,
            keys[0..key_count],
            200,
            &stats,
        ) catch
            @panic("Cuckoo build benchmark failed");
    };
    verifyBuild(built, stats, expected_build, "Cuckoo build witness failed");
    bench.coz.progressNamed("simd.cuckoo.build.complete");
}

pub fn buildMaximum(_: std.mem.Allocator) void {
    var stats: simd.CuckooBuildStats = .{};
    const built = blk: {
        const phase = bench.phaseAt("simd.cuckoo.match", @src());
        defer phase.end();
        const matched = matching_builder.build(
            keys[0..key_count],
            matching_primary,
            matching_secondary,
            &stats,
        ) catch @panic("Cuckoo matching benchmark failed");
        if (!matched) @panic("Cuckoo matching benchmark found no matching");
        break :blk matching_builder.take(keys[0..key_count], &build_slots) catch
            @panic("Cuckoo matching benchmark table failed");
    };
    verifyBuild(built, stats, expected_matching, "Cuckoo matching witness failed");
    bench.coz.progressNamed("simd.cuckoo.match.complete");
}

pub fn buildMinimumCost(_: std.mem.Allocator) void {
    var stats: simd.CuckooBuildStats = .{ .collect_path_cost_stats = true };
    const built = blk: {
        const phase = bench.phaseAt("simd.cuckoo.optimize", @src());
        defer phase.end();
        const matched = optimized_builder.build(
            keys[0..optimized_key_count],
            matching_primary,
            matching_secondary,
            &stats,
        ) catch @panic("Cuckoo optimized benchmark failed");
        if (!matched) @panic("Cuckoo optimized benchmark found no matching");
        break :blk optimized_builder.take(keys[0..optimized_key_count], &build_slots) catch
            @panic("Cuckoo optimized benchmark table failed");
    };
    verifyBuild(built, stats, expected_optimized, "Cuckoo optimized witness failed");
    bench.coz.progressNamed("simd.cuckoo.optimize.complete");
}

pub fn buildLocalSearch(_: std.mem.Allocator) void {
    var stats: simd.CuckooBuildStats = .{};
    const built = blk: {
        const phase = bench.phaseAt("simd.cuckoo.local", @src());
        defer phase.end();
        const matched = local_search.build(
            keys[0..key_count],
            local_primary,
            local_secondary,
            &stats,
        ) catch @panic("Cuckoo local search benchmark failed");
        if (!matched) @panic("Cuckoo local search benchmark found no matching");
        break :blk local_search.take(keys[0..key_count], &build_slots) catch
            @panic("Cuckoo local search benchmark table failed");
    };
    verifyBuild(built, stats, expected_local, "Cuckoo local search witness failed");
    bench.coz.progressNamed("simd.cuckoo.local.complete");
}

pub fn scalar(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.cuckoo.scalar", @src());
        defer phase.end();
        scalarPipeline();
    }
    verifyQuery(expected_query, "scalar Cuckoo witness failed");
    bench.coz.progressNamed("simd.cuckoo.scalar.complete");
}

pub fn batch(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.cuckoo.batch", @src());
        defer phase.end();
        batchPipeline(false);
    }
    verifyQuery(expected_query, "batch Cuckoo witness failed");
    bench.coz.progressNamed("simd.cuckoo.batch.complete");
}

pub fn batchPrecomputed(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.cuckoo.batch.precomputed", @src());
        defer phase.end();
        batchPipeline(true);
    }
    verifyQuery(expected_query, "precomputed batch Cuckoo witness failed");
    bench.coz.progressNamed("simd.cuckoo.batch.precomputed.complete");
}

pub fn scalarU16(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.cuckoo.u16.scalar", @src());
        defer phase.end();
        scalarU16Pipeline();
    }
    verifyQuery(expected_u16_query, "scalar u16 Cuckoo witness failed");
    bench.coz.progressNamed("simd.cuckoo.u16.scalar.complete");
}

pub fn batchU16(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.cuckoo.u16.batch", @src());
        defer phase.end();
        batchU16Pipeline(false);
    }
    verifyQuery(expected_u16_query, "batch u16 Cuckoo witness failed");
    bench.coz.progressNamed("simd.cuckoo.u16.batch.complete");
}

pub fn convertU16(_: std.mem.Allocator) void {
    const converted = blk: {
        const phase = bench.phaseAt("simd.cuckoo.u16.convert", @src());
        defer phase.end();
        break :blk u16_source.buildU16Slots(&fingerprint_slots) catch
            @panic("Cuckoo u16 conversion failed");
    };
    if (checksum(u16, converted.fingerprints()) != expected_fingerprints) {
        @panic("Cuckoo u16 conversion witness failed");
    }
    std.mem.doNotOptimizeAway(&converted);
    bench.coz.progressNamed("simd.cuckoo.u16.convert.complete");
}

fn scalarPipeline() void {
    for (query_input, &query_output) |key, *output| {
        output.* = @intFromBool(table.queryOne(key));
    }
}

fn batchPipeline(comptime precompute_secondary: bool) void {
    var index: usize = 0;
    while (index + D.lane_count <= query_count) : (index += D.lane_count) {
        const input: D.Vector = query_input[index..][0..D.lane_count].*;
        const not_found = table.queryBatch(precompute_secondary, D, input);
        inline for (0..D.lane_count) |lane| {
            query_output[index + lane] = @intFromBool(!not_found[lane]);
        }
    }
    for (query_input[index..], query_output[index..]) |key, *output| {
        output.* = @intFromBool(table.queryOne(key));
    }
}

fn scalarU16Pipeline() void {
    for (query_input, &query_output) |key, *output| {
        output.* = @intFromBool(u16_table.queryOneU16(key) catch unreachable);
    }
}

fn batchU16Pipeline(comptime precompute_secondary: bool) void {
    var index: usize = 0;
    while (index + D.lane_count <= query_count) : (index += D.lane_count) {
        const input: D.Vector = query_input[index..][0..D.lane_count].*;
        const not_found = u16_table.queryBatchU16(precompute_secondary, D, input) catch
            unreachable;
        inline for (0..D.lane_count) |lane| {
            query_output[index + lane] = @intFromBool(!not_found[lane]);
        }
    }
    for (query_input[index..], query_output[index..]) |key, *output| {
        output.* = @intFromBool(u16_table.queryOneU16(key) catch unreachable);
    }
}

fn verifyQuery(expected: u64, message: []const u8) void {
    if (checksum(u8, &query_output) != expected) @panic(message);
    std.mem.doNotOptimizeAway(&query_output);
}

fn verifyBuild(
    built: Family.Table,
    stats: simd.CuckooBuildStats,
    expected: u64,
    message: []const u8,
) void {
    if (buildChecksum(built, stats) != expected) @panic(message);
    std.mem.doNotOptimizeAway(&built);
}

fn buildChecksum(built: Family.Table, stats: simd.CuckooBuildStats) u64 {
    var result = checksum(u32, built.slots());
    result = (result ^ stats.num_primary) *% 0x0000_0100_0000_01b3;
    result = (result ^ stats.global_seed) *% 0x0000_0100_0000_01b3;
    result = (result ^ stats.attempts) *% 0x0000_0100_0000_01b3;
    result = (result ^ stats.num_unmatched_after_greedy) *% 0x0000_0100_0000_01b3;
    for (stats.paths_per_path_cost) |count| {
        result = (result ^ count) *% 0x0000_0100_0000_01b3;
    }
    return result;
}

fn checksum(comptime T: type, values: []const T) u64 {
    var result: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| result = (result ^ @as(u64, value)) *% 0x0000_0100_0000_01b3;
    return result;
}
