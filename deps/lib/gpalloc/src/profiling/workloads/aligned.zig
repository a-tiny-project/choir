const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");
const raw_record = @import("raw.zig");

const RawRecord = raw_record.RawRecord;

pub fn run(allocator: std.mem.Allocator) void {
    var records: [parameters.aligned_mix_count]RawRecord = undefined;

    {
        const allocate_phase = bench.phaseAt("gpalloc.phase.aligned_mix.allocate", @src());
        defer allocate_phase.end();

        for (&records, 0..) |*record, index| {
            const record_alignment = alignment(index);
            const len = 24 + (index * 97) % 8192;
            const ptr = allocator.rawAlloc(len, record_alignment, @returnAddress()) orelse @panic("allocation failed");
            if (@intFromPtr(ptr) % record_alignment.toByteUnits() != 0) @panic("misaligned allocation");
            @memset(ptr[0..len], @truncate(index));
            record.* = .{ .ptr = ptr, .len = len, .alignment = record_alignment };
        }
    }

    {
        const free_phase = bench.phaseAt("gpalloc.phase.aligned_mix.free", @src());
        defer free_phase.end();

        var index: usize = records.len;
        while (index > 0) {
            index -= 1;
            const record = records[index];
            std.mem.doNotOptimizeAway(record.ptr);
            allocator.rawFree(record.ptr[0..record.len], record.alignment, @returnAddress());
        }
    }

    coz.progressNamed("gpalloc.workload.aligned_mix");
}

fn alignment(index: usize) std.mem.Alignment {
    const alignments = [_]usize{ 1, 8, 16, 32, 64, 256, 4096 };
    return .fromByteUnits(alignments[index % alignments.len]);
}
