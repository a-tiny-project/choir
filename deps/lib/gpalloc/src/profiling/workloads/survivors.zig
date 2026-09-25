const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const gpalloc = @import("gpalloc");
const parameters = @import("parameters.zig");

pub fn run(allocator: std.mem.Allocator) void {
    runWith(
        parameters.phase_survivor_phase_count,
        parameters.phase_survivor_object_count,
        parameters.phase_survivor_count,
        parameters.phase_survivor_replay_count,
        allocator,
    );
}

pub fn full(allocator: std.mem.Allocator) void {
    runWith(
        parameters.phase_survivor_full_phase_count,
        parameters.phase_survivor_full_object_count,
        parameters.phase_survivor_full_count,
        parameters.phase_survivor_full_replay_count,
        allocator,
    );
}

fn runWith(
    comptime phase_count: usize,
    comptime object_count: usize,
    comptime survivor_count: usize,
    comptime replay_count: usize,
    allocator: std.mem.Allocator,
) void {
    var survivors: [survivor_count]?[]u8 = @as([survivor_count]?[]u8, @splat(null));
    var survivor_index: usize = 0;

    var phase: usize = 0;
    while (phase < phase_count) : (phase += 1) {
        var phase_records: [object_count]?[]u8 = @as([object_count]?[]u8, @splat(null));

        {
            const allocate_phase = bench.phaseAt("gpalloc.phase.phase_survivors.allocate", @src());
            defer allocate_phase.end();

            for (&phase_records, 0..) |*record, index| {
                const len = survivorSize(index, phase);
                const bytes = allocator.alloc(u8, len) catch @panic("allocation failed");
                bytes[0] = @truncate(index + phase);
                record.* = bytes;
            }
        }

        {
            const filter_phase = bench.phaseAt("gpalloc.phase.phase_survivors.filter", @src());
            defer filter_phase.end();

            for (&phase_records, 0..) |*record, index| {
                const bytes = record.* orelse continue;
                if (survivor_index < survivor_count and (index + phase * 11) % 8 == 0) {
                    survivors[survivor_index] = bytes;
                    survivor_index += 1;
                    record.* = null;
                }
            }
        }

        {
            const release_phase = bench.phaseAt("gpalloc.phase.phase_survivors.release", @src());
            defer release_phase.end();

            for (&phase_records) |*record| {
                const bytes = record.* orelse continue;
                std.mem.doNotOptimizeAway(bytes.ptr);
                allocator.free(bytes);
                record.* = null;
            }
        }

        {
            const replay_phase = bench.phaseAt("gpalloc.phase.phase_survivors.replay", @src());
            defer replay_phase.end();

            var replay: usize = 0;
            while (replay < replay_count) : (replay += 1) {
                const bytes = allocator.alloc(u8, replaySize(replay, phase)) catch @panic("allocation failed");
                bytes[0] = @truncate(replay);
                std.mem.doNotOptimizeAway(bytes.ptr);
                allocator.free(bytes);
            }
        }

        coz.progressNamed("gpalloc.phase.phase_survivors.phase");
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.phase_survivors.drain", @src());
        defer drain_phase.end();

        for (&survivors) |*record| {
            const bytes = record.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            record.* = null;
        }
    }
}

fn survivorSize(index: usize, phase: usize) usize {
    const sizes = [_]usize{
        24,
        48,
        96,
        192,
        384,
        768,
        1536,
        3072,
        8192,
        16 * 1024,
        gpalloc.max_small_size,
        gpalloc.max_small_size + 4096,
        64 * 1024,
    };
    return sizes[(index * 7 + phase * 5) % sizes.len];
}

fn replaySize(index: usize, phase: usize) usize {
    const sizes = [_]usize{
        32,
        64,
        128,
        256,
        512,
        1024,
        2048,
        4096,
        gpalloc.max_small_size + 512,
    };
    return sizes[(index * 11 + phase * 3) % sizes.len];
}
