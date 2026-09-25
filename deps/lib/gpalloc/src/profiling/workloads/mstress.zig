const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys_thread = @import("sys").thread;
const parameters = @import("parameters.zig");

pub fn run(allocator: std.mem.Allocator) void {
    var survivors: [parameters.mstress_trace_survivor_count]?[]u8 =
        @as([parameters.mstress_trace_survivor_count]?[]u8, @splat(null));
    var survivor_cursor: usize = 0;

    var phase: usize = 0;
    while (phase < parameters.mstress_trace_phase_count) : (phase += 1) {
        {
            const survivor_phase = bench.phaseAt("gpalloc.phase.mstress_trace.survivors", @src());
            defer survivor_phase.end();

            var index: usize = phase % 3;
            while (index < survivor_cursor) : (index += 4) {
                const bytes = survivors[index] orelse continue;
                const resized = allocator.realloc(bytes, survivorSize(index, phase)) catch @panic("realloc failed");
                resized[0] = @truncate(index + phase);
                survivors[index] = resized;
            }
        }

        runPhase(allocator, phase, &survivors, &survivor_cursor);
        coz.progressNamed("gpalloc.phase.mstress_trace.phase");
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.mstress_trace.drain", @src());
        defer drain_phase.end();

        for (&survivors) |*survivor| {
            const bytes = survivor.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            survivor.* = null;
        }
    }
}

fn runPhase(
    allocator: std.mem.Allocator,
    phase: usize,
    survivors: *[parameters.mstress_trace_survivor_count]?[]u8,
    survivor_cursor: *usize,
) void {
    const Work = struct {
        allocator: std.mem.Allocator,
        index: usize,
        phase: usize,
        barrier_epoch: *std.atomic.Value(u32),
        barrier_arrivals: *std.atomic.Value(u32),
        records: *[parameters.mstress_trace_thread_count][parameters.mstress_trace_slot_count]?[]u8,

        fn run(work: *const @This()) void {
            var round: usize = 0;
            while (round < parameters.mstress_trace_round_count) : (round += 1) {
                {
                    const allocate_phase = bench.phaseAt("gpalloc.phase.mstress_trace.allocate", @src());
                    defer allocate_phase.end();

                    const active_count = parameters.mstress_trace_slot_count - ((work.index + work.phase + round) % 3) * 16;
                    var slot: usize = 0;
                    while (slot < active_count) : (slot += 1) {
                        if (work.records[work.index][slot]) |old| {
                            std.mem.doNotOptimizeAway(old.ptr);
                            work.allocator.free(old);
                        }

                        const bytes = work.allocator.alloc(u8, blockSize(work.index, slot, work.phase, round)) catch @panic("allocation failed");
                        bytes[0] = @truncate(slot + round + work.index);
                        work.records[work.index][slot] = bytes;
                    }
                }

                work.waitForBarrier(@intCast(round * 2));

                {
                    const remote_phase = bench.phaseAt("gpalloc.phase.mstress_trace.remote_free", @src());
                    defer remote_phase.end();

                    const owner = (work.index + parameters.mstress_trace_thread_count - 1) % parameters.mstress_trace_thread_count;
                    var slot: usize = 0;
                    while (slot < parameters.mstress_trace_slot_count) : (slot += 1) {
                        const bytes = work.records[owner][slot] orelse continue;
                        if ((slot + round + work.phase + work.index) % 7 == 0) continue;
                        std.mem.doNotOptimizeAway(bytes.ptr);
                        work.allocator.free(bytes);
                        work.records[owner][slot] = null;
                    }
                }

                work.waitForBarrier(@intCast(round * 2 + 1));
                coz.progressNamed("gpalloc.phase.mstress_trace.round");
            }
        }

        fn waitForBarrier(work: *const @This(), expected_epoch: u32) void {
            const arrived = work.barrier_arrivals.fetchAdd(1, .acq_rel) + 1;
            if (arrived == parameters.mstress_trace_thread_count) {
                work.barrier_arrivals.store(0, .release);
                work.barrier_epoch.store(expected_epoch + 1, .release);
                return;
            }

            while (work.barrier_epoch.load(.acquire) == expected_epoch) {
                std.atomic.spinLoopHint();
            }
        }
    };

    const empty_records = @as([parameters.mstress_trace_slot_count]?[]u8, @splat(null));
    var records: [parameters.mstress_trace_thread_count][parameters.mstress_trace_slot_count]?[]u8 =
        @as([parameters.mstress_trace_thread_count][parameters.mstress_trace_slot_count]?[]u8, @splat(empty_records));
    var barrier_epoch = std.atomic.Value(u32).init(0);
    var barrier_arrivals = std.atomic.Value(u32).init(0);
    var work: [parameters.mstress_trace_thread_count]Work = undefined;
    var threads: [parameters.mstress_trace_thread_count]sys_thread.JoinHandle = undefined;

    {
        const thread_phase = bench.phaseAt("gpalloc.phase.mstress_trace.thread_lifetime", @src());
        defer thread_phase.end();

        for (&threads, 0..) |*thread, index| {
            work[index] = .{
                .allocator = allocator,
                .index = index,
                .phase = phase,
                .barrier_epoch = &barrier_epoch,
                .barrier_arrivals = &barrier_arrivals,
                .records = &records,
            };
            thread.* = sys_thread.spawn(Work.run, .{&work[index]}) catch @panic("thread spawn failed");
        }

        for (threads) |thread| thread.join();
    }

    {
        const collect_phase = bench.phaseAt("gpalloc.phase.mstress_trace.collect", @src());
        defer collect_phase.end();

        for (&records, 0..) |*thread_records, thread_index| {
            for (thread_records, 0..) |*record, slot| {
                const bytes = record.* orelse continue;
                if (survivor_cursor.* < survivors.len and (thread_index * 17 + slot + phase * 5) % 5 == 0) {
                    survivors[survivor_cursor.*] = bytes;
                    survivor_cursor.* += 1;
                } else {
                    std.mem.doNotOptimizeAway(bytes.ptr);
                    allocator.free(bytes);
                }
                record.* = null;
            }
        }
    }
}

fn blockSize(thread_index: usize, slot: usize, phase: usize, round: usize) usize {
    const sizes = [_]usize{
        16,
        32,
        64,
        128,
        256,
        512,
        1024,
        2048,
        4096,
        8192,
        16 * 1024,
        32 * 1024,
    };
    return sizes[(thread_index * 7 + slot * 5 + phase * 3 + round * 11) % sizes.len];
}

fn survivorSize(index: usize, phase: usize) usize {
    const sizes = [_]usize{
        64,
        128,
        256,
        512,
        1024,
        2048,
        4096,
        8192,
        16 * 1024,
        32 * 1024,
    };
    return sizes[(index * 13 + phase * 7) % sizes.len];
}
