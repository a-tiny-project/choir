const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys_thread = @import("sys").thread;
const parameters = @import("parameters.zig");

const Record = struct {
    bytes: []u8,
};

const ThreadWork = struct {
    allocator: std.mem.Allocator,
    size: usize,
    seed: u8,
};

const ThreadChurnWork = struct {
    allocator: std.mem.Allocator,
    records: *[parameters.thread_churn_batch_count]Record,
    seed: u8,
};

const mixed_thread_sizes = [_]usize{ 16, 2048 };

pub fn sameClass(allocator: std.mem.Allocator) void {
    run(allocator, false);
    coz.progressNamed("gpalloc.phase.parallel_same_class.pass");
}

pub fn mixedClasses(allocator: std.mem.Allocator) void {
    run(allocator, true);
    coz.progressNamed("gpalloc.phase.parallel_mixed_classes.pass");
}

pub fn threadChurn(allocator: std.mem.Allocator) void {
    var records: [parameters.thread_churn_thread_count][parameters.thread_churn_batch_count]Record = undefined;
    var work: [parameters.thread_churn_thread_count]ThreadChurnWork = undefined;
    var threads: [parameters.thread_churn_thread_count]sys_thread.JoinHandle = undefined;

    var round: usize = 0;
    while (round < parameters.thread_churn_round_count) : (round += 1) {
        for (&threads, 0..) |*thread, index| {
            work[index] = .{
                .allocator = allocator,
                .records = &records[index],
                .seed = @truncate(index * 19 + round * 43),
            };
            thread.* = sys_thread.spawn(threadChurnWorker, .{&work[index]}) catch @panic("thread spawn failed");
        }

        for (threads) |thread| thread.join();
        coz.progressNamed("gpalloc.phase.thread_churn.round");
    }
}

fn run(allocator: std.mem.Allocator, comptime mixed_classes: bool) void {
    comptime assertMixedSizeTable();

    var work: [parameters.parallel_thread_count]ThreadWork = undefined;
    var threads: [parameters.parallel_thread_count]sys_thread.JoinHandle = undefined;

    for (&threads, 0..) |*thread, index| {
        work[index] = .{
            .allocator = allocator,
            .size = if (mixed_classes) mixed_thread_sizes[index] else 48,
            .seed = @truncate(index * 31),
        };
        thread.* = sys_thread.spawn(parallelWorker, .{&work[index]}) catch @panic("thread spawn failed");
    }

    for (threads) |thread| thread.join();
}

fn parallelWorker(work: *const ThreadWork) void {
    var records: [parameters.parallel_batch_count]Record = undefined;
    var round: usize = 0;
    while (round < parameters.parallel_round_count) : (round += 1) {
        for (&records, 0..) |*record, index| {
            const bytes = work.allocator.alloc(u8, work.size) catch @panic("allocation failed");
            @memset(bytes, @truncate(index + round + work.seed));
            record.* = .{ .bytes = bytes };
        }
        for (&records) |record| {
            std.mem.doNotOptimizeAway(record.bytes.ptr);
            work.allocator.free(record.bytes);
        }
    }
}

fn threadChurnWorker(work: *const ThreadChurnWork) void {
    for (work.records, 0..) |*record, index| {
        const bytes = work.allocator.alloc(u8, 48) catch @panic("allocation failed");
        @memset(bytes, @truncate(index + work.seed));
        record.* = .{ .bytes = bytes };
    }
    for (work.records.*) |record| {
        std.mem.doNotOptimizeAway(record.bytes.ptr);
        work.allocator.free(record.bytes);
    }
}

fn assertMixedSizeTable() void {
    if (mixed_thread_sizes.len != parameters.parallel_thread_count) {
        @compileError("mixed_thread_sizes must have one size per worker thread");
    }
}
