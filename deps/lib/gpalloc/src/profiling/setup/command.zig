const std = @import("std");
const pretty_usage = @import("pretty_usage");
const sys = @import("sys");

const install = @import("install.zig");
const options = @import("options.zig");
const output = @import("output.zig");

pub fn main(init: sys.process.Init) u8 {
    return mainWithExitCode(init) catch |err| {
        pretty_usage.Terminal.stderr(init.gpa, .{}).writeErrorTextFmt(
            "gpalloc setup",
            "{s}",
            .{@errorName(err)},
        ) catch {};
        return 1;
    };
}

fn mainWithExitCode(init: sys.process.Init) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args_z = try init.minimal.args.toSlice(arena);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(arena);
    for (args_z[1..]) |arg_z| try args.append(arena, arg_z[0..arg_z.len]);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = sys.stdio.stdout().writer(sys.stdio.debugIo(), &stdout_buffer);
    defer stdout_writer.interface.flush() catch {};
    var stdout_text_buffer: [4096]u8 = undefined;
    var stdout_text = pretty_usage.pretty.TextWriter.init(
        &stdout_writer.interface,
        &stdout_text_buffer,
        .{ .width = 100 },
    );
    const stdout = &stdout_text.writer;
    defer stdout.flush() catch {};

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = sys.stdio.stderr().writer(sys.stdio.debugIo(), &stderr_buffer);
    defer stderr_writer.interface.flush() catch {};
    var stderr_text_buffer: [4096]u8 = undefined;
    var stderr_text = pretty_usage.pretty.TextWriter.init(
        &stderr_writer.interface,
        &stderr_text_buffer,
        .{ .width = 100 },
    );
    const stderr = &stderr_text.writer;
    defer stderr.flush() catch {};

    var parsed = try options.parse(arena, args.items);
    defer options.deinit(&parsed, arena);
    if (parsed.help) {
        try output.writeUsage(arena, stdout);
        return 0;
    }
    return try install.run(arena, init.io, init.environ_map, stdout, stderr, parsed);
}
