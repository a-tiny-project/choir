const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys_thread = @import("sys").thread;
const parameters = @import("parameters.zig");

const Record = struct {
    bytes: []u8,
};

pub fn falseSharing(allocator: std.mem.Allocator) void {
    runFalseSharingWith(
        parameters.false_sharing_thread_count,
        parameters.false_sharing_slot_count,
        parameters.false_sharing_round_count,
        allocator,
    );
}

pub fn asymmetricHandoff(allocator: std.mem.Allocator) void {
    runAsymmetricHandoffWith(
        parameters.asymmetric_handoff_producer_count,
        parameters.asymmetric_handoff_batch_count,
        parameters.asymmetric_handoff_round_count,
        allocator,
    );
}

fn runFalseSharingWith(
    comptime thread_count: usize,
    comptime slot_count: usize,
    comptime round_count: usize,
    allocator: std.mem.Allocator,
) void {
    const Work = struct {
        allocator: std.mem.Allocator,
        index: usize,
        ready: *std.atomic.Value(u32),
        gate: *std.atomic.Value(u32),

        fn run(work: *const @This()) void {
            _ = work.ready.fetchAdd(1, .acq_rel);
            while (work.gate.load(.acquire) == 0) {
                std.atomic.spinLoopHint();
            }

            var records: [slot_count]Record = undefined;
            var round: usize = 0;
            while (round < round_count) : (round += 1) {
                {
                    const allocate_phase = bench.phaseAt("gpalloc.phase.false_sharing.allocate", @src());
                    defer allocate_phase.end();

                    for (&records, 0..) |*record, index| {
                        const bytes = work.allocator.alloc(u8, 16) catch @panic("allocation failed");
                        bytes[0] = @truncate(index + round + work.index);
                        record.* = .{ .bytes = bytes };
                    }
                }

                {
                    const touch_phase = bench.phaseAt("gpalloc.phase.false_sharing.touch", @src());
                    defer touch_phase.end();

                    var touch: usize = 0;
                    while (touch < parameters.false_sharing_touch_count) : (touch += 1) {
                        for (&records) |*record| {
                            record.bytes[0] +%= 1;
                            std.mem.doNotOptimizeAway(record.bytes.ptr);
                        }
                    }
                }

                {
                    const free_phase = bench.phaseAt("gpalloc.phase.false_sharing.free", @src());
                    defer free_phase.end();

                    for (records) |record| {
                        work.allocator.free(record.bytes);
                    }
                }

                coz.progressNamed("gpalloc.phase.false_sharing.round");
            }
        }
    };

    var ready = std.atomic.Value(u32).init(0);
    var gate = std.atomic.Value(u32).init(0);
    var work: [thread_count]Work = undefined;
    var threads: [thread_count]sys_thread.JoinHandle = undefined;

    for (&threads, 0..) |*thread, index| {
        work[index] = .{
            .allocator = allocator,
            .index = index,
            .ready = &ready,
            .gate = &gate,
        };
        thread.* = sys_thread.spawn(Work.run, .{&work[index]}) catch @panic("thread spawn failed");
    }

    while (ready.load(.acquire) != thread_count) {
        std.atomic.spinLoopHint();
    }
    gate.store(1, .release);

    for (threads) |thread| thread.join();
}

fn runAsymmetricHandoffWith(
    comptime producer_count: usize,
    comptime batch_count: usize,
    comptime round_count: usize,
    allocator: std.mem.Allocator,
) void {
    const ProducerWork = struct {
        allocator: std.mem.Allocator,
        index: usize,
        states: *[producer_count]std.atomic.Value(u32),
        records: *[producer_count][batch_count]Record,

        fn run(work: *const @This()) void {
            var round: usize = 0;
            while (round < round_count) : (round += 1) {
                while (work.states[work.index].load(.acquire) != 0) {
                    std.atomic.spinLoopHint();
                }

                {
                    const allocate_phase = bench.phaseAt("gpalloc.phase.asymmetric_handoff.allocate", @src());
                    defer allocate_phase.end();

                    for (&work.records[work.index], 0..) |*record, index| {
                        const len = 16 + ((index + work.index * 13 + round * 29) % 8) * 32;
                        const bytes = work.allocator.alloc(u8, len) catch @panic("allocation failed");
                        @memset(bytes, @truncate(index + work.index + round));
                        record.* = .{ .bytes = bytes };
                    }
                }

                work.states[work.index].store(1, .release);
                while (work.states[work.index].load(.acquire) != 0) {
                    std.atomic.spinLoopHint();
                }
                coz.progressNamed("gpalloc.phase.asymmetric_handoff.producer");
            }
        }
    };

    const ConsumerWork = struct {
        allocator: std.mem.Allocator,
        states: *[producer_count]std.atomic.Value(u32),
        records: *[producer_count][batch_count]Record,

        fn run(work: *const @This()) void {
            var round: usize = 0;
            while (round < round_count) : (round += 1) {
                var producer: usize = 0;
                while (producer < producer_count) : (producer += 1) {
                    while (work.states[producer].load(.acquire) != 1) {
                        std.atomic.spinLoopHint();
                    }

                    {
                        const free_phase = bench.phaseAt("gpalloc.phase.asymmetric_handoff.remote_free", @src());
                        defer free_phase.end();

                        for (work.records[producer]) |record| {
                            std.mem.doNotOptimizeAway(record.bytes.ptr);
                            work.allocator.free(record.bytes);
                        }
                    }

                    work.states[producer].store(0, .release);
                }
                coz.progressNamed("gpalloc.phase.asymmetric_handoff.consumer");
            }
        }
    };

    var states = @as([producer_count]std.atomic.Value(u32), @splat(std.atomic.Value(u32).init(0)));
    var records: [producer_count][batch_count]Record = undefined;
    var producer_work: [producer_count]ProducerWork = undefined;
    var producers: [producer_count]sys_thread.JoinHandle = undefined;
    var consumer_work: ConsumerWork = .{
        .allocator = allocator,
        .states = &states,
        .records = &records,
    };

    const consumer = sys_thread.spawn(ConsumerWork.run, .{&consumer_work}) catch @panic("thread spawn failed");
    for (&producers, 0..) |*thread, index| {
        producer_work[index] = .{
            .allocator = allocator,
            .index = index,
            .states = &states,
            .records = &records,
        };
        thread.* = sys_thread.spawn(ProducerWork.run, .{&producer_work[index]}) catch @panic("thread spawn failed");
    }
    for (producers) |thread| thread.join();
    consumer.join();
}
