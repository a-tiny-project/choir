const std = @import("std");
const build_api = @import("build_api");

pub const Kind = enum {
    record,
    replay,
};

pub const Inputs = struct {
    bench: *std.Build.Module,
    memtrace: *std.Build.Module,
    sys: *std.Build.Module,
};

pub fn createModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    kind: Kind,
    inputs: Inputs,
) *std.Build.Module {
    const source_file = switch (kind) {
        .record => "src/profiling/main/record.zig",
        .replay => "src/profiling/main/replay.zig",
    };
    const profiling_module = b.createModule(options.createOptions(b, "src/profiling/root.zig", &.{
        .{ .name = "bench", .module = inputs.bench },
        .{ .name = "memtrace", .module = inputs.memtrace },
        .{ .name = "sys", .module = inputs.sys },
    }));
    return b.createModule(options.createOptions(b, source_file, &.{.{
        .name = "profiling",
        .module = profiling_module,
    }}));
}
