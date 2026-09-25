const std = @import("std");
const build_api = @import("build_api");
const configuration = @import("configuration.zig");
const deps = @import("deps.zig");
const module = @import("module.zig");

pub fn add(
    b: *std.Build,
    policies: configuration.Policies,
    dependencies: deps.Requested,
    gpalloc: *std.Build.Module,
    filters: []const []const u8,
) *std.Build.Step {
    const gpalloc_tests = module.createTestModule(
        b,
        policies.requested,
        .{ .sys = dependencies.sys },
    );
    const test_step = addUnit(b, gpalloc_tests, filters);
    addProperties(b, policies.requested, dependencies, gpalloc, filters);
    addTsan(b, policies.tsan, dependencies);
    return test_step;
}

fn addUnit(
    b: *std.Build,
    gpalloc: *std.Build.Module,
    filters: []const []const u8,
) *std.Build.Step {
    const tests = b.addTest(.{
        .root_module = gpalloc,
        .filters = filters,
    });
    const run = b.addRunArtifact(tests);
    const step = b.step("test", "Run gpalloc unit tests");
    step.dependOn(&run.step);
    return step;
}

fn addProperties(
    b: *std.Build,
    policy: build_api.ModuleOptions,
    dependencies: deps.Requested,
    gpalloc: *std.Build.Module,
    filters: []const []const u8,
) void {
    const property = module.createPropertyTestModule(b, policy, .{
        .gpalloc = gpalloc,
        .hypothesis = dependencies.hypothesis,
        .sys = dependencies.sys,
    });
    const tests = b.addTest(.{
        .root_module = property,
        .filters = filters,
    });
    const run = b.addRunArtifact(tests);
    const step = b.step("pbt", "Run gpalloc property tests");
    step.dependOn(&run.step);
}

fn addTsan(
    b: *std.Build,
    policy: build_api.ModuleOptions,
    dependencies: deps.Requested,
) void {
    const gpalloc = module.createModule(b, policy, .{ .sys = dependencies.sys });
    const property = module.createPropertyTestModule(b, policy, .{
        .gpalloc = gpalloc,
        .hypothesis = dependencies.hypothesis,
        .sys = dependencies.sys,
    });
    const tests = b.addTest(.{
        .root_module = property,
        .filters = &.{"concurrent"},
        .use_llvm = true,
    });
    const run = b.addRunArtifact(tests);
    const step = b.step(
        "pbt-tsan",
        "Run concurrent gpalloc properties under ThreadSanitizer",
    );
    step.dependOn(&run.step);
}
