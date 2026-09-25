const std = @import("std");
const subject = @import("root.zig");
const allocator = @import("allocator.zig");
const command = @import("command.zig");
const compare = @import("compare/test.zig");
const options = @import("options.zig");
const output = @import("output.zig");
const profile = @import("profile.zig");
const runner = @import("runner.zig");
const trace = @import("trace.zig");

comptime {
    _ = subject;
}

test "gpalloc driver package namespace" {
    std.testing.refAllDecls(allocator);
    std.testing.refAllDecls(command);
    std.testing.refAllDecls(compare);
    std.testing.refAllDecls(options);
    std.testing.refAllDecls(output);
    std.testing.refAllDecls(profile);
    std.testing.refAllDecls(runner);
    std.testing.refAllDecls(trace);
}
