const std = @import("std");
const hypothesis = @import("hypothesis");
const gpalloc = @import("gpalloc");
const sys = @import("sys");

const allocator_properties = @import("allocator.zig");
const draw = @import("draw.zig");

const Allocator = std.mem.Allocator;
const GpAllocator = gpalloc.GpAllocator;
const max_small_size = gpalloc.max_small_size;
const drawUsize = draw.drawUsize;

const failed_sentinel: usize = 1;

const Record = struct {
    bytes: []u8,
    seed: u64,
};

fn patternByte(seed: u64, index: usize) u8 {
    return @truncate(seed +% index *% 33 +% (index >> 3));
}

fn fillPattern(bytes: []u8, seed: u64) void {
    const span = @min(bytes.len, 256);
    for (bytes[0..span], 0..) |*byte, index| byte.* = patternByte(seed, index);
    bytes[bytes.len - 1] = patternByte(seed, bytes.len - 1);
}

fn checkPattern(bytes: []const u8, seed: u64) bool {
    const span = @min(bytes.len, 256);
    for (bytes[0..span], 0..) |byte, index| {
        if (byte != patternByte(seed, index)) return false;
    }
    return bytes[bytes.len - 1] == patternByte(seed, bytes.len - 1);
}

fn randomLen(random: std.Random, include_large: bool) usize {
    const variant = random.uintLessThan(u8, 10);
    if (include_large and variant == 9) {
        return random.intRangeAtMost(usize, max_small_size + 1, 128 * 1024);
    }
    if (variant >= 7) {
        return random.intRangeAtMost(usize, 1025, max_small_size);
    }
    return random.intRangeAtMost(usize, 1, 1024);
}

fn reportFailure(failures: *std.atomic.Value(u32)) void {
    _ = failures.fetchAdd(1, .monotonic);
}

fn checkRecord(record: Record, failures: *std.atomic.Value(u32)) void {
    if (!checkPattern(record.bytes, record.seed)) reportFailure(failures);
}

const HandoffPair = struct {
    heap_allocator: Allocator,
    len: usize,
    seed: u64,
    items: usize,
    slots: []std.atomic.Value(usize),
    failures: *std.atomic.Value(u32),
};

pub const HandoffProperty = struct {
    const max_pairs = 2;
    const max_items = 96;

    fn produce(pair: *const HandoffPair) void {
        for (pair.slots[0..pair.items], 0..) |*slot, index| {
            const bytes = pair.heap_allocator.alloc(u8, pair.len) catch {
                reportFailure(pair.failures);
                slot.store(failed_sentinel, .release);
                continue;
            };
            fillPattern(bytes, pair.seed +% index);
            slot.store(@intFromPtr(bytes.ptr), .release);
        }
    }

    fn consume(pair: *const HandoffPair) void {
        for (pair.slots[0..pair.items], 0..) |*slot, index| {
            var value = slot.load(.acquire);
            while (value == 0) {
                sys.thread.yield();
                value = slot.load(.acquire);
            }
            if (value == failed_sentinel) continue;
            const ptr: [*]u8 = @ptrFromInt(value);
            const bytes = ptr[0..pair.len];
            checkRecord(.{ .bytes = bytes, .seed = pair.seed +% index }, pair.failures);
            pair.heap_allocator.free(bytes);
        }
    }

    fn drawLen(conjecture: *hypothesis.ConjectureData) !usize {
        const variant = try drawUsize(conjecture, 0, 9, 0);
        return switch (variant) {
            0...6 => try drawUsize(conjecture, 1, 1024, 16),
            7...8 => try drawUsize(conjecture, 1025, max_small_size, 1025),
            else => try drawUsize(conjecture, max_small_size + 1, 128 * 1024, max_small_size + 1),
        };
    }

    pub fn property(
        conjecture: *hypothesis.ConjectureData,
        property_allocator: Allocator,
    ) !void {
        var heap = GpAllocator.init(property_allocator, .{});
        defer heap.deinit();
        const heap_allocator = heap.allocator();

        var failures = std.atomic.Value(u32).init(0);
        var slot_storage: [max_pairs][max_items]std.atomic.Value(usize) = undefined;
        var pairs: [max_pairs]HandoffPair = undefined;

        const pair_count = try drawUsize(conjecture, 1, max_pairs, 1);
        for (0..pair_count) |pair_index| {
            for (&slot_storage[pair_index]) |*slot| slot.* = .init(0);
            pairs[pair_index] = .{
                .heap_allocator = heap_allocator,
                .len = try drawLen(conjecture),
                .seed = 0x9e3779b97f4a7c15 +% @as(u64, pair_index) *% 0x100,
                .items = try drawUsize(conjecture, 4, max_items, 8),
                .slots = &slot_storage[pair_index],
                .failures = &failures,
            };
        }

        var handles: [max_pairs * 2]sys.thread.JoinHandle = undefined;
        var spawned: usize = 0;
        {
            errdefer for (handles[0..spawned]) |handle| handle.join();
            for (pairs[0..pair_count]) |*pair| {
                handles[spawned] = try sys.thread.spawn(produce, .{pair});
                spawned += 1;
                handles[spawned] = try sys.thread.spawn(consume, .{pair});
                spawned += 1;
            }
        }
        for (handles[0..spawned]) |handle| handle.join();

        if (failures.load(.monotonic) != 0) return error.PropertyFailed;
    }
};

const ChurnWork = struct {
    heap_allocator: Allocator,
    prng_seed: u64,
    rounds: usize,
    slots: usize,
    survivors: []?Record,
    failures: *std.atomic.Value(u32),
};

pub const ChurnProperty = struct {
    const max_threads = 4;
    const max_slots = 32;

    fn churn(work: *const ChurnWork) void {
        var prng = std.Random.DefaultPrng.init(work.prng_seed);
        const random = prng.random();
        var active = @as([max_slots]?Record, @splat(null));
        var round: usize = 0;
        while (round < work.rounds) : (round += 1) {
            for (active[0..work.slots]) |*slot| {
                if (slot.*) |record| {
                    checkRecord(record, work.failures);
                    if (random.boolean()) {
                        work.heap_allocator.free(record.bytes);
                        slot.* = null;
                    }
                } else {
                    const len = randomLen(random, true);
                    const bytes = work.heap_allocator.alloc(u8, len) catch {
                        reportFailure(work.failures);
                        continue;
                    };
                    const seed = random.int(u64);
                    fillPattern(bytes, seed);
                    slot.* = .{ .bytes = bytes, .seed = seed };
                }
            }
        }
        for (active[0..work.slots], work.survivors[0..work.slots]) |slot, *survivor| {
            survivor.* = slot;
        }
    }

    pub fn property(
        conjecture: *hypothesis.ConjectureData,
        property_allocator: Allocator,
    ) !void {
        var heap = GpAllocator.init(property_allocator, .{});
        defer heap.deinit();
        const heap_allocator = heap.allocator();

        var failures = std.atomic.Value(u32).init(0);
        var survivor_storage: [max_threads][max_slots]?Record =
            @as([max_threads][max_slots]?Record, @splat(@as([max_slots]?Record, @splat(null))));
        var work_items: [max_threads]ChurnWork = undefined;

        const thread_count = try drawUsize(conjecture, 2, max_threads, 2);
        const base_seed = try drawUsize(conjecture, 0, 1 << 32, 0);
        for (0..thread_count) |thread_index| {
            work_items[thread_index] = .{
                .heap_allocator = heap_allocator,
                .prng_seed = @as(u64, base_seed) +% thread_index,
                .rounds = try drawUsize(conjecture, 1, 6, 2),
                .slots = try drawUsize(conjecture, 4, max_slots, 8),
                .survivors = &survivor_storage[thread_index],
                .failures = &failures,
            };
        }

        var handles: [max_threads]sys.thread.JoinHandle = undefined;
        var spawned: usize = 0;
        {
            errdefer for (handles[0..spawned]) |handle| handle.join();
            for (work_items[0..thread_count]) |*work| {
                handles[spawned] = try sys.thread.spawn(churn, .{work});
                spawned += 1;
            }
        }
        for (handles[0..spawned]) |handle| handle.join();

        for (survivor_storage[0..thread_count]) |*row| {
            for (row) |*slot| {
                if (slot.*) |record| {
                    checkRecord(record, &failures);
                    heap_allocator.free(record.bytes);
                    slot.* = null;
                }
            }
        }

        if (failures.load(.monotonic) != 0) return error.PropertyFailed;
    }
};

const LifecycleWork = struct {
    heap_allocator: Allocator,
    prng_seed: u64,
    burst: usize,
    adopt: []?Record,
    publish: []?Record,
    failures: *std.atomic.Value(u32),
};

pub const LifecycleProperty = struct {
    const max_waves = 3;
    const max_workers = 3;
    const max_burst = 48;
    const publish_capacity = max_burst / 2 + 1;

    fn wave(work: *const LifecycleWork) void {
        for (work.adopt) |*entry| {
            if (entry.*) |record| {
                checkRecord(record, work.failures);
                work.heap_allocator.free(record.bytes);
                entry.* = null;
            }
        }
        var prng = std.Random.DefaultPrng.init(work.prng_seed);
        const random = prng.random();
        var index: usize = 0;
        while (index < work.burst) : (index += 1) {
            const len = randomLen(random, false);
            const bytes = work.heap_allocator.alloc(u8, len) catch {
                reportFailure(work.failures);
                continue;
            };
            const seed = random.int(u64);
            fillPattern(bytes, seed);
            if (index % 2 == 0) {
                work.publish[index / 2] = .{ .bytes = bytes, .seed = seed };
            } else {
                checkRecord(.{ .bytes = bytes, .seed = seed }, work.failures);
                work.heap_allocator.free(bytes);
            }
        }
    }

    pub fn property(
        conjecture: *hypothesis.ConjectureData,
        property_allocator: Allocator,
    ) !void {
        var heap = GpAllocator.init(property_allocator, .{
            .thread_cache_active_limit = try drawUsize(conjecture, 0, 2, 0),
            .thread_cache_retention_limit = try drawUsize(conjecture, 0, 2, 1),
        });
        defer heap.deinit();
        const heap_allocator = heap.allocator();

        var failures = std.atomic.Value(u32).init(0);
        var publish_storage: [max_waves][max_workers][publish_capacity]?Record =
            @as([max_waves][max_workers][publish_capacity]?Record, @splat(@as([max_workers][publish_capacity]?Record, @splat(@as([publish_capacity]?Record, @splat(null))))));
        var work_storage: [max_workers]LifecycleWork = undefined;

        const wave_count = try drawUsize(conjecture, 1, max_waves, 1);
        const base_seed = try drawUsize(conjecture, 0, 1 << 32, 0);
        var previous_workers: usize = 0;
        for (0..wave_count) |wave_index| {
            const worker_count = try drawUsize(conjecture, 1, max_workers, 1);
            var handles: [max_workers]sys.thread.JoinHandle = undefined;
            var spawned: usize = 0;
            errdefer for (handles[0..spawned]) |handle| handle.join();
            for (0..worker_count) |worker_index| {
                const adopt: []?Record = if (wave_index > 0 and worker_index < previous_workers)
                    &publish_storage[wave_index - 1][worker_index]
                else
                    &.{};
                work_storage[worker_index] = .{
                    .heap_allocator = heap_allocator,
                    .prng_seed = @as(u64, base_seed) +% wave_index *% 31 +% worker_index,
                    .burst = try drawUsize(conjecture, 4, max_burst, 8),
                    .adopt = adopt,
                    .publish = &publish_storage[wave_index][worker_index],
                    .failures = &failures,
                };
                handles[spawned] = try sys.thread.spawn(wave, .{&work_storage[worker_index]});
                spawned += 1;
            }
            for (handles[0..spawned]) |handle| handle.join();
            previous_workers = worker_count;
        }

        for (&publish_storage) |*wave_rows| {
            for (wave_rows) |*worker_row| {
                for (worker_row) |*slot| {
                    if (slot.*) |record| {
                        checkRecord(record, &failures);
                        heap_allocator.free(record.bytes);
                        slot.* = null;
                    }
                }
            }
        }

        if (failures.load(.monotonic) != 0) return error.PropertyFailed;
    }
};

const StatsTotals = struct {
    small_allocations: u64 = 0,
    small_frees: u64 = 0,
    large_allocations: u64 = 0,
    large_frees: u64 = 0,
};

const StatsWork = struct {
    heap_allocator: Allocator,
    prng_seed: u64,
    ops: usize,
    totals: *StatsTotals,
    failures: *std.atomic.Value(u32),
};

pub const StatsProperty = struct {
    const max_threads = 4;
    const max_ops = 48;
    const live_limit = 8;

    fn recordAlloc(totals: *StatsTotals, len: usize) void {
        if (len <= max_small_size) {
            totals.small_allocations += 1;
        } else {
            totals.large_allocations += 1;
        }
    }

    fn recordFree(totals: *StatsTotals, len: usize) void {
        if (len <= max_small_size) {
            totals.small_frees += 1;
        } else {
            totals.large_frees += 1;
        }
    }

    fn exercise(work: *const StatsWork) void {
        var prng = std.Random.DefaultPrng.init(work.prng_seed);
        const random = prng.random();
        var active = @as([live_limit]?Record, @splat(null));
        var totals: StatsTotals = .{};
        var op: usize = 0;
        while (op < work.ops) : (op += 1) {
            const slot = &active[random.uintLessThan(usize, live_limit)];
            if (slot.*) |record| {
                checkRecord(record, work.failures);
                recordFree(&totals, record.bytes.len);
                work.heap_allocator.free(record.bytes);
                slot.* = null;
            } else {
                const len = randomLen(random, true);
                const bytes = work.heap_allocator.alloc(u8, len) catch {
                    reportFailure(work.failures);
                    continue;
                };
                recordAlloc(&totals, len);
                const seed = random.int(u64);
                fillPattern(bytes, seed);
                slot.* = .{ .bytes = bytes, .seed = seed };
            }
        }
        for (&active) |*slot| {
            if (slot.*) |record| {
                checkRecord(record, work.failures);
                recordFree(&totals, record.bytes.len);
                work.heap_allocator.free(record.bytes);
                slot.* = null;
            }
        }
        work.totals.* = totals;
    }

    pub fn property(
        conjecture: *hypothesis.ConjectureData,
        property_allocator: Allocator,
    ) !void {
        var heap = GpAllocator.init(property_allocator, .{ .collect_stats = true });
        defer heap.deinit();
        const heap_allocator = heap.allocator();

        var failures = std.atomic.Value(u32).init(0);
        var totals_storage = @as([max_threads]StatsTotals, @splat(.{}));
        var work_items: [max_threads]StatsWork = undefined;

        const thread_count = try drawUsize(conjecture, 2, max_threads, 2);
        const base_seed = try drawUsize(conjecture, 0, 1 << 32, 0);
        for (0..thread_count) |thread_index| {
            work_items[thread_index] = .{
                .heap_allocator = heap_allocator,
                .prng_seed = @as(u64, base_seed) +% thread_index *% 977,
                .ops = try drawUsize(conjecture, 8, max_ops, 8),
                .totals = &totals_storage[thread_index],
                .failures = &failures,
            };
        }

        var handles: [max_threads]sys.thread.JoinHandle = undefined;
        var spawned: usize = 0;
        {
            errdefer for (handles[0..spawned]) |handle| handle.join();
            for (work_items[0..thread_count]) |*work| {
                handles[spawned] = try sys.thread.spawn(exercise, .{work});
                spawned += 1;
            }
        }
        for (handles[0..spawned]) |handle| handle.join();

        var expected: StatsTotals = .{};
        for (totals_storage[0..thread_count]) |totals| {
            expected.small_allocations += totals.small_allocations;
            expected.small_frees += totals.small_frees;
            expected.large_allocations += totals.large_allocations;
            expected.large_frees += totals.large_frees;
        }

        const actual = heap.stats();
        try std.testing.expectEqual(expected.small_allocations, actual.small_allocations);
        try std.testing.expectEqual(expected.small_frees, actual.small_frees);
        try std.testing.expectEqual(expected.large_allocations, actual.large_allocations);
        try std.testing.expectEqual(expected.large_frees, actual.large_frees);
        try std.testing.expectEqual(@as(usize, 0), actual.active_small_bytes);
        try std.testing.expectEqual(@as(usize, 0), actual.active_large_bytes);

        if (failures.load(.monotonic) != 0) return error.PropertyFailed;
    }
};

test "property: concurrent handoff preserves remote-freed block contents" {
    try hypothesis.checkNamed(
        HandoffProperty,
        "gpalloc-concurrent-handoff",
        allocator_properties.settings(),
    );
}

test "property: concurrent churn survives thread exit reclamation" {
    try hypothesis.checkNamed(
        ChurnProperty,
        "gpalloc-concurrent-churn",
        allocator_properties.settings(),
    );
}

test "property: thread lifecycle waves preserve blocks under cache caps" {
    try hypothesis.checkNamed(
        LifecycleProperty,
        "gpalloc-concurrent-lifecycle",
        allocator_properties.settings(),
    );
}

test "property: concurrent stats reconcile with per-thread totals" {
    try hypothesis.checkNamed(
        StatsProperty,
        "gpalloc-concurrent-stats",
        allocator_properties.settings(),
    );
}
