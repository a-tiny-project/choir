const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const D = simd.FixedTag(u32, 8);

fn drawVector(data: *hypothesis.ConjectureData) !D.Vector {
    var result: D.Vector = undefined;
    inline for (0..D.lane_count) |index| {
        result[index] = @truncate(try data.drawInteger(0, std.math.maxInt(u32), 0));
    }
    return result;
}

fn drawMask(data: *hypothesis.ConjectureData) !D.Mask {
    var result: D.Mask = undefined;
    inline for (0..D.lane_count) |index| result[index] = try data.drawBoolean();
    return result;
}

pub const CompactProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawVector(data);
        const mask = try drawMask(data);
        const compacted = simd.compress(D, value, mask);
        const restored = simd.expand(D, compacted, mask);
        const compacted_lanes: [D.lane_count]u32 = @bitCast(compacted);
        var selected: usize = 0;
        var rejected = simd.countTrue(D, mask);
        inline for (0..D.lane_count) |index| {
            if (mask[index]) {
                try std.testing.expectEqual(value[index], compacted_lanes[selected]);
                try std.testing.expectEqual(value[index], restored[index]);
                selected += 1;
            } else {
                try std.testing.expectEqual(value[index], compacted_lanes[rejected]);
                try std.testing.expectEqual(@as(u32, 0), restored[index]);
                rejected += 1;
            }
        }
        try std.testing.expectEqual(D.lane_count, rejected);
    }
};

pub const SwizzleProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawVector(data);
        try std.testing.expect(@reduce(.And, simd.reverse(D, simd.reverse(D, value)) == value));
        try std.testing.expect(@reduce(.And, simd.reverse2(D, simd.reverse2(D, value)) == value));
        try std.testing.expect(@reduce(.And, simd.reverse4(D, simd.reverse4(D, value)) == value));
        try std.testing.expect(@reduce(.And, simd.reverse8(D, simd.reverse8(D, value)) == value));
        try std.testing.expect(@reduce(.And, simd.oddEven(D, value, value) == value));
    }
};

pub const InterleavedProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const a = try drawVector(data);
        const b = try drawVector(data);
        const c = try drawVector(data);
        const d = try drawVector(data);
        var output: [D.lane_count * 4]u32 = undefined;
        simd.storeInterleaved4(D, a, b, c, d, &output);
        const restored = simd.loadInterleaved4(D, &output);
        try std.testing.expect(@reduce(.And, restored[0] == a));
        try std.testing.expect(@reduce(.And, restored[1] == b));
        try std.testing.expect(@reduce(.And, restored[2] == c));
        try std.testing.expect(@reduce(.And, restored[3] == d));
    }
};

pub const ReductionProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawVector(data);
        const mask = try drawMask(data);
        var expected: u32 = 0;
        var masked: u32 = 0;
        inline for (0..D.lane_count) |index| {
            expected +%= value[index];
            if (mask[index]) masked +%= value[index];
        }
        try std.testing.expectEqual(expected, simd.reduceSum(D, value));
        try std.testing.expectEqual(masked, simd.maskedReduceSum(D, mask, value));
        try std.testing.expect(@reduce(.And, simd.sumOfLanes(D, value) == @as(D.Vector, @splat(expected))));
    }
};

pub const TableProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawVector(data);
        var indices: D.Vector = undefined;
        inline for (0..D.lane_count) |index| {
            indices[index] = @intCast(try data.drawInteger(0, D.lane_count - 1, 0));
        }
        const actual = simd.tableLookupLanes(D, value, indices);
        const lanes: [D.lane_count]u32 = @bitCast(value);
        inline for (0..D.lane_count) |index| {
            try std.testing.expectEqual(lanes[@intCast(indices[index])], actual[index]);
        }
    }
};

pub const SlideProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawVector(data);
        const amount: usize = @intCast(try data.drawInteger(0, D.lane_count, 0));
        const up = simd.slideUpLanes(D, value, amount);
        const down = simd.slideDownLanes(D, value, amount);
        const lanes: [D.lane_count]u32 = @bitCast(value);
        inline for (0..D.lane_count) |index| {
            const expected_up = if (index < amount) 0 else lanes[index - amount];
            const expected_down = if (index + amount < D.lane_count) lanes[index + amount] else 0;
            try std.testing.expectEqual(expected_up, up[index]);
            try std.testing.expectEqual(expected_down, down[index]);
        }
    }
};

test "property: compress and expand preserve stable selected ordering" {
    try hypothesis.checkNamed(CompactProperty, "simd-compact-stable", run.settings());
}

test "property: whole-vector reversals are involutions" {
    try hypothesis.checkNamed(SwizzleProperty, "simd-swizzle-involutions", run.settings());
}

test "property: interleaved memory round trips four channels" {
    try hypothesis.checkNamed(InterleavedProperty, "simd-interleaved-roundtrip", run.settings());
}

test "property: reductions agree with wrapping scalar folds" {
    try hypothesis.checkNamed(ReductionProperty, "simd-reduction-fold", run.settings());
}

test "property: lane table lookup matches bounded scalar gather" {
    try hypothesis.checkNamed(TableProperty, "simd-table-gather", run.settings());
}

test "property: whole-vector slides match zero-filled scalar movement" {
    try hypothesis.checkNamed(SlideProperty, "simd-slide-geometry", run.settings());
}
