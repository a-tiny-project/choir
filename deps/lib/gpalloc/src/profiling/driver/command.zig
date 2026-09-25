const std = @import("std");
const sys = @import("sys");

const allocator_module = @import("allocator.zig");
const compare = @import("compare/root.zig");
const options = @import("options.zig");
const output = @import("output.zig");
const profile = @import("profile.zig");
const runner = @import("runner.zig");
const trace = @import("trace.zig");

pub fn main(init: sys.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len > 1 and std.mem.eql(u8, args[1], "compare")) {
        try runCompare(arena, args[2..]);
        return;
    }
    const parsed = options.parse(args[1..]) catch |err| {
        try output.writeParseError(arena, err);
        sys.process.exit(2);
    };

    if (parsed.show_help or parsed.list_workloads) {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = sys.stdio.stdout().writer(sys.stdio.debugIo(), &stdout_buffer);
        const stdout = &stdout_writer.interface;
        if (parsed.show_help) {
            try output.writeUsage(arena);
            return;
        }
        try runner.writeWorkloads(stdout);
        try stdout.flush();
        return;
    }

    var profile_runtime: profile.Runtime = .{};
    try profile.start(&profile_runtime, init.gpa, parsed);
    defer profile.deinit(&profile_runtime);

    var selected_allocator: allocator_module.Selected = .{};
    allocator_module.init(&selected_allocator, parsed.allocator_mode, parsed.allocator_stats);
    defer allocator_module.deinit(&selected_allocator);

    var trace_session: trace.Session = .{};
    try trace_session.start(init.gpa, selected_allocator.allocator);
    defer trace_session.deinit(init.gpa);
    selected_allocator.allocator = trace_session.allocator(selected_allocator.allocator);

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = sys.stdio.stdout().writer(sys.stdio.debugIo(), &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try output.writeRunStart(stdout, parsed);
    const benches = try runner.runSelectedWorkloads(
        arena,
        stdout,
        parsed,
        &selected_allocator,
        trace_session.tracerPtr(),
    );
    try trace_session.finish();
    try output.writeRunEnd(stdout, benches);
    try stdout.flush();
}

fn runCompare(arena: std.mem.Allocator, args: []const [:0]const u8) !void {
    const parsed = compare.parseOptions(args) catch |err| {
        try output.writeCompareParseError(arena, err);
        sys.process.exit(2);
    };
    if (parsed.show_help) {
        try output.writeCompareUsage(arena);
        return;
    }

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = sys.stdio.stdout().writer(sys.stdio.debugIo(), &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const code = try compare.run(arena, stdout, parsed);
    try stdout.flush();
    if (code != 0) sys.process.exit(code);
}
