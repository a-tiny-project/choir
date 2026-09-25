const std = @import("std");
const pretty = @import("pretty");
const pretty_usage = @import("pretty_usage");

const options_module = @import("options.zig");

const usage =
    \\usage: gpalloc-setup [options] [suite-dir] [allocators...]
    \\
    \\Options:
    \\  --suite-dir path  mimalloc-bench checkout. Default: zig-out/external/mimalloc-bench
    \\  --url url         suite repository URL. Default: TINYALLOC_ALLOCATOR_SUITE_URL
    \\                    or mimalloc-bench
    \\  --procs n         build parallelism. Default: TINYALLOC_ALLOCATOR_PROCS or host CPUs
    \\  --dry-run         print clone/build commands without running them
    \\  -h, --help        print this message
;

pub fn writeUsage(allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    try pretty_usage.writeUsageText(allocator, writer, usage, .{ .layout = .{ .width = 88 } });
}

pub fn writePrettyFmt(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try writePrettyText(writer, text);
}

fn writePrettyText(writer: *std.Io.Writer, text: []const u8) !void {
    try pretty.write(writer, .{ .text = text }, .{ .width = 88 });
}

pub fn writeBuildLine(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    options: options_module.Options,
) !void {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.writer.writeAll("gpalloc allocators: building");
    for (options.allocators) |name| try out.writer.print(" {s}", .{name});
    try out.writer.print(" in {s}\n", .{options.suite_dir});
    try writePrettyText(writer, out.written());
}

pub fn writeShellCommand(writer: *std.Io.Writer, argv: []const []const u8) !void {
    for (argv, 0..) |arg, index| {
        if (index != 0) try writer.writeByte(' ');
        try writeShellArgument(writer, arg);
    }
    try writer.writeByte('\n');
}

fn writeShellArgument(writer: *std.Io.Writer, arg: []const u8) !void {
    if (arg.len != 0 and shellSafe(arg)) {
        try writer.writeAll(arg);
        return;
    }
    try writer.writeByte('\'');
    for (arg) |byte| {
        if (byte == '\'') {
            try writer.writeAll("'\\''");
        } else {
            try writer.writeByte(byte);
        }
    }
    try writer.writeByte('\'');
}

fn shellSafe(arg: []const u8) bool {
    for (arg) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        switch (byte) {
            '_', '-', '.', '/', ':', '@', '%', '+', '=', ',' => continue,
            else => return false,
        }
    }
    return true;
}
