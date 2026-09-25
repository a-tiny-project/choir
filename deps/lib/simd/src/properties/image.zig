const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;

pub const ImageLayoutProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const component_shift: u4 = @intCast(try data.drawInteger(0, 3, 0));
        const component_size = @as(usize, 1) << component_shift;
        const scalar = try data.drawBoolean();
        const vector_shift: u4 = @intCast(try data.drawInteger(
            component_shift,
            10,
            component_shift,
        ));
        const selected_vector_size = if (scalar) 1 else @as(usize, 1) << vector_shift;
        const width: usize = @intCast(try data.drawInteger(0, 1_000_000, 0));
        const stride = try simd.imageBytesPerRowFor(
            width,
            component_size,
            selected_vector_size,
        );
        const valid = width * component_size + if (selected_vector_size == 1)
            0
        else
            selected_vector_size - component_size;
        const alignment = @max(simd.alignment, selected_vector_size);
        const rounded = (valid + alignment - 1) & ~(alignment - 1);
        try std.testing.expectEqual(rounded + alignment, stride);
        try std.testing.expectEqual(@as(usize, 0), stride % alignment);
        try std.testing.expect(stride >= valid + alignment);
        try std.testing.expect(stride < valid + 2 * alignment);
    }
};

pub const ImageMirrorProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const size: usize = @intCast(try data.drawInteger(1, 100_000, 1));
        const offset_choice: i64 = @intCast(try data.drawInteger(0, 2 * size, size));
        const offset = offset_choice - @as(i64, @intCast(size));
        const cycle_choice: i64 = @intCast(try data.drawInteger(0, 20_000, 10_000));
        const cycles = cycle_choice - 10_000;
        const period: i64 = @intCast(2 * size);
        const coordinate = cycles * period + offset;
        const observed = simd.mirror(coordinate, size);
        try std.testing.expect(observed < size);
        try std.testing.expectEqual(
            observed,
            simd.mirror(coordinate + period, size),
        );
        try std.testing.expectEqual(
            observed,
            simd.mirror(-coordinate - 1, size),
        );
        if (coordinate >= 0 and coordinate < size) {
            try std.testing.expectEqual(@as(usize, @intCast(coordinate)), observed);
        }
    }
};

pub const ImageRectProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const width: usize = @intCast(try data.drawInteger(0, 10_000, 0));
        const height: usize = @intCast(try data.drawInteger(0, 10_000, 0));
        const xbegin: usize = @intCast(try data.drawInteger(0, 20_000, 0));
        const ybegin: usize = @intCast(try data.drawInteger(0, 20_000, 0));
        const max_width: usize = @intCast(try data.drawInteger(0, 20_000, 0));
        const max_height: usize = @intCast(try data.drawInteger(0, 20_000, 0));
        const rect = simd.Rect.initClamped(
            xbegin,
            ybegin,
            max_width,
            max_height,
            width,
            height,
        );
        try std.testing.expect(rect.xsize() <= max_width);
        try std.testing.expect(rect.ysize() <= max_height);
        if (xbegin >= width) {
            try std.testing.expectEqual(@as(usize, 0), rect.xsize());
        } else {
            try std.testing.expect(rect.x0() + rect.xsize() <= width);
            try std.testing.expectEqual(@min(max_width, width - xbegin), rect.xsize());
        }
        if (ybegin >= height) {
            try std.testing.expectEqual(@as(usize, 0), rect.ysize());
        } else {
            try std.testing.expect(rect.y0() + rect.ysize() <= height);
            try std.testing.expectEqual(@min(max_height, height - ybegin), rect.ysize());
        }
    }
};

test "property: image row layout retains Highway alignment and padding" {
    try hypothesis.checkNamed(ImageLayoutProperty, "simd-image-layout", run.settings());
}

test "property: image coordinate mirror is periodic symmetric and in range" {
    try hypothesis.checkNamed(ImageMirrorProperty, "simd-image-mirror", run.settings());
}

test "property: image rectangles clamp independently on both axes" {
    try hypothesis.checkNamed(ImageRectProperty, "simd-image-rect", run.settings());
}
