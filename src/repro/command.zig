const std = @import("std");
const choir = @import("choir");
const pretty = @import("pretty");
const sys = @import("sys");
const namespace = @import("root.zig");

const Allocator = std.mem.Allocator;
const fs_io = std.Options.debug_io;
pub const input = namespace.input;
const InputLimits = input.Limits;
const default_input_limits = input.default_limits;
const options_mod = namespace.options;
const help_mod = namespace.help;

pub const Limits = struct {
    reproducer_input: InputLimits,
};

pub const default_limits: Limits = .{
    .reproducer_input = default_input_limits,
};

pub fn run(
    arena: Allocator,
    backing_allocator: Allocator,
    args: []const []const u8,
    limits: Limits,
) !u8 {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout = sys.stdio.stdout().writer(sys.stdio.debugIo(), &stdout_buffer);
    defer stdout.interface.flush() catch {};
    return try runWithWriter(
        arena,
        backing_allocator,
        &stdout.interface,
        args,
        limits,
    );
}

pub fn runWithWriter(
    arena: Allocator,
    backing_allocator: Allocator,
    out: *std.Io.Writer,
    args: []const []const u8,
    limits: Limits,
) !u8 {
    const options = try options_mod.parseArgs(args);
    switch (options.command) {
        .help => {
            try pretty.write(out, .{ .text = help_mod.usage_text }, .{ .width = 88 });
            return 0;
        },
        .replay => {
            var reproducer = try readReproducer(
                arena,
                backing_allocator,
                options.path.?,
                limits.reproducer_input,
            );
            defer reproducer.deinit(arena);
            var registry = try buildStandardRegistry(arena);
            defer registry.deinit();
            var ctx = try choir.initCompilerContext(arena, .{
                .context_limits = choir.ir.Context.Limits.standard,
                .preload_all_choir_dialects = true,
            });
            defer ctx.deinit(arena);
            return try replayReproducer(
                arena,
                backing_allocator,
                out,
                &registry,
                &ctx,
                options.path.?,
                &reproducer,
            );
        },
    }
}

pub fn replayReproducer(
    arena: Allocator,
    worker_allocator: Allocator,
    out: *std.Io.Writer,
    registry: *const choir.passes.PassRegistry,
    ctx: *choir.ir.Context,
    path: []const u8,
    reproducer: *const choir.passes.PassFailureReproducer,
) !u8 {
    const replayed = try choir.passes.replayPassFailureReproducer(arena, registry, ctx, reproducer, .{
        .worker_allocator = worker_allocator,
    });
    if (replayed.result == .failure) {
        try writeReplayReport(arena, out, path, reproducer, replayed, true);
        return 0;
    }

    try writeReplayReport(arena, out, path, reproducer, replayed, false);
    return 1;
}

pub fn readReproducer(
    arena: Allocator,
    input_allocator: Allocator,
    path: []const u8,
    maximum: InputLimits,
) !choir.passes.PassFailureReproducer {
    const exact = try exactInputLimits(path, maximum);
    var storage = try input.Storage.init(input_allocator, exact);
    defer storage.deinit(input_allocator);
    storage.activate();
    const file_bytes = try storage.readFile(std.Io.Dir.cwd(), fs_io, path);
    defer storage.release();
    return try choir.passes.parsePassFailureReproducerAlloc(arena, file_bytes);
}

fn exactInputLimits(path: []const u8, maximum: InputLimits) !InputLimits {
    var file = if (std.fs.path.isAbsolute(path))
        try std.Io.Dir.openFileAbsolute(fs_io, path, .{})
    else
        try std.Io.Dir.cwd().openFile(fs_io, path, .{});
    defer file.close(fs_io);
    return try input.exactLimitsForFile((try file.stat(fs_io)).size, maximum);
}

fn buildStandardRegistry(allocator: Allocator) !choir.passes.PassRegistry {
    var registry = choir.passes.PassRegistry.init(allocator);
    errdefer registry.deinit();
    try choir.passes.registerOptimizationPassEntries(&registry);
    return registry;
}

fn writeReplayReport(
    arena: Allocator,
    out: *std.Io.Writer,
    path: []const u8,
    reproducer: *const choir.passes.PassFailureReproducer,
    replay_result: choir.passes.ReplayResult,
    reproduced: bool,
) !void {
    var text: std.Io.Writer.Allocating = .init(arena);
    defer text.deinit();
    try text.writer.print("choir-pass-repro: {s}\n", .{if (reproduced) "reproduced failure" else "did not reproduce failure"});
    try text.writer.print("file: {s}\n", .{path});
    try text.writer.print("pipeline: {s}\n", .{reproducer.pipeline});
    try text.writer.print("failure: captured {s}, replayed {s}\n", .{ failureKindName(reproducer.failure_kind), failureKindName(replay_result.failure_kind) });
    if (reproducer.pass_name) |name| try text.writer.print("pass: {s}\n", .{name});
    if (reproducer.target_op_name) |name| try text.writer.print("target: {s}\n", .{name});
    if (reproducer.target_symbol_name) |name| try text.writer.print("symbol: {s}\n", .{name});
    try text.writer.print("threads: requested {d}, captured workers {d}, replay workers {d}\n", .{ reproducer.max_threads, reproducer.worker_count, replay_result.worker_count });
    try text.writer.print("pass runs: {d}\n", .{replay_result.stats.pass_runs});
    try text.writer.print("passes skipped: {d}\n", .{replay_result.stats.passes_skipped});
    try text.writer.print("modified passes: {d}\n", .{replay_result.stats.passes_modified});
    try pretty.write(out, .{ .text = text.written() }, .{ .width = 88 });
}

fn failureKindName(kind: ?choir.passes.PassFailureKind) []const u8 {
    return switch (kind orelse return "none") {
        .exhausted => "exhausted",
        .pass => "pass",
        .verifier => "verifier",
        .target => "target",
    };
}
