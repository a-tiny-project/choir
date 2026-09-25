const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys_thread = @import("sys").thread;
const parameters = @import("parameters.zig");
const preload_record = @import("preload.zig");
const raw_record = @import("raw.zig");
const touch = @import("touch.zig");

const RawRecord = raw_record.RawRecord;
const touchEdges = touch.edges;

const Record = struct {
    bytes: []u8,
};

const ConsumerWork = struct {
    allocator: std.mem.Allocator,
    handoff: *std.atomic.Value(u32),
    records: *[parameters.producer_consumer_batch_count]Record,
};

pub fn consumer(allocator: std.mem.Allocator) void {
    var handoff = std.atomic.Value(u32).init(0);
    var records: [parameters.producer_consumer_batch_count]Record = undefined;
    var work: ConsumerWork = .{
        .allocator = allocator,
        .handoff = &handoff,
        .records = &records,
    };

    const consumer_thread = sys_thread.spawn(consumerFreeWorker, .{&work}) catch @panic("thread spawn failed");
    consumerAllocWorker(&work);
    consumer_thread.join();
}

pub fn xmallocPreloadTrace(allocator: std.mem.Allocator) void {
    const alignment = std.mem.Alignment.fromByteUnits(parameters.preload_alignment_bytes);
    var records: [parameters.xmalloc_preload_trace_pair_count][parameters.xmalloc_preload_trace_object_count]RawRecord = undefined;
    var phases: [parameters.xmalloc_preload_trace_pair_count]std.atomic.Value(u32) = undefined;
    var work: [parameters.xmalloc_preload_trace_pair_count]struct {
        allocator: std.mem.Allocator,
        alignment: std.mem.Alignment,
        index: usize,
        phase: *std.atomic.Value(u32),
        records: *[parameters.xmalloc_preload_trace_object_count]RawRecord,

        fn produce(self: *const @This()) void {
            var round: usize = 0;
            while (round < parameters.xmalloc_preload_trace_round_count) : (round += 1) {
                while (self.phase.load(.acquire) != 0) {
                    std.atomic.spinLoopHint();
                }

                {
                    const allocate_phase = bench.phaseAt("gpalloc.phase.xmalloc_preload_trace.allocate", @src());
                    defer allocate_phase.end();

                    for (&self.records.*, 0..) |*record, object_index| {
                        record.* = preload_record.alloc(
                            self.allocator,
                            self.alignment,
                            parameters.xmalloc_preload_trace_object_size,
                            self.index * 131_071 + round * 4099 + object_index,
                        );
                    }
                }

                self.phase.store(1, .release);
                while (self.phase.load(.acquire) != 2) {
                    std.atomic.spinLoopHint();
                }
                self.phase.store(0, .release);
                coz.progressNamed("gpalloc.phase.xmalloc_preload_trace.producer");
            }
        }

        fn consume(self: *const @This()) void {
            var round: usize = 0;
            while (round < parameters.xmalloc_preload_trace_round_count) : (round += 1) {
                while (self.phase.load(.acquire) != 1) {
                    std.atomic.spinLoopHint();
                }

                {
                    const free_phase = bench.phaseAt("gpalloc.phase.xmalloc_preload_trace.free", @src());
                    defer free_phase.end();

                    for (self.records.*) |record| {
                        preload_record.free(self.allocator, record);
                    }
                }

                self.phase.store(2, .release);
                coz.progressNamed("gpalloc.phase.xmalloc_preload_trace.consumer");
            }
        }
    } = undefined;
    var producers: [parameters.xmalloc_preload_trace_pair_count]sys_thread.JoinHandle = undefined;
    var consumers: [parameters.xmalloc_preload_trace_pair_count]sys_thread.JoinHandle = undefined;

    for (&phases) |*phase| {
        phase.* = std.atomic.Value(u32).init(0);
    }

    for (&work, 0..) |*item, index| {
        item.* = .{
            .allocator = allocator,
            .alignment = alignment,
            .index = index,
            .phase = &phases[index],
            .records = &records[index],
        };
        consumers[index] = sys_thread.spawn(@TypeOf(item.*).consume, .{item}) catch @panic("thread spawn failed");
        producers[index] = sys_thread.spawn(@TypeOf(item.*).produce, .{item}) catch @panic("thread spawn failed");
    }

    for (producers) |thread| thread.join();
    for (consumers) |thread| thread.join();
}

pub fn reuseTrace(allocator: std.mem.Allocator) void {
    var handoff = std.atomic.Value(u32).init(0);
    var records: [parameters.producer_reuse_batch_count]Record = undefined;

    const Work = struct {
        allocator: std.mem.Allocator,
        handoff: *std.atomic.Value(u32),
        records: *[parameters.producer_reuse_batch_count]Record,

        fn consume(work: *const @This()) void {
            var round: usize = 0;
            while (round < parameters.producer_reuse_round_count) : (round += 1) {
                waitForHandoff(work.handoff, 1);
                {
                    const free_phase = bench.phaseAt("gpalloc.phase.producer_reuse_trace.remote_free", @src());
                    defer free_phase.end();

                    for (work.records.*) |record| {
                        std.mem.doNotOptimizeAway(record.bytes.ptr);
                        work.allocator.free(record.bytes);
                    }
                }
                work.handoff.store(2, .release);
                waitForHandoff(work.handoff, 3);
                work.handoff.store(0, .release);
                coz.progressNamed("gpalloc.phase.producer_reuse_trace.consumer");
            }
        }
    };

    var work = Work{
        .allocator = allocator,
        .handoff = &handoff,
        .records = &records,
    };
    const consumer_thread = sys_thread.spawn(Work.consume, .{&work}) catch @panic("thread spawn failed");

    var round: usize = 0;
    while (round < parameters.producer_reuse_round_count) : (round += 1) {
        if (round == 0) {
            const phase = bench.phaseAt("gpalloc.phase.producer_reuse_trace.allocate", @src());
            defer phase.end();
            reuseAllocate(parameters.producer_reuse_batch_count, allocator, &records, round);
        } else {
            const phase = bench.phaseAt("gpalloc.phase.producer_reuse_trace.reuse", @src());
            defer phase.end();
            reuseAllocate(parameters.producer_reuse_batch_count, allocator, &records, round);
        }

        handoff.store(1, .release);
        waitForHandoff(&handoff, 2);

        handoff.store(3, .release);
        waitForHandoff(&handoff, 0);
        coz.progressNamed("gpalloc.phase.producer_reuse_trace.round");
    }

    consumer_thread.join();
}

fn consumerAllocWorker(work: *ConsumerWork) void {
    var round: usize = 0;
    while (round < parameters.producer_consumer_round_count) : (round += 1) {
        waitForHandoff(work.handoff, 0);
        for (work.records, 0..) |*record, index| {
            const bytes = work.allocator.alloc(u8, 48) catch @panic("allocation failed");
            @memset(bytes, @truncate(index + round));
            record.* = .{ .bytes = bytes };
        }
        work.handoff.store(1, .release);
        waitForHandoff(work.handoff, 0);
    }
}

fn consumerFreeWorker(work: *ConsumerWork) void {
    var round: usize = 0;
    while (round < parameters.producer_consumer_round_count) : (round += 1) {
        waitForHandoff(work.handoff, 1);
        for (work.records) |record| {
            std.mem.doNotOptimizeAway(record.bytes.ptr);
            work.allocator.free(record.bytes);
        }
        work.handoff.store(0, .release);
    }
}

fn waitForHandoff(handoff: *std.atomic.Value(u32), expected: u32) void {
    while (handoff.load(.acquire) != expected) {
        std.atomic.spinLoopHint();
    }
}

fn reuseAllocate(
    comptime count: usize,
    allocator: std.mem.Allocator,
    records: *[count]Record,
    round: usize,
) void {
    for (records, 0..) |*record, index| {
        const bytes = allocator.alloc(u8, reuseSize(index, round)) catch @panic("allocation failed");
        touchEdges(bytes, index + round * 11);
        record.* = .{ .bytes = bytes };
    }
}

fn reuseSize(index: usize, round: usize) usize {
    const sizes = [_]usize{ 48, 64, 96, 128 };
    return sizes[(index * 3 + round) % sizes.len];
}
