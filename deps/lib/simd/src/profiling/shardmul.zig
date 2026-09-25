const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D32 = simd.FixedTag(u32, 8);
const D64 = simd.FixedTag(u64, 4);
const query_count: usize = 262_157;
const build_key_count: usize = 8192;
const build_extra_count: usize = 1024;
const build_scratch_count: usize = 25_600;

var query_input: [query_count]u64 = undefined;
var query_output: [query_count]u32 = undefined;
var build_keys: [build_key_count]u64 = undefined;
var build_extras: [build_extra_count]u32 = undefined;
var build_scratch: [build_scratch_count]u64 = undefined;
var query_shard: simd.ShardMul = undefined;
var expected_query: u64 = 0;
var expected_build: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (&query_input, 0..) |*value, index| {
        value.* = index *% 0x9e37_79b9_7f4a_7c15 +% 0x1234_5678_9abc_def0;
    }
    const key_hash = simd.Moremur.initKey(0x5348_4152_444d_554c);
    const extra_hash = simd.Triple32.initKey(0x4558_5452);
    for (&build_keys, 0..) |*value, index| value.* = key_hash.hash(index);
    for (&build_extras, 0..) |*value, index| value.* = extra_hash.hash(@intCast(index));
    const data = buildPipeline() catch @panic("ShardMul benchmark build failed");
    if (simd.ShardMul.init(data).isEmpty()) @panic("ShardMul benchmark produced an empty reducer");
    query_shard = simd.ShardMul.init(data);
    expected_build = checksumData(data);
    vectorPipeline();
    expected_query = checksum(u32, &query_output);
}

pub fn scalar(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.shardmul.scalar", @src());
        defer phase.end();
        scalarPipeline();
    }
    if (checksum(u32, &query_output) != expected_query) @panic("scalar ShardMul witness failed");
    std.mem.doNotOptimizeAway(&query_output);
    bench.coz.progressNamed("simd.shardmul.scalar.complete");
}

pub fn vector(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.shardmul.u64x8", @src());
        defer phase.end();
        vectorPipeline();
    }
    if (checksum(u32, &query_output) != expected_query) @panic("vector ShardMul witness failed");
    std.mem.doNotOptimizeAway(&query_output);
    bench.coz.progressNamed("simd.shardmul.u64x8.complete");
}

pub fn build(_: std.mem.Allocator) void {
    const data = blk: {
        const phase = bench.phaseAt("simd.shardmul.build", @src());
        defer phase.end();
        break :blk buildPipeline() catch @panic("ShardMul benchmark build failed");
    };
    if (checksumData(data) != expected_build) @panic("ShardMul build witness failed");
    std.mem.doNotOptimizeAway(&data);
    bench.coz.progressNamed("simd.shardmul.build.complete");
}

fn scalarPipeline() void {
    for (query_input, &query_output) |input, *output| output.* = query_shard.hash(input);
}

fn vectorPipeline() void {
    var index: usize = 0;
    while (index + D32.lane_count <= query_count) : (index += D32.lane_count) {
        const first: D64.Vector = query_input[index..][0..D64.lane_count].*;
        const second: D64.Vector = query_input[index + D64.lane_count ..][0..D64.lane_count].*;
        const output: [D32.lane_count]u32 = query_shard.twoVec(D32, first, second);
        @memcpy(query_output[index..][0..D32.lane_count], &output);
    }
    for (query_input[index..], query_output[index..]) |input, *output| {
        output.* = query_shard.hash(input);
    }
}

fn buildPipeline() !simd.ShardMulData {
    const plan = try simd.ShardMulPlan.inspect(&build_keys, &build_extras);
    if (plan.scratch_len > build_scratch.len) return error.BenchmarkScratchTooSmall;
    return plan.build(build_scratch[0..plan.scratch_len], &build_keys, &build_extras);
}

fn checksumData(data: simd.ShardMulData) u64 {
    var result = checksum(u32, &data.table);
    result ^= checksum(u32, &data.keys);
    result *%= 0x0000_0100_0000_01b3;
    result ^= checksum(u32, &data.attempts);
    return result;
}

fn checksum(comptime T: type, values: []const T) u64 {
    var result: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| result = (result ^ @as(u64, value)) *% 0x0000_0100_0000_01b3;
    return result;
}
