const std = @import("std");
const sys = @import("sys");

const host = @import("host.zig");
const options_module = @import("options.zig");
const output = @import("output.zig");

const required_tools = [_][]const u8{ "git", "cmake", "make", "cc" };

pub fn run(
    allocator: std.mem.Allocator,
    process_io: std.Io,
    env: *const sys.process.Environ.Map,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    options: options_module.Options,
) !u8 {
    const suite_url = options.suite_url orelse
        env.get("TINYALLOC_ALLOCATOR_SUITE_URL") orelse
        options_module.default_suite_url;
    const procs = options.procs orelse
        env.get("TINYALLOC_ALLOCATOR_PROCS") orelse
        try host.procs(allocator, process_io);

    if (!options.dry_run) {
        if (try missingTool(allocator, env)) |tool| {
            try output.writePrettyFmt(
                allocator,
                stderr,
                "gpalloc allocators: required tool not found on PATH: {s}\n",
                .{tool},
            );
            return 1;
        }
    }

    if (try ensureCheckout(allocator, process_io, stdout, options, suite_url)) |status| {
        return status;
    }
    return try buildSuite(allocator, process_io, stdout, options, procs);
}

fn missingTool(
    allocator: std.mem.Allocator,
    env: *const sys.process.Environ.Map,
) !?[]const u8 {
    for (required_tools) |tool| {
        if (!try host.commandOnPath(allocator, env, tool)) return tool;
    }
    return null;
}

fn ensureCheckout(
    allocator: std.mem.Allocator,
    process_io: std.Io,
    stdout: *std.Io.Writer,
    options: options_module.Options,
    suite_url: []const u8,
) !?u8 {
    const git_dir = try std.fs.path.join(allocator, &.{ options.suite_dir, ".git" });
    defer allocator.free(git_dir);
    if (host.isDir(git_dir)) return null;

    if (std.fs.path.dirname(options.suite_dir)) |parent| {
        if (!options.dry_run) try sys.fs.createDirPath(parent);
    }
    try output.writePrettyFmt(
        allocator,
        stdout,
        "gpalloc allocators: cloning {s} -> {s}\n",
        .{ suite_url, options.suite_dir },
    );
    const clone_argv = [_][]const u8{
        "git",
        "clone",
        "--depth",
        "1",
        suite_url,
        options.suite_dir,
    };
    if (options.dry_run) {
        try output.writeShellCommand(stdout, &clone_argv);
        return null;
    }

    try stdout.flush();
    const status = try host.runInherited(process_io, null, &clone_argv);
    if (status != 0) return status;
    return null;
}

fn buildSuite(
    allocator: std.mem.Allocator,
    process_io: std.Io,
    stdout: *std.Io.Writer,
    options: options_module.Options,
    procs: []const u8,
) !u8 {
    try output.writeBuildLine(allocator, stdout, options);
    const procs_arg = try std.fmt.allocPrint(allocator, "--procs={s}", .{procs});
    defer allocator.free(procs_arg);
    var build_argv: std.ArrayList([]const u8) = .empty;
    defer build_argv.deinit(allocator);
    try build_argv.append(allocator, "./build-bench-env.sh");
    for (options.allocators) |name| try build_argv.append(allocator, name);
    try build_argv.append(allocator, procs_arg);
    if (options.dry_run) {
        try output.writeShellCommand(stdout, build_argv.items);
        return 0;
    }

    try stdout.flush();
    const build_status = try host.runInherited(process_io, options.suite_dir, build_argv.items);
    if (build_status == 0) {
        try output.writePrettyFmt(
            allocator,
            stdout,
            "gpalloc allocators: libraries are under {s}/extern\n",
            .{options.suite_dir},
        );
    }
    return build_status;
}
