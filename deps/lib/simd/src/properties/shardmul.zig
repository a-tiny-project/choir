const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const D32 = simd.FixedTag(u32, 8);
const D64 = simd.FixedTag(u64, 4);
const max_keys: usize = 65;
const max_extras: usize = 32;
const max_scratch: usize = max_keys + max_extras + 128;

pub const ShardMulProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const key_seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const extra_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const key_count: usize = @intCast(try data.drawInteger(1, max_keys, 0));
        const extra_count: usize = @intCast(try data.drawInteger(0, max_extras, 0));
        const key_hash = simd.Moremur.initKey(key_seed);
        const extra_hash = simd.Triple32.initKey(extra_seed);
        var keys: [max_keys]u64 = undefined;
        var extras: [max_extras]u32 = undefined;
        for (keys[0..key_count], 0..) |*key, index| key.* = key_hash.hash(index);
        for (extras[0..extra_count], 0..) |*extra, index| {
            extra.* = extra_hash.hash(@intCast(index));
        }

        const plan = try simd.ShardMulPlan.inspect(keys[0..key_count], extras[0..extra_count]);
        try std.testing.expect(plan.scratch_len <= max_scratch);
        try std.testing.expectEqual(
            plan.scratch_len,
            try simd.shardMulScratchLen(keys[0..key_count], extras[0..extra_count]),
        );
        var scratch: [max_scratch]u64 = undefined;
        var replay_scratch: [max_scratch]u64 = undefined;
        const built = try plan.build(
            scratch[0..plan.scratch_len],
            keys[0..key_count],
            extras[0..extra_count],
        );
        const replayed = try plan.build(
            replay_scratch[0..plan.scratch_len],
            keys[0..key_count],
            extras[0..extra_count],
        );
        try std.testing.expectEqual(built, replayed);
        const shard = simd.ShardMul.init(built);
        try std.testing.expect(!shard.isEmpty());

        var outputs: [max_keys]u32 = undefined;
        for (keys[0..key_count], outputs[0..key_count], 0..) |key, *output, index| {
            output.* = shard.hash(key);
            const pair = shard.feistel(key);
            try std.testing.expectEqual(simd.ShardMul.bucketIndex(pair.left), output.* >> 28);
            for (outputs[0..index]) |prior| try std.testing.expect(output.* != prior);
            for (extras[0..extra_count]) |extra| try std.testing.expect(output.* != extra);
        }

        var offset: usize = 0;
        while (offset + D32.lane_count <= key_count) : (offset += D32.lane_count) {
            const first: D64.Vector = keys[offset..][0..D64.lane_count].*;
            const second: D64.Vector = keys[offset + D64.lane_count ..][0..D64.lane_count].*;
            const vector: [D32.lane_count]u32 = shard.twoVec(D32, first, second);
            try std.testing.expectEqualSlices(u32, outputs[offset..][0..D32.lane_count], &vector);
        }
        if (key_count >= D64.lane_count) {
            const input: D64.Vector = keys[0..D64.lane_count].*;
            const vector: [D64.lane_count]u32 = shard.oneVec(D64, input);
            try std.testing.expectEqualSlices(u32, outputs[0..D64.lane_count], &vector);
        }
    }
};

test "property: ShardMul builds deterministic collision-free scalar and vector reducers" {
    try hypothesis.checkNamed(ShardMulProperty, "simd-shardmul", run.settings());
}
