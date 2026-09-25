const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const D = simd.FixedTag(u32, 8);
const max_keys: usize = 48;
const max_slots: usize = 64;
const max_scratch: usize = 9_000;
const max_seed_words: usize = 8;

var first_scratch: [max_scratch]u32 = undefined;
var second_scratch: [max_scratch]u32 = undefined;
var first_seed_words: [max_seed_words]u32 = undefined;
var second_seed_words: [max_seed_words]u32 = undefined;

pub const PhastBuilderProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const key_seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const key_count: usize = @intCast(try data.drawInteger(1, max_keys, 1));
        const payload_bytes: usize = @intCast(try data.drawInteger(0, 16, 0));
        const permutation = simd.Triple32.initKey(key_seed);
        var keys: [max_keys]u32 = undefined;
        for (keys[0..key_count], 0..) |*key, index| key.* = permutation.hash(@intCast(index));

        const plan = try simd.PhastBuildPlan.inspect(key_count, payload_bytes);
        try std.testing.expect(plan.scratch_len <= first_scratch.len);
        try std.testing.expect(plan.seeds_len <= first_seed_words.len);
        try std.testing.expectEqual(
            plan.scratch_len,
            try simd.phastScratchLen(key_count, payload_bytes),
        );
        try std.testing.expectEqual(
            plan.seeds_len,
            try simd.phastSeedsLen(key_count, payload_bytes),
        );

        const built = try plan.build(
            first_scratch[0..plan.scratch_len],
            first_seed_words[0..plan.seeds_len],
            keys[0..key_count],
        );
        const replayed = try plan.build(
            second_scratch[0..plan.scratch_len],
            second_seed_words[0..plan.seeds_len],
            keys[0..key_count],
        );
        try verifyLayout(built, replayed, key_count, payload_bytes);

        const phast = try simd.Phast.init(built);
        const replayed_phast = try simd.Phast.init(replayed);
        var scalar: [max_keys]u32 = undefined;
        var batch: [max_keys]u32 = undefined;
        var occupied: [max_slots]bool = @splat(false);
        for (keys[0..key_count], scalar[0..key_count]) |key, *position| {
            position.* = phast.index(key);
            try std.testing.expectEqual(position.*, replayed_phast.index(key));
            try std.testing.expect(position.* < built.config.num_slots);
            try std.testing.expect(!occupied[position.*]);
            occupied[position.*] = true;
        }
        try phast.indexBatch(D, keys[0..key_count], batch[0..key_count]);
        try std.testing.expectEqualSlices(u32, scalar[0..key_count], batch[0..key_count]);
        var offset: usize = 0;
        while (offset + 2 * D.lane_count <= key_count) : (offset += 2 * D.lane_count) {
            const pair = phast.twoVec(
                D,
                keys[offset..][0..D.lane_count].*,
                keys[offset + D.lane_count ..][0..D.lane_count].*,
            );
            try std.testing.expect(@reduce(.And, pair.first ==
                @as(D.Vector, scalar[offset..][0..D.lane_count].*)));
            try std.testing.expect(@reduce(.And, pair.second ==
                @as(D.Vector, scalar[offset + D.lane_count ..][0..D.lane_count].*)));
        }
    }
};

fn verifyLayout(
    built: simd.PhastData,
    replayed: simd.PhastData,
    key_count: usize,
    payload_bytes: usize,
) !void {
    try std.testing.expectEqual(built.config, replayed.config);
    try std.testing.expectEqual(built.config_index, replayed.config_index);
    try std.testing.expectEqual(built.attempt_index, replayed.attempt_index);
    try std.testing.expectEqualSlices(u32, built.seeds.words, replayed.seeds.words);
    try std.testing.expectEqual(built.config.seedWordsLen(), built.seeds.words.len);
    try std.testing.expect(built.config.num_slots >= key_count);
    try std.testing.expect(built.config.num_slots <= max_slots);
    try std.testing.expect(std.math.isPowerOfTwo(built.config.numBuckets()));
    const payload = built.config.num_slots * payload_bytes;
    const seed_bytes = std.mem.alignForward(
        usize,
        built.config.numBuckets(),
        @sizeOf(u32),
    );
    try std.testing.expectEqual(payload + seed_bytes, try built.allocatedBytes(payload_bytes));
}

pub const PhastPlacementProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const slice_shift: u5 = @intCast(try data.drawInteger(0, 20, 0));
        const slice_length = @as(usize, 1) << slice_shift;
        const extra: usize = @intCast(try data.drawInteger(0, 1_000_000, 0));
        const num_slots = slice_length + extra;
        const placement = try simd.PhastPlacement.init(num_slots, slice_length);
        var first_hashes: D.Vector = undefined;
        var second_hashes: D.Vector = undefined;
        var first_seeds: D.Vector = undefined;
        var second_seeds: D.Vector = undefined;
        inline for (0..D.lane_count) |lane| {
            first_hashes[lane] = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
            second_hashes[lane] = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
            first_seeds[lane] = @intCast(try data.drawInteger(0, 255, 0));
            second_seeds[lane] = @intCast(try data.drawInteger(0, 255, 0));
        }
        const pair = simd.phastPositionPairFromHashesAndSeeds(
            placement,
            D,
            first_hashes,
            second_hashes,
            first_seeds,
            second_seeds,
        );
        inline for (0..D.lane_count) |lane| {
            const first = simd.phastPositionFromHashAndSeed(
                placement,
                first_hashes[lane],
                first_seeds[lane],
            );
            const second = simd.phastPositionFromHashAndSeed(
                placement,
                second_hashes[lane],
                second_seeds[lane],
            );
            try std.testing.expectEqual(first, pair.first[lane]);
            try std.testing.expectEqual(second, pair.second[lane]);
            try std.testing.expect(first < num_slots);
            try std.testing.expect(second < num_slots);
        }
    }
};

test "property: PHAST builds deterministic perfect scalar and vector maps" {
    try hypothesis.checkNamed(PhastBuilderProperty, "simd-phast-builder", run.settings());
}

test "property: PHAST scalar and paired placement agree and remain in range" {
    try hypothesis.checkNamed(PhastPlacementProperty, "simd-phast-placement", run.settings());
}
