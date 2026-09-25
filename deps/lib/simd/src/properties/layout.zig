const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const D = simd.FixedTag(u32, 8);
const H = D.half();

fn drawVector(data: *hypothesis.ConjectureData) !D.Vector {
    var result: D.Vector = undefined;
    inline for (0..D.lane_count) |index| {
        result[index] = @truncate(try data.drawInteger(0, std.math.maxInt(u32), 0));
    }
    return result;
}

pub const LayoutProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const a = try drawVector(data);
        const b = try drawVector(data);
        const low = simd.lowerHalf(H, a);
        const high = simd.upperHalf(H, a);
        try std.testing.expect(@reduce(.And, simd.combine(D, high, low) == a));
        const interleaved_low = simd.interleaveWholeLower(D, a, b);
        const interleaved_high = simd.interleaveWholeUpper(D, a, b);
        inline for (0..D.lane_count / 2) |index| {
            try std.testing.expectEqual(a[index], interleaved_low[index * 2]);
            try std.testing.expectEqual(b[index], interleaved_low[index * 2 + 1]);
            try std.testing.expectEqual(a[D.lane_count / 2 + index], interleaved_high[index * 2]);
            try std.testing.expectEqual(b[D.lane_count / 2 + index], interleaved_high[index * 2 + 1]);
        }
    }
};

pub const ResizeProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawVector(data);
        const small = simd.resizeBitCast(H, value);
        const extended = simd.zeroExtendResizeBitCast(D, H, small);
        try std.testing.expect(@reduce(.And, simd.lowerHalf(H, extended) == small));
        try std.testing.expect(@reduce(.And, simd.upperHalf(H, extended) ==
            @as(H.Vector, @splat(0))));
    }
};

test "property: halves combine and whole interleaves preserve lanes" {
    try hypothesis.checkNamed(LayoutProperty, "simd-layout-lane-order", run.settings());
}

test "property: zero extending a resize preserves bytes and clears the tail" {
    try hypothesis.checkNamed(ResizeProperty, "simd-resize-zero-extension", run.settings());
}
