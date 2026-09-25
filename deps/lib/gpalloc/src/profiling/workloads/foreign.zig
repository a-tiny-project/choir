const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys_thread = @import("sys").thread;
const histogram = @import("histogram.zig");
const parameters = @import("parameters.zig");
const record = @import("entry.zig");
const raw_record = @import("raw.zig");

const RawRecord = raw_record.RawRecord;
const Mode = record.Mode;

pub fn foreignFreeTrace(allocator: std.mem.Allocator) void {
    runTrace(
        parameters.foreign_free_trace_slot_count,
        parameters.foreign_free_trace_iteration_count,
        parameters.foreign_free_trace_foreign_count,
        allocator,
    );
}

pub fn foreignFreeDetailTrace(allocator: std.mem.Allocator) void {
    runTrace(
        parameters.foreign_free_detail_trace_slot_count,
        parameters.foreign_free_detail_trace_iteration_count,
        parameters.foreign_free_detail_trace_foreign_count,
        allocator,
    );
}

pub fn foreignFreePreloadTrace(allocator: std.mem.Allocator) void {
    runPreloadTrace(
        parameters.foreign_free_preload_trace_slot_count,
        parameters.foreign_free_preload_trace_iteration_count,
        parameters.foreign_free_preload_trace_foreign_count,
        allocator,
    );
}

pub fn sh8PreloadTrace(allocator: std.mem.Allocator) void {
    runSh8PreloadTrace(
        parameters.sh8_preload_trace_thread_count,
        parameters.sh8_preload_trace_slot_count,
        parameters.sh8_preload_trace_iteration_count,
        allocator,
    );
}

pub fn sh8PreloadDetailTrace(allocator: std.mem.Allocator) void {
    runModeWith(
        .sh8_preload_detail,
        parameters.sh8_preload_detail_trace_thread_count,
        parameters.sh8_preload_detail_trace_slot_count,
        parameters.sh8_preload_detail_trace_iteration_count,
        parameters.sh8_preload_detail_trace_foreign_count,
        allocator,
    );
}

fn runTrace(
    comptime slot_count: usize,
    comptime iteration_count: usize,
    comptime foreign_count: usize,
    allocator: std.mem.Allocator,
) void {
    runModeWith(
        .direct,
        parameters.foreign_free_trace_thread_count,
        slot_count,
        iteration_count,
        foreign_count,
        allocator,
    );
}

fn runPreloadTrace(
    comptime slot_count: usize,
    comptime iteration_count: usize,
    comptime foreign_count: usize,
    allocator: std.mem.Allocator,
) void {
    runModeWith(
        .preload,
        parameters.foreign_free_trace_thread_count,
        slot_count,
        iteration_count,
        foreign_count,
        allocator,
    );
}

fn runSh8PreloadTrace(
    comptime thread_count: usize,
    comptime slot_count: usize,
    comptime iteration_count: usize,
    allocator: std.mem.Allocator,
) void {
    const empty_records = @as([slot_count]?RawRecord, @splat(null));
    var records: [thread_count][slot_count]?RawRecord =
        @as([thread_count][slot_count]?RawRecord, @splat(empty_records));

    const Work = struct {
        allocator: std.mem.Allocator,
        index: usize,
        records: *[slot_count]?RawRecord,
        ready: *std.atomic.Value(u32),
        gate: *std.atomic.Value(u32),

        fn run(work: *const @This()) void {
            _ = work.ready.fetchAdd(1, .acq_rel);
            while (work.gate.load(.acquire) == 0) {
                std.atomic.spinLoopHint();
            }
            runLocalTraceWith(
                .sh8_preload,
                slot_count,
                iteration_count,
                work.allocator,
                std.mem.Alignment.fromByteUnits(parameters.preload_alignment_bytes),
                work.records,
                work.index,
            );
        }
    };

    var ready = std.atomic.Value(u32).init(0);
    var gate = std.atomic.Value(u32).init(0);
    var work: [thread_count]Work = undefined;
    var threads: [thread_count - 1]sys_thread.JoinHandle = undefined;

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

    while (ready.load(.acquire) != thread_count - 1) {
        std.atomic.spinLoopHint();
    }
    gate.store(1, .release);

    runLocalTraceWith(
        .sh8_preload,
        slot_count,
        iteration_count,
        allocator,
        std.mem.Alignment.fromByteUnits(parameters.preload_alignment_bytes),
        &records[0],
        0,
    );

    for (threads) |thread| thread.join();
}

fn runModeWith(
    comptime mode: Mode,
    comptime thread_count: usize,
    comptime slot_count: usize,
    comptime iteration_count: usize,
    comptime foreign_count: usize,
    allocator: std.mem.Allocator,
) void {
    const RecordType = record.Value(mode);
    const alignment = std.mem.Alignment.fromByteUnits(parameters.preload_alignment_bytes);
    const empty_records = @as([slot_count]?RecordType, @splat(null));
    var records: [thread_count][slot_count]?RecordType =
        @as([thread_count][slot_count]?RecordType, @splat(empty_records));
    var foreign_records: [foreign_count]?RecordType = @as([foreign_count]?RecordType, @splat(null));

    const Producer = struct {
        allocator: std.mem.Allocator,
        alignment: std.mem.Alignment,
        foreign_records: *[foreign_count]?RecordType,

        fn run(producer: *const @This()) void {
            const allocate_phase = bench.phaseAt(record.phase(mode, "remote_allocate"), @src());
            defer allocate_phase.end();

            for (producer.foreign_records, 0..) |*slot, index| {
                slot.* = record.alloc(
                    mode,
                    producer.allocator,
                    producer.alignment,
                    histogram.values[0].size,
                    index,
                );
            }
            coz.progressNamed(record.phase(mode, "remote_allocate"));
        }
    };

    var producer = Producer{
        .allocator = allocator,
        .alignment = alignment,
        .foreign_records = &foreign_records,
    };
    const producer_thread = sys_thread.spawn(Producer.run, .{&producer}) catch @panic("thread spawn failed");
    producer_thread.join();

    const Work = struct {
        allocator: std.mem.Allocator,
        alignment: std.mem.Alignment,
        index: usize,
        records: *[slot_count]?RecordType,
        foreign_records: *[foreign_count]?RecordType,
        ready: *std.atomic.Value(u32),
        gate: *std.atomic.Value(u32),

        fn run(work: *const @This()) void {
            _ = work.ready.fetchAdd(1, .acq_rel);
            while (work.gate.load(.acquire) == 0) {
                std.atomic.spinLoopHint();
            }
            runWorker(
                mode,
                thread_count,
                slot_count,
                iteration_count,
                foreign_count,
                work.allocator,
                work.alignment,
                work.records,
                work.foreign_records,
                work.index,
            );
        }
    };

    var ready = std.atomic.Value(u32).init(0);
    var gate = std.atomic.Value(u32).init(0);
    var work: [thread_count]Work = undefined;
    var threads: [thread_count - 1]sys_thread.JoinHandle = undefined;

    for (&threads, 0..) |*thread, worker_index| {
        const index = worker_index + 1;
        work[index] = .{
            .allocator = allocator,
            .alignment = alignment,
            .index = index,
            .records = &records[index],
            .foreign_records = &foreign_records,
            .ready = &ready,
            .gate = &gate,
        };
        thread.* = sys_thread.spawn(Work.run, .{&work[index]}) catch @panic("thread spawn failed");
    }

    while (ready.load(.acquire) != thread_count - 1) {
        std.atomic.spinLoopHint();
    }
    gate.store(1, .release);

    runWorker(
        mode,
        thread_count,
        slot_count,
        iteration_count,
        foreign_count,
        allocator,
        alignment,
        &records[0],
        &foreign_records,
        0,
    );

    for (threads) |thread| thread.join();

    {
        const drain_phase = bench.phaseAt(record.phase(mode, "foreign_drain"), @src());
        defer drain_phase.end();

        for (&foreign_records) |*slot| {
            const allocation = slot.* orelse continue;
            record.free(mode, allocator, allocation);
            slot.* = null;
        }
        coz.progressNamed(record.phase(mode, "foreign_drain"));
    }
}

fn runWorker(
    comptime mode: Mode,
    comptime thread_count: usize,
    comptime slot_count: usize,
    comptime iteration_count: usize,
    comptime foreign_count: usize,
    allocator: std.mem.Allocator,
    alignment: std.mem.Alignment,
    records: *[slot_count]?record.Value(mode),
    foreign_records: *[foreign_count]?record.Value(mode),
    index: usize,
) void {
    const thread_phase = bench.phaseAt(record.phase(mode, "thread"), @src());
    defer thread_phase.end();

    {
        const foreign_phase = bench.phaseAt(record.phase(mode, "foreign_free"), @src());
        defer foreign_phase.end();

        var slot = index;
        while (slot < foreign_count) : (slot += thread_count) {
            const allocation = foreign_records[slot] orelse continue;
            record.free(mode, allocator, allocation);
            foreign_records[slot] = null;
        }
        coz.progressNamed(record.phase(mode, "foreign_free"));
    }

    runLocalTraceWith(mode, slot_count, iteration_count, allocator, alignment, records, index);
    coz.progressNamed(record.phase(mode, "thread"));
}

fn runLocalTraceWith(
    comptime mode: Mode,
    comptime slot_count: usize,
    comptime iteration_count: usize,
    allocator: std.mem.Allocator,
    alignment: std.mem.Alignment,
    records: *[slot_count]?record.Value(mode),
    seed: usize,
) void {
    var cursor: usize = 0;
    var save_start: usize = slot_count;
    var save_end: usize = slot_count;

    var iteration: usize = 0;
    while (iteration < iteration_count) : (iteration += 1) {
        const entry = histogram.values[(iteration + seed) % histogram.values.len];
        {
            const allocate_phase = bench.phaseAt(record.phase(mode, "allocate"), @src());
            defer allocate_phase.end();

            var count = entry.count;
            while (count != 0) : (count -= 1) {
                while (true) {
                    if (cursor == save_start) cursor = save_end;
                    if (cursor < slot_count) break;
                    cycleFree(mode, slot_count, allocator, records, &save_start, &save_end, &cursor);
                }

                if (records[cursor]) |allocation| {
                    record.free(mode, allocator, allocation);
                }
                records[cursor] = record.alloc(
                    mode,
                    allocator,
                    alignment,
                    entry.size,
                    entry.size + cursor + iteration + seed * 19,
                );
                cursor += 1;
            }
        }
        coz.progressNamed(record.phase(mode, "allocate"));
    }

    {
        const drain_phase = bench.phaseAt(record.phase(mode, "drain"), @src());
        defer drain_phase.end();

        for (records) |*slot| {
            const allocation = slot.* orelse continue;
            record.free(mode, allocator, allocation);
            slot.* = null;
        }
        coz.progressNamed(record.phase(mode, "drain"));
    }
}

fn cycleFree(
    comptime mode: Mode,
    comptime slot_count: usize,
    allocator: std.mem.Allocator,
    records: *[slot_count]?record.Value(mode),
    save_start: *usize,
    save_end: *usize,
    cursor: *usize,
) void {
    cursor.* = 0;
    save_start.* = save_end.*;
    if (save_start.* >= slot_count) save_start.* = 0;
    save_end.* = @min(save_start.* + slot_count / 5, slot_count);

    {
        const fifo_phase = bench.phaseAt(record.phase(mode, "fifo_free"), @src());
        defer fifo_phase.end();

        while (cursor.* < save_start.*) : (cursor.* += 1) {
            const allocation = records[cursor.*] orelse continue;
            record.free(mode, allocator, allocation);
            records[cursor.*] = null;
        }
        coz.progressNamed(record.phase(mode, "fifo_free"));
    }

    {
        const lifo_phase = bench.phaseAt(record.phase(mode, "lifo_free"), @src());
        defer lifo_phase.end();

        cursor.* = slot_count;
        while (cursor.* > save_end.*) {
            cursor.* -= 1;
            const allocation = records[cursor.*] orelse continue;
            record.free(mode, allocator, allocation);
            records[cursor.*] = null;
        }
        coz.progressNamed(record.phase(mode, "lifo_free"));
    }

    cursor.* = 0;
    coz.progressNamed(record.phase(mode, "cycle"));
}
