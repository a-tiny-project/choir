const std = @import("std");

pub const AllocatorMode = enum {
    gpalloc,
    system,
};

pub const Options = struct {
    allocator_mode: AllocatorMode = .gpalloc,
    case_id: ?[]const u8 = null,
    show_help: bool = false,
};

pub const Error = error{
    InvalidArgument,
    UnknownAllocatorMode,
};

pub fn parse(args: []const [:0]const u8) Error!Options {
    var options: Options = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--allocator")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            options.allocator_mode = parseAllocatorMode(args[index]) orelse
                return error.UnknownAllocatorMode;
        } else if (std.mem.eql(u8, arg, "--case")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            options.case_id = args[index];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            options.show_help = true;
        } else {
            return error.InvalidArgument;
        }
    }
    return options;
}

fn parseAllocatorMode(text: []const u8) ?AllocatorMode {
    if (std.mem.eql(u8, text, "gpalloc")) return .gpalloc;
    if (std.mem.eql(u8, text, "system")) return .system;
    return null;
}

test "parse contract case and allocator mode" {
    const options = try parse(&.{
        "--allocator",
        "system",
        "--case",
        "native-alloc-roundtrip",
    });
    try std.testing.expectEqual(AllocatorMode.system, options.allocator_mode);
    try std.testing.expectEqualStrings("native-alloc-roundtrip", options.case_id.?);
    try std.testing.expect(!options.show_help);
}

test "parse contract help flag" {
    const options = try parse(&.{"--help"});
    try std.testing.expect(options.show_help);
}

test "parse rejects missing option values" {
    try std.testing.expectError(error.InvalidArgument, parse(&.{"--allocator"}));
    try std.testing.expectError(error.InvalidArgument, parse(&.{"--case"}));
}

test "parse rejects unknown allocator mode" {
    try std.testing.expectError(
        error.UnknownAllocatorMode,
        parse(&.{ "--allocator", "unknown" }),
    );
}
