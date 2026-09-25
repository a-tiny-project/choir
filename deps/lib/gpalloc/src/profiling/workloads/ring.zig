const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys_thread = @import("sys").thread;
const parameters = @import("parameters.zig");

const Record = struct {
    bytes: []u8,
};

pub fn run(allocator: std.mem.Allocator) void {
    runWith(parameters.remote_ring_thread_count, parameters.remote_ring_batch_count, parameters.remote_ring_round_count, allocator);
    coz.progressNamed("gpalloc.phase.remote_ring.pass");
}

pub fn full(allocator: std.mem.Allocator) void {
    runWith(parameters.remote_ring_full_thread_count, parameters.remote_ring_full_batch_count, parameters.remote_ring_full_round_count, allocator);
    coz.progressNamed("gpalloc.phase.remote_ring_full.pass");
}

fn runWith(
    comptime thread_count: usize,
    comptime batch_count: usize,
    comptime round_count: usize,
    allocator: std.mem.Allocator,
) void {
    const Work = struct {
        allocator: std.mem.Allocator,
        index: usize,
        barrier_epoch: *std.atomic.Value(u32),
        barrier_arrivals: *std.atomic.Value(u32),
        records: *[thread_count][batch_count]Record,

        fn run(work: *const @This()) void {
            var round: usize = 0;
            while (round < round_count) : (round += 1) {
                for (&work.records[work.index], 0..) |*record, index| {
                    const len = 16 + ((index + work.index * 17 + round * 29) % 4) * 32;
                    const bytes = work.allocator.alloc(u8, len) catch @panic("allocation failed");
                    @memset(bytes, @truncate(index + round + work.index));
                    record.* = .{ .bytes = bytes };
                }

                work.waitForBarrier(@intCast(round * 2));

                const free_index = (work.index + thread_count - 1) % thread_count;
                for (work.records[free_index]) |record| {
                    std.mem.doNotOptimizeAway(record.bytes.ptr);
                    work.allocator.free(record.bytes);
                }

                work.waitForBarrier(@intCast(round * 2 + 1));
            }
        }

        fn waitForBarrier(work: *const @This(), expected_epoch: u32) void {
            const arrived = work.barrier_arrivals.fetchAdd(1, .acq_rel) + 1;
            if (arrived == thread_count) {
                work.barrier_arrivals.store(0, .release);
                work.barrier_epoch.store(expected_epoch + 1, .release);
                return;
            }

            while (work.barrier_epoch.load(.acquire) == expected_epoch) {
                std.atomic.spinLoopHint();
            }
        }
    };

    var barrier_epoch = std.atomic.Value(u32).init(0);
    var barrier_arrivals = std.atomic.Value(u32).init(0);
    var records: [thread_count][batch_count]Record = undefined;
    var work: [thread_count]Work = undefined;
    var threads: [thread_count]sys_thread.JoinHandle = undefined;

    for (&threads, 0..) |*thread, index| {
        work[index] = .{
            .allocator = allocator,
            .index = index,
            .barrier_epoch = &barrier_epoch,
            .barrier_arrivals = &barrier_arrivals,
            .records = &records,
        };
        thread.* = sys_thread.spawn(Work.run, .{&work[index]}) catch @panic("thread spawn failed");
    }

    for (threads) |thread| thread.join();
}
