const std = @import("std");
const subject = @import("root.zig");
const command = @import("command.zig");
const options = @import("options.zig");
const reader = @import("reader.zig");
const report = @import("report.zig");
const stats = @import("stats/test.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(subject);
    std.testing.refAllDecls(command);
    std.testing.refAllDecls(options);
    std.testing.refAllDecls(reader);
    std.testing.refAllDecls(report);
    std.testing.refAllDecls(stats);
}
