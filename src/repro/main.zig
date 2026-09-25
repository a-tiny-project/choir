const std = @import("std");
const alloc_arena = @import("alloc_arena");
const alloc_observe = @import("alloc_observe");
const pretty = @import("pretty");
const sys = @import("sys");
const namespace = @import("root.zig");

const Allocator = std.mem.Allocator;
const command_mod = namespace.command;

pub fn main(init: sys.process.Init) !void {
    var gpa = alloc_observe.debug.Allocator(.{}).init(
        sys.memory.page_allocator,
    );
    const backing_allocator = gpa.allocator();

    const exit_code: u8 = blk: {
        var arena_state = alloc_arena.Arena.init(backing_allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const args = init.minimal.args.toSlice(arena) catch |err| {
            try writeError(arena, err);
            break :blk 1;
        };

        break :blk command_mod.run(
            arena,
            backing_allocator,
            args[1..],
            command_mod.default_limits,
        ) catch |err| switch (err) {
            error.InvalidArguments => 2,
            else => {
                try writeError(arena, err);
                break :blk 1;
            },
        };
    };

    if (gpa.deinit() == .leak) sys.process.exit(1);
    sys.process.exit(exit_code);
}

fn writeError(arena: Allocator, err: anyerror) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr = sys.stdio.stderr().writer(sys.stdio.debugIo(), &stderr_buffer);
    defer stderr.interface.flush() catch {};
    const detail = switch (err) {
        error.ReproducerInputCapacityExceeded => "reproducer file exceeds configured input capacity",
        else => @errorName(err),
    };
    const text = try std.fmt.allocPrint(arena, "choir-pass-repro: {s}\n", .{detail});
    try pretty.write(&stderr.interface, .{ .text = text }, .{ .width = 88 });
}
