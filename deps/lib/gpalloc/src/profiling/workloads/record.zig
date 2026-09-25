const std = @import("std");
const parameters = @import("parameters.zig");
const preload_record = @import("preload.zig");
const raw_record = @import("raw.zig");

const RawRecord = raw_record.RawRecord;

pub const Mode = enum {
    direct,
    preload,
    preload_threaded,
};

pub fn Value(comptime mode: Mode) type {
    return switch (mode) {
        .direct => []u8,
        .preload, .preload_threaded => RawRecord,
    };
}

pub fn phase(comptime mode: Mode, comptime name: []const u8) []const u8 {
    const workload = switch (mode) {
        .direct => "alloc_test_trace",
        .preload => "alloc_test_preload_trace",
        .preload_threaded => "alloc_test_preload_threaded_trace",
    };
    return "gpalloc.phase." ++ workload ++ "." ++ name;
}

pub fn progressName(comptime mode: Mode) []const u8 {
    return switch (mode) {
        .direct => "gpalloc.workload.alloc_test_trace",
        .preload => "gpalloc.workload.alloc_test_preload_trace",
        .preload_threaded => "gpalloc.workload.alloc_test_preload_threaded_trace",
    };
}

pub fn alloc(
    comptime mode: Mode,
    allocator: std.mem.Allocator,
    len: usize,
) Value(mode) {
    return switch (mode) {
        .direct => blk: {
            const bytes = allocator.alloc(u8, len) catch @panic("allocation failed");
            @memset(bytes, @truncate(len));
            break :blk bytes;
        },
        .preload, .preload_threaded => blk: {
            const result = preload_record.alloc(allocator, .fromByteUnits(parameters.preload_alignment_bytes), len, len);
            @memset(preload_record.payload(result), @truncate(len));
            break :blk result;
        },
    };
}

pub fn free(
    comptime mode: Mode,
    allocator: std.mem.Allocator,
    value: Value(mode),
) void {
    switch (mode) {
        .direct => allocator.free(value),
        .preload, .preload_threaded => preload_record.free(allocator, value),
    }
}

pub fn read(comptime mode: Mode, value: Value(mode)) usize {
    const bytes = switch (mode) {
        .direct => value,
        .preload, .preload_threaded => preload_record.payload(value),
    };
    var sum: usize = 0;
    for (bytes) |byte| {
        sum +%= byte;
    }
    std.mem.doNotOptimizeAway(bytes.ptr);
    return sum;
}
