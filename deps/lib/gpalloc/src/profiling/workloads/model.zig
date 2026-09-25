const std = @import("std");

pub const WorkloadFn = *const fn (std.mem.Allocator) void;

pub const Workload = struct {
    id: []const u8,
    name: []const u8,
    run: WorkloadFn,
};
