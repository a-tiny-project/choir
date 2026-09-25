const std = @import("std");
const bench_build = @import("bench");
const build_api = @import("build_api");
const profile = @import("profile.zig");

pub const Requested = struct {
    sys: *std.Build.Module,
    hypothesis: *std.Build.Module,
    pretty: *std.Build.Module,
};

pub const Profiling = struct {
    alloc_phase: *std.Build.Module,
    sys: *std.Build.Module,
    pretty: *std.Build.Module,
    pretty_usage: *std.Build.Module,
    bench: *std.Build.Module,
    profile_build_options: *std.Build.Module,

    pub fn modules(inputs: Profiling, gpalloc: *std.Build.Module) profile.ProfilingModules {
        return .{
            .alloc_phase = inputs.alloc_phase,
            .sys = inputs.sys,
            .pretty = inputs.pretty,
            .pretty_usage = inputs.pretty_usage,
            .bench = inputs.bench,
            .gpalloc = gpalloc,
            .profile_build_options = inputs.profile_build_options,
        };
    }
};

pub const Setup = struct {
    policy: build_api.ModuleOptions,
    inputs: profile.SetupInputs,
};

pub const Setups = struct {
    benchmark: Setup,
    tests: Setup,
};

pub fn resolveRequested(
    b: *std.Build,
    policy: build_api.ModuleOptions,
) Requested {
    const sys = b.dependency("sys", .{
        .target = policy.target,
        .optimize = policy.optimize,
    }).module("sys");
    const hypothesis = b.dependency("hypothesis", .{
        .target = policy.target,
        .optimize = policy.optimize,
    }).module("hypothesis");
    const pretty = b.dependency("pretty", .{
        .target = policy.target,
        .optimize = policy.optimize,
    }).module("pretty");
    return .{
        .sys = sys,
        .hypothesis = hypothesis,
        .pretty = pretty,
    };
}

pub fn resolveProfiling(
    b: *std.Build,
    policy: build_api.ModuleOptions,
    tracy_enabled: bool,
    shared_sys: ?*std.Build.Module,
) Profiling {
    const bench_dep = bench_build.dependency(
        b,
        policy.target,
        policy.optimize,
        .{ .tracy = tracy_enabled },
    );
    const alloc_phase = b.dependency("alloc_phase", .{
        .target = policy.target,
        .optimize = policy.optimize,
    }).module("alloc_phase");
    const pretty_dep = b.dependency("pretty", .{
        .target = policy.target,
        .optimize = policy.optimize,
    });
    const sys = shared_sys orelse b.dependency("sys", .{
        .target = policy.target,
        .optimize = policy.optimize,
    }).module("sys");
    return .{
        .alloc_phase = alloc_phase,
        .sys = sys,
        .pretty = pretty_dep.module("pretty"),
        .pretty_usage = pretty_dep.module("pretty_usage"),
        .bench = bench_dep.module("bench"),
        .profile_build_options = bench_build.profileBuildOptions(
            b,
            policy.target,
            policy.optimize,
        ),
    };
}

pub fn resolveSetups(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    test_optimize: std.builtin.OptimizeMode,
) Setups {
    return .{
        .benchmark = resolveSetup(b, target, .fast),
        .tests = resolveSetup(b, target, test_optimize),
    };
}

fn resolveSetup(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) Setup {
    const sys = b.dependency("sys", .{
        .target = target,
        .optimize = optimize,
    });
    const pretty = b.dependency("pretty", .{
        .target = target,
        .optimize = optimize,
    });
    return .{
        .policy = .{
            .target = target,
            .optimize = optimize,
        },
        .inputs = .{
            .pretty = pretty.module("pretty"),
            .pretty_usage = pretty.module("pretty_usage"),
            .sys = sys.module("sys"),
        },
    };
}
