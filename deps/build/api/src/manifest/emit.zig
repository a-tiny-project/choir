const std = @import("std");
const model = @import("model.zig");

const Capture = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    entries: std.ArrayList(model.Entry) = .empty,
    counter: model.ByteCounter = .{},

    fn append(self: *Capture, item: model.Entry) !void {
        std.debug.assert(self.entries.items.len <= model.maximum_entries);
        if (self.entries.items.len == model.maximum_entries) {
            return error.CompilerInputCountExceeded;
        }
        const physical: ?[]const u8 = if (item.pinned_source.len == 0)
            null
        else
            item.pinned_source;
        try self.counter.add(self.allocator, physical, item.byte_length, item.sha256);
        try self.entries.append(self.allocator, item);
    }

    fn file(self: *Capture, input: model.Input, path: []const u8) !void {
        try self.captureFile(input, path, null);
    }

    fn captureFile(
        self: *Capture,
        input: model.Input,
        path: []const u8,
        source_pin: ?[]const u8,
    ) !void {
        try model.validatePath(input.path);
        const source = try std.Io.Dir.cwd().openFile(self.io, path, .{});
        defer source.close(self.io);
        const stat = try source.stat(self.io);
        if (stat.kind != .file) return error.UnsupportedCompilerInput;
        if (stat.size > model.maximum_file_bytes) return error.CompilerInputTooLarge;
        var buffer: [64 * 1024]u8 = undefined;
        var reader = source.reader(self.io, &.{});
        var digest = std.crypto.hash.sha2.Sha256.init(.{});
        var length: u64 = 0;
        while (length <= model.maximum_file_bytes) {
            const count = try reader.interface.readSliceShort(&buffer);
            if (count == 0) break;
            length += count;
            if (length > model.maximum_file_bytes) return error.CompilerInputTooLarge;
            digest.update(buffer[0..count]);
        }
        if (length != stat.size) return error.CompilerInputChangedDuringCapture;
        const pinned_source = source_pin orelse if (input.pinned) try self.pin(path) else "";
        try self.append(.{
            .path = try self.allocator.dupe(u8, input.path),
            .pinned_source = pinned_source,
            .byte_length = length,
            .sha256 = digest.finalResult(),
        });
    }

    fn pin(self: *Capture, path: []const u8) ![]const u8 {
        const resolved = try std.Io.Dir.cwd().realPathFileAlloc(self.io, path, self.allocator);
        _ = try storePin(resolved);
        return resolved;
    }

    fn tree(self: *Capture, input: model.Input, path: []const u8) !void {
        if (!input.pinned and !input.generated) return error.UntrackedCompilerDirectory;
        if (input.pinned) {
            const root = try std.Io.Dir.cwd().realPathFileAlloc(self.io, path, self.allocator);
            _ = try storePin(root);
            try self.treeContents(input, root, root);
        } else {
            try self.treeContents(input, path, "");
        }
    }

    /// The caller qualifies the canonical root once. A resolved descendant can
    /// borrow that pin; an alias outside the root must establish its own pin.
    fn treeContents(
        self: *Capture,
        input: model.Input,
        path: []const u8,
        pinned_source: []const u8,
    ) !void {
        std.debug.assert(input.pinned == (pinned_source.len != 0));
        var directory = try std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true });
        defer directory.close(self.io);
        var root_buffer: [model.maximum_path_bytes]u8 = undefined;
        const root_length = try directory.realPath(self.io, &root_buffer);
        const root = root_buffer[0..root_length];
        var walker = try directory.walkSelectively(self.allocator);
        defer walker.deinit();
        defer while (walker.stack.items.len > 0) walker.leave(self.io);
        var budget: WalkBudget = .{};
        while (try walker.next(self.io)) |item| {
            const links = try budget.visit(item.depth());
            if (item.kind == .sym_link and !input.pinned) return error.MutableCompilerInput;
            if (item.kind != .file and item.kind != .directory and item.kind != .sym_link) {
                return error.UnsupportedCompilerInput;
            }
            if (item.kind == .directory) {
                try walker.enter(self.io, item);
                continue;
            }
            var logical_buffer: [model.maximum_path_bytes]u8 = undefined;
            const logical = std.fmt.bufPrint(&logical_buffer, "{s}/{s}", .{ input.path, item.path }) catch
                return error.InvalidCompilerInputPath;
            try model.validatePath(logical);
            var resolved: ResolvedLink = undefined;
            var physical_buffer: [model.maximum_path_bytes]u8 = undefined;
            const physical = if (item.kind == .sym_link) target: {
                resolved = try ResolvedLink.resolve(self.io, item.dir, item.basename, links, root);
                break :target resolved.path();
            } else target: {
                const length = try item.dir.realPathFile(self.io, item.basename, &physical_buffer);
                break :target physical_buffer[0..length];
            };
            const entry_pin = if (input.pinned) try self.resolvedPin(root, pinned_source, physical) else "";
            if (item.kind == .sym_link) {
                const stat = try std.Io.Dir.cwd().statFile(self.io, physical, .{ .follow_symlinks = false });
                if (stat.kind == .directory) {
                    budget.enter(item.depth(), resolved.links);
                    var target = item;
                    target.dir = std.Io.Dir.cwd();
                    target.basename = resolved.path();
                    target.kind = .directory;
                    try walker.enter(self.io, target);
                    continue;
                }
                if (stat.kind != .file) return error.UnsupportedCompilerInput;
            }
            try self.captureFile(.{ .path = logical, .pinned = input.pinned }, physical, entry_pin);
        }
    }

    fn resolvedPin(
        self: *Capture,
        root: []const u8,
        root_pin: []const u8,
        path: []const u8,
    ) ![]const u8 {
        std.debug.assert(root_pin.len != 0);
        if (withinRoot(root, path)) {
            if (std.mem.eql(u8, root, root_pin)) return self.allocator.dupe(u8, path);
            return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ root_pin, path[root.len..] });
        }
        return self.pin(path) catch |err| switch (err) {
            error.UnpinnedCompilerToolchain => error.MutableCompilerInput,
            else => err,
        };
    }

    fn inherit(self: *Capture, path: []const u8) !void {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(
            self.io,
            path,
            self.allocator,
            .limited(model.maximum_manifest_bytes),
        );
        const entries = try model.decode(self.allocator, bytes);
        for (entries) |item| try self.append(item);
    }

    fn write(self: *Capture, path: []const u8) !void {
        const bytes = try model.encode(self.allocator, self.entries.items);
        var directory = try std.Io.Dir.cwd().openDir(self.io, path, .{});
        defer directory.close(self.io);
        try directory.writeFile(self.io, .{ .sub_path = "manifest.bin", .data = bytes });
        const source = try std.fmt.allocPrint(
            self.allocator,
            "pub const qualified = true;\n" ++
                "pub const refusal: ?[]const u8 = null;\n" ++
                "pub const bytes: []const u8 = @embedFile(\"manifest.bin\");\n" ++
                "pub const input_count: u32 = {d};\n" ++
                "pub const foreign_bytes: u64 = {d};\n",
            .{ self.entries.items.len, self.counter.bytes },
        );
        try directory.writeFile(self.io, .{ .sub_path = "root.zig", .data = source });
    }
};

/// Directory handles keep ancestor aliases out of subsequent kernel path walks.
/// Link expansions are counted explicitly, including links in a target's parents.
const ResolvedLink = struct {
    buffer: [model.maximum_path_bytes + 1]u8 = undefined,
    length: usize,
    links: u32,

    fn path(self: *const ResolvedLink) [:0]const u8 {
        std.debug.assert(self.length <= model.maximum_path_bytes);
        std.debug.assert(self.buffer[self.length] == 0);
        return self.buffer[0..self.length :0];
    }

    fn resolve(
        io: std.Io,
        directory: std.Io.Dir,
        name: []const u8,
        links: u32,
        root: []const u8,
    ) !ResolvedLink {
        std.debug.assert(links <= model.maximum_symlink_depth);
        var result = ResolvedLink{
            .length = 0,
            .links = links,
        };
        result.length = try directory.realPath(io, result.buffer[0..model.maximum_path_bytes]);
        var pending: [model.maximum_path_bytes]u8 = undefined;
        if (name.len > pending.len) return error.CompilerInputPathTooLong;
        @memcpy(pending[0..name.len], name);
        var length = name.len;
        var position: usize = 0;
        const maximum_steps = model.maximum_path_bytes * (model.maximum_symlink_depth + 1);
        var steps: u32 = 0;
        while (position < length) {
            std.debug.assert(steps < maximum_steps);
            steps += 1;
            const end = std.mem.indexOfScalarPos(u8, pending[0..length], position, '/') orelse length;
            const part = pending[position..end];
            position = @min(end + 1, length);
            if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
            if (std.mem.eql(u8, part, "..")) {
                result.parent();
                continue;
            }
            const parent_length = result.length;
            const separator: usize = @intFromBool(result.length > 1);
            if (result.length + separator + part.len > model.maximum_path_bytes) {
                return error.CompilerInputPathTooLong;
            }
            if (separator != 0) {
                result.buffer[result.length] = '/';
                result.length += 1;
            }
            @memcpy(result.buffer[result.length..][0..part.len], part);
            result.length += part.len;
            result.buffer[result.length] = 0;
            if (!withinRoot(root, result.path()) and
                !withinRoot(result.path(), root) and
                !withinRoot(result.path(), "/nix/store"))
            {
                _ = storePin(result.path()) catch return error.MutableCompilerInput;
            }
            const stat = try std.Io.Dir.cwd().statFile(io, result.path(), .{
                .follow_symlinks = false,
            });
            if (stat.kind != .sym_link) {
                if (position < length and stat.kind != .directory) return error.NotDir;
                continue;
            }
            if (result.links == model.maximum_symlink_depth) {
                return error.CompilerInputSymlinkDepthExceeded;
            }
            result.links += 1;
            var target: [model.maximum_path_bytes]u8 = undefined;
            const target_length = try std.Io.Dir.cwd().readLink(io, result.path(), &target);
            const rest = pending[position..length];
            const join: usize = @intFromBool(rest.len != 0);
            if (target_length + join + rest.len > pending.len) return error.CompilerInputPathTooLong;
            if (join != 0) target[target_length] = '/';
            @memcpy(target[target_length + join ..][0..rest.len], rest);
            length = target_length + join + rest.len;
            @memcpy(pending[0..length], target[0..length]);
            position = 0;
            result.length = if (std.fs.path.isAbsolute(target[0..target_length])) 1 else parent_length;
        }
        result.buffer[result.length] = 0;
        return result;
    }

    fn parent(self: *ResolvedLink) void {
        std.debug.assert(self.length > 0);
        const end = std.mem.lastIndexOfScalar(u8, self.buffer[0..self.length], '/').?;
        self.length = @max(end, 1);
    }
};

const WalkBudget = struct {
    const Frame = struct { depth: usize, links: u32 };
    frames: [model.maximum_symlink_depth]Frame = undefined,
    frame_count: u32 = 0,
    visited: u32 = 0,

    fn visit(self: *WalkBudget, depth: usize) !u32 {
        std.debug.assert(self.visited <= model.maximum_entries);
        std.debug.assert(self.frame_count <= self.frames.len);
        if (self.visited == model.maximum_entries) return error.CompilerInputCountExceeded;
        self.visited += 1;
        while (self.frame_count > 0 and self.frames[self.frame_count - 1].depth >= depth) {
            self.frame_count -= 1;
        }
        return if (self.frame_count == 0) 0 else self.frames[self.frame_count - 1].links;
    }

    fn enter(self: *WalkBudget, depth: usize, links: u32) void {
        std.debug.assert(links > 0);
        std.debug.assert(links <= model.maximum_symlink_depth);
        std.debug.assert(self.frame_count < self.frames.len);
        if (self.frame_count > 0) {
            const parent = self.frames[self.frame_count - 1];
            std.debug.assert(depth > parent.depth);
            std.debug.assert(links > parent.links);
        }
        self.frames[self.frame_count] = .{ .depth = depth, .links = links };
        self.frame_count += 1;
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    var arguments = try init.minimal.args.iterateAllocator(allocator);
    defer arguments.deinit();
    std.debug.assert(arguments.skip());
    const output = arguments.next() orelse return error.MissingManifestOutput;
    const request_path = arguments.next() orelse return error.MissingManifestRequest;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        request_path,
        allocator,
        .limited(model.maximum_manifest_bytes),
    );
    const parsed = try std.json.parseFromSlice(model.Request, allocator, bytes, .{});
    const request = parsed.value;
    if (request.inputs.len > model.maximum_entries) return error.CompilerInputCountExceeded;
    var capture = Capture{ .allocator = allocator, .io = init.io };
    if (request.inherited) {
        try capture.inherit(arguments.next() orelse return error.MissingInheritedManifest);
    }
    for (request.inputs) |input| {
        const path = arguments.next() orelse return error.MissingCompilerInput;
        if (input.directory) try capture.tree(input, path) else try capture.file(input, path);
    }
    if (arguments.next() != null) return error.UnexpectedCompilerInput;
    try capture.write(output);
}

fn withinRoot(root: []const u8, path: []const u8) bool {
    return std.mem.startsWith(u8, path, root) and
        (path.len == root.len or path[root.len] == '/');
}

fn storePin(path: []const u8) ![]const u8 {
    const prefix = "/nix/store/";
    if (!std.mem.startsWith(u8, path, prefix)) return error.UnpinnedCompilerToolchain;
    const suffix = path[prefix.len..];
    const end = std.mem.indexOfScalar(u8, suffix, '/') orelse suffix.len;
    const result = path[0 .. prefix.len + end];
    try model.validatePin(result);
    return result;
}

test "compiler manifest refuses generated directory symlinks to mutable inputs" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    try temporary.dir.writeFile(io, .{ .sub_path = "foreign", .data = "mutable input" });
    try temporary.dir.createDir(io, "generated", .default_dir);
    try temporary.dir.symLink(io, "../foreign", "generated/input", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const path = try temporary.dir.realPathFileAlloc(io, "generated", arena.allocator());
    var captured = Capture{ .allocator = arena.allocator(), .io = io };
    try std.testing.expectError(error.MutableCompilerInput, captured.tree(.{
        .path = "generated",
        .directory = true,
        .generated = true,
    }, path));
    try std.testing.expectEqual(0, captured.entries.items.len);
}

test "compiler manifest traverses pinned directory symlinks with logical identities" {
    const io = std.testing.io;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const fixture = @import("compiled_inputs_fixture");
    const entries = try model.decode(allocator, fixture.bytes);
    var pin: ?[]const u8 = null;
    for (entries) |item| {
        if (std.mem.eql(u8, item.path, "toolchain/zig")) pin = item.pinned_source;
    }
    const store_root = try storePin(pin.?);
    const target = try std.fs.path.join(allocator, &.{ store_root, "lib/zig/std/Random" });
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.symLink(io, target, "alias", .{ .is_directory = true });
    const path = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    var expected = Capture{ .allocator = allocator, .io = io };
    try expected.tree(.{ .path = "include/alias", .pinned = true }, target);
    var captured = Capture{ .allocator = allocator, .io = io };
    try captured.treeContents(.{ .path = "include", .pinned = true }, path, fixture_pin);
    var root_alias = Capture{ .allocator = allocator, .io = io };
    try root_alias.tree(.{ .path = "include/alias", .pinned = true }, try std.fs.path.join(allocator, &.{ path, "alias" }));
    try std.testing.expectEqualSlices(u8, try model.encode(allocator, expected.entries.items), try model.encode(allocator, root_alias.entries.items));
    try std.testing.expect(expected.entries.items.len > 0);
    try std.testing.expectEqualSlices(u8, try model.encode(allocator, expected.entries.items), try model.encode(allocator, captured.entries.items));
    for (captured.entries.items) |item| {
        try std.testing.expect(std.mem.startsWith(u8, item.path, "include/alias/"));
        try std.testing.expect(std.mem.startsWith(u8, item.pinned_source, store_root));
    }
}

/// These fixtures supply the already-qualified root capability directly. The
/// public tree entry point and the toolchain regression still validate real pins.
const fixture_pin = "/nix/store/00000000000000000000000000000000-fixture";

test "compiler manifest counts physical store aliases once against a small bound" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const path = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    const contents = "header";
    try temporary.dir.writeFile(io, .{ .sub_path = "value.h", .data = contents });
    try temporary.dir.symLink(io, "value.h", "alias.h", .{});
    var capture = Capture{ .allocator = allocator, .io = io, .counter = .{ .limit = contents.len } };
    try capture.treeContents(.{ .path = "include", .pinned = true }, path, fixture_pin);
    try std.testing.expectEqual(2, capture.entries.items.len);
    try std.testing.expectEqual(contents.len, capture.counter.bytes);
}

test "compiler manifest preserves relative directory aliases and their pins" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const path = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.createDir(io, "headers", .default_dir);
    try temporary.dir.writeFile(io, .{ .sub_path = "headers/value.h", .data = "header" });
    try temporary.dir.symLink(io, "headers", "alias", .{ .is_directory = true });
    try temporary.dir.symLink(io, "alias/value.h", "value.h", .{});
    var capture = Capture{ .allocator = allocator, .io = io };
    try capture.treeContents(.{ .path = "include", .pinned = true }, path, fixture_pin);
    const expected = [_]model.Entry{
        try model.entry("include/headers/value.h", fixture_pin ++ "/headers/value.h", "header"),
        try model.entry("include/alias/value.h", fixture_pin ++ "/headers/value.h", "header"),
        try model.entry("include/value.h", fixture_pin ++ "/headers/value.h", "header"),
    };
    try std.testing.expectEqualSlices(u8, try model.encode(allocator, &expected), try model.encode(allocator, capture.entries.items));
    try std.testing.expectError(error.UnpinnedCompilerToolchain, capture.tree(.{ .path = "include", .pinned = true }, path));
}

test "compiler manifest bounds link chains at the limit and one past it" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.writeFile(io, .{ .sub_path = "0", .data = "header" });
    for (1..model.maximum_symlink_depth + 2) |index| {
        const name = try std.fmt.allocPrint(allocator, "{d}", .{index});
        const target = try std.fmt.allocPrint(allocator, "{d}", .{index - 1});
        try temporary.dir.symLink(io, target, name, .{});
        if (index == model.maximum_symlink_depth) {
            const resolved = try ResolvedLink.resolve(io, temporary.dir, name, 0, root);
            try std.testing.expectEqual(model.maximum_symlink_depth, resolved.links);
            try std.testing.expectEqualStrings(try std.fs.path.join(allocator, &.{ root, "0" }), resolved.path());
        } else if (index == model.maximum_symlink_depth + 1) {
            try std.testing.expectError(error.CompilerInputSymlinkDepthExceeded, ResolvedLink.resolve(io, temporary.dir, name, 0, root));
        }
    }
    try temporary.dir.symLink(io, "self", "self", .{});
    try temporary.dir.symLink(io, "right", "left", .{});
    try temporary.dir.symLink(io, "left", "right", .{});
    for ([_][]const u8{ "self", "left" }) |name| {
        try std.testing.expectError(error.CompilerInputSymlinkDepthExceeded, ResolvedLink.resolve(io, temporary.dir, name, 0, root));
    }
}

test "compiler manifest bounds directory cycles and restores sibling link depth" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const path = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.symLink(io, ".", "loop", .{ .is_directory = true });
    var capture = Capture{ .allocator = allocator, .io = io };
    try std.testing.expectError(error.CompilerInputSymlinkDepthExceeded, capture.treeContents(.{ .path = "include", .pinned = true }, path, fixture_pin));
    try std.testing.expectEqual(0, capture.entries.items.len);

    var budget: WalkBudget = .{};
    for (1..model.maximum_symlink_depth + 1) |depth| {
        try std.testing.expectEqual(depth - 1, try budget.visit(depth));
        budget.enter(depth, @intCast(depth));
    }
    try std.testing.expectEqual(model.maximum_symlink_depth, try budget.visit(model.maximum_symlink_depth + 1));
    try std.testing.expectError(error.CompilerInputSymlinkDepthExceeded, ResolvedLink.resolve(io, temporary.dir, "loop", model.maximum_symlink_depth, path));
    try std.testing.expectEqual(0, try budget.visit(1));
    try std.testing.expectEqual(0, budget.frame_count);
}

test "compiler manifest refuses mutable directory file and indirect escapes" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try temporary.dir.createDir(io, "pinned", .default_dir);
    try temporary.dir.createDir(io, "pinned-other", .default_dir);
    try temporary.dir.writeFile(io, .{ .sub_path = "foreign", .data = "mutable" });
    try temporary.dir.writeFile(io, .{ .sub_path = "pinned/safe", .data = "immutable fixture" });
    try temporary.dir.symLink(io, "pinned/safe", "redirect", .{});
    const path = try temporary.dir.realPathFileAlloc(io, "pinned", allocator);
    for ([_][]const u8{ "../pinned-other", "../foreign", "../redirect", "../pinned-other/../pinned/safe" }) |target| {
        try temporary.dir.symLink(io, target, "pinned/escape", .{});
        defer temporary.dir.deleteFile(io, "pinned/escape") catch unreachable;
        var capture = Capture{ .allocator = allocator, .io = io };
        try std.testing.expectError(error.MutableCompilerInput, capture.treeContents(.{ .path = "include", .pinned = true }, path, fixture_pin));
    }
}

test "compiler manifest preserves unpinned files and generated directory behavior" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try temporary.dir.createDir(io, "generated", .default_dir);
    try temporary.dir.writeFile(io, .{ .sub_path = "generated/value", .data = "generated" });
    const path = try temporary.dir.realPathFileAlloc(io, "generated", allocator);
    var capture = Capture{ .allocator = allocator, .io = io };
    try std.testing.expectError(error.UntrackedCompilerDirectory, capture.tree(.{ .path = "input" }, path));
    try capture.tree(.{ .path = "input", .generated = true }, path);
    try std.testing.expectEqual(1, capture.entries.items.len);
    try std.testing.expectEqualStrings("", capture.entries.items[0].pinned_source);
    try std.testing.expectEqualStrings("input/value", capture.entries.items[0].path);
    try temporary.dir.symLink(io, "generated/value", "file-link", .{});
    try capture.file(.{ .path = "direct" }, try std.fs.path.join(allocator, &.{
        try temporary.dir.realPathFileAlloc(io, ".", allocator), "file-link",
    }));
    try std.testing.expectEqualStrings("", capture.entries.items[1].pinned_source);
    try std.testing.expectEqual(2 * "generated".len, capture.counter.bytes);
    try capture.tree(.{ .path = "generated-again", .generated = true }, path);
    try std.testing.expectEqual(3, capture.entries.items.len);
    try std.testing.expectEqual(3 * "generated".len, capture.counter.bytes);
    try temporary.dir.symLink(io, ".", "generated/directory-link", .{ .is_directory = true });
    try std.testing.expectError(error.MutableCompilerInput, capture.tree(.{ .path = "input", .generated = true }, path));
}

test "compiler manifest enforces visited and captured entry limits exactly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var capture = Capture{ .allocator = arena.allocator(), .io = std.testing.io };
    var budget: WalkBudget = .{};
    const entry = try model.entry("empty", "", "");
    for (0..model.maximum_entries) |_| {
        _ = try budget.visit(1);
        try capture.append(entry);
    }
    try std.testing.expectEqual(model.maximum_entries, budget.visited);
    try std.testing.expectEqual(model.maximum_entries, capture.entries.items.len);
    try std.testing.expectError(error.CompilerInputCountExceeded, budget.visit(1));
    try std.testing.expectError(error.CompilerInputCountExceeded, capture.append(entry));
    try std.testing.expectEqual(model.maximum_entries, budget.visited);
    try std.testing.expectEqual(model.maximum_entries, capture.entries.items.len);
}

test "compiler manifest resolves dot dot after expanding a directory alias" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.createDirPath(io, "target/nested");
    try temporary.dir.writeFile(io, .{ .sub_path = "target/value", .data = "header" });
    try temporary.dir.symLink(io, "target/nested", "alias", .{ .is_directory = true });
    try temporary.dir.symLink(io, "alias/../value", "chosen", .{});
    const resolved = try ResolvedLink.resolve(io, temporary.dir, "chosen", 0, root);
    try std.testing.expectEqual(2, resolved.links);
    try std.testing.expectEqualStrings(
        try std.fs.path.join(allocator, &.{ root, "target/value" }),
        resolved.path(),
    );
}

test "compiler manifest traverses the directory link depth limit and refuses one past" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    for (0..model.maximum_symlink_depth + 1) |index| {
        const name = try std.fmt.allocPrint(allocator, "d{d}", .{index});
        try temporary.dir.createDir(io, name, .default_dir);
        if (index > 0) {
            const link = try std.fmt.allocPrint(allocator, "d{d}/next", .{index - 1});
            const target = try std.fmt.allocPrint(allocator, "../d{d}", .{index});
            try temporary.dir.symLink(io, target, link, .{ .is_directory = true });
        }
    }
    const leaf = try std.fmt.allocPrint(allocator, "d{d}/value", .{model.maximum_symlink_depth});
    try temporary.dir.writeFile(io, .{ .sub_path = leaf, .data = "header" });
    var capture = Capture{ .allocator = allocator, .io = io };
    try capture.treeContents(.{ .path = "include", .pinned = true }, root, fixture_pin);
    try std.testing.expectEqual(model.maximum_symlink_depth + 1, capture.entries.items.len);
    var found_limit = false;
    for (capture.entries.items) |entry| {
        if (std.mem.startsWith(u8, entry.path, "include/d0/")) {
            try std.testing.expectEqual(
                model.maximum_symlink_depth,
                std.mem.count(u8, entry.path, "/next"),
            );
            try std.testing.expect(std.mem.startsWith(
                u8,
                entry.pinned_source,
                fixture_pin ++ "/d",
            ));
            found_limit = true;
        }
    }
    try std.testing.expect(found_limit);
    try temporary.dir.createDir(io, "past", .default_dir);
    const link = try std.fmt.allocPrint(allocator, "d{d}/next", .{model.maximum_symlink_depth});
    try temporary.dir.symLink(io, "../past", link, .{ .is_directory = true });
    var excessive = Capture{ .allocator = allocator, .io = io };
    try std.testing.expectError(error.CompilerInputSymlinkDepthExceeded, excessive.treeContents(.{ .path = "include", .pinned = true }, root, fixture_pin));
}
