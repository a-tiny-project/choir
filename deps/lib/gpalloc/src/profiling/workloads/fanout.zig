const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys_thread = @import("sys").thread;
const parameters = @import("parameters.zig");

const Record = struct {
    bytes: []u8,
};

pub fn run(allocator: std.mem.Allocator) void {
    runWith(parameters.active_fanout_thread_count, parameters.active_fanout_batch_count, allocator);
    coz.progressNamed("gpalloc.phase.active_fanout.pass");
}

pub fn full(allocator: std.mem.Allocator) void {
    runWith(parameters.active_fanout_full_thread_count, parameters.active_fanout_full_batch_count, allocator);
    coz.progressNamed("gpalloc.phase.active_fanout_full.pass");
}

fn runWith(comptime thread_count: usize, comptime batch_count: usize, allocator: std.mem.Allocator) void {
    const Work = struct {
        allocator: std.mem.Allocator,
        index: usize,
        ready: *std.atomic.Value(u32),
        gate: *std.atomic.Value(u32),
        records: *[thread_count][batch_count]Record,

        fn run(work: *const @This()) void {
            for (&work.records[work.index], 0..) |*record, index| {
                const bytes = work.allocator.alloc(u8, 48) catch @panic("allocation failed");
                @memset(bytes, @truncate(index + work.index));
                record.* = .{ .bytes = bytes };
            }
            for (work.records[work.index]) |record| {
                std.mem.doNotOptimizeAway(record.bytes.ptr);
                work.allocator.free(record.bytes);
            }

            _ = work.ready.fetchAdd(1, .acq_rel);
            while (work.gate.load(.acquire) == 0) {
                std.atomic.spinLoopHint();
            }
        }
    };

    var ready = std.atomic.Value(u32).init(0);
    var gate = std.atomic.Value(u32).init(0);
    var records: [thread_count][batch_count]Record = undefined;
    var work: [thread_count]Work = undefined;
    var threads: [thread_count]sys_thread.JoinHandle = undefined;

    for (&threads, 0..) |*thread, index| {
        work[index] = .{
            .allocator = allocator,
            .index = index,
            .ready = &ready,
            .gate = &gate,
            .records = &records,
        };
        thread.* = sys_thread.spawn(Work.run, .{&work[index]}) catch @panic("thread spawn failed");
    }

    while (ready.load(.acquire) != thread_count) {
        std.atomic.spinLoopHint();
    }
    gate.store(1, .release);

    for (threads) |thread| thread.join();
}
