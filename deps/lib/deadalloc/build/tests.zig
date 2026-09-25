const std = @import("std");

pub const Unit = struct {
    parent: *std.Build.Step,
    run: *std.Build.Step,
};

pub fn unit(
    b: *std.Build,
    deadalloc: *std.Build.Module,
    filters: []const []const u8,
) Unit {
    const artifact = b.addTest(.{
        .root_module = deadalloc,
        .filters = filters,
    });
    const run = b.addRunArtifact(artifact);
    const parent = b.step("test", "Run deadalloc unit tests");
    parent.dependOn(&run.step);
    return .{
        .parent = parent,
        .run = &run.step,
    };
}

pub fn property(
    b: *std.Build,
    properties: *std.Build.Module,
    filters: []const []const u8,
) void {
    const artifact = b.addTest(.{
        .root_module = properties,
        .filters = filters,
    });
    const run = b.addRunArtifact(artifact);
    const parent = b.step("pbt", "Run deadalloc property tests");
    parent.dependOn(&run.step);
}
