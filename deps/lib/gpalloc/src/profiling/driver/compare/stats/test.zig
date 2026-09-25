const std = @import("std");
const alloc_phase = @import("alloc_phase");
const subject = @import("root.zig");

const Verdict = subject.Verdict;
const Result = subject.Result;
const ComparisonStorage = subject.ComparisonStorage;
const compareSeries = subject.compareSeries;

test "identical series compare neutral at ratio one" {
    const series = [_]u64{ 100, 101, 99, 100, 100, 102 };
    var storage = try ComparisonStorage.init(std.testing.allocator, .{
        .max_samples_per_series = series.len,
        .max_bootstrap_iterations = 500,
    });
    defer storage.deinit(std.testing.allocator);
    storage.activate();
    const result = try compareSeries(&storage, &series, &series, 500, 7);
    try std.testing.expectEqual(@as(u64, 100), result.base_median);
    try std.testing.expectEqual(@as(u64, 100), result.candidate_median);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.ratio, 0.001);
    try std.testing.expectEqual(Verdict.neutral, result.verdict);
}

test "separated series produce directional verdicts" {
    const base = [_]u64{ 100, 102, 98, 101, 99, 100, 103, 97 };
    const faster = [_]u64{ 80, 81, 79, 80, 82, 78, 80, 81 };
    const slower = [_]u64{ 120, 121, 119, 122, 120, 118, 121, 120 };
    var storage = try ComparisonStorage.init(std.testing.allocator, .{
        .max_samples_per_series = base.len,
        .max_bootstrap_iterations = 500,
    });
    defer storage.deinit(std.testing.allocator);
    storage.activate();
    const improved = try compareSeries(&storage, &base, &faster, 500, 7);
    try std.testing.expectEqual(Verdict.improved, improved.verdict);
    try std.testing.expect(improved.ci_high < 1.0);

    const regressed = try compareSeries(&storage, &base, &slower, 500, 7);
    try std.testing.expectEqual(Verdict.regressed, regressed.verdict);
    try std.testing.expect(regressed.ci_low > 1.0);
}

test "bootstrap is deterministic and permutation invariant" {
    var base = [_]u64{ 100, 105, 95, 102 };
    var candidate = [_]u64{ 97, 99, 101, 96 };
    var storage = try ComparisonStorage.init(std.testing.allocator, .{
        .max_samples_per_series = base.len,
        .max_bootstrap_iterations = 300,
    });
    defer storage.deinit(std.testing.allocator);
    storage.activate();
    const first = try compareSeries(&storage, &base, &candidate, 300, 42);
    std.mem.reverse(u64, &base);
    std.mem.reverse(u64, &candidate);
    const second = try compareSeries(&storage, &base, &candidate, 300, 42);
    try std.testing.expectEqual(first, second);
}

test "comparison storage rejects every input boundary before mutation" {
    var storage = try ComparisonStorage.init(std.testing.allocator, .{
        .max_samples_per_series = 3,
        .max_bootstrap_iterations = 5,
    });
    defer storage.deinit(std.testing.allocator);
    storage.activate();
    @memset(storage.bytes, 42);

    try std.testing.expectError(
        error.EmptyBaseSeries,
        compareSeries(&storage, &.{}, &.{1}, 1, 7),
    );
    try std.testing.expectError(
        error.EmptyCandidateSeries,
        compareSeries(&storage, &.{1}, &.{}, 1, 7),
    );
    try std.testing.expectError(
        error.InvalidBootstrapIterations,
        compareSeries(&storage, &.{1}, &.{1}, 0, 7),
    );
    try std.testing.expectError(
        error.BaseSampleCapacityExceeded,
        compareSeries(&storage, &.{ 1, 2, 3, 4 }, &.{ 1, 2, 3 }, 5, 7),
    );
    try std.testing.expectError(
        error.CandidateSampleCapacityExceeded,
        compareSeries(&storage, &.{ 1, 2, 3 }, &.{ 1, 2, 3, 4 }, 5, 7),
    );
    try std.testing.expectError(
        error.BootstrapIterationCapacityExceeded,
        compareSeries(&storage, &.{ 1, 2, 3 }, &.{ 1, 2, 3 }, 6, 7),
    );
    for (storage.bytes) |byte| try std.testing.expectEqual(@as(u8, 42), byte);
    const regions = try storage.acquireU64(1, 1, 1);
    _ = regions;
    try std.testing.expectError(
        error.ComparisonStorageInUse,
        compareSeries(&storage, &.{1}, &.{1}, 1, 7),
    );
    for (storage.bytes) |byte| try std.testing.expectEqual(@as(u8, 42), byte);
    storage.reset();
    _ = try compareSeries(&storage, &.{ 1, 2, 3 }, &.{ 2, 3, 4 }, 5, 7);
    try std.testing.expect(!storage.status().in_use);
}

test "comparison storage preserves output and reusable state" {
    const base = [_]u64{ 100, 105, 95, 102, 98, 103, 97, 101 };
    const candidate = [_]u64{ 97, 99, 101, 96, 100, 98, 102, 95 };
    var storage = try ComparisonStorage.init(std.testing.allocator, .{
        .max_samples_per_series = base.len,
        .max_bootstrap_iterations = 500,
    });
    defer storage.deinit(std.testing.allocator);
    storage.activate();
    const first = try compareSeries(&storage, &base, &candidate, 500, 42);
    const second = try compareSeries(&storage, &base, &candidate, 500, 42);
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(Result{
        .base_median = 101,
        .candidate_median = 99,
        .ratio = 0.9801980198019802,
        .ci_low = 0.941747572815534,
        .ci_high = 1.0204081632653061,
        .verdict = .neutral,
    }, first);
    try std.testing.expect(!storage.status().in_use);
}

test "activated comparison storage performs no backing allocation" {
    comptime {
        alloc_phase.capacity.record(
            alloc_phase.capacity.witness(@import("bench").ComparisonStorage, "bench_comparison_sealed_u64"),
        );
    }

    const base = @as([8]u64, @splat(10));
    const candidate = @as([8]u64, @splat(20));
    var counting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var storage = try ComparisonStorage.init(counting.allocator(), .{
        .max_samples_per_series = base.len,
        .max_bootstrap_iterations = 500,
    });
    defer storage.deinit(counting.allocator());
    storage.activate();
    const allocations = counting.alloc_index;
    const bytes = counting.allocated_bytes;

    const result = try compareSeries(&storage, &base, &candidate, 500, 7);

    try std.testing.expectEqual(@as(u64, 10), result.base_median);
    try std.testing.expectEqual(@as(u64, 20), result.candidate_median);
    try std.testing.expectEqual(@as(f64, 2), result.ratio);
    try std.testing.expectEqual(@as(f64, 2), result.ci_low);
    try std.testing.expectEqual(@as(f64, 2), result.ci_high);
    try std.testing.expectEqual(Verdict.regressed, result.verdict);
    try std.testing.expectEqual(@as(usize, 1), allocations);
    try std.testing.expectEqual(@as(usize, 4_096), bytes);
    try std.testing.expectEqual(allocations, counting.alloc_index);
    try std.testing.expectEqual(bytes, counting.allocated_bytes);
}
