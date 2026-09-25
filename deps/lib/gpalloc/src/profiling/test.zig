const std = @import("std");
const profiling = @import("root.zig");
const workloads = @import("workloads/test.zig");

test {
    std.testing.refAllDecls(profiling);
    std.testing.refAllDecls(workloads);
}
