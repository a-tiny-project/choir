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

pub fn reverseFreeTrace(allocator: std.mem.Allocator) void {
    var records: [parameters.reverse_free_trace_slot_count]?[]u8 =
        @as([parameters.reverse_free_trace_slot_count]?[]u8, @splat(null));
    runTraceWith(
        parameters.reverse_free_trace_slot_count,
        parameters.reverse_free_trace_repeat_count,
        allocator,
        &records,
        0,
    );
}

pub fn reverseFreePreloadTrace(allocator: std.mem.Allocator) void {
    var records: [parameters.reverse_free_preload_trace_slot_count]?RawRecord =
        @as([parameters.reverse_free_preload_trace_slot_count]?RawRecord, @splat(null));
    runPreloadTraceWith(
        parameters.reverse_free_preload_trace_slot_count,
        parameters.reverse_free_preload_trace_repeat_count,
        allocator,
        &records,
        0,
    );
}

pub fn reverseFreeThreadedTrace(allocator: std.mem.Allocator) void {
    const Work = struct {
        allocator: std.mem.Allocator,
        index: usize,
        records: *[parameters.reverse_free_threaded_trace_slot_count]?[]u8,
        ready: *std.atomic.Value(u32),
        gate: *std.atomic.Value(u32),

        fn run(work: *const @This()) void {
            _ = work.ready.fetchAdd(1, .acq_rel);
            while (work.gate.load(.acquire) == 0) {
                std.atomic.spinLoopHint();
            }
            runTraceWith(
                parameters.reverse_free_threaded_trace_slot_count,
                parameters.reverse_free_threaded_trace_repeat_count,
                work.allocator,
                work.records,
                work.index + 1,
            );
        }
    };

    const empty_records = @as([parameters.reverse_free_threaded_trace_slot_count]?[]u8, @splat(null));
    var records: [parameters.reverse_free_threaded_trace_thread_count][parameters.reverse_free_threaded_trace_slot_count]?[]u8 =
        @as([parameters.reverse_free_threaded_trace_thread_count][parameters.reverse_free_threaded_trace_slot_count]?[]u8, @splat(empty_records));
    var ready = std.atomic.Value(u32).init(0);
    var gate = std.atomic.Value(u32).init(0);
    var work: [parameters.reverse_free_threaded_trace_thread_count]Work = undefined;
    var threads: [parameters.reverse_free_threaded_trace_thread_count - 1]sys_thread.JoinHandle = undefined;

    for (&threads, 0..) |*thread, worker_index| {
        const index = worker_index + 1;
        work[index] = .{
            .allocator = allocator,
            .index = index,
            .records = &records[index],
            .ready = &ready,
            .gate = &gate,
        };
        thread.* = sys_thread.spawn(Work.run, .{&work[index]}) catch @panic("thread spawn failed");
    }

    while (ready.load(.acquire) != parameters.reverse_free_threaded_trace_thread_count - 1) {
        std.atomic.spinLoopHint();
    }
    gate.store(1, .release);

    runTraceWith(
        parameters.reverse_free_threaded_trace_slot_count,
        parameters.reverse_free_threaded_trace_repeat_count,
        allocator,
        &records[0],
        0,
    );

    for (threads) |thread| thread.join();
}

fn runTraceWith(
    comptime slot_count: usize,
    comptime repeat_count: usize,
    allocator: std.mem.Allocator,
    records: *[slot_count]?[]u8,
    seed: usize,
) void {
    var cursor: usize = 0;
    var save_start: usize = slot_count;
    var save_end: usize = slot_count;

    var repeat: usize = 0;
    while (repeat < repeat_count) : (repeat += 1) {
        var size_base: usize = 1;
        while (size_base < parameters.reverse_free_trace_max_size) : (size_base = size_base * 3 / 2 + 1) {
            var size = size_base;
            while (size != 0) : (size /= 2) {
                {
                    const allocate_phase = bench.phaseAt("gpalloc.phase.reverse_free_trace.allocate", @src());
                    defer allocate_phase.end();

                    var count = iterations(size);
                    while (count != 0) : (count -= 1) {
                        while (true) {
                            if (cursor == save_start) cursor = save_end;
                            if (cursor < slot_count) break;
                            cycleFree(slot_count, allocator, records, &save_start, &save_end, &cursor);
                        }

                        if (records[cursor]) |bytes| {
                            std.mem.doNotOptimizeAway(bytes.ptr);
                            allocator.free(bytes);
                        }
                        const bytes = allocator.alloc(u8, size) catch @panic("allocation failed");
                        touchEdges(bytes, size + cursor + repeat + seed * 17);
                        records[cursor] = bytes;
                        cursor += 1;
                    }
                }
                coz.progressNamed("gpalloc.phase.reverse_free_trace.allocate");
            }
        }
        coz.progressNamed("gpalloc.phase.reverse_free_trace.repeat");
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.reverse_free_trace.drain", @src());
        defer drain_phase.end();

        for (records) |*record| {
            const bytes = record.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            record.* = null;
        }
        coz.progressNamed("gpalloc.phase.reverse_free_trace.drain");
    }
}

fn runPreloadTraceWith(
    comptime slot_count: usize,
    comptime repeat_count: usize,
    allocator: std.mem.Allocator,
    records: *[slot_count]?RawRecord,
    seed: usize,
) void {
    const alignment = std.mem.Alignment.fromByteUnits(parameters.preload_alignment_bytes);
    var cursor: usize = 0;
    var save_start: usize = slot_count;
    var save_end: usize = slot_count;

    var repeat: usize = 0;
    while (repeat < repeat_count) : (repeat += 1) {
        var size_base: usize = 1;
        while (size_base < parameters.reverse_free_trace_max_size) : (size_base = size_base * 3 / 2 + 1) {
            var size = size_base;
            while (size != 0) : (size /= 2) {
                {
                    const allocate_phase = bench.phaseAt("gpalloc.phase.reverse_free_preload_trace.allocate", @src());
                    defer allocate_phase.end();

                    var count = iterations(size);
                    while (count != 0) : (count -= 1) {
                        while (true) {
                            if (cursor == save_start) cursor = save_end;
                            if (cursor < slot_count) break;
                            preloadCycleFree(slot_count, allocator, records, &save_start, &save_end, &cursor);
                        }

                        if (records[cursor]) |record| {
                            preload_record.free(allocator, record);
                        }
                        records[cursor] = preload_record.alloc(allocator, alignment, size, size + cursor + repeat + seed * 17);
                        cursor += 1;
                    }
                }
                coz.progressNamed("gpalloc.phase.reverse_free_preload_trace.allocate");
            }
        }
        coz.progressNamed("gpalloc.phase.reverse_free_preload_trace.repeat");
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.reverse_free_preload_trace.drain", @src());
        defer drain_phase.end();

        for (records) |*record| {
            const value = record.* orelse continue;
            preload_record.free(allocator, value);
            record.* = null;
        }
        coz.progressNamed("gpalloc.phase.reverse_free_preload_trace.drain");
    }
}

fn cycleFree(
    comptime slot_count: usize,
    allocator: std.mem.Allocator,
    records: *[slot_count]?[]u8,
    save_start: *usize,
    save_end: *usize,
    cursor: *usize,
) void {
    cursor.* = 0;
    save_start.* = save_end.*;
    if (save_start.* >= slot_count) save_start.* = 0;
    save_end.* = @min(save_start.* + slot_count / 5, slot_count);

    {
        const fifo_phase = bench.phaseAt("gpalloc.phase.reverse_free_trace.fifo_free", @src());
        defer fifo_phase.end();

        while (cursor.* < save_start.*) : (cursor.* += 1) {
            const bytes = records[cursor.*] orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            records[cursor.*] = null;
        }
        coz.progressNamed("gpalloc.phase.reverse_free_trace.fifo_free");
    }

    {
        const lifo_phase = bench.phaseAt("gpalloc.phase.reverse_free_trace.lifo_free", @src());
        defer lifo_phase.end();

        cursor.* = slot_count;
        while (cursor.* > save_end.*) {
            cursor.* -= 1;
            const bytes = records[cursor.*] orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            records[cursor.*] = null;
        }
        coz.progressNamed("gpalloc.phase.reverse_free_trace.lifo_free");
    }

    cursor.* = 0;
    coz.progressNamed("gpalloc.phase.reverse_free_trace.cycle");
}

fn preloadCycleFree(
    comptime slot_count: usize,
    allocator: std.mem.Allocator,
    records: *[slot_count]?RawRecord,
    save_start: *usize,
    save_end: *usize,
    cursor: *usize,
) void {
    cursor.* = 0;
    save_start.* = save_end.*;
    if (save_start.* >= slot_count) save_start.* = 0;
    save_end.* = @min(save_start.* + slot_count / 5, slot_count);

    {
        const fifo_phase = bench.phaseAt("gpalloc.phase.reverse_free_preload_trace.fifo_free", @src());
        defer fifo_phase.end();

        while (cursor.* < save_start.*) : (cursor.* += 1) {
            const record = records[cursor.*] orelse continue;
            preload_record.free(allocator, record);
            records[cursor.*] = null;
        }
        coz.progressNamed("gpalloc.phase.reverse_free_preload_trace.fifo_free");
    }

    {
        const lifo_phase = bench.phaseAt("gpalloc.phase.reverse_free_preload_trace.lifo_free", @src());
        defer lifo_phase.end();

        cursor.* = slot_count;
        while (cursor.* > save_end.*) {
            cursor.* -= 1;
            const record = records[cursor.*] orelse continue;
            preload_record.free(allocator, record);
            records[cursor.*] = null;
        }
        coz.progressNamed("gpalloc.phase.reverse_free_preload_trace.lifo_free");
    }

    cursor.* = 0;
    coz.progressNamed("gpalloc.phase.reverse_free_preload_trace.cycle");
}

fn iterations(size: usize) usize {
    var count: usize = 1;
    if (size < 10000) count = 10;
    if (size < 1000) count *= 5;
    if (size < 100) count *= 5;
    return count;
}
