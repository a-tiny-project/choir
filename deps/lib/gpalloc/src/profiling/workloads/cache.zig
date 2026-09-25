const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys_thread = @import("sys").thread;
const gpalloc = @import("gpalloc");
const parameters = @import("parameters.zig");
const touch = @import("touch.zig");

const nextWorkingSetState = touch.nextWorkingSetState;

const Record = struct {
    bytes: []u8,
};

pub fn workingSetChurn(allocator: std.mem.Allocator) void {
    runWorkingSetWith(parameters.working_set_thread_count, parameters.working_set_slot_count, allocator, parameters.working_set_operation_count, null);
    coz.progressNamed("gpalloc.phase.working_set_churn.pass");
}

pub fn workingSetSteady(allocator: std.mem.Allocator) void {
    runWorkingSetWith(parameters.working_set_thread_count, parameters.working_set_slot_count, allocator, parameters.working_set_steady_operation_count, null);
    coz.progressNamed("gpalloc.phase.working_set_steady.pass");
}

pub fn workingSetSteadyFull(allocator: std.mem.Allocator) void {
    runWorkingSetWith(
        parameters.working_set_full_thread_count,
        parameters.working_set_full_slot_count,
        allocator,
        parameters.working_set_steady_full_operation_count,
        null,
    );
    coz.progressNamed("gpalloc.phase.working_set_steady_full.pass");
}

pub fn workingSetSteady16Full(allocator: std.mem.Allocator) void {
    runWorkingSetWith(
        parameters.working_set_full_thread_count,
        parameters.working_set_full_slot_count,
        allocator,
        parameters.working_set_steady_16_full_operation_count,
        16,
    );
    coz.progressNamed("gpalloc.phase.working_set_steady_16_full.pass");
}

pub fn localCache16(allocator: std.mem.Allocator) void {
    runLocalCacheWith(allocator, 16);
    coz.progressNamed("gpalloc.phase.local_cache_16.pass");
}

pub fn localCache48(allocator: std.mem.Allocator) void {
    runLocalCacheWith(allocator, 48);
    coz.progressNamed("gpalloc.phase.local_cache_48.pass");
}

pub fn oversubscribedCache(allocator: std.mem.Allocator) void {
    runOversubscribedCacheWith(parameters.oversubscribed_thread_count, parameters.oversubscribed_batch_count, allocator);
}

fn runLocalCacheWith(allocator: std.mem.Allocator, comptime size: usize) void {
    var records: [parameters.local_cache_slot_count]?[]u8 = @as([parameters.local_cache_slot_count]?[]u8, @splat(null));
    var state: u32 = 0x9e37_79b9;
    var operation: usize = 0;
    while (operation < parameters.local_cache_operation_count) : (operation += 1) {
        const offset = nextWorkingSetState(&state) % parameters.local_cache_slot_count;
        if (records[offset]) |bytes| {
            allocator.free(bytes);
        }

        const bytes = allocator.alloc(u8, size) catch @panic("allocation failed");
        @memset(bytes, @truncate(operation));
        records[offset] = bytes;
    }

    for (&records) |*record| {
        const bytes = record.* orelse continue;
        std.mem.doNotOptimizeAway(bytes.ptr);
        allocator.free(bytes);
        record.* = null;
    }
}

fn runOversubscribedCacheWith(
    comptime thread_count: usize,
    comptime batch_count: usize,
    allocator: std.mem.Allocator,
) void {
    const Work = struct {
        allocator: std.mem.Allocator,
        index: usize,

        fn run(work: *const @This()) void {
            var records: [batch_count]Record = undefined;
            {
                const allocate_phase = bench.phaseAt("gpalloc.phase.oversubscribed_cache.allocate", @src());
                defer allocate_phase.end();

                for (&records, 0..) |*record, index| {
                    const len = gpalloc.class_sizes[(index + work.index * 5) % gpalloc.class_sizes.len];
                    const bytes = work.allocator.alloc(u8, len) catch @panic("allocation failed");
                    bytes[0] = @truncate(index + work.index);
                    record.* = .{ .bytes = bytes };
                }
            }

            {
                const free_phase = bench.phaseAt("gpalloc.phase.oversubscribed_cache.free", @src());
                defer free_phase.end();

                for (records) |record| {
                    std.mem.doNotOptimizeAway(record.bytes.ptr);
                    work.allocator.free(record.bytes);
                }
            }

            coz.progressNamed("gpalloc.phase.oversubscribed_cache.thread");
        }
    };

    var work: [thread_count]Work = undefined;
    var threads: [thread_count]sys_thread.JoinHandle = undefined;
    for (&threads, 0..) |*thread, index| {
        work[index] = .{ .allocator = allocator, .index = index };
        thread.* = sys_thread.spawn(Work.run, .{&work[index]}) catch @panic("thread spawn failed");
    }
    for (threads) |thread| thread.join();
}

fn runWorkingSetWith(
    comptime thread_count: usize,
    comptime slot_count: usize,
    allocator: std.mem.Allocator,
    operations: usize,
    comptime fixed_size: ?usize,
) void {
    const Work = struct {
        allocator: std.mem.Allocator,
        index: usize,
        operations: usize,
        records: *[slot_count]?[]u8,

        fn run(work: *const @This()) void {
            var state: u32 = @intCast(0x9e37_79b9 ^ (work.index * 0x85eb_ca6b));
            var operation: usize = 0;
            while (operation < work.operations) : (operation += 1) {
                const offset = nextWorkingSetState(&state) % slot_count;
                if (work.records[offset]) |bytes| {
                    work.allocator.free(bytes);
                }

                const len = fixed_size orelse workingSetBlockSize(nextWorkingSetState(&state));
                const bytes = work.allocator.alloc(u8, len) catch @panic("allocation failed");
                @memset(bytes, @truncate(operation + work.index));
                work.records[offset] = bytes;
            }

            for (work.records) |*record| {
                const bytes = record.* orelse continue;
                std.mem.doNotOptimizeAway(bytes.ptr);
                work.allocator.free(bytes);
                record.* = null;
            }
        }
    };

    const empty_records = @as([slot_count]?[]u8, @splat(null));
    var records: [thread_count][slot_count]?[]u8 =
        @as([thread_count][slot_count]?[]u8, @splat(empty_records));
    var work: [thread_count]Work = undefined;
    var threads: [thread_count]sys_thread.JoinHandle = undefined;

    for (&threads, 0..) |*thread, index| {
        work[index] = .{
            .allocator = allocator,
            .index = index,
            .operations = operations,
            .records = &records[index],
        };
        thread.* = sys_thread.spawn(Work.run, .{&work[index]}) catch @panic("thread spawn failed");
    }

    for (threads) |thread| thread.join();
}

fn workingSetBlockSize(state: usize) usize {
    const min_size = 4;
    const max_size = gpalloc.max_small_size;
    const scale = 65_535;
    const sample = state & scale;
    const denominator = max_size * scale - sample * (max_size - min_size);
    return (min_size * max_size * scale) / denominator;
}
