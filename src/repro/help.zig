const std = @import("std");
const namespace = @import("root.zig");

const default_input_limits = input.default_limits;
pub const input = namespace.input;
const default_input_mebibytes = default_input_limits.file_bytes / (1024 * 1024);

pub const usage_text = std.fmt.comptimePrint(
    \\usage: choir-pass-repro replay FILE
    \\       choir-pass-repro --help
    \\
    \\commands:
    \\  replay FILE    Replay a Choir pass failure reproducer.
    \\
    \\input:
    \\  FILE           Read up to {d} MiB inclusive through caller-owned input storage.
    \\
    \\exit status:
    \\  0  the captured failure reproduced
    \\  1  the replay did not reproduce, or execution failed
    \\  2  invalid arguments
    \\
,
    .{default_input_mebibytes},
);
