const std = @import("std");
const bench = @import("bench");
const memtrace = @import("memtrace");

const coz = bench.coz;
const batch_size: usize = 256;
const rounds: usize = 9;
const operation_count: usize = batch_size * rounds;

pub fn churn(allocator: std.mem.Allocator) void {
    const phase = bench.phaseAt("memtrace.record.churn", @src());
    defer phase.end();
    run(allocator, .{});
    coz.progressNamed("memtrace.record.churn.complete");
}

pub fn churnRecorded(allocator: std.mem.Allocator) void {
    const phase = bench.phaseAt("memtrace.record.events", @src());
    defer phase.end();
    run(allocator, .{ .record_events = true });
    coz.progressNamed("memtrace.record.events.complete");
}

pub fn churnExact(allocator: std.mem.Allocator) void {
    const phase = bench.phaseAt("memtrace.record.exact", @src());
    defer phase.end();
    run(allocator, .{
        .record_events = true,
        .allocation_attribution = .stack,
    });
    coz.progressNamed("memtrace.record.exact.complete");
}

fn run(allocator: std.mem.Allocator, config: memtrace.Config) void {
    var tracer = memtrace.Tracer.init(
        allocator,
        config,
    ) catch @panic("memtrace tracer init failed");
    defer tracer.deinit();
    var traced = tracer.tracedAllocator(allocator, "bench.heap") catch @panic("memtrace traced allocator init failed");
    const traced_allocator = traced.allocator();

    var span = tracer.enter("workload") catch @panic("memtrace scope enter failed");
    var live: [batch_size][]u8 = undefined;
    for (0..rounds) |round| {
        for (&live, 0..) |*slot, index| {
            const len = 16 + ((round * batch_size + index) % 16) * 8;
            slot.* = traced_allocator.alloc(u8, len) catch @panic("memtrace churn allocation failed");
            slot.*[0] = @truncate(index);
            slot.*[slot.len - 1] = @truncate(round);
        }
        freeRound(traced_allocator, &live, round);
    }
    span.exit();

    const snapshot = tracer.snapshot();
    if (snapshot.allocations != operation_count or snapshot.frees != operation_count or snapshot.live_bytes != 0) {
        @panic("memtrace churn witness failed");
    }
    std.mem.doNotOptimizeAway(snapshot.completed_lifetimes);
}

fn freeRound(allocator: std.mem.Allocator, live: *const [batch_size][]u8, round: usize) void {
    switch (round % 3) {
        0 => {
            var index = live.len;
            while (index > 0) {
                index -= 1;
                freeOne(allocator, live[index]);
            }
        },
        1 => for (live) |memory| freeOne(allocator, memory),
        2 => for (0..live.len) |index| {
            const shuffled: u8 = @bitReverse(@as(u8, @intCast(index)));
            freeOne(allocator, live[shuffled]);
        },
        else => unreachable,
    }
}

fn freeOne(allocator: std.mem.Allocator, memory: []u8) void {
    std.mem.doNotOptimizeAway(memory[0]);
    allocator.free(memory);
}
