const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys_thread = @import("sys").thread;
const parameters = @import("parameters.zig");
const preload_record = @import("preload.zig");
const raw_record = @import("raw.zig");
const touch = @import("touch.zig");

const RawRecord = raw_record.RawRecord;
const nextWorkingSetState = touch.nextWorkingSetState;

const Record = struct {
    bytes: []u8,
};

const Work = struct {
    allocator: std.mem.Allocator,
    records: *[parameters.larson_live_count]Record,
    seed: u32,
};

const PreloadWork = struct {
    allocator: std.mem.Allocator,
    records: *[parameters.larson_preload_live_count]RawRecord,
    seed: u32,
};

pub fn run(allocator: std.mem.Allocator) void {
    var records: [parameters.larson_thread_count][parameters.larson_live_count]Record = undefined;
    var work: [parameters.larson_thread_count]Work = undefined;
    var threads: [parameters.larson_thread_count]sys_thread.JoinHandle = undefined;
    for (&threads, 0..) |*thread, index| {
        const seed: u32 = @truncate(index);
        work[index] = .{
            .allocator = allocator,
            .records = &records[index],
            .seed = 0x9e37_79b9 +% seed *% 0x85eb_ca6b,
        };
        thread.* = sys_thread.spawn(worker, .{&work[index]}) catch @panic("thread spawn failed");
    }
    for (threads) |thread| thread.join();
}

pub fn preloadTrace(allocator: std.mem.Allocator) void {
    var records: [parameters.larson_preload_thread_count][parameters.larson_preload_live_count]RawRecord = undefined;
    var work: [parameters.larson_preload_thread_count]PreloadWork = undefined;
    var threads: [parameters.larson_preload_thread_count]sys_thread.JoinHandle = undefined;
    for (&threads, 0..) |*thread, index| {
        const seed: u32 = @truncate(index);
        work[index] = .{
            .allocator = allocator,
            .records = &records[index],
            .seed = 0x6d2b_79f5 +% seed *% 0x9e37_79b9,
        };
        thread.* = sys_thread.spawn(preloadWorker, .{&work[index]}) catch @panic("thread spawn failed");
    }
    for (threads) |thread| thread.join();
}

fn worker(work: *const Work) void {
    var state = work.seed;
    for (work.records, 0..) |*record, index| {
        const len = blockSize(nextWorkingSetState(&state));
        const bytes = work.allocator.alloc(u8, len) catch @panic("allocation failed");
        bytes[0] = @truncate(index);
        record.* = .{ .bytes = bytes };
    }

    var round: usize = 0;
    while (round < parameters.larson_round_count) : (round += 1) {
        var slot: usize = 0;
        while (slot < parameters.larson_live_count) : (slot += 1) {
            const operation = round * parameters.larson_live_count + slot;
            const victim = nextWorkingSetState(&state) % parameters.larson_live_count;
            const old = work.records[victim].bytes;
            std.mem.doNotOptimizeAway(old.ptr);
            work.allocator.free(old);

            const len = blockSize(nextWorkingSetState(&state));
            const bytes = work.allocator.alloc(u8, len) catch @panic("allocation failed");
            bytes[0] = @truncate(operation);
            work.records[victim] = .{ .bytes = bytes };
        }
        coz.progressNamed("gpalloc.phase.larson.round");
    }

    for (work.records.*) |record| {
        std.mem.doNotOptimizeAway(record.bytes.ptr);
        work.allocator.free(record.bytes);
    }
    coz.progressNamed("gpalloc.phase.larson.thread");
}

fn preloadWorker(work: *const PreloadWork) void {
    var state = work.seed;
    const alignment = std.mem.Alignment.fromByteUnits(parameters.preload_alignment_bytes);

    {
        const fill_phase = bench.phaseAt("gpalloc.phase.larson_preload_trace.fill", @src());
        defer fill_phase.end();

        for (work.records, 0..) |*record, index| {
            const user_len = preloadUserSize(nextWorkingSetState(&state));
            record.* = preload_record.alloc(work.allocator, alignment, user_len, index);
        }
    }

    var round: usize = 0;
    while (round < parameters.larson_preload_round_count) : (round += 1) {
        {
            const churn_phase = bench.phaseAt("gpalloc.phase.larson_preload_trace.churn", @src());
            defer churn_phase.end();

            var operation: usize = 0;
            while (operation < parameters.larson_preload_live_count) : (operation += 1) {
                const victim = nextWorkingSetState(&state) % parameters.larson_preload_live_count;
                const old = work.records[victim];
                preload_record.free(work.allocator, old);

                const user_len = preloadUserSize(nextWorkingSetState(&state));
                work.records[victim] = preload_record.alloc(
                    work.allocator,
                    alignment,
                    user_len,
                    operation + round * parameters.larson_preload_live_count,
                );
            }
        }

        coz.progressNamed("gpalloc.phase.larson_preload_trace.round");
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.larson_preload_trace.drain", @src());
        defer drain_phase.end();

        for (work.records) |record| {
            preload_record.free(work.allocator, record);
        }
    }
}

fn blockSize(state: usize) usize {
    return parameters.larson_min_size + state % (parameters.larson_max_size - parameters.larson_min_size);
}

fn preloadUserSize(state: usize) usize {
    return parameters.larson_preload_min_size + state % (parameters.larson_preload_max_size - parameters.larson_preload_min_size);
}
