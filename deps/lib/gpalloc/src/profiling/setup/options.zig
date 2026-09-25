const std = @import("std");

pub const default_suite_dir = "zig-out/external/mimalloc-bench";
pub const default_suite_url = "https://github.com/daanx/mimalloc-bench";

const default_allocators = [_][]const u8{ "mi", "je", "tc" };

pub const Options = struct {
    suite_dir: []const u8 = default_suite_dir,
    suite_url: ?[]const u8 = null,
    procs: ?[]const u8 = null,
    allocators: []const []const u8 = &.{},
    dry_run: bool = false,
    help: bool = false,
};

pub fn deinit(options: *Options, allocator: std.mem.Allocator) void {
    allocator.free(options.allocators);
    options.* = .{};
}

pub fn parse(allocator: std.mem.Allocator, args: []const []const u8) !Options {
    var options = Options{};
    var suite_dir_set = false;
    var allocators: std.ArrayList([]const u8) = .empty;
    errdefer allocators.deinit(allocator);
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--dry-run")) {
            options.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            options.help = true;
        } else if (std.mem.eql(u8, arg, "--suite-dir")) {
            index += 1;
            if (index >= args.len) return error.MissingArgument;
            options.suite_dir = args[index];
            suite_dir_set = true;
        } else if (std.mem.eql(u8, arg, "--url")) {
            index += 1;
            if (index >= args.len) return error.MissingArgument;
            options.suite_url = args[index];
        } else if (std.mem.eql(u8, arg, "--procs")) {
            index += 1;
            if (index >= args.len) return error.MissingArgument;
            options.procs = args[index];
        } else if (!suite_dir_set) {
            options.suite_dir = arg;
            suite_dir_set = true;
        } else {
            try appendAllocatorSpec(allocator, &allocators, arg);
        }
    }
    if (allocators.items.len == 0) {
        for (default_allocators) |name| try allocators.append(allocator, name);
    }
    options.allocators = try allocators.toOwnedSlice(allocator);
    return options;
}

fn appendAllocatorSpec(
    allocator: std.mem.Allocator,
    allocators: *std.ArrayList([]const u8),
    spec: []const u8,
) !void {
    var pieces = std.mem.tokenizeAny(u8, spec, " \t\r\n");
    while (pieces.next()) |piece| try allocators.append(allocator, piece);
}

test "parse defaults allocator suite" {
    var options = try parse(std.testing.allocator, &.{});
    defer deinit(&options, std.testing.allocator);
    try std.testing.expectEqualStrings(default_suite_dir, options.suite_dir);
    try std.testing.expectEqual(@as(usize, 3), options.allocators.len);
    try std.testing.expectEqualStrings("mi", options.allocators[0]);
    try std.testing.expectEqualStrings("je", options.allocators[1]);
    try std.testing.expectEqualStrings("tc", options.allocators[2]);
}

test "parse positional suite and split allocator spec" {
    var options = try parse(std.testing.allocator, &.{ "out/suite", "mi je", "tc" });
    defer deinit(&options, std.testing.allocator);
    try std.testing.expectEqualStrings("out/suite", options.suite_dir);
    try std.testing.expectEqual(@as(usize, 3), options.allocators.len);
    try std.testing.expectEqualStrings("mi", options.allocators[0]);
    try std.testing.expectEqualStrings("je", options.allocators[1]);
    try std.testing.expectEqualStrings("tc", options.allocators[2]);
}

test "parse named options" {
    var options = try parse(std.testing.allocator, &.{
        "--suite-dir",
        "suite",
        "--url",
        "https://example.test/suite",
        "--procs",
        "7",
        "--dry-run",
        "mi",
    });
    defer deinit(&options, std.testing.allocator);
    try std.testing.expect(options.dry_run);
    try std.testing.expectEqualStrings("suite", options.suite_dir);
    try std.testing.expectEqualStrings("https://example.test/suite", options.suite_url.?);
    try std.testing.expectEqualStrings("7", options.procs.?);
    try std.testing.expectEqual(@as(usize, 1), options.allocators.len);
    try std.testing.expectEqualStrings("mi", options.allocators[0]);
}
