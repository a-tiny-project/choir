const std = @import("std");

const catalog = @import("catalog.zig");

pub const default_suite_dir = "zig-out/external/mimalloc-bench";
pub const default_gpalloc_preload = "zig-out/lib/libgpalloc_malloc.so";

pub const AllocatorMode = union(enum) {
    libc,
    gpalloc,
    mimalloc,
    jemalloc,
    tcmalloc,
    preload: []const u8,

    pub fn label(self: AllocatorMode) []const u8 {
        return switch (self) {
            .libc => "libc",
            .gpalloc => "gpalloc",
            .mimalloc => "mimalloc",
            .jemalloc => "jemalloc",
            .tcmalloc => "tcmalloc",
            .preload => "preload",
        };
    }
};

pub const Options = struct {
    suite_dir: []const u8 = default_suite_dir,
    allocator_mode: AllocatorMode = .libc,
    allocator_label: ?[]const u8 = null,
    benchmark_id: ?[]const u8 = null,
    profile: catalog.Profile = .smoke,
    samples: u32 = 5,
    warmup: u32 = 1,
    procs: usize = 0,
    show_help: bool = false,
    list_benchmarks: bool = false,
};

pub const Error = error{
    InvalidArgument,
    UnknownAllocatorMode,
    UnknownBenchmark,
};

pub fn parse(args: []const [:0]const u8) Error!Options {
    var parsed: Options = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--suite-dir")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.suite_dir = args[index];
        } else if (std.mem.eql(u8, arg, "--allocator")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.allocator_mode = parseAllocatorMode(args[index]) orelse
                return error.UnknownAllocatorMode;
        } else if (std.mem.eql(u8, arg, "--label")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.allocator_label = args[index];
        } else if (std.mem.eql(u8, arg, "--benchmark")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            if (!std.mem.eql(u8, args[index], "all")) {
                if (catalog.byId(args[index]) == null) return error.UnknownBenchmark;
                parsed.benchmark_id = args[index];
            }
        } else if (std.mem.eql(u8, arg, "--full")) {
            parsed.profile = .full;
        } else if (std.mem.eql(u8, arg, "--samples")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.samples = parsePositiveU32(args[index]) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--warmup")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.warmup = std.fmt.parseInt(u32, args[index], 10) catch
                return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--procs")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.procs = parsePositiveUsize(args[index]) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--list-benchmarks")) {
            parsed.list_benchmarks = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            parsed.show_help = true;
        } else {
            return error.InvalidArgument;
        }
    }
    return parsed;
}

pub fn label(parsed: Options) []const u8 {
    return parsed.allocator_label orelse parsed.allocator_mode.label();
}

pub fn preloadPath(
    allocator: std.mem.Allocator,
    parsed: Options,
) !?[]const u8 {
    return switch (parsed.allocator_mode) {
        .libc => null,
        .gpalloc => default_gpalloc_preload,
        .mimalloc => try std.fs.path.join(
            allocator,
            &.{ parsed.suite_dir, "extern", "mi", "out", "release", "libmimalloc.so" },
        ),
        .jemalloc => try std.fs.path.join(
            allocator,
            &.{ parsed.suite_dir, "extern", "je", "lib", "libjemalloc.so" },
        ),
        .tcmalloc => try std.fs.path.join(
            allocator,
            &.{ parsed.suite_dir, "extern", "tc", ".libs", "libtcmalloc_minimal.so" },
        ),
        .preload => |path| path,
    };
}

fn parseAllocatorMode(text: []const u8) ?AllocatorMode {
    if (std.mem.eql(u8, text, "libc")) return .libc;
    if (std.mem.eql(u8, text, "gpalloc")) return .gpalloc;
    if (std.mem.eql(u8, text, "mimalloc")) return .mimalloc;
    if (std.mem.eql(u8, text, "jemalloc")) return .jemalloc;
    if (std.mem.eql(u8, text, "tcmalloc")) return .tcmalloc;
    if (std.mem.startsWith(u8, text, "preload:")) {
        const path = text["preload:".len..];
        if (path.len == 0) return null;
        return .{ .preload = path };
    }
    return null;
}

fn parsePositiveU32(text: []const u8) !u32 {
    const value = try std.fmt.parseInt(u32, text, 10);
    if (value == 0) return error.InvalidValue;
    return value;
}

fn parsePositiveUsize(text: []const u8) !usize {
    const value = try std.fmt.parseInt(usize, text, 10);
    if (value == 0) return error.InvalidValue;
    return value;
}

test "parse external runner options" {
    const parsed = try parse(&.{
        "--suite-dir",
        "suite",
        "--allocator",
        "mimalloc",
        "--benchmark",
        "cfrac",
        "--full",
        "--samples",
        "9",
        "--warmup",
        "2",
        "--procs",
        "8",
    });
    try std.testing.expectEqualStrings("suite", parsed.suite_dir);
    try std.testing.expectEqualStrings("mimalloc", label(parsed));
    try std.testing.expectEqualStrings("cfrac", parsed.benchmark_id.?);
    try std.testing.expectEqual(catalog.Profile.full, parsed.profile);
    try std.testing.expectEqual(@as(u32, 9), parsed.samples);
    try std.testing.expectEqual(@as(u32, 2), parsed.warmup);
    try std.testing.expectEqual(@as(usize, 8), parsed.procs);
}

test "parse external runner rejects invalid input" {
    try std.testing.expectError(error.UnknownAllocatorMode, parse(&.{ "--allocator", "x" }));
    try std.testing.expectError(error.UnknownAllocatorMode, parse(&.{ "--allocator", "preload:" }));
    try std.testing.expectError(error.UnknownBenchmark, parse(&.{ "--benchmark", "x" }));
    try std.testing.expectError(error.InvalidArgument, parse(&.{ "--samples", "0" }));
    try std.testing.expectError(error.InvalidArgument, parse(&.{"--mystery"}));
}

test "preload paths resolve per allocator mode" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try std.testing.expect(try preloadPath(arena, .{ .allocator_mode = .libc }) == null);
    try std.testing.expectEqualStrings(
        default_gpalloc_preload,
        (try preloadPath(arena, .{ .allocator_mode = .gpalloc })).?,
    );
    try std.testing.expectEqualStrings(
        "suite/extern/mi/out/release/libmimalloc.so",
        (try preloadPath(arena, .{ .allocator_mode = .mimalloc, .suite_dir = "suite" })).?,
    );
    try std.testing.expectEqualStrings(
        "/x/lib.so",
        (try preloadPath(arena, .{ .allocator_mode = .{ .preload = "/x/lib.so" } })).?,
    );
}
