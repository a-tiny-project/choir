const std = @import("std");
const subject = @import("root.zig");
const catalog = @import("catalog.zig");
const command = @import("command.zig");
const metric = @import("metric.zig");
const options = @import("options.zig");
const output = @import("output.zig");
const runner = @import("runner.zig");

comptime {
    _ = subject;
}

test "gpalloc external package namespace" {
    std.testing.refAllDecls(catalog);
    std.testing.refAllDecls(command);
    std.testing.refAllDecls(metric);
    std.testing.refAllDecls(options);
    std.testing.refAllDecls(output);
    std.testing.refAllDecls(runner);
}
