const std = @import("std");
const model = @import("../../validation/root.zig");

const source_cap = 1024;
const source_bytes_cap = 4 * 1024 * 1024;

pub fn capture(
    b: *std.Build,
    repository: []const u8,
    paths: []const []const u8,
) []const model.Source {
    var values: std.ArrayList(model.Source) = .empty;
    for (paths) |path| collect(b, repository, path, &values) catch |err| {
        std.debug.panic("validation framework source {s}: {s}", .{ path, @errorName(err) });
    };
    std.mem.sort(model.Source, values.items, {}, less);
    return values.toOwnedSlice(b.allocator) catch @panic("OOM");
}

fn collect(
    b: *std.Build,
    repository: []const u8,
    path: []const u8,
    values: *std.ArrayList(model.Source),
) !void {
    const relative = b.pathJoin(&.{ repository, path });
    const absolute = try b.root.joinString(b.allocator, relative);
    const stat = try std.Io.Dir.cwd().statFile(b.graph.io, absolute, .{ .follow_symlinks = false });
    if (stat.kind == .file) return add(b, relative, path, values);
    if (stat.kind != .directory) return error.UnsupportedValidationFrameworkSource;
    b.dependOnDirectory(b.graph.cwdRelativePath(absolute));
    var directory = try b.root.openDir(b.graph.io, relative, .{ .iterate = true });
    defer directory.close(b.graph.io);
    var walker = try directory.walk(b.allocator);
    defer walker.deinit();
    var visited: usize = 0;
    while (try walker.next(b.graph.io)) |entry| {
        if (visited == source_cap) return error.ValidationFrameworkSourceLimit;
        visited += 1;
        const child = b.pathJoin(&.{ relative, entry.path });
        if (entry.kind == .directory) {
            const child_absolute = try b.root.joinString(b.allocator, child);
            b.dependOnDirectory(b.graph.cwdRelativePath(child_absolute));
            continue;
        }
        if (entry.kind != .file) return error.UnsupportedValidationFrameworkSource;
        try add(b, child, b.pathJoin(&.{ path, entry.path }), values);
    }
}

fn add(
    b: *std.Build,
    relative: []const u8,
    path: []const u8,
    values: *std.ArrayList(model.Source),
) !void {
    if (values.items.len == source_cap) return error.ValidationFrameworkSourceLimit;
    const absolute = try b.root.joinString(b.allocator, relative);
    b.dependOnFileContents(b.graph.cwdRelativePath(absolute));
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        b.graph.io,
        absolute,
        b.allocator,
        .limited(source_bytes_cap),
    );
    defer b.allocator.free(bytes);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    try values.append(b.allocator, .{
        .path = path,
        .sha256 = b.dupe(&std.fmt.bytesToHex(hash, .lower)),
    });
}

fn less(_: void, a: model.Source, b: model.Source) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}
