const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const gpalloc = @import("gpalloc");
const parameters = @import("parameters.zig");

const Record = struct {
    bytes: []u8,
};

pub fn smallChurn(allocator: std.mem.Allocator) void {
    var records: [parameters.allocation_count]Record = undefined;
    for (&records, 0..) |*record, index| {
        const bytes = allocator.alloc(u8, 48) catch @panic("allocation failed");
        @memset(bytes, @truncate(index));
        record.* = .{ .bytes = bytes };
    }
    for (&records) |record| {
        std.mem.doNotOptimizeAway(record.bytes.ptr);
        allocator.free(record.bytes);
    }
    coz.progressNamed("gpalloc.phase.small_churn.pass");
}

pub fn repeatedBursts(allocator: std.mem.Allocator) void {
    var records: [parameters.burst_allocation_count]Record = undefined;
    var burst: usize = 0;
    while (burst < parameters.burst_count) : (burst += 1) {
        for (&records, 0..) |*record, index| {
            const bytes = allocator.alloc(u8, 48) catch @panic("allocation failed");
            @memset(bytes, @truncate(index + burst));
            record.* = .{ .bytes = bytes };
        }
        for (&records) |record| {
            std.mem.doNotOptimizeAway(record.bytes.ptr);
            allocator.free(record.bytes);
        }
        coz.progressNamed("gpalloc.phase.retained_bursts.burst");
    }
}

pub fn mixedSizeChurn(allocator: std.mem.Allocator) void {
    var records: [1024]Record = undefined;
    for (&records, 0..) |*record, index| {
        const len = 16 + (index * 73) % 8192;
        const bytes = allocator.alloc(u8, len) catch @panic("allocation failed");
        @memset(bytes, @truncate(index));
        record.* = .{ .bytes = bytes };
    }
    for (&records, 0..) |*record, index| {
        const new_len = 16 + (index * 131) % 32768;
        const resized = allocator.realloc(record.bytes, new_len) catch @panic("realloc failed");
        std.mem.doNotOptimizeAway(resized.ptr);
        record.bytes = resized;
    }
    for (&records) |record| {
        allocator.free(record.bytes);
    }
    coz.progressNamed("gpalloc.phase.mixed_realloc.pass");
}

pub fn reallocInPlace(allocator: std.mem.Allocator) void {
    var records: [parameters.realloc_in_place_count]Record = undefined;
    for (&records, 0..) |*record, index| {
        const bytes = allocator.alloc(u8, 200) catch @panic("allocation failed");
        @memset(bytes, @truncate(index));
        record.* = .{ .bytes = bytes };
    }
    for (&records) |*record| {
        const resized = allocator.realloc(record.bytes, 24) catch @panic("realloc failed");
        std.mem.doNotOptimizeAway(resized.ptr);
        record.bytes = resized;
    }
    for (&records) |*record| {
        const resized = allocator.realloc(record.bytes, 128) catch @panic("realloc failed");
        std.mem.doNotOptimizeAway(resized.ptr);
        record.bytes = resized;
    }
    for (&records) |record| {
        allocator.free(record.bytes);
    }
    coz.progressNamed("gpalloc.phase.realloc_in_place.pass");
}

pub fn reallocMixedSparse(allocator: std.mem.Allocator) void {
    var records: [parameters.realloc_mixed_sparse_count]Record = undefined;
    for (&records, 0..) |*record, index| {
        const len = 16 + (index * 73) % 8192;
        const bytes = allocator.alloc(u8, len) catch @panic("allocation failed");
        bytes[0] = @truncate(index);
        record.* = .{ .bytes = bytes };
    }
    for (&records, 0..) |*record, index| {
        const new_len = 16 + (index * 131) % 32768;
        const resized = allocator.realloc(record.bytes, new_len) catch @panic("realloc failed");
        std.mem.doNotOptimizeAway(resized.ptr);
        record.bytes = resized;
    }
    for (&records) |record| {
        allocator.free(record.bytes);
    }
    coz.progressNamed("gpalloc.phase.realloc_mixed_sparse.pass");
}

pub fn reallocCrossClass(allocator: std.mem.Allocator) void {
    var records: [parameters.realloc_cross_class_count]Record = undefined;
    for (&records, 0..) |*record, index| {
        const class_index = index % (gpalloc.class_sizes.len - 1);
        const len = gpalloc.class_sizes[class_index];
        const bytes = allocator.alloc(u8, len) catch @panic("allocation failed");
        bytes[0] = @truncate(index);
        record.* = .{ .bytes = bytes };
    }
    for (&records, 0..) |*record, index| {
        const class_index = index % (gpalloc.class_sizes.len - 1);
        const new_len = gpalloc.class_sizes[class_index + 1];
        const resized = allocator.realloc(record.bytes, new_len) catch @panic("realloc failed");
        std.mem.doNotOptimizeAway(resized.ptr);
        record.bytes = resized;
    }
    for (&records) |record| {
        allocator.free(record.bytes);
    }
    coz.progressNamed("gpalloc.phase.realloc_cross_class.pass");
}
