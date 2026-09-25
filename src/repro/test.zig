const std = @import("std");
const alloc_phase = @import("alloc_phase");

const alloc_arena = @import("alloc_arena");

const choir = @import("choir");

const repro = @import("root.zig");

const command = repro.command;

const input = @import("input/test.zig");

const Allocator = std.mem.Allocator;

const fs_io = std.Options.debug_io;

test {
    std.testing.refAllDecls(repro);
    _ = input;
}

fn failingPass(_: *choir.passes.PassContext) choir.passes.PassResult {
    return .failure;
}

fn buildTestRegistry(allocator: Allocator) !choir.passes.PassRegistry {
    var registry = choir.passes.PassRegistry.init(allocator);
    errdefer registry.deinit();
    try registry.registerPass(.{
        .name = "choir-pass-repro-test-fail",
        .description = "test failure pass",
        .pass = .{
            .name = "choir-pass-repro-test-fail",
            .description = "test failure pass",
            .run_fn = failingPass,
            .mutation_scope = .read_only,
        },
    });
    return registry;
}

fn initTestContext(allocator: Allocator) !choir.ir.Context {
    return choir.initCompilerContext(allocator, .{
        .context_limits = choir.ir.Context.Limits.testing,
        .preload_dialects = &.{ "builtin", "arith", "func" },
    });
}

fn buildTestModule(ctx: *choir.ir.Context) !*choir.ir.Operation {
    const loc = choir.ir.Location.getUnknown();
    const module = try choir.dialects.BuiltinDialect.ModuleOp.create(ctx, loc);
    const body = module.getBodyBlock();
    const i32_type = try choir.dialects.ArithDialect.getScalarType(ctx, .i32);
    for (0..2) |index| {
        const name = try std.fmt.allocPrint(choir.ir.context.transientAllocator(ctx), "pass_repro_{d}", .{index});
        var func = try choir.dialects.FuncDialect.FuncOp.create(ctx, loc, name, &.{i32_type}, &.{i32_type});
        try body.addOperation(func.op);
        const ret = try choir.dialects.FuncDialect.ReturnOp.create(ctx, loc, &.{func.getArgument(0)});
        try func.getEntryBlock().addOperation(ret.op);
    }
    return module.op;
}

test "Choir pass reproducer root exposes caller-selected input storage" {
    comptime {
        alloc_phase.capacity.record(
            alloc_phase.capacity.witness(@import("./input/root.zig").Storage, "choir_pass_reproducer_input_root"),
        );
    }

    var storage = try repro.InputStorage.init(std.testing.allocator, .{ .file_bytes = 17 });
    defer storage.deinit(std.testing.allocator);
    storage.activate();
    try std.testing.expectEqual(@as(usize, 17), storage.status().file_bytes);
    try std.testing.expectEqual(@as(usize, 18), storage.status().storage_bytes);
    try std.testing.expectEqual(
        @as(usize, 16 * 1024 * 1024),
        repro.default_limits.reproducer_input.file_bytes,
    );
}

test "Choir pass reproducer command composes file input storage only for replay" {
    comptime {
        alloc_phase.capacity.record(
            alloc_phase.capacity.witness(@import("./input/root.zig").Storage, "choir_pass_reproducer_input_command_composition"),
        );
    }

    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    var arena_state = alloc_arena.Arena.init(std.testing.allocator);
    defer arena_state.deinit();
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expectEqual(
        @as(u8, 0),
        try command.runWithWriter(
            arena_state.allocator(),
            failing.allocator(),
            &output.writer,
            &.{"--help"},
            .{ .reproducer_input = .{ .file_bytes = 0 } },
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), failing.alloc_index);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "16 MiB inclusive") != null);
}

test "Choir pass reproducer parser consumes borrowed input bytes" {
    comptime {
        alloc_phase.capacity.record(
            alloc_phase.capacity.witness(@import("./input/root.zig").Storage, "choir_pass_reproducer_input_byte_boundary"),
        );
    }

    const testing = std.testing;
    var arena_state = alloc_arena.Arena.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var registry = try buildTestRegistry(arena);
    defer registry.deinit();

    var ctx = try initTestContext(arena);
    defer ctx.deinit(arena);
    const module = try buildTestModule(&ctx);

    var manager = choir.passes.PassManager.init(arena);
    defer manager.deinit();
    try choir.passes.parsePassPipeline(&registry, "func.func(choir-pass-repro-test-fail)", &manager);

    const result = manager.runWithOptions(module, &ctx, .{ .max_threads = 2 });
    try testing.expectEqual(choir.passes.PassResult.failure, result);
    const reproducer = manager.getLastFailureReproducer() orelse return error.TestExpectedReproducer;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fs.path.join(arena, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "pass.choirrepro" });
    try choir.passes.writePassFailureReproducerFile(arena, path, reproducer);
    const file_size = (try std.Io.Dir.cwd().statFile(fs_io, path, .{})).size;
    const exact_file_bytes = std.math.cast(usize, file_size) orelse
        return error.TestUnexpectedResult;
    var input_allocations = testing.FailingAllocator.init(testing.allocator, .{});
    var from_file = try command.readReproducer(
        arena,
        input_allocations.allocator(),
        path,
        .{ .file_bytes = exact_file_bytes },
    );
    defer from_file.deinit(arena);
    try testing.expectEqual(@as(usize, 1), input_allocations.alloc_index);
    try testing.expectEqual(@as(usize, 0), input_allocations.resize_index);
    try testing.expectEqual(exact_file_bytes + 1, input_allocations.allocated_bytes);
    try testing.expectEqual(@as(usize, 1), input_allocations.deallocations);

    var replay_ctx = try initTestContext(arena);
    defer replay_ctx.deinit(arena);
    var output: std.Io.Writer.Allocating = .init(arena);
    defer output.deinit();

    const exit_code = try command.replayReproducer(
        arena,
        arena,
        &output.writer,
        &registry,
        &replay_ctx,
        path,
        &from_file,
    );
    try testing.expectEqual(@as(u8, 0), exit_code);
    try testing.expect(std.mem.indexOf(u8, output.written(), "reproduced failure") != null);
    try testing.expect(std.mem.indexOf(u8, output.written(), "func.func(choir-pass-repro-test-fail)") != null);
}

test "Choir pass reproducer rejects max plus one before input allocation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(
        fs_io,
        .{ .sub_path = "pass.choirrepro", .data = "123456" },
    );
    const path = try temporary.dir.realPathFileAlloc(
        fs_io,
        "pass.choirrepro",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(path);

    var input_allocations = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{},
    );
    try std.testing.expectError(
        error.ReproducerInputCapacityExceeded,
        command.readReproducer(
            std.testing.allocator,
            input_allocations.allocator(),
            path,
            .{ .file_bytes = 5 },
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), input_allocations.alloc_index);
}
