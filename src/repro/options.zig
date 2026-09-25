const std = @import("std");

const Command = enum {
    help,
    replay,
};

pub const Options = struct {
    command: Command = .help,
    path: ?[]const u8 = null,
};

pub fn parseArgs(args: []const []const u8) !Options {
    if (args.len == 0) return .{ .command = .help };
    if (args.len == 1 and (std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "help"))) {
        return .{ .command = .help };
    }
    if (args.len == 2 and std.mem.eql(u8, args[0], "replay")) {
        return .{ .command = .replay, .path = args[1] };
    }
    return error.InvalidArguments;
}

test "parseArgs accepts help and replay" {
    try std.testing.expectEqual(.help, (try parseArgs(&.{})).command);
    try std.testing.expectEqual(.help, (try parseArgs(&.{"--help"})).command);
    const replay_options = try parseArgs(&.{ "replay", "failure.choirrepro" });
    try std.testing.expectEqual(.replay, replay_options.command);
    try std.testing.expectEqualStrings("failure.choirrepro", replay_options.path.?);
}

test "parseArgs rejects invalid arguments" {
    try std.testing.expectError(error.InvalidArguments, parseArgs(&.{"replay"}));
    try std.testing.expectError(error.InvalidArguments, parseArgs(&.{ "replay", "a", "b" }));
    try std.testing.expectError(error.InvalidArguments, parseArgs(&.{"unknown"}));
}
