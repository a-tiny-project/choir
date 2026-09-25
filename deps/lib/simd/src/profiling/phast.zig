const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D = simd.FixedTag(u32, 8);
const query_count: usize = 262_157;
const query_bucket_count: usize = 262_144;
const query_seed_word_count: usize = query_bucket_count / @sizeOf(u32);
const query_slot_count: usize = 300_001;
const query_slice_length: usize = 2_048;
const build_key_count: usize = 500;
const build_scratch_count: usize = 10_364;
const build_seed_word_count: usize = 64;

var query_input: [query_count]u32 = undefined;
var query_output: [query_count]u32 = undefined;
var query_seed_words: [query_seed_word_count]u32 = undefined;
var build_keys: [build_key_count]u32 = undefined;
var build_scratch: [build_scratch_count]u32 = undefined;
var build_seed_words: [build_seed_word_count]u32 = undefined;
var query_phast: simd.Phast = undefined;
var build_plan: simd.PhastBuildPlan = undefined;
var expected_query: u64 = 0;
var expected_build: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    const query_permutation = simd.Triple32.initKey(0x5155_4552);
    const seed_permutation = simd.Triple32.initKey(0x5345_4544);
    for (&query_input, 0..) |*key, index| key.* = query_permutation.hash(@intCast(index));
    for (&query_seed_words, 0..) |*word, index| {
        word.* = seed_permutation.hash(@intCast(index));
    }
    const query_config = simd.PhastConfig{
        .num_slots = query_slot_count,
        .hash_key = 0x5048_4153,
        .bucket_mask = query_bucket_count - 1,
        .placement = simd.PhastPlacement.init(
            query_slot_count,
            query_slice_length,
        ) catch @panic("PHAST query placement failed"),
    };
    query_phast = simd.Phast.init(.{
        .config = query_config,
        .seeds = .{ .words = &query_seed_words },
    }) catch @panic("PHAST query data failed");
    vectorPipeline();
    expected_query = checksum(u32, &query_output);

    const build_permutation = simd.Triple32.initKey(0);
    for (&build_keys, 0..) |*key, index| key.* = build_permutation.hash(@intCast(index));
    build_plan = simd.PhastBuildPlan.inspect(build_key_count, 0) catch
        @panic("PHAST build plan failed");
    if (build_plan.scratch_len != build_scratch.len or
        build_plan.seeds_len != build_seed_words.len)
    {
        @panic("PHAST build capacity drifted");
    }
    const built = buildPipeline() catch @panic("PHAST benchmark build failed");
    if (built.config_index == 0 or built.attempt_index == 0) {
        @panic("PHAST build retries not exercised");
    }
    expected_build = checksumData(built);
}

pub fn scalar(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.phast.scalar", @src());
        defer phase.end();
        scalarPipeline();
    }
    verifyQuery();
    bench.coz.progressNamed("simd.phast.scalar.complete");
}

pub fn vector(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.phast.u32x8", @src());
        defer phase.end();
        vectorPipeline();
    }
    verifyQuery();
    bench.coz.progressNamed("simd.phast.u32x8.complete");
}

pub fn build(_: std.mem.Allocator) void {
    const built = blk: {
        const phase = bench.phaseAt("simd.phast.build", @src());
        defer phase.end();
        break :blk buildPipeline() catch @panic("PHAST benchmark build failed");
    };
    if (checksumData(built) != expected_build) @panic("PHAST build witness failed");
    std.mem.doNotOptimizeAway(&built);
    bench.coz.progressNamed("simd.phast.build.complete");
}

fn scalarPipeline() void {
    for (query_input, &query_output) |key, *output| output.* = query_phast.index(key);
}

fn vectorPipeline() void {
    query_phast.indexBatch(D, &query_input, &query_output) catch
        @panic("PHAST vector query failed");
}

fn buildPipeline() !simd.PhastData {
    return build_plan.build(&build_scratch, &build_seed_words, &build_keys);
}

fn verifyQuery() void {
    if (checksum(u32, &query_output) != expected_query) @panic("PHAST query witness failed");
    std.mem.doNotOptimizeAway(&query_output);
}

fn checksumData(data: simd.PhastData) u64 {
    var result = checksum(u32, data.seeds.words);
    result = mix(result, data.config.num_slots);
    result = mix(result, data.config.hash_key);
    result = mix(result, data.config.bucket_mask);
    result = mix(result, data.config.placement.num_slice_offsets);
    result = mix(result, data.config.placement.slice_mask);
    result = mix(result, data.config_index);
    return mix(result, data.attempt_index);
}

fn checksum(comptime T: type, values: []const T) u64 {
    var result: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| result = mix(result, @as(u64, value));
    return result;
}

fn mix(digest: u64, value: anytype) u64 {
    return (digest ^ @as(u64, @intCast(value))) *% 0x0000_0100_0000_01b3;
}
