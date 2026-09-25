const std = @import("std");
const alloc_phase = @import("alloc_phase");
const input = @import("root.zig");

test "Choir pass reproducer input namespace" {
    std.testing.refAllDecls(input);
}

test "Choir pass reproducer input stat preflight accepts the maximum and rejects max plus one" {
    comptime {
        alloc_phase.capacity.record(
            alloc_phase.capacity.witness(@import("./root.zig").Storage, "choir_pass_reproducer_input_preflight"),
        );
    }

    const maximum = input.Limits{ .file_bytes = 17 };
    try std.testing.expectEqual(
        input.Limits{ .file_bytes = 17 },
        try input.exactLimitsForFile(17, maximum),
    );
    try std.testing.expectError(
        error.ReproducerInputCapacityExceeded,
        input.exactLimitsForFile(18, maximum),
    );
    if (@sizeOf(usize) < @sizeOf(u64)) {
        try std.testing.expectError(
            error.ReproducerInputCapacityExceeded,
            input.exactLimitsForFile(@as(u64, std.math.maxInt(usize)) + 1, maximum),
        );
    }
}
