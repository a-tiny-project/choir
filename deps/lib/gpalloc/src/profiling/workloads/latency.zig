const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const gpalloc = @import("gpalloc");
const parameters = @import("parameters.zig");

const Record = struct {
    bytes: []u8,
};

pub fn run(allocator: std.mem.Allocator) void {
    var records: [parameters.tail_latency_batch_count]Record = undefined;

    var burst: usize = 0;
    while (burst < parameters.tail_latency_burst_count) : (burst += 1) {
        {
            const fill_phase = bench.phaseAt("gpalloc.phase.tail_latency.fill", @src());
            defer fill_phase.end();

            for (&records, 0..) |*record, index| {
                const len = size(index, burst);
                const bytes = allocator.alloc(u8, len) catch @panic("allocation failed");
                bytes[0] = @truncate(index + burst);
                record.* = .{ .bytes = bytes };
            }
        }

        {
            const release_phase = bench.phaseAt("gpalloc.phase.tail_latency.release", @src());
            defer release_phase.end();

            var index: usize = records.len;
            while (index > 0) {
                index -= 1;
                const record = records[index];
                std.mem.doNotOptimizeAway(record.bytes.ptr);
                allocator.free(record.bytes);
            }
        }

        {
            const probe_phase = bench.phaseAt("gpalloc.phase.tail_latency.probe", @src());
            defer probe_phase.end();

            var probe_index: usize = 0;
            while (probe_index < 8) : (probe_index += 1) {
                const bytes = allocator.alloc(u8, size(probe_index * 17, burst)) catch @panic("allocation failed");
                bytes[0] = @truncate(probe_index);
                std.mem.doNotOptimizeAway(bytes.ptr);
                allocator.free(bytes);
            }
        }

        coz.progressNamed("gpalloc.phase.tail_latency.burst");
    }
}

fn size(index: usize, burst: usize) usize {
    const sizes = [_]usize{
        16,
        48,
        96,
        192,
        512,
        2048,
        8192,
        gpalloc.max_small_size,
        gpalloc.max_small_size + 512,
    };
    return sizes[(index * 5 + burst * 3) % sizes.len];
}
