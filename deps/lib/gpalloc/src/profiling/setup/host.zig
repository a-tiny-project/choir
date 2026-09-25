const std = @import("std");
const sys = @import("sys");

const fs_io = sys.fs.debugIo();

pub fn procs(allocator: std.mem.Allocator, process_io: std.Io) ![]const u8 {
    if (try commandOutputTrimmed(allocator, process_io, &.{"nproc"})) |value| {
        return value;
    }
    const sysctl_argv = [_][]const u8{ "sysctl", "-n", "hw.physicalcpu" };
    if (try commandOutputTrimmed(allocator, process_io, &sysctl_argv)) |value| {
        return value;
    }
    return try allocator.dupe(u8, "1");
}

fn commandOutputTrimmed(
    allocator: std.mem.Allocator,
    process_io: std.Io,
    argv: []const []const u8,
) !?[]const u8 {
    const result = sys.process.run(allocator, process_io, .{
        .argv = argv,
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(1024),
    }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);
    if (!exitedZero(result.term)) return null;
    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (trimmed.len == 0) return null;
    return try allocator.dupe(u8, trimmed);
}

pub fn commandOnPath(
    allocator: std.mem.Allocator,
    env: *const sys.process.Environ.Map,
    name: []const u8,
) !bool {
    if (std.mem.indexOfScalar(u8, name, '/') != null) return canExecute(name);
    const path = env.get("PATH") orelse return false;
    var dirs = std.mem.splitScalar(u8, path, ':');
    while (dirs.next()) |raw_dir| {
        const dir = if (raw_dir.len == 0) "." else raw_dir;
        const candidate = try std.fs.path.join(allocator, &.{ dir, name });
        defer allocator.free(candidate);
        if (canExecute(candidate)) return true;
    }
    return false;
}

fn canExecute(path: []const u8) bool {
    sys.fs.cwd().access(fs_io, path, .{ .execute = true }) catch return false;
    return true;
}

pub fn isDir(path: []const u8) bool {
    var dir = sys.fs.cwd().openDir(fs_io, path, .{}) catch return false;
    dir.close(fs_io);
    return true;
}

pub fn runInherited(process_io: std.Io, cwd: ?[]const u8, argv: []const []const u8) !u8 {
    var child = sys.process.spawn(process_io, .{
        .argv = argv,
        .cwd = if (cwd) |path| .{ .path = path } else .inherit,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| switch (err) {
        error.FileNotFound => return 127,
        else => return err,
    };
    defer sys.process.killAndReap(&child, process_io);
    return exitCode(try sys.process.wait(&child, process_io));
}

fn exitedZero(term: sys.process.Termination) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn exitCode(term: sys.process.Termination) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal => 128,
        .stopped => 128,
        .unknown => 1,
    };
}
