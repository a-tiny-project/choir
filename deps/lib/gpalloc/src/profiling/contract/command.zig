const std = @import("std");
const sys = @import("sys");
const gpalloc = @import("gpalloc");

const cases = @import("cases.zig");
const options = @import("options.zig");
const output = @import("output.zig");

pub fn main(init: sys.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const parsed = options.parse(args[1..]) catch |err| {
        try output.writeParseError(arena, err);
        sys.process.exit(2);
    };
    if (parsed.show_help) {
        try output.writeUsage(arena);
        return;
    }
    const case_id = parsed.case_id orelse {
        try output.writeMissingCase(arena);
        sys.process.exit(2);
    };

    var heap_storage: gpalloc.GpAllocator = undefined;
    var owns_heap = false;
    const allocator: std.mem.Allocator = switch (parsed.allocator_mode) {
        .gpalloc => blk: {
            heap_storage = gpalloc.GpAllocator.init(systemAllocator(), .{});
            owns_heap = true;
            break :blk heap_storage.allocator();
        },
        .system => systemAllocator(),
    };
    defer if (owns_heap) heap_storage.deinit();

    cases.run(allocator, case_id) catch |err| {
        try output.writeCaseError(arena, case_id, err);
        sys.process.exit(1);
    };
}

fn systemAllocator() std.mem.Allocator {
    return sys.allocator.requiredHostInteropAllocator("gpalloc semantic contracts");
}
