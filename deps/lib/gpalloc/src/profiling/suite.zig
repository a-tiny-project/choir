const std = @import("std");
const bench = @import("bench");
const gpalloc = @import("gpalloc");
const cases = @import("cases.zig");
const workloads = @import("workloads/root.zig");

const Mode = union(enum) {
    gpalloc: gpalloc.Config,
    system,
};

const Entry = struct {
    name: []const u8,
    workload: workloads.WorkloadFn,
    mode: Mode,
};

const entries = [_]Entry{
    .{ .name = "gpalloc small alloc/free x256", .workload = workloads.smallChurn, .mode = .{ .gpalloc = .{} } },
    .{ .name = "gpalloc release-empty small x256", .workload = workloads.smallChurn, .mode = .{ .gpalloc = .{ .empty_page_retention_limit = 0 } } },
    .{ .name = "system small alloc/free x256", .workload = workloads.smallChurn, .mode = .system },
    .{ .name = "gpalloc retained burst reuse", .workload = workloads.repeatedBursts, .mode = .{ .gpalloc = .{} } },
    .{ .name = "gpalloc release-empty bursts", .workload = workloads.repeatedBursts, .mode = .{ .gpalloc = .{ .empty_page_retention_limit = 0 } } },
    .{ .name = "gpalloc mixed realloc churn", .workload = workloads.mixedSizeChurn, .mode = .{ .gpalloc = .{} } },
    .{ .name = "gpalloc in-place realloc x256", .workload = workloads.reallocInPlace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system in-place realloc x256", .workload = workloads.reallocInPlace, .mode = .system },
    .{ .name = "gpalloc large direct x128", .workload = workloads.largeDirect, .mode = .{ .gpalloc = .{} } },
    .{ .name = "gpalloc large cache pressure x64", .workload = workloads.largeCachePressure, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system large cache pressure x64", .workload = workloads.largeCachePressure, .mode = .system },
    .{ .name = "gpalloc huge cache pressure x40", .workload = workloads.hugeCachePressure, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system huge cache pressure x40", .workload = workloads.hugeCachePressure, .mode = .system },
    .{ .name = "gpalloc parallel same-class x256", .workload = workloads.parallelSameClass, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system parallel same-class x256", .workload = workloads.parallelSameClass, .mode = .system },
    .{ .name = "gpalloc parallel mixed-classes x256", .workload = workloads.parallelMixedClasses, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system parallel mixed-classes x256", .workload = workloads.parallelMixedClasses, .mode = .system },
    .{ .name = "gpalloc short-lived thread churn x128", .workload = workloads.threadChurn, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system short-lived thread churn x128", .workload = workloads.threadChurn, .mode = .system },
    .{ .name = "gpalloc Larson server simulator x16384", .workload = workloads.larson, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system Larson server simulator x16384", .workload = workloads.larson, .mode = .system },
    .{ .name = "gpalloc Larson preload header trace x40000", .workload = workloads.larsonPreloadTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system Larson preload header trace x40000", .workload = workloads.larsonPreloadTrace, .mode = .system },
    .{ .name = "gpalloc active thread-cache fanout x256", .workload = workloads.activeFanout, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system active thread-cache fanout x256", .workload = workloads.activeFanout, .mode = .system },
    .{ .name = "gpalloc producer-consumer x128", .workload = workloads.producerConsumer, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system producer-consumer x128", .workload = workloads.producerConsumer, .mode = .system },
    .{ .name = "gpalloc producer remote-free reuse trace x8192", .workload = workloads.producerReuseTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system producer remote-free reuse trace x8192", .workload = workloads.producerReuseTrace, .mode = .system },
    .{ .name = "gpalloc remote ring x256", .workload = workloads.remoteRing, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system remote ring x256", .workload = workloads.remoteRing, .mode = .system },
    .{ .name = "gpalloc working-set churn x1024", .workload = workloads.workingSetChurn, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system working-set churn x1024", .workload = workloads.workingSetChurn, .mode = .system },
    .{ .name = "gpalloc steady working-set churn x2048", .workload = workloads.workingSetSteady, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system steady working-set churn x2048", .workload = workloads.workingSetSteady, .mode = .system },
    .{ .name = "gpalloc cfrac precision arithmetic trace x4096", .workload = workloads.cfracTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system cfrac precision arithmetic trace x4096", .workload = workloads.cfracTrace, .mode = .system },
    .{ .name = "gpalloc espresso sparse cover trace x6144", .workload = workloads.espressoTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system espresso sparse cover trace x6144", .workload = workloads.espressoTrace, .mode = .system },
    .{ .name = "gpalloc Barnes tree table trace x1024 bodies", .workload = workloads.barnesTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system Barnes tree table trace x1024 bodies", .workload = workloads.barnesTrace, .mode = .system },
    .{ .name = "gpalloc RocksDB fillrandom trace x4 memtables", .workload = workloads.rocksdbFillrandomTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system RocksDB fillrandom trace x4 memtables", .workload = workloads.rocksdbFillrandomTrace, .mode = .system },
    .{ .name = "gpalloc RocksDB fillrandom preload trace x4 memtables", .workload = workloads.rocksdbFillrandomPreloadTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system RocksDB fillrandom preload trace x4 memtables", .workload = workloads.rocksdbFillrandomPreloadTrace, .mode = .system },
    .{ .name = "gpalloc Redis list benchmark trace x1024", .workload = workloads.redisTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system Redis list benchmark trace x1024", .workload = workloads.redisTrace, .mode = .system },
    .{ .name = "gpalloc MicroQuill sh6 reverse-free trace x1024 slots", .workload = workloads.reverseFreeTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system MicroQuill sh6 reverse-free trace x1024 slots", .workload = workloads.reverseFreeTrace, .mode = .system },
    .{ .name = "gpalloc MicroQuill sh6 preload reverse-free trace x1024 slots", .workload = workloads.reverseFreePreloadTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system MicroQuill sh6 preload reverse-free trace x1024 slots", .workload = workloads.reverseFreePreloadTrace, .mode = .system },
    .{ .name = "gpalloc MicroQuill sh8 foreign-free trace x2x1024 slots", .workload = workloads.foreignFreeTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system MicroQuill sh8 foreign-free trace x2x1024 slots", .workload = workloads.foreignFreeTrace, .mode = .system },
    .{ .name = "gpalloc MicroQuill sh8 preload foreign-free trace x2x1024 slots", .workload = workloads.foreignFreePreloadTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system MicroQuill sh8 preload foreign-free trace x2x1024 slots", .workload = workloads.foreignFreePreloadTrace, .mode = .system },
    .{ .name = "gpalloc MicroQuill sh8 preload local trace x29284", .workload = workloads.sh8PreloadTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system MicroQuill sh8 preload local trace x29284", .workload = workloads.sh8PreloadTrace, .mode = .system },
    .{ .name = "gpalloc server phase migration trace x9216", .workload = workloads.mstressTrace, .mode = .{ .gpalloc = .{} } },
    .{ .name = "system server phase migration trace x9216", .workload = workloads.mstressTrace, .mode = .system },
};

pub fn run(allocator: std.mem.Allocator) !void {
    var benchmark_suite = bench.Suite.init(allocator, .{
        .min_time_ns = 1_000_000,
        .max_iterations = 100,
        .warmup_iterations = 0,
        .allocation_attribution = .sample_call,
        .layout_randomization = null,
    });
    defer benchmark_suite.deinit();

    try addEntries(&benchmark_suite);
    try benchmark_suite.run();
}

fn addEntries(benchmark_suite: *bench.Suite) !void {
    inline for (entries) |entry| {
        switch (entry.mode) {
            .gpalloc => |config| try benchmark_suite.add(entry.name, cases.gp(entry.workload, config), .{}),
            .system => try benchmark_suite.add(entry.name, cases.system(entry.workload), .{}),
        }
    }
}

test "bench: allocation throughput" {
    try run(std.testing.allocator);
}
