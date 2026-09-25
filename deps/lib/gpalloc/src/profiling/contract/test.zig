const std = @import("std");
const subject = @import("root.zig");
const cases = @import("cases.zig");
const command = @import("command.zig");
const options = @import("options.zig");
const output = @import("output.zig");

comptime {
    _ = subject;
}

test {
    std.testing.refAllDecls(cases);
    std.testing.refAllDecls(command);
    std.testing.refAllDecls(options);
    std.testing.refAllDecls(output);
}
