const std = @import("std");
const alloc_build = @import("alloc");
const build_api = @import("build_api");
const module = @import("module.zig");

pub const Configuration = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    test_filters: []const []const u8,
    alloc_options: alloc_build.DependencyOptions,
    observe_allocations: bool,
    browserish: bool,
};

pub fn configure(b: *std.Build) Configuration {
    const target = build_api.standardTargets(b).product;
    const optimize = b.standardOptimizeOption(.{});
    const test_filters = build_api.focusedTestFilters(b);
    const alloc_options = alloc_build.dependencyOptions(b);
    const observe_allocations = b.option(
        bool,
        "observe-allocations",
        "Compile allocator observation into owned Choir producers",
    ) orelse false;
    return .{
        .target = target,
        .optimize = optimize,
        .test_filters = test_filters,
        .alloc_options = alloc_options,
        .observe_allocations = observe_allocations,
        .browserish = isBrowserish(target.result),
    };
}

pub fn resolveRequested(b: *std.Build, configuration: Configuration) module.Inputs {
    const alloc = alloc_build.dependency(
        b,
        configuration.target,
        configuration.optimize,
        configuration.alloc_options,
    );
    const arena = arenaDependency(
        b,
        configuration.target,
        configuration.optimize,
        configuration.observe_allocations,
    ).module("alloc_arena");
    const alloc_observe = arena.import_table.get("alloc_observe") orelse
        @panic("arena module is missing alloc_observe");
    const fixed = fixedDependency(
        b,
        configuration.target,
        configuration.optimize,
        configuration.observe_allocations,
    ).module("alloc_fixed");
    build_api.requireImport(fixed, "alloc_observe", alloc_observe);
    const sys = b.dependency("sys", .{
        .target = configuration.target,
        .optimize = configuration.optimize,
    });
    const pretty = b.dependency("pretty", .{
        .target = configuration.target,
        .optimize = configuration.optimize,
    });
    return .{
        .alloc_arena = arena,
        .alloc_fixed = fixed,
        .alloc_observe = alloc_observe,
        .alloc_phase = alloc.module("alloc_phase"),
        .pretty = pretty.module("pretty"),
        .isa = b.dependency("isa", .{
            .target = configuration.target,
            .optimize = configuration.optimize,
        }).module("isa"),
        .simd = b.dependency("simd", .{
            .target = configuration.target,
            .optimize = configuration.optimize,
        }).module("simd"),
        .sys = if (configuration.browserish)
            sys.module("sys_no_libc")
        else
            sys.module("sys"),
    };
}

fn arenaDependency(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    observe_allocations: bool,
) *std.Build.Dependency {
    if (!observe_allocations) {
        return b.dependency("alloc_arena", .{
            .target = target,
            .optimize = optimize,
        });
    }
    return b.dependency("alloc_arena", .{
        .target = target,
        .optimize = optimize,
        .@"observe-allocations" = true,
    });
}

fn fixedDependency(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    observe_allocations: bool,
) *std.Build.Dependency {
    if (!observe_allocations) {
        return b.dependency("alloc_fixed", .{
            .target = target,
            .optimize = optimize,
        });
    }
    return b.dependency("alloc_fixed", .{
        .target = target,
        .optimize = optimize,
        .@"observe-allocations" = true,
    });
}

fn isBrowserish(target: std.Target) bool {
    return target.cpu.arch.isWasm() and target.os.tag == .freestanding;
}
