const std = @import("std");
const pretty_json = @import("pretty").json;
const sys = @import("sys");

pub const Digest = [std.crypto.hash.sha2.Sha256.digest_length]u8;
pub const digest_hex_len = @sizeOf(Digest) * 2;
const metadata_tag = "\"meta\":\"memtrace.executable\"";

pub fn isMetadataLine(line: []const u8) bool {
    return std.mem.indexOf(u8, line, metadata_tag) != null;
}

pub fn runningDigest() !Digest {
    if (comptime @import("builtin").os.tag != .linux) {
        return error.UnsupportedExecutableIdentity;
    }
    const file = try sys.fs.openAbsoluteFile("/proc/self/exe", .{});
    defer sys.fs.closeHandle(file);
    return try digestHandle(file);
}

pub fn fileDigest(allocator: std.mem.Allocator, path: []const u8) !Digest {
    const absolute = try sys.fs.realPathAlloc(allocator, path);
    defer allocator.free(absolute);
    const file = try sys.fs.openAbsoluteFile(absolute, .{});
    defer sys.fs.closeHandle(file);
    return try digestHandle(file);
}

pub fn artifactPathAlloc(
    allocator: std.mem.Allocator,
    events_path: []const u8,
) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}.exe", .{events_path});
}

pub fn copyRunningExecutable(
    path: []const u8,
    expected: Digest,
) !void {
    if (comptime @import("builtin").os.tag != .linux) {
        return error.UnsupportedExecutableIdentity;
    }
    const source = try sys.fs.openAbsoluteFile("/proc/self/exe", .{});
    defer sys.fs.closeHandle(source);
    const destination = try sys.fs.createFile(path, .{ .truncate = true });
    defer sys.fs.closeHandle(destination);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const count = try sys.fs.readHandle(source, &buffer);
        if (count == 0) break;
        hasher.update(buffer[0..count]);
        try sys.fs.writeHandleAll(destination, buffer[0..count]);
    }
    var actual: Digest = undefined;
    hasher.final(&actual);
    if (!std.mem.eql(u8, &expected, &actual)) {
        return error.ExecutableIdentityChanged;
    }
}

pub fn writeMetadata(writer: *std.Io.Writer, digest: Digest) !void {
    var stream = pretty_json.Writer.init(writer, .minified);
    const object = try stream.object();
    try object.field("v", 1);
    try object.field("meta", "memtrace.executable");
    try object.hexString("sha256", &digest);
    try object.endLine();
}

pub fn parseDigest(text: []const u8) !Digest {
    if (text.len != digest_hex_len) return error.InvalidExecutableIdentity;
    var digest: Digest = undefined;
    _ = std.fmt.hexToBytes(&digest, text) catch
        return error.InvalidExecutableIdentity;
    return digest;
}

fn digestHandle(file: std.Io.File) !Digest {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const count = try sys.fs.readHandle(file, &buffer);
        if (count == 0) break;
        hasher.update(buffer[0..count]);
    }
    var digest: Digest = undefined;
    hasher.final(&digest);
    return digest;
}

test "digest parser accepts exact lowercase identity" {
    const expected: Digest = @splat(0xab);
    const hex = std.fmt.bytesToHex(expected, .lower);
    const actual = try parseDigest(&hex);
    try std.testing.expectEqualSlices(u8, &expected, &actual);
}
