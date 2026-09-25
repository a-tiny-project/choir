const std = @import("std");

pub const AllocatorMode = enum {
    gpalloc,
    gpalloc_limited_thread_caches,
    gpalloc_unlimited_thread_caches,
    gpalloc_no_large_cache,
    gpalloc_no_thread_exit_flush,
    gpalloc_os_pages,
    gpalloc_os_discard,
    gpalloc_release_empty,
    smp,
    system,
};

pub const Options = struct {
    allocator_mode: AllocatorMode = .gpalloc,
    allocator_label: ?[]const u8 = null,
    workload_id: ?[]const u8 = null,
    warmup: u32 = 5,
    samples: u32 = 30,
    evals: u32 = 1,
    coz_profile_path: ?[]const u8 = null,
    coz_experiments: bool = false,
    coz_experiment_duration_ns: ?u64 = null,
    coz_source_pattern: ?[]const u8 = null,
    stabilizer: bool = false,
    stabilizer_seed: u64 = 20260612,
    allocator_stats: bool = false,
    show_help: bool = false,
    list_workloads: bool = false,
};

pub const Error = error{
    InvalidArgument,
    UnknownAllocatorMode,
};

pub fn parse(args: []const [:0]const u8) Error!Options {
    var parsed: Options = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--allocator")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.allocator_mode = parseAllocatorMode(args[index]) orelse
                return error.UnknownAllocatorMode;
        } else if (std.mem.eql(u8, arg, "--label")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.allocator_label = args[index];
        } else if (std.mem.eql(u8, arg, "--workload")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.workload_id = args[index];
        } else if (std.mem.eql(u8, arg, "--warmup")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.warmup = parsePositiveU32(args[index]) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--samples")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.samples = parsePositiveU32(args[index]) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--evals")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.evals = parsePositiveU32(args[index]) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--coz-profile")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.coz_profile_path = args[index];
        } else if (std.mem.eql(u8, arg, "--coz-experiments")) {
            parsed.coz_experiments = true;
        } else if (std.mem.eql(u8, arg, "--coz-experiment-ms")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.coz_experiment_duration_ns =
                parseDurationMs(args[index]) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--coz-source")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.coz_source_pattern = args[index];
        } else if (std.mem.eql(u8, arg, "--stabilizer")) {
            parsed.stabilizer = true;
        } else if (std.mem.eql(u8, arg, "--stabilizer-seed")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.stabilizer_seed = std.fmt.parseInt(u64, args[index], 10) catch
                return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--allocator-stats")) {
            parsed.allocator_stats = true;
        } else if (std.mem.eql(u8, arg, "--list-workloads")) {
            parsed.list_workloads = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            parsed.show_help = true;
        } else {
            return error.InvalidArgument;
        }
    }
    return parsed;
}

pub fn modeName(mode: AllocatorMode) []const u8 {
    return switch (mode) {
        .gpalloc => "gpalloc",
        .gpalloc_limited_thread_caches => "gpalloc-limited-thread-caches",
        .gpalloc_unlimited_thread_caches => "gpalloc-unlimited-thread-caches",
        .gpalloc_no_large_cache => "gpalloc-no-large-cache",
        .gpalloc_no_thread_exit_flush => "gpalloc-no-thread-exit-flush",
        .gpalloc_os_pages => "gpalloc-os-pages",
        .gpalloc_os_discard => "gpalloc-os-discard",
        .gpalloc_release_empty => "gpalloc-release-empty",
        .smp => "smp",
        .system => "system",
    };
}

pub fn label(parsed: Options) []const u8 {
    return parsed.allocator_label orelse modeName(parsed.allocator_mode);
}

fn parseDurationMs(text: []const u8) !u64 {
    const value = try std.fmt.parseInt(u64, text, 10);
    if (value == 0) return error.InvalidValue;
    return try std.math.mul(u64, value, std.time.ns_per_ms);
}

fn parsePositiveU32(text: []const u8) !u32 {
    const value = try std.fmt.parseInt(u32, text, 10);
    if (value == 0) return error.InvalidValue;
    return value;
}

fn parseAllocatorMode(text: []const u8) ?AllocatorMode {
    if (std.mem.eql(u8, text, "gpalloc")) return .gpalloc;
    if (std.mem.eql(u8, text, "gpalloc-limited-thread-caches"))
        return .gpalloc_limited_thread_caches;
    if (std.mem.eql(u8, text, "gpalloc-unlimited-thread-caches"))
        return .gpalloc_unlimited_thread_caches;
    if (std.mem.eql(u8, text, "gpalloc-no-large-cache"))
        return .gpalloc_no_large_cache;
    if (std.mem.eql(u8, text, "gpalloc-no-thread-exit-flush"))
        return .gpalloc_no_thread_exit_flush;
    if (std.mem.eql(u8, text, "gpalloc-os-pages")) return .gpalloc_os_pages;
    if (std.mem.eql(u8, text, "gpalloc-os-discard")) return .gpalloc_os_discard;
    if (std.mem.eql(u8, text, "gpalloc-release-empty")) return .gpalloc_release_empty;
    if (std.mem.eql(u8, text, "smp")) return .smp;
    if (std.mem.eql(u8, text, "system")) return .system;
    return null;
}

test "parse benchmark driver options" {
    const parsed = try parse(&.{
        "--allocator",
        "gpalloc-os-discard",
        "--label",
        "candidate",
        "--workload",
        "small_churn",
        "--warmup",
        "2",
        "--samples",
        "3",
        "--evals",
        "4",
        "--coz-profile",
        "profile.coz",
        "--coz-experiments",
        "--coz-experiment-ms",
        "5",
        "--coz-source",
        "src",
        "--allocator-stats",
    });
    try std.testing.expectEqual(AllocatorMode.gpalloc_os_discard, parsed.allocator_mode);
    try std.testing.expectEqualStrings("candidate", label(parsed));
    try std.testing.expectEqualStrings("small_churn", parsed.workload_id.?);
    try std.testing.expectEqual(@as(u32, 2), parsed.warmup);
    try std.testing.expectEqual(@as(u32, 3), parsed.samples);
    try std.testing.expectEqual(@as(u32, 4), parsed.evals);
    try std.testing.expectEqualStrings("profile.coz", parsed.coz_profile_path.?);
    try std.testing.expect(parsed.coz_experiments);
    try std.testing.expectEqual(
        @as(u64, 5 * std.time.ns_per_ms),
        parsed.coz_experiment_duration_ns.?,
    );
    try std.testing.expectEqualStrings("src", parsed.coz_source_pattern.?);
    try std.testing.expect(parsed.allocator_stats);
}

test "parse stabilizer options" {
    const parsed = try parse(&.{ "--stabilizer", "--stabilizer-seed", "99" });
    try std.testing.expect(parsed.stabilizer);
    try std.testing.expectEqual(@as(u64, 99), parsed.stabilizer_seed);
    try std.testing.expectError(error.InvalidArgument, parse(&.{ "--stabilizer-seed", "x" }));
}

test "parse benchmark driver help and workload listing" {
    const parsed = try parse(&.{ "--help", "--list-workloads" });
    try std.testing.expect(parsed.show_help);
    try std.testing.expect(parsed.list_workloads);
}

test "parse rejects invalid benchmark driver arguments" {
    try std.testing.expectError(error.UnknownAllocatorMode, parse(&.{ "--allocator", "unknown" }));
    try std.testing.expectError(error.InvalidArgument, parse(&.{ "--samples", "0" }));
    try std.testing.expectError(error.InvalidArgument, parse(&.{ "--coz-experiment-ms", "0" }));
    try std.testing.expectError(error.InvalidArgument, parse(&.{"--label"}));
}
