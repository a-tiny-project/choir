const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const max_operations: usize = 128;
const max_dimension: usize = 8;
const max_vector_bytes: usize = 16;
const max_view_items: usize = max_dimension * max_dimension * max_dimension * max_vector_bytes;

pub const AllocationProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, allocator: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(1, 1024, 1));
        const seed = try drawU64(data);
        var allocation = try simd.AlignedAllocation(u64).init(allocator, count);
        defer allocation.deinit(allocator);
        try std.testing.expect(simd.isAligned(allocation.values.ptr));
        try std.testing.expect(simd.isDescriptorAligned(
            simd.FixedTag(u64, 4),
            allocation.values.ptr,
        ));
        var expected: u64 = 0;
        for (allocation.values, 0..) |*value, index| {
            value.* = seed +% (@as(u64, @intCast(index)) *% 0x9e37_79b9_7f4a_7c15);
            expected +%= value.*;
        }
        var observed: u64 = 0;
        for (allocation.constSlice()) |value| observed +%= value;
        try std.testing.expectEqual(expected, observed);
        try std.testing.expectEqual(count, allocation.slice().len);
    }
};

pub const ViewProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var shape: [4]usize = undefined;
        for (&shape) |*dimension| {
            dimension.* = @intCast(try data.drawInteger(1, max_dimension, 1));
        }
        const vector_shift: u4 = @intCast(try data.drawInteger(0, 4, 0));
        const vector_bytes = @as(usize, 1) << vector_shift;
        const sentinel: u16 = @intCast(try data.drawInteger(0, std.math.maxInt(u16), 0));
        var storage: [max_view_items]u16 align(simd.alignment) = @splat(sentinel);
        var view = try simd.AlignedView(u16, 4).initFor(&storage, shape, vector_bytes);
        const layout = view.layout;
        const expected_last = (shape[3] + vector_bytes - 1) & ~(vector_bytes - 1);
        try std.testing.expectEqual(expected_last, layout.memoryShape()[3]);
        try std.testing.expectEqual(shape[0] * shape[1] * shape[2] * shape[3], layout.len());
        try std.testing.expectEqual(
            shape[0] * shape[1] * shape[2] * expected_last,
            layout.memoryLen(),
        );
        var indices: [3]usize = undefined;
        for (&indices, shape[0..3]) |*index, dimension| {
            index.* = @intCast(try data.drawInteger(0, dimension - 1, 0));
        }
        const replacement: u16 = @intCast(try data.drawInteger(0, std.math.maxInt(u16), 1));
        const offset = try layout.rowOffset(indices);
        @memset(try view.row(indices), replacement);
        for (storage[0..layout.memoryLen()], 0..) |value, index| {
            const expected = if (index >= offset and index < offset + shape[3])
                replacement
            else
                sentinel;
            try std.testing.expectEqual(expected, value);
        }
        var truncated = shape;
        for (&truncated, shape) |*dimension, original| {
            dimension.* = @intCast(try data.drawInteger(0, original, 0));
        }
        try view.truncate(truncated);
        try std.testing.expectEqual(truncated, view.layout.shape());
        try std.testing.expectEqual(layout.memoryShape(), view.layout.memoryShape());
    }
};

pub const VectorProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, allocator: Allocator) !void {
        const operation_count: usize = @intCast(try data.drawInteger(0, max_operations, 0));
        var vector = try simd.AlignedVector(u32).initCapacity(allocator, 0);
        defer vector.deinit(allocator);
        var model: [max_operations]u32 = undefined;
        var model_len: usize = 0;
        for (0..operation_count) |_| {
            const operation: u2 = @intCast(try data.drawInteger(0, 2, 0));
            switch (operation) {
                0 => {
                    if (model_len == model.len) continue;
                    const value: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
                    try vector.append(allocator, value);
                    model[model_len] = value;
                    model_len += 1;
                },
                1 => {
                    const observed = vector.pop();
                    const expected = if (model_len == 0) null else blk: {
                        model_len -= 1;
                        break :blk model[model_len];
                    };
                    try std.testing.expectEqual(expected, observed);
                },
                2 => {
                    vector.clearRetainingCapacity();
                    model_len = 0;
                },
                else => unreachable,
            }
            try std.testing.expectEqualSlices(u32, model[0..model_len], vector.constItems());
            if (vector.capacity() != 0) {
                try std.testing.expect(simd.isAlignedTo(
                    vector.storage.?.values.ptr,
                    simd.alignment,
                ));
            }
        }
    }
};

fn drawU64(data: *hypothesis.ConjectureData) !u64 {
    const low: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
    const high: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
    return @as(u64, high) << 32 | low;
}

test "property: aligned allocations preserve exact typed payloads" {
    try hypothesis.checkNamed(
        AllocationProperty,
        "simd-aligned-allocation-payload",
        run.settings(),
    );
}

test "property: padded aligned views match a bounded scalar row model" {
    try hypothesis.checkNamed(
        ViewProperty,
        "simd-aligned-view-row-model",
        run.settings(),
    );
}

test "property: aligned vector operations match a fixed scalar sequence" {
    try hypothesis.checkNamed(
        VectorProperty,
        "simd-aligned-vector-model",
        run.settings(),
    );
}
