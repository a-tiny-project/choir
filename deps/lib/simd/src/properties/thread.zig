const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const max_permutation_size: usize = 128;

pub const ShuffleProperty = struct {
    pub fn property(
        data: *hypothesis.ConjectureData,
        _: Allocator,
    ) !void {
        const size: u32 = @intCast(try data.drawInteger(
            1,
            max_permutation_size,
            0,
        ));
        const start: u32 = @intCast(try data.drawInteger(0, size - 1, 0));
        const seed: u32 = @intCast(try data.drawInteger(0, 4_096, 0));
        const coprime = simd.ShuffledIota.findAnotherCoprime(size, seed);
        try std.testing.expectEqual(@as(u32, 1), euclideanGcd(coprime, size));
        const shuffled = simd.ShuffledIota.init(coprime);
        var visited: [max_permutation_size]bool = @splat(false);
        var current = start;
        for (0..size) |_| {
            try std.testing.expect(current < size);
            try std.testing.expect(!visited[current]);
            visited[current] = true;
            const expected: u32 = @intCast(
                (@as(u64, current) + coprime) % size,
            );
            current = shuffled.next(current, size);
            try std.testing.expectEqual(expected, current);
        }
        try std.testing.expectEqual(start, current);
        for (visited[0..size]) |was_visited| {
            try std.testing.expect(was_visited);
        }
    }
};

pub const WorkerRangeProperty = struct {
    pub fn property(
        data: *hypothesis.ConjectureData,
        _: Allocator,
    ) !void {
        const begin: u64 = @intCast(try data.drawInteger(0, 1_000_000, 0));
        const task_count: usize = @intCast(try data.drawInteger(0, 1_024, 0));
        const worker_count: usize = @intCast(try data.drawInteger(1, 128, 0));
        const minimum = task_count / worker_count;
        const remainder = task_count % worker_count;
        var cursor = begin;
        var observed_minimum: usize = std.math.maxInt(usize);
        var observed_maximum: usize = 0;
        for (0..worker_count) |worker| {
            const actual = try simd.thread.testing.workerRange(
                begin,
                begin + task_count,
                worker_count,
                worker,
            );
            const expected_begin =
                begin + worker * minimum + @min(worker, remainder);
            const expected_count =
                minimum + @intFromBool(worker < remainder);
            try std.testing.expectEqual(expected_begin, actual.begin);
            try std.testing.expectEqual(
                expected_begin + expected_count,
                actual.end,
            );
            try std.testing.expectEqual(cursor, actual.begin);
            cursor = actual.end;
            observed_minimum = @min(observed_minimum, expected_count);
            observed_maximum = @max(observed_maximum, expected_count);
        }
        try std.testing.expectEqual(begin + task_count, cursor);
        try std.testing.expect(observed_maximum - observed_minimum <= 1);
    }
};

pub const PartitionProperty = struct {
    pub fn property(
        data: *hypothesis.ConjectureData,
        _: Allocator,
    ) !void {
        const begin: usize = @intCast(try data.drawInteger(0, 1_000, 0));
        const count: usize = @intCast(try data.drawInteger(1, 1_024, 0));
        const task_size: usize = @intCast(try data.drawInteger(1, 128, 0));
        const partition = try simd.IndexRangePartition.init(
            try simd.IndexRange.init(begin, begin + count),
            task_size,
        );
        const expected_tasks = std.math.divCeil(
            usize,
            count,
            task_size,
        ) catch unreachable;
        try std.testing.expectEqual(expected_tasks, partition.taskCount());
        var cursor = begin;
        for (0..partition.taskCount()) |task| {
            const range = try partition.rangeAt(task);
            try std.testing.expectEqual(cursor, range.begin);
            try std.testing.expect(range.count() >= 1);
            try std.testing.expect(range.count() <= task_size);
            cursor = range.end;
        }
        try std.testing.expectEqual(begin + count, cursor);
        const single = try simd.IndexRangePartition.single(count);
        try std.testing.expectEqual(@as(usize, 1), single.taskCount());
        try std.testing.expectEqual(
            simd.IndexRange{ .begin = 0, .end = count },
            try single.rangeAt(0),
        );
    }
};

fn euclideanGcd(a_value: u32, b_value: u32) u32 {
    var a = a_value;
    var b = b_value;
    while (b != 0) {
        const remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}

test "property: shuffled iota is an independently proved full cycle" {
    try hypothesis.checkNamed(
        ShuffleProperty,
        "simd-thread-shuffle",
        run.settings(),
    );
}

test "property: worker ranges match an independent quotient model" {
    try hypothesis.checkNamed(
        WorkerRangeProperty,
        "simd-thread-worker-range",
        run.settings(),
    );
}

test "property: index partitions form one exact bounded cover" {
    try hypothesis.checkNamed(
        PartitionProperty,
        "simd-thread-partition",
        run.settings(),
    );
}
