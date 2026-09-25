const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D = simd.FixedTag(u32, 8);
const query_count: usize = 262_157;
const build_key_count: usize = 60_000;
const build_scratch_count: usize = 664_824;
const build_entry_count: usize = simd.cuckoo2x2.minimum_bucket_count;

var query_input: [query_count]u32 = undefined;
var query_output: [query_count]u8 = undefined;
var build_keys: [build_key_count]u32 = undefined;
var build_scratch: [build_scratch_count]u32 = undefined;
var build_entries: [build_entry_count]u32 = undefined;
var query_set: simd.Cuckoo2x2 = undefined;
var expected_query: u64 = 0;
var expected_build: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    const permutation = simd.Triple32.initKey(0x3243_5543);
    for (&build_keys, 0..) |*key, index| key.* = permutation.hash(@intCast(index));
    for (&query_input, 0..) |*key, index| {
        key.* = if (index & 1 == 0)
            build_keys[index % build_keys.len]
        else
            permutation.hash(@intCast(build_keys.len + index));
    }
    const data = buildPipeline() catch @panic("Cuckoo2x2 benchmark build failed");
    query_set = simd.Cuckoo2x2.init(data);
    expected_build = checksumData(data);
    vectorPipeline();
    expected_query = checksum(u8, &query_output);
}

pub fn scalar(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.cuckoo2x2.scalar", @src());
        defer phase.end();
        scalarPipeline();
    }
    if (checksum(u8, &query_output) != expected_query) @panic("scalar Cuckoo2x2 witness failed");
    std.mem.doNotOptimizeAway(&query_output);
    bench.coz.progressNamed("simd.cuckoo2x2.scalar.complete");
}

pub fn vector(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.cuckoo2x2.u32x8", @src());
        defer phase.end();
        vectorPipeline();
    }
    if (checksum(u8, &query_output) != expected_query) @panic("vector Cuckoo2x2 witness failed");
    std.mem.doNotOptimizeAway(&query_output);
    bench.coz.progressNamed("simd.cuckoo2x2.u32x8.complete");
}

pub fn build(_: std.mem.Allocator) void {
    const data = blk: {
        const phase = bench.phaseAt("simd.cuckoo2x2.build", @src());
        defer phase.end();
        break :blk buildPipeline() catch @panic("Cuckoo2x2 benchmark build failed");
    };
    if (checksumData(data) != expected_build) @panic("Cuckoo2x2 build witness failed");
    std.mem.doNotOptimizeAway(&data);
    bench.coz.progressNamed("simd.cuckoo2x2.build.complete");
}

fn scalarPipeline() void {
    for (query_input, &query_output) |key, *output| {
        output.* = @intFromBool(query_set.contains(key));
    }
}

fn vectorPipeline() void {
    var index: usize = 0;
    while (index + D.lane_count <= query_count) : (index += D.lane_count) {
        const input: D.Vector = query_input[index..][0..D.lane_count].*;
        const found = query_set.containsVec(D, input);
        inline for (0..D.lane_count) |lane| query_output[index + lane] = @intFromBool(found[lane]);
    }
    for (query_input[index..], query_output[index..]) |key, *output| {
        output.* = @intFromBool(query_set.contains(key));
    }
}

fn buildPipeline() !simd.Cuckoo2x2Data {
    const plan = try simd.Cuckoo2x2Plan.inspect(build_keys.len);
    if (plan.scratch_len > build_scratch.len) return error.BenchmarkScratchTooSmall;
    if (plan.entries_len > build_entries.len) return error.BenchmarkEntriesTooSmall;
    return plan.build(
        build_scratch[0..plan.scratch_len],
        build_entries[0..plan.entries_len],
        &build_keys,
    );
}

fn checksumData(data: simd.Cuckoo2x2Data) u64 {
    var result = checksum(u32, data.entries);
    result ^= data.config.bucket_mask;
    result *%= 0x0000_0100_0000_01b3;
    result ^= data.config.hash_key;
    result *%= 0x0000_0100_0000_01b3;
    result ^= data.num_primary;
    result *%= 0x0000_0100_0000_01b3;
    result ^= data.num_secondary;
    return result;
}

fn checksum(comptime T: type, values: []const T) u64 {
    var result: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| result = (result ^ @as(u64, value)) *% 0x0000_0100_0000_01b3;
    return result;
}
