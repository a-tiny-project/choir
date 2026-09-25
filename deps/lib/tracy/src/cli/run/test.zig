const namespace = @import("root.zig");
const std = @import("std");

const dispatch = namespace.dispatch;
test {
    std.testing.refAllDecls(@This());
}
