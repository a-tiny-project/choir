const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const D = simd.FixedTag(u32, 8);
const max_keys: usize = 129;
const max_scratch: usize = 589_986;
const max_entries: usize = simd.cuckoo2x2.minimum_bucket_count;

var property_scratch: [max_scratch]u32 = undefined;
var property_entries: [max_entries]u32 = undefined;

pub const Cuckoo2x2Property = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const seed: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const key_count: usize = @intCast(try data.drawInteger(1, max_keys, 0));
        const permutation = simd.Triple32.initKey(seed);
        var keys: [max_keys]u32 = undefined;
        var absent: [max_keys]u32 = undefined;
        for (keys[0..key_count], 0..) |*key, index| key.* = permutation.hash(@intCast(index));
        for (absent[0..key_count], 0..) |*key, index| {
            key.* = permutation.hash(@intCast(max_keys + index));
        }

        const plan = try simd.Cuckoo2x2Plan.inspect(key_count);
        try std.testing.expect(plan.scratch_len <= property_scratch.len);
        try std.testing.expect(plan.entries_len <= property_entries.len);
        try std.testing.expectEqual(plan.scratch_len, try simd.cuckoo2x2ScratchLen(key_count));
        try std.testing.expectEqual(plan.entries_len, try simd.cuckoo2x2EntriesLen(key_count));
        const built = try plan.build(
            property_scratch[0..plan.scratch_len],
            property_entries[0..plan.entries_len],
            keys[0..key_count],
        );
        const first_digest = digest(built.entries);
        const first_config = built.config;
        const first_config_idx = built.config_idx;
        const first_attempt_idx = built.attempt_idx;
        const first_primary = built.num_primary;
        const first_secondary = built.num_secondary;
        const replayed = try plan.build(
            property_scratch[0..plan.scratch_len],
            property_entries[0..plan.entries_len],
            keys[0..key_count],
        );
        try std.testing.expectEqual(first_config, replayed.config);
        try std.testing.expectEqual(first_config_idx, replayed.config_idx);
        try std.testing.expectEqual(first_attempt_idx, replayed.attempt_idx);
        try std.testing.expectEqual(first_primary, replayed.num_primary);
        try std.testing.expectEqual(first_secondary, replayed.num_secondary);
        try std.testing.expectEqual(first_digest, digest(replayed.entries));
        try std.testing.expectEqual(key_count, replayed.num_primary + replayed.num_secondary);

        const set = simd.Cuckoo2x2.init(replayed);
        for (keys[0..key_count]) |key| try std.testing.expect(set.contains(key));
        for (absent[0..key_count]) |key| try std.testing.expect(!set.contains(key));
        var offset: usize = 0;
        while (offset + D.lane_count <= key_count) : (offset += D.lane_count) {
            const present: D.Vector = keys[offset..][0..D.lane_count].*;
            const missing: D.Vector = absent[offset..][0..D.lane_count].*;
            try std.testing.expect(@reduce(.And, set.containsVec(D, present)));
            try std.testing.expect(@reduce(.And, set.query(D, missing)));
        }

        var occupied: usize = 0;
        for (replayed.entries) |entry| {
            if (entry == 0) continue;
            occupied += 1;
            const low: u16 = @truncate(entry);
            const high: u16 = @truncate(entry >> 16);
            const low_tag = low >> 14;
            const high_tag = high >> 14;
            try std.testing.expect(low_tag == 1 or low_tag == 2);
            try std.testing.expect(high_tag == 1 or high_tag == 2);
        }
        try std.testing.expect(occupied <= key_count);
    }
};

fn digest(entries: []const u32) u64 {
    var result: u64 = 1_469_598_103_934_665_603;
    for (entries) |entry| result = (result ^ entry) *% 1_099_511_628_211;
    return result;
}

test "property: Cuckoo2x2 preserves deterministic exact membership" {
    try hypothesis.checkNamed(Cuckoo2x2Property, "simd-cuckoo2x2", run.settings());
}
