const std = @import("std");
const manifest = @import("root.zig");
const invocation = @import("../invocation/root.zig");

const maximum_compilers = 4096;
const unavailable_source =
    "pub const qualified = false;\n" ++
    "pub const refusal = \"UnrecordedCompilerBuild\";\n" ++
    "pub const bytes: []const u8 = &.{};\n";

/// Install the derived-input marker before any caller caches the module graph.
/// The root lifecycle fills it after all compiler and module owners have run.
pub fn attach(b: *std.Build, module: *std.Build.Module) void {
    std.debug.assert(!module.import_table.contains(manifest.graph.import_name));
    const source = b.addWriteFiles().add("compiler.zig", unavailable_source);
    module.addImport(manifest.graph.import_name, b.createModule(.{ .root_source_file = source }));
}

pub fn finalize(b: *std.Build) !void {
    if (!b.isRoot()) return;
    const compilers = collectCompilers(b) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return;
    };
    const record = try invocation.configuration.observe(b) orelse return;
    const generator = manifest.Generator.init(b);
    const toolchain = generator.toolchain();
    for (compilers) |compile| {
        const markers = isolate(b, compile) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            continue;
        };
        if (markers.len == 0) continue;
        const source = qualify(b, generator, toolchain, record, compile, markers) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            const text = try std.fmt.allocPrint(
                b.graph.arena,
                "pub const qualified = false;\npub const refusal = \"{s}\";\n" ++
                    "pub const bytes: []const u8 = &.{{}};\n",
                .{@errorName(err)},
            );
            for (markers) |marker| {
                marker.root_source_file = b.addWriteFiles().add("compiler.zig", text);
            }
            continue;
        };
        for (markers) |marker| marker.root_source_file = source;
    }
}

fn qualify(
    b: *std.Build,
    generator: manifest.Generator,
    toolchain: manifest.Manifest,
    record: invocation.Record,
    compile: *std.Build.Step.Compile,
    markers: []const *std.Build.Module,
) !std.Build.LazyPath {
    var inputs = manifest.paths.Inputs{ .build = b };
    const invocation_bytes = try std.json.Stringify.valueAlloc(b.graph.arena, record, .{});
    try inputs.file(b.addWriteFiles().add("invocation.json", invocation_bytes), "invocation.json");
    try manifest.foreign.capture(&inputs, record);
    const snapshot = try manifest.graph.capture(b, compile, markers);
    if (snapshot.native_discovery) return error.UnqualifiedCompilerNativeDiscovery;
    const prefix = "compilations/0";
    try inputs.file(
        b.addWriteFiles().add("compilation.json", snapshot.bytes),
        prefix ++ "/compilation.json",
    );
    for (snapshot.files) |file| {
        var scoped = file;
        scoped.identity.path = b.pathJoin(&.{ prefix, file.identity.path });
        try manifest.source.append(b, &inputs.files, scoped);
    }
    manifest.source.sort(inputs.files.items);
    return generator.capture(inputs.files.items, toolchain).source;
}

/// The compiler owns its derived marker. Module aliases remain shared within
/// that compiler, while unrelated artifacts receive independent module graphs.
fn isolate(b: *std.Build, compile: *std.Build.Step.Compile) ![]const *std.Build.Module {
    const allocator = b.graph.arena;
    var modules: std.AutoArrayHashMapUnmanaged(*std.Build.Module, *std.Build.Module) = .empty;
    try modules.put(allocator, compile.root_module, undefined);
    var has_marker = false;
    var cursor: usize = 0;
    while (cursor < modules.count()) : (cursor += 1) {
        const module = modules.keys()[cursor];
        if (module.import_table.count() > manifest.graph.maximum_imports) {
            return error.CompilerImportCountExceeded;
        }
        for (module.import_table.keys(), module.import_table.values()) |name, imported| {
            has_marker = has_marker or std.mem.eql(u8, name, manifest.graph.import_name);
            if (modules.contains(imported)) continue;
            if (modules.count() == manifest.graph.maximum_modules) {
                return error.CompilerModuleCountExceeded;
            }
            try modules.put(allocator, imported, undefined);
        }
    }
    if (!has_marker) return &.{};
    for (modules.keys(), modules.values()) |original, *replacement| {
        const copied = try allocator.create(std.Build.Module);
        copied.* = original.*;
        copied.import_table = .empty;
        copied.cached_graph = .{ .modules = &.{}, .names = &.{} };
        replacement.* = copied;
    }
    var markers: std.ArrayList(*std.Build.Module) = .empty;
    for (modules.keys(), modules.values()) |original, copied| {
        for (original.import_table.keys(), original.import_table.values()) |name, imported| {
            const replacement = modules.get(imported).?;
            copied.addImport(name, replacement);
            if (std.mem.eql(u8, name, manifest.graph.import_name)) {
                const present = for (markers.items) |marker| {
                    if (marker == replacement) break true;
                } else false;
                if (!present) try markers.append(allocator, replacement);
            }
        }
    }
    compile.root_module = modules.get(compile.root_module).?;
    return markers.items;
}

fn collectCompilers(b: *std.Build) ![]*std.Build.Step.Compile {
    var pending: std.ArrayList(*std.Build.Step) = .empty;
    var seen: std.AutoHashMapUnmanaged(*std.Build.Step, void) = .empty;
    var result: std.ArrayList(*std.Build.Step.Compile) = .empty;
    for (b.top_level_steps.values()) |top| try pending.append(b.graph.arena, &top.step);
    while (pending.pop()) |step| {
        const entry = try seen.getOrPut(b.graph.arena, step);
        if (entry.found_existing) continue;
        if (step.cast(std.Build.Step.Compile)) |compile| {
            if (result.items.len == maximum_compilers) return error.CompilerCountExceeded;
            try result.append(b.graph.arena, compile);
        }
        try pending.appendSlice(b.graph.arena, step.dependencies.items);
    }
    std.mem.sort(*std.Build.Step.Compile, result.items, {}, struct {
        fn less(_: void, a: *std.Build.Step.Compile, c: *std.Build.Step.Compile) bool {
            return std.mem.lessThan(u8, a.step.name, c.step.name);
        }
    }.less);
    return result.toOwnedSlice(b.graph.arena);
}
