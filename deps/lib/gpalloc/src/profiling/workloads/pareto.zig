const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");
const touch = @import("touch.zig");

const nextWorkingSetState = touch.nextWorkingSetState;

pub fn sizeMix(allocator: std.mem.Allocator) void {
    var records: [parameters.pareto_slot_count]?[]u8 = @as([parameters.pareto_slot_count]?[]u8, @splat(null));
    var state: u32 = 0x7f4a_7c15;

    {
        const churn_phase = bench.phaseAt("gpalloc.phase.pareto_size_mix.churn", @src());
        defer churn_phase.end();

        var operation: usize = 0;
        while (operation < parameters.pareto_operation_count) : (operation += 1) {
            const offset = nextWorkingSetState(&state) % parameters.pareto_slot_count;
            if (records[offset]) |bytes| {
                allocator.free(bytes);
            }

            const len = blockSize(nextWorkingSetState(&state));
            const bytes = allocator.alloc(u8, len) catch @panic("allocation failed");
            bytes[0] = @truncate(operation);
            records[offset] = bytes;
        }
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.pareto_size_mix.drain", @src());
        defer drain_phase.end();

        for (&records) |*record| {
            const bytes = record.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            record.* = null;
        }
    }

    coz.progressNamed("gpalloc.workload.pareto_size_mix");
}

fn blockSize(state: usize) usize {
    const min_size = 8;
    const max_size = 64 * 1024;
    const scale = 65_535;
    const sample = state & scale;
    const denominator = max_size * scale - sample * (max_size - min_size);
    return (min_size * max_size * scale) / denominator;
}
