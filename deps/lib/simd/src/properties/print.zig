const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const max_lanes: usize = 32;

pub const IntegerProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const value = try drawU64(data);
        var unsigned_buffer: [32]u8 = undefined;
        var unsigned_writer = std.Io.Writer.fixed(&unsigned_buffer);
        try simd.writeLaneValue(&unsigned_writer, value);
        const unsigned = unsigned_writer.buffered();
        try std.testing.expectEqual(@as(usize, 18), unsigned.len);
        try std.testing.expectEqualStrings("0x", unsigned[0..2]);
        try std.testing.expectEqual(value, try std.fmt.parseInt(u64, unsigned[2..], 16));

        const signed: i32 = @bitCast(@as(u32, @truncate(value)));
        var signed_buffer: [32]u8 = undefined;
        var signed_writer = std.Io.Writer.fixed(&signed_buffer);
        try simd.writeLaneValue(&signed_writer, signed);
        try std.testing.expectEqual(
            signed,
            try std.fmt.parseInt(i32, signed_writer.buffered(), 10),
        );
    }
};

pub const WindowProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const len: usize = @intCast(try data.drawInteger(0, max_lanes, 0));
        const lane: usize = @intCast(try data.drawInteger(0, max_lanes + 8, 0));
        const limit: usize = @intCast(try data.drawInteger(0, 12, 0));
        const seed = try drawU64(data);
        var values: [max_lanes]u32 = undefined;
        for (&values, 0..) |*value, index| {
            value.* = @truncate(seed +% @as(u64, @intCast(index)) *% 0x9e37_79b9);
        }
        var buffer: [1024]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try simd.writeLaneArray(
            &writer,
            "property",
            values[0..len],
            .{ .lane = lane, .max_lanes = limit },
        );
        const rendered = writer.buffered();
        const marker = std.mem.indexOf(u8, rendered, "\n  ") orelse
            return error.MissingDiagnosticBody;
        try std.testing.expect(rendered.len != 0 and rendered[rendered.len - 1] == '\n');
        const body = rendered[marker + 3 .. rendered.len - 1];
        const begin = lane -| 2;
        const end = @min(begin +| limit, len);
        if (begin >= end) {
            try std.testing.expectEqualStrings("(out of bounds)", body);
            return;
        }
        var fields = std.mem.splitScalar(u8, body, ',');
        var index = begin;
        while (fields.next()) |field| {
            if (field.len == 0) break;
            try std.testing.expect(index < end);
            try std.testing.expectEqual(values[index], try std.fmt.parseInt(u32, field, 10));
            index += 1;
        }
        try std.testing.expectEqual(end, index);
    }
};

pub const VectorProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const D = simd.FixedTag(u32, 8);
        var values: [8]u32 = undefined;
        for (&values) |*value| value.* = @truncate(try drawU64(data));
        const lane: usize = @intCast(try data.drawInteger(0, 12, 0));
        const limit: usize = @intCast(try data.drawInteger(0, 12, 0));
        const options = simd.DiagnosticWindow{ .lane = lane, .max_lanes = limit };
        var array_buffer: [512]u8 = undefined;
        var array_writer = std.Io.Writer.fixed(&array_buffer);
        try simd.writeLaneArray(&array_writer, "equivalent", &values, options);
        const vector: D.Vector = values;
        var vector_buffer: [512]u8 = undefined;
        var vector_writer = std.Io.Writer.fixed(&vector_buffer);
        try simd.writeVector(&vector_writer, D, "equivalent", vector, options);
        try std.testing.expectEqualStrings(array_writer.buffered(), vector_writer.buffered());
    }
};

fn drawU64(data: *hypothesis.ConjectureData) !u64 {
    const low: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
    const high: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
    return @as(u64, high) << 32 | low;
}

test "property: diagnostic integers round trip through their declared radix" {
    try hypothesis.checkNamed(
        IntegerProperty,
        "simd-print-integer-round-trip",
        run.settings(),
    );
}

test "property: diagnostic windows expose exactly the scalar model range" {
    try hypothesis.checkNamed(
        WindowProperty,
        "simd-print-window-model",
        run.settings(),
    );
}

test "property: vector diagnostics equal memory-order array diagnostics" {
    try hypothesis.checkNamed(
        VectorProperty,
        "simd-print-vector-array-equivalence",
        run.settings(),
    );
}
