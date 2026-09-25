const std = @import("std");
const configuration = @import("configuration.zig");

pub fn unit(
    b: *std.Build,
    config: configuration.Configuration,
    memtrace: *std.Build.Module,
) *std.Build.Step {
    const artifact = b.addTest(.{
        .root_module = memtrace,
        .filters = config.test_filters,
    });
    const run = b.addRunArtifact(artifact);
    const parent = b.step(
        "test",
        if (config.browserish) "Run memtrace unit tests" else "Run memtrace unit and CLI tests",
    );
    parent.dependOn(&run.step);
    return parent;
}

pub fn properties(
    b: *std.Build,
    config: configuration.Configuration,
    module: *std.Build.Module,
) void {
    const artifact = b.addTest(.{
        .root_module = module,
        .filters = config.test_filters,
    });
    const run = b.addRunArtifact(artifact);
    const parent = b.step("pbt", "Run memtrace property tests");
    parent.dependOn(&run.step);
}
