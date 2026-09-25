const std = @import("std");

const metric = @import("metric.zig");

pub const Profile = enum {
    smoke,
    full,
};

pub const Metric = metric.Metric;
pub const deriveNs = metric.deriveNs;

pub const Benchmark = struct {
    id: []const u8,
    binary: []const u8,
    name: []const u8,
    uses_stdin: bool = false,
    metric: Metric = .wall,
};

pub const all = [_]Benchmark{
    .{ .id = "cfrac", .binary = "cfrac", .name = "continued-fraction factorization" },
    .{ .id = "espresso", .binary = "espresso", .name = "espresso logic minimization" },
    .{ .id = "barnes", .binary = "barnes", .name = "Barnes-Hut N-body tree phases", .uses_stdin = true },
    .{ .id = "xmalloc-test", .binary = "xmalloc-test", .name = "asymmetric alloc/free thread handoff", .metric = .rtime },
    .{ .id = "larson", .binary = "larson", .name = "Larson server-style remote frees", .metric = .relative_time },
    .{ .id = "larson-sized", .binary = "larson-sized", .name = "Larson with sized deallocation", .metric = .relative_time },
    .{ .id = "alloc-test1", .binary = "alloc-test", .name = "single-thread Pareto allocation" },
    .{ .id = "alloc-testN", .binary = "alloc-test", .name = "multi-thread Pareto allocation" },
    .{ .id = "mstress", .binary = "mstress", .name = "server phases with object migration" },
    .{ .id = "malloc-large", .binary = "malloc-large", .name = "multi-MiB allocation churn" },
    .{ .id = "cache-scratch", .binary = "cache-scratch", .name = "Hoard passive false sharing" },
    .{ .id = "cache-thrash", .binary = "cache-thrash", .name = "Hoard active false sharing" },
    .{ .id = "glibc-simple", .binary = "glibc-simple", .name = "glibc single-thread benchtest" },
    .{ .id = "rptest", .binary = "rptest", .name = "rpmalloc-style allocation pattern", .metric = .memory_ops },
};

pub fn byId(id: []const u8) ?Benchmark {
    for (all) |benchmark| {
        if (std.mem.eql(u8, benchmark.id, id)) return benchmark;
    }
    return null;
}

pub fn binaryPath(
    allocator: std.mem.Allocator,
    suite_dir: []const u8,
    benchmark: Benchmark,
) ![]const u8 {
    return std.fs.path.join(allocator, &.{ suite_dir, "out", "bench", benchmark.binary });
}

pub fn stdinPath(
    allocator: std.mem.Allocator,
    suite_dir: []const u8,
    benchmark: Benchmark,
) !?[]const u8 {
    if (!benchmark.uses_stdin) return null;
    if (std.mem.eql(u8, benchmark.id, "barnes")) {
        return try std.fs.path.join(allocator, &.{ suite_dir, "bench", "barnes", "input" });
    }
    return null;
}

pub fn arguments(
    allocator: std.mem.Allocator,
    suite_dir: []const u8,
    benchmark: Benchmark,
    profile: Profile,
    procs: usize,
) ![]const []const u8 {
    const many = @max(@as(usize, 1), procs);
    const few = cappedProcs(procs, 2);
    if (std.mem.eql(u8, benchmark.id, "cfrac")) {
        return dupeArgs(allocator, &.{"17545186520507317056371138836327483792789528"});
    }
    if (std.mem.eql(u8, benchmark.id, "espresso")) {
        const input = try std.fs.path.join(
            allocator,
            &.{ suite_dir, "bench", "espresso", "largest.espresso" },
        );
        return dupeArgs(allocator, &.{input});
    }
    if (std.mem.eql(u8, benchmark.id, "barnes")) {
        return dupeArgs(allocator, &.{});
    }
    if (std.mem.eql(u8, benchmark.id, "xmalloc-test")) {
        const workers = if (profile == .full) many else few;
        const seconds: []const u8 = if (profile == .full) "5" else "1";
        return dupeArgs(allocator, &.{
            "-w",
            try formatCount(allocator, workers),
            "-t",
            seconds,
            "-s",
            "64",
        });
    }
    if (std.mem.eql(u8, benchmark.id, "larson") or
        std.mem.eql(u8, benchmark.id, "larson-sized"))
    {
        if (profile == .full) {
            return dupeArgs(allocator, &.{
                "5",                              "8",   "1000",
                "5000",                           "100", "4141",
                try formatCount(allocator, many),
            });
        }
        return dupeArgs(allocator, &.{
            "1",                             "4",  "200",
            "1000",                          "20", "4141",
            try formatCount(allocator, few),
        });
    }
    if (std.mem.eql(u8, benchmark.id, "alloc-test1")) {
        return dupeArgs(allocator, &.{"1"});
    }
    if (std.mem.eql(u8, benchmark.id, "alloc-testN")) {
        const workers = if (profile == .full) cappedProcs(procs, 16) else few;
        return dupeArgs(allocator, &.{try formatCount(allocator, workers)});
    }
    if (std.mem.eql(u8, benchmark.id, "mstress")) {
        if (profile == .full) {
            return dupeArgs(allocator, &.{ try formatCount(allocator, many), "50", "25" });
        }
        return dupeArgs(allocator, &.{ try formatCount(allocator, few), "5", "3" });
    }
    if (std.mem.eql(u8, benchmark.id, "malloc-large")) {
        return dupeArgs(allocator, &.{});
    }
    if (std.mem.eql(u8, benchmark.id, "cache-scratch")) {
        const workers = if (profile == .full) many else few;
        const inner: []const u8 = if (profile == .full) "2000000" else "100000";
        const count = try formatCount(allocator, workers);
        return dupeArgs(allocator, &.{ count, "1000", "1", inner, count });
    }
    if (std.mem.eql(u8, benchmark.id, "cache-thrash")) {
        const workers = if (profile == .full) many else few;
        const inner: []const u8 = if (profile == .full) "2000000" else "200000";
        const count = try formatCount(allocator, workers);
        return dupeArgs(allocator, &.{ count, "2000", "64", inner, count });
    }
    if (std.mem.eql(u8, benchmark.id, "glibc-simple")) {
        return dupeArgs(allocator, &.{});
    }
    if (std.mem.eql(u8, benchmark.id, "rptest")) {
        if (profile == .full) {
            return dupeArgs(allocator, &.{
                try formatCount(allocator, many),
                "0",
                "1",
                "2",
                "500",
                "1000",
                "100",
                "8",
                "16000",
            });
        }
        return dupeArgs(allocator, &.{
            try formatCount(allocator, few),
            "0",
            "1",
            "2",
            "100",
            "250",
            "100",
            "8",
            "4000",
        });
    }
    return error.UnknownBenchmark;
}

fn cappedProcs(procs: usize, cap: usize) usize {
    return @max(@as(usize, 1), @min(procs, cap));
}

fn formatCount(allocator: std.mem.Allocator, value: usize) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{value});
}

fn dupeArgs(
    allocator: std.mem.Allocator,
    args: []const []const u8,
) ![]const []const u8 {
    const owned = try allocator.alloc([]const u8, args.len);
    for (owned, args) |*slot, arg| slot.* = try allocator.dupe(u8, arg);
    return owned;
}

test "catalog resolves binaries arguments and stdin" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const cfrac = byId("cfrac").?;
    const cfrac_args = try arguments(arena, "suite", cfrac, .smoke, 16);
    try std.testing.expectEqual(@as(usize, 1), cfrac_args.len);
    try std.testing.expectEqualStrings(
        "17545186520507317056371138836327483792789528",
        cfrac_args[0],
    );
    try std.testing.expectEqualStrings(
        "suite/out/bench/cfrac",
        try binaryPath(arena, "suite", cfrac),
    );
    try std.testing.expect(try stdinPath(arena, "suite", cfrac) == null);

    const barnes = byId("barnes").?;
    try std.testing.expectEqualStrings(
        "suite/bench/barnes/input",
        (try stdinPath(arena, "suite", barnes)).?,
    );

    const xmalloc = byId("xmalloc-test").?;
    const smoke_args = try arguments(arena, "suite", xmalloc, .smoke, 16);
    try std.testing.expectEqualStrings("2", smoke_args[1]);
    const full_args = try arguments(arena, "suite", xmalloc, .full, 16);
    try std.testing.expectEqualStrings("16", full_args[1]);
    try std.testing.expectEqualStrings("5", full_args[3]);

    try std.testing.expect(byId("missing") == null);
}

test "catalog larson smoke matches recovered argv" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const larson = byId("larson").?;
    const args = try arguments(arena, "suite", larson, .smoke, 8);
    const expected = [_][]const u8{ "1", "4", "200", "1000", "20", "4141", "2" };
    try std.testing.expectEqual(expected.len, args.len);
    for (expected, args) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "fixed-duration benchmarks derive time from stdout" {
    try std.testing.expectEqual(Metric.relative_time, byId("larson").?.metric);
    try std.testing.expectEqual(Metric.relative_time, byId("larson-sized").?.metric);
    try std.testing.expectEqual(Metric.rtime, byId("xmalloc-test").?.metric);
    try std.testing.expectEqual(Metric.memory_ops, byId("rptest").?.metric);
    try std.testing.expectEqual(Metric.wall, byId("cfrac").?.metric);
}
