const std = @import("std");
const bench = @import("bench");
const gpalloc = @import("gpalloc");
const workloads = @import("workloads/root.zig");

fn GpCaseType(comptime workload: workloads.WorkloadFn, comptime config: gpalloc.Config) type {
    return struct {
        fn run(backing_allocator: std.mem.Allocator) void {
            var heap = gpalloc.GpAllocator.init(backing_allocator, config);
            defer heap.deinit();
            const allocator = heap.allocator();

            workload(allocator);
        }
    };
}

fn SystemCaseType(comptime workload: workloads.WorkloadFn) type {
    return struct {
        fn run(allocator: std.mem.Allocator) void {
            workload(allocator);
        }
    };
}

pub fn gp(comptime workload: workloads.WorkloadFn, comptime config: gpalloc.Config) bench.BenchFn {
    return GpCaseType(workload, config).run;
}

pub fn system(comptime workload: workloads.WorkloadFn) bench.BenchFn {
    return SystemCaseType(workload).run;
}
