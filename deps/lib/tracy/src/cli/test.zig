const namespace = @import("root.zig");
const std = @import("std");

const args = namespace.args;
const run = namespace.run;
const usage = namespace.usage;
const dispatch = namespace.dispatch;
const printError = namespace.printError;
test {
    _ = @import("args/test.zig");
    _ = @import("run/test.zig");
}

test {
    std.testing.refAllDecls(@This());
}
