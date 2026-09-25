const std = @import("std");
const preload_record = @import("preload.zig");
const raw_record = @import("raw.zig");
const touch = @import("touch.zig");

const RawRecord = raw_record.RawRecord;
const touchEdges = touch.edges;

pub const Mode = enum {
    direct,
    preload,
    sh8_preload,
    sh8_preload_detail,
};

pub fn Value(comptime mode: Mode) type {
    return switch (mode) {
        .direct => []u8,
        .preload, .sh8_preload, .sh8_preload_detail => RawRecord,
    };
}

pub fn phase(comptime mode: Mode, comptime name: []const u8) []const u8 {
    const workload = switch (mode) {
        .direct => "foreign_free_trace",
        .preload => "foreign_free_preload_trace",
        .sh8_preload => "sh8_preload_trace",
        .sh8_preload_detail => "sh8_preload_detail_trace",
    };
    return "gpalloc.phase." ++ workload ++ "." ++ name;
}

pub fn alloc(
    comptime mode: Mode,
    allocator: std.mem.Allocator,
    alignment: std.mem.Alignment,
    user_len: usize,
    salt: usize,
) Value(mode) {
    return switch (mode) {
        .direct => blk: {
            const bytes = allocator.alloc(u8, user_len) catch @panic("allocation failed");
            touchEdges(bytes, salt);
            break :blk bytes;
        },
        .preload, .sh8_preload, .sh8_preload_detail => preload_record.alloc(allocator, alignment, user_len, salt),
    };
}

pub fn free(
    comptime mode: Mode,
    allocator: std.mem.Allocator,
    value: Value(mode),
) void {
    switch (mode) {
        .direct => {
            std.mem.doNotOptimizeAway(value.ptr);
            allocator.free(value);
        },
        .preload, .sh8_preload, .sh8_preload_detail => preload_record.free(allocator, value),
    }
}
