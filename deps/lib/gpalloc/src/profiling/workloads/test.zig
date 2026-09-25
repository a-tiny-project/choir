const std = @import("std");
const workloads = @import("root.zig");

test {
    std.testing.refAllDecls(workloads);
}
