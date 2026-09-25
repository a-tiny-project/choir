const std = @import("std");
const model = @import("model.zig");
const fixture = @import("compiled_inputs_fixture");

test {
    std.testing.refAllDecls(model);
    std.testing.refAllDecls(@import("emit.zig"));
}

test "compiler manifest generator records sources options and the entire pinned toolchain" {
    const allocator = std.testing.allocator;
    const entries = try model.decode(allocator, fixture.bytes);
    defer allocator.free(entries);
    try std.testing.expectEqual(fixture.input_count, entries.len);
    var total: u64 = 0;
    var executable = false;
    var library_files: u32 = 0;
    var source = false;
    var options = false;
    for (entries) |entry| {
        total += entry.byte_length;
        if (std.mem.eql(u8, entry.path, "toolchain/zig")) {
            try std.testing.expect(entry.byte_length > 0);
            try std.testing.expect(entry.pinned_source.len > 0);
            executable = true;
        } else if (std.mem.startsWith(u8, entry.path, "toolchain/lib/")) {
            try std.testing.expect(entry.pinned_source.len > 0);
            library_files += 1;
        } else if (std.mem.eql(u8, entry.path, "fixture/source/value.txt")) {
            const expected = try model.entry("fixture/source/value.txt", "", "source directory\n");
            try std.testing.expectEqual(expected.byte_length, entry.byte_length);
            try std.testing.expectEqualSlices(u8, &expected.sha256, &entry.sha256);
            source = true;
        } else if (std.mem.eql(u8, entry.path, "fixture/options.zig")) {
            const expected = try model.entry(
                "fixture/options.zig",
                "",
                "pub const enabled: bool = false;\n",
            );
            try std.testing.expectEqual(expected.byte_length, entry.byte_length);
            try std.testing.expectEqualSlices(u8, &expected.sha256, &entry.sha256);
            options = true;
        } else return error.UnexpectedCompilerInput;
    }
    try std.testing.expect(executable);
    try std.testing.expect(library_files > 1);
    try std.testing.expect(source);
    try std.testing.expect(options);
    try std.testing.expectEqual(fixture.foreign_bytes, total);
}

test "compiler manifest graph captures import edges generated settings and compiler options" {
    const compiled = @import("compiled_graph_fixture");
    const record = @import("compiled_graph_record");
    const allocator = std.testing.allocator;
    const entries = try model.decode(allocator, compiled.bytes);
    defer allocator.free(entries);
    var settings = false;
    var source = false;
    var generated = false;
    var graph = false;
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.path, "modules/2/source/options.zig")) {
            const expected = try model.entry(entry.path, "", "pub const enabled: bool = false;\n");
            try std.testing.expectEqualSlices(u8, &expected.sha256, &entry.sha256);
            settings = true;
        } else if (std.mem.eql(u8, entry.path, "modules/0/source/main.zig")) {
            try std.testing.expect(entry.byte_length > 0);
            source = true;
        } else if (std.mem.eql(u8, entry.path, "modules/1/source/value.txt")) {
            const expected = try model.entry(entry.path, "", "generated compiler input\n");
            try std.testing.expectEqualSlices(u8, &expected.sha256, &entry.sha256);
            generated = true;
        } else if (std.mem.eql(u8, entry.path, "compilation.json")) {
            const expected = try model.entry(entry.path, "", record.graph);
            try std.testing.expectEqualSlices(u8, &expected.sha256, &entry.sha256);
            graph = true;
        }
    }
    try std.testing.expect(settings);
    try std.testing.expect(source);
    try std.testing.expect(graph);
    try std.testing.expect(generated);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, record.graph, .{});
    defer parsed.deinit();
    const modules = parsed.value.object.get("modules").?.array.items;
    try std.testing.expectEqual(3, modules.len);
    try std.testing.expectEqualStrings("debug", modules[0].object.get("optimize").?.string);
    const imports = modules[0].object.get("imports").?.array.items;
    try std.testing.expectEqualStrings("constants", imports[0].object.get("name").?.string);
    try std.testing.expectEqual(1, imports[0].object.get("module").?.integer);
    try std.testing.expectEqualStrings("settings", imports[1].object.get("name").?.string);
    try std.testing.expectEqual(2, imports[1].object.get("module").?.integer);
    const compile = parsed.value.object.get("compile").?.object;
    try std.testing.expect(!compile.get("use_llvm").?.bool);
}
