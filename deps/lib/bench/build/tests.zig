const std = @import("std");
const build_api = @import("build_api");
const deps = @import("deps.zig");
const profile = @import("profile.zig");

pub fn add(
    b: *std.Build,
    options: build_api.ModuleOptions,
    configuration: deps.Configuration,
    dependencies: deps.Requested,
    bench: *std.Build.Module,
    bench_tests: *std.Build.Module,
) void {
    const test_step = b.step("test", "Run unit tests");
    const verify_step = b.step(
        "verify",
        "Compile unit-test AIR for verification",
    );
    const provenance_module = b.createModule(options.createOptions(
        b,
        "src/provenance.zig",
        &.{.{
            .name = "profile_build_options",
            .module = profile.profileBuildOptions(
                b,
                configuration.target,
                configuration.optimize,
            ),
        }},
    ));
    const floor_module = b.createModule(options.createOptions(b, "src/floor/test.zig", &.{}));
    const suites = [_]*std.Build.Module{ bench_tests, provenance_module, floor_module };
    for (suites) |suite| {
        addSuite(b, suite, configuration.test_filters, test_step, verify_step);
    }

    const property_module = b.createModule(options.createOptions(
        b,
        "src/properties/test.zig",
        &.{
            .{ .name = "bench", .module = bench },
            .{ .name = "hypothesis", .module = dependencies.hypothesis },
            .{ .name = "pretty", .module = dependencies.inputs.pretty },
        },
    ));
    const property_tests = b.addTest(.{
        .root_module = property_module,
        .filters = configuration.test_filters,
    });
    const run_property_tests = b.addRunArtifact(property_tests);

    const property_step = b.step("pbt", "Run benchmark property tests");
    property_step.dependOn(&run_property_tests.step);
}

fn addSuite(
    b: *std.Build,
    root_module: *std.Build.Module,
    filters: []const []const u8,
    test_step: *std.Build.Step,
    verify_step: *std.Build.Step,
) void {
    const tests = b.addTest(.{ .root_module = root_module, .filters = filters });
    test_step.dependOn(&b.addRunArtifact(tests).step);
    verify_step.dependOn(&compileOnlyTest(b, root_module, filters).step);
}

fn compileOnlyTest(
    b: *std.Build,
    root_module: *std.Build.Module,
    filters: []const []const u8,
) *std.Build.Step.Compile {
    const tests = b.addTest(.{
        .root_module = root_module,
        .filters = filters,
    });
    tests.generated_bin = .none;
    return tests;
}
