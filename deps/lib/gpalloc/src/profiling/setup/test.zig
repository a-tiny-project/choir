const std = @import("std");
const subject = @import("root.zig");
const command = @import("command.zig");
const host = @import("host.zig");
const install = @import("install.zig");
const options = @import("options.zig");
const output = @import("output.zig");

comptime {
    _ = subject;
}

test "gpalloc setup package namespace" {
    std.testing.refAllDecls(command);
    std.testing.refAllDecls(host);
    std.testing.refAllDecls(install);
    std.testing.refAllDecls(options);
    std.testing.refAllDecls(output);
}
