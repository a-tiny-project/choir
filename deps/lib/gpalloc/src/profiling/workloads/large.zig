const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const gpalloc = @import("gpalloc");
const parameters = @import("parameters.zig");

const Record = struct {
    bytes: []u8,
};

pub fn direct(allocator: std.mem.Allocator) void {
    var records: [128]Record = undefined;
    for (&records, 0..) |*record, index| {
        const len = gpalloc.max_small_size + 1 + index * 64;
        const bytes = allocator.alloc(u8, len) catch @panic("allocation failed");
        bytes[0] = @truncate(index);
        record.* = .{ .bytes = bytes };
    }
    for (&records) |record| {
        std.mem.doNotOptimizeAway(record.bytes.ptr);
        allocator.free(record.bytes);
    }
    coz.progressNamed("gpalloc.phase.large_direct.pass");
}

pub fn cachePressure(allocator: std.mem.Allocator) void {
    var records: [parameters.large_pressure_count]Record = undefined;
    var index: usize = 0;
    while (index < parameters.large_pressure_count) : (index += 1) {
        const class_index = index / parameters.large_pressure_per_class_count;
        const len = pressureSize(class_index);
        const bytes = allocator.alloc(u8, len) catch @panic("allocation failed");
        bytes[0] = @truncate(index);
        records[index] = .{ .bytes = bytes };
    }
    for (records) |record| {
        std.mem.doNotOptimizeAway(record.bytes.ptr);
        allocator.free(record.bytes);
    }

    var probes: [parameters.large_pressure_probe_count]Record = undefined;
    for (&probes, 0..) |*probe, probe_index| {
        const bytes = allocator.alloc(u8, pressureSize(parameters.large_pressure_class_count - 1)) catch @panic("allocation failed");
        bytes[0] = @truncate(probe_index);
        probe.* = .{ .bytes = bytes };
    }
    for (probes) |probe| {
        std.mem.doNotOptimizeAway(probe.bytes.ptr);
        allocator.free(probe.bytes);
    }
    coz.progressNamed("gpalloc.phase.large_cache_pressure.pass");
}

pub fn hugeCachePressure(allocator: std.mem.Allocator) void {
    var records: [parameters.huge_pressure_slot_count]?[]u8 = @as([parameters.huge_pressure_slot_count]?[]u8, @splat(null));

    var operation: usize = 0;
    while (operation < parameters.huge_pressure_operation_count) : (operation += 1) {
        const slot = (operation * 17) % parameters.huge_pressure_slot_count;
        if (records[slot]) |bytes| {
            allocator.free(bytes);
        }

        const len = hugePressureSize(operation);
        const bytes = allocator.alloc(u8, len) catch @panic("allocation failed");
        bytes[0] = @truncate(operation);
        records[slot] = bytes;
    }

    for (&records) |*record| {
        const bytes = record.* orelse continue;
        std.mem.doNotOptimizeAway(bytes.ptr);
        allocator.free(bytes);
        record.* = null;
    }

    var probes: [parameters.huge_pressure_probe_count]Record = undefined;
    for (&probes, 0..) |*probe, index| {
        const bytes = allocator.alloc(u8, hugePressureSize(index + parameters.huge_pressure_operation_count)) catch @panic("allocation failed");
        bytes[0] = @truncate(index);
        probe.* = .{ .bytes = bytes };
    }
    for (probes) |probe| {
        std.mem.doNotOptimizeAway(probe.bytes.ptr);
        allocator.free(probe.bytes);
    }
    coz.progressNamed("gpalloc.phase.huge_cache_pressure.pass");
}

fn pressureSize(class_index: usize) usize {
    return gpalloc.max_small_size + 512 + class_index * 4096;
}

fn hugePressureSize(index: usize) usize {
    const sizes = [_]usize{
        5 * 1024 * 1024 + 1,
        9 * 1024 * 1024 + 1,
        13 * 1024 * 1024 + 1,
        17 * 1024 * 1024 + 1,
        21 * 1024 * 1024 + 1,
        25 * 1024 * 1024 + 1,
    };
    return sizes[index % sizes.len];
}
