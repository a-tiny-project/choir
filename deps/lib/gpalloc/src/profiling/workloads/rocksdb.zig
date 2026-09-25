const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const memtable = @import("memtable.zig");
const parameters = @import("parameters.zig");
const profile = @import("profile.zig");
const touch = @import("touch.zig");

const Profile = profile.Profile;
const touchEdges = touch.edges;

pub fn rocksdbFillrandomTrace(allocator: std.mem.Allocator) void {
    run(.native, allocator);
}

pub fn rocksdbFillrandomPreloadTrace(allocator: std.mem.Allocator) void {
    run(.preload, allocator);
}

fn run(comptime active_profile: Profile, allocator: std.mem.Allocator) void {
    var memtables: [parameters.rocksdb_trace_memtable_count]memtable.Memtable =
        @as([parameters.rocksdb_trace_memtable_count]memtable.Memtable, @splat(.{}));

    {
        const open_phase = bench.phaseAt(profile.phase(active_profile, "open"), @src());
        defer open_phase.end();

        var options: [8]?[]u8 = @as([8]?[]u8, @splat(null));
        for (&options, 0..) |*option, index| {
            const bytes = allocator.alloc(u8, profile.size(active_profile, profile.optionsSize(index))) catch @panic("allocation failed");
            touchEdges(bytes, index);
            option.* = bytes;
        }
        for (&options) |*option| {
            const bytes = option.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            option.* = null;
        }
        coz.progressNamed(profile.phase(active_profile, "open"));
    }

    var round: usize = 0;
    while (round < parameters.rocksdb_trace_round_count) : (round += 1) {
        const slot = round % parameters.rocksdb_trace_memtable_count;
        if (memtable.active(&memtables[slot])) {
            memtable.flushAndDrop(active_profile, allocator, &memtables[slot], round + 0x100);
        }

        memtable.create(active_profile, allocator, &memtables[slot], round);
        memtable.fill(active_profile, allocator, &memtables[slot], round);

        if (round > 0) {
            const flush_slot = (round + parameters.rocksdb_trace_memtable_count - 1) % parameters.rocksdb_trace_memtable_count;
            if (memtable.active(&memtables[flush_slot])) {
                memtable.flushAndDrop(active_profile, allocator, &memtables[flush_slot], round);
            }
        }
        coz.progressNamed(profile.phase(active_profile, "round"));
    }

    {
        const drain_phase = bench.phaseAt(profile.phase(active_profile, "drain"), @src());
        defer drain_phase.end();

        for (&memtables, 0..) |*slot, index| {
            if (memtable.active(slot)) {
                memtable.flushAndDrop(active_profile, allocator, slot, index + parameters.rocksdb_trace_round_count);
            }
        }
        coz.progressNamed(profile.phase(active_profile, "drain"));
    }
}
