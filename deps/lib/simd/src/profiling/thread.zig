const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

var pool_storage: ?simd.ThreadPool = null;
var counters: [simd.max_pool_workers]std.atomic.Value(usize) =
    @splat(std.atomic.Value(usize).init(0));

pub fn prepareBlock(_: std.mem.Allocator) void {
    prepare(.block);
}

pub fn prepareSpin(_: std.mem.Allocator) void {
    prepare(.spin);
}

pub fn teardown() void {
    if (pool_storage) |*value| value.deinit();
    pool_storage = null;
}

pub fn blockStatic(_: std.mem.Allocator) void {
    runTasks(
        "simd.thread.block-static",
        "simd.thread.block-static.complete",
        pool().numWorkers(),
    );
}

pub fn blockDynamic(_: std.mem.Allocator) void {
    runTasks(
        "simd.thread.block-dynamic",
        "simd.thread.block-dynamic.complete",
        pool().numWorkers() * 257,
    );
}

pub fn spinStatic(_: std.mem.Allocator) void {
    runTasks(
        "simd.thread.spin-static",
        "simd.thread.spin-static.complete",
        pool().numWorkers(),
    );
}

pub fn spinDynamic(_: std.mem.Allocator) void {
    runTasks(
        "simd.thread.spin-dynamic",
        "simd.thread.spin-dynamic.complete",
        pool().numWorkers() * 257,
    );
}

fn prepare(mode: simd.PoolWaitMode) void {
    if (pool_storage == null) {
        pool_storage = simd.ThreadPool.init(
            @min(simd.ThreadPool.maxThreads(), 7),
            .{},
        );
        pool().start() catch @panic("thread pool benchmark start failed");
    }
    if (pool().waitMode() != mode) {
        pool().setWaitMode(mode) catch
            @panic("thread pool benchmark mode change failed");
    }
    pool().resetStats() catch
        @panic("thread pool benchmark stats reset failed");
    for (counters[0..pool().numWorkers()]) |*counter| {
        counter.store(0, .monotonic);
    }
}

fn runTasks(
    comptime phase_name: []const u8,
    comptime progress_name: []const u8,
    task_count: usize,
) void {
    const phase = bench.phaseAt(phase_name, @src());
    pool().run(0, task_count, &counters, countTask) catch
        @panic("thread pool benchmark run failed");
    phase.end();
    var actual: usize = 0;
    for (counters[0..pool().numWorkers()]) |*counter| {
        actual +%= counter.load(.monotonic);
    }
    const expected = task_count *% (task_count +% 1) / 2;
    if (actual != expected) {
        @panic("thread pool benchmark witness failed");
    }
    std.mem.doNotOptimizeAway(&actual);
    bench.coz.progressNamed(progress_name);
}

fn countTask(
    worker_counters: *[simd.max_pool_workers]std.atomic.Value(usize),
    task: u64,
    worker: usize,
) void {
    _ = worker_counters[worker].fetchAdd(@intCast(task +% 1), .monotonic);
}

fn pool() *simd.ThreadPool {
    if (pool_storage) |*value| return value;
    @panic("thread pool benchmark was not prepared");
}
