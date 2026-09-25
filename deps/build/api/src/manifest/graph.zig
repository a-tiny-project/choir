const std = @import("std");
const manifest = @import("root.zig");

pub const maximum_modules = 512;
pub const maximum_imports = 512;
pub const maximum_graph_bytes = 4 * 1024 * 1024;
pub const import_name = "__tiny_compiled_inputs_v1";

pub const Snapshot = struct {
    bytes: []const u8,
    files: []const manifest.File,
    native_discovery: bool,
};

const Capture = struct {
    inputs: manifest.paths.Inputs,
    excluded: []const *std.Build.Module,
    native_discovery: bool = false,
    modules: std.ArrayList(*std.Build.Module) = .empty,
    ids: std.AutoHashMapUnmanaged(*std.Build.Module, u32) = .empty,

    fn append(self: *Capture, value: *std.Build.Module) !u32 {
        if (self.ids.get(value)) |id| return id;
        if (self.modules.items.len == maximum_modules) return error.CompilerModuleCountExceeded;
        const id: u32 = @intCast(self.modules.items.len);
        const allocator = self.inputs.build.graph.arena;
        try self.modules.append(allocator, value);
        try self.ids.put(allocator, value, id);
        return id;
    }

    fn isExcluded(self: *const Capture, value: *std.Build.Module) bool {
        for (self.excluded) |item| if (item == value) return true;
        return false;
    }

    fn module(self: *Capture, json: *std.json.Stringify, value: *std.Build.Module, id: u32) !void {
        const b = self.inputs.build;
        const prefix = b.fmt("modules/{d}", .{id});
        if (value.link_libc == true or value.link_libcpp == true) self.native_discovery = true;
        try json.beginObject();
        try json.objectField("id");
        try json.write(id);
        try manifest.options.moduleValues(json, value);
        try json.objectField("root_source_file");
        if (value.root_source_file) |path| {
            const name = try self.inputs.module(path, b.pathJoin(&.{ prefix, "source" }));
            try json.write(.{ .input = name, .origin = try manifest.paths.origin(b, path) });
        } else try json.write(null);
        try self.imports(json, value);
        try manifest.native.module(json, &self.inputs, value, prefix);
        try json.endObject();
    }

    fn imports(self: *Capture, json: *std.json.Stringify, value: *std.Build.Module) !void {
        const names = value.import_table.keys();
        if (names.len > maximum_imports) return error.CompilerImportCountExceeded;
        const sorted = try self.inputs.build.graph.arena.dupe([]const u8, names);
        std.mem.sort([]const u8, sorted, {}, less);
        try json.objectField("imports");
        try json.beginArray();
        for (sorted) |name| {
            const imported = value.import_table.get(name).?;
            if (self.isExcluded(imported)) {
                try json.write(.{ .name = name, .derived = "compiled-input-manifest/v1" });
            } else try json.write(.{ .name = name, .module = try self.append(imported) });
        }
        try json.endArray();
    }
};

pub fn capture(
    b: *std.Build,
    compile: *std.Build.Step.Compile,
    excluded: []const *std.Build.Module,
) !Snapshot {
    if (excluded.len > maximum_modules) return error.CompilerModuleCountExceeded;
    var context = Capture{ .inputs = .{ .build = b }, .excluded = excluded };
    _ = try context.append(compile.root_module);
    var output = std.Io.Writer.Allocating.init(b.graph.arena);
    var json = std.json.Stringify{ .writer = &output.writer };
    try json.beginObject();
    try json.objectField("schema");
    try json.write("tiny.compilation/v1");
    try json.objectField("compile");
    try json.beginObject();
    try manifest.options.compileValues(&json, compile);
    try manifest.native.compile(&json, &context.inputs, compile);
    try json.endObject();
    try json.objectField("modules");
    try json.beginArray();
    var cursor: u32 = 0;
    while (cursor < context.modules.items.len) : (cursor += 1) {
        try context.module(&json, context.modules.items[cursor], cursor);
        if (output.written().len > maximum_graph_bytes) return error.CompilerGraphTooLarge;
    }
    try json.endArray();
    try json.endObject();
    manifest.source.sort(context.inputs.files.items);
    return .{
        .bytes = try output.toOwnedSlice(),
        .files = context.inputs.files.items,
        .native_discovery = context.native_discovery,
    };
}

fn less(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
