const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const sys_thread = @import("sys").thread;
const distribution = @import("distribution.zig");
const parameters = @import("parameters.zig");
const record = @import("record.zig");

const Mode = record.Mode;

pub fn allocTestTrace(allocator: std.mem.Allocator) void {
    runWithSeed(.direct, allocator, 41);
}

pub fn allocTestPreloadTrace(allocator: std.mem.Allocator) void {
    runWithSeed(.preload, allocator, 41);
}

pub fn allocTestPreloadThreadedTrace(allocator: std.mem.Allocator) void {
    const Work = struct {
        allocator: std.mem.Allocator,
        index: usize,

        fn run(work: *const @This()) void {
            const thread_phase = bench.phaseAt("gpalloc.phase.alloc_test_preload_threaded_trace.thread", @src());
            defer thread_phase.end();

            runWithSeed(.preload_threaded, work.allocator, 41 + work.index * 131);
            coz.progressNamed("gpalloc.phase.alloc_test_preload_threaded_trace.thread");
        }
    };

    var work: [parameters.alloc_test_thread_count]Work = undefined;
    var threads: [parameters.alloc_test_thread_count]sys_thread.JoinHandle = undefined;
    for (&threads, 0..) |*thread, index| {
        work[index] = .{ .allocator = allocator, .index = index };
        thread.* = sys_thread.spawn(Work.run, .{&work[index]}) catch @panic("thread spawn failed");
    }
    for (threads) |thread| thread.join();
}

fn runWithSeed(comptime mode: Mode, allocator: std.mem.Allocator, seed: u64) void {
    const RecordType = record.Value(mode);
    var records: [parameters.alloc_test_slot_count]?RecordType = @as([parameters.alloc_test_slot_count]?RecordType, @splat(null));
    var state: u64 = seed;
    var dummy: usize = 0;

    {
        const setup_phase = bench.phaseAt(record.phase(mode, "setup"), @src());
        defer setup_phase.end();

        var group: usize = 0;
        while (group < parameters.alloc_test_slot_count / 32) : (group += 1) {
            const bits = distribution.random32(&state);
            for (0..32) |bit| {
                if (((bits >> @intCast(bit)) & 1) == 0) continue;
                const offset = group * 32 + bit;
                const len = distribution.blockSize(distribution.random64(&state));
                records[offset] = record.alloc(mode, allocator, len);
            }
        }
    }

    {
        const churn_phase = bench.phaseAt(record.phase(mode, "churn"), @src());
        defer churn_phase.end();

        var operation: usize = 0;
        while (operation < parameters.alloc_test_operation_count) : (operation += 1) {
            const offset = distribution.paretoSlot(distribution.random32(&state), distribution.random32(&state));
            if (records[offset]) |allocation| {
                dummy +%= record.read(mode, allocation);
                record.free(mode, allocator, allocation);
                records[offset] = null;
            } else {
                const len = distribution.blockSize(distribution.random64(&state));
                records[offset] = record.alloc(mode, allocator, len);
            }
        }
    }

    {
        const drain_phase = bench.phaseAt(record.phase(mode, "drain"), @src());
        defer drain_phase.end();

        for (&records) |*slot| {
            const allocation = slot.* orelse continue;
            dummy +%= record.read(mode, allocation);
            record.free(mode, allocator, allocation);
            slot.* = null;
        }
    }

    std.mem.doNotOptimizeAway(dummy);
    coz.progressNamed(record.progressName(mode));
}
