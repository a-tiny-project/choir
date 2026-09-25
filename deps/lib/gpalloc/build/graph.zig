const std = @import("std");
const build_api = @import("build_api");
const deps = @import("deps.zig");
const module = @import("module.zig");
const profile = @import("profile.zig");

pub const Benchmark = struct {
    benchmark: *std.Build.Module,
    driver: *std.Build.Module,
    contract: *std.Build.Module,
    preload: *std.Build.Module,
    external: *std.Build.Module,
};

pub const Tests = struct {
    driver: *std.Build.Module,
    contract: *std.Build.Module,
    preload: *std.Build.Module,
    external: *std.Build.Module,
};

pub const Setup = struct {
    executable: *std.Build.Module,
    tests: *std.Build.Module,
};

pub fn createBenchmark(
    b: *std.Build,
    policy: build_api.ModuleOptions,
    inputs: deps.Profiling,
) Benchmark {
    const gpalloc = module.createModule(b, policy, .{ .sys = inputs.sys });
    const modules = inputs.modules(gpalloc);
    const benchmark = profile.createBenchModule(b, policy, .{
        .bench = modules.bench,
        .gpalloc = modules.gpalloc,
        .sys = modules.sys,
    });
    const workloads = profile.createWorkloadsModule(b, policy, modules);
    return .{
        .benchmark = benchmark,
        .driver = profile.createDriverModule(b, policy, modules, workloads),
        .contract = profile.createContractModule(b, policy, modules),
        .preload = profile.createPreloadModule(b, policy, modules),
        .external = profile.createExternalModule(b, policy, modules),
    };
}

pub fn createTests(
    b: *std.Build,
    policy: build_api.ModuleOptions,
    inputs: deps.Profiling,
    gpalloc: *std.Build.Module,
) Tests {
    const modules = inputs.modules(gpalloc);
    const workloads = profile.createWorkloadsModule(b, policy, modules);
    return .{
        .driver = profile.createDriverTestModule(b, policy, modules, workloads),
        .contract = profile.createContractTestModule(b, policy, modules),
        .preload = profile.createPreloadTestModule(b, policy, modules),
        .external = profile.createExternalTestModule(b, policy, modules),
    };
}

pub fn createSetup(b: *std.Build, inputs: deps.Setups) Setup {
    return .{
        .executable = profile.createSetupModule(
            b,
            inputs.benchmark.policy,
            inputs.benchmark.inputs,
        ),
        .tests = profile.createSetupTestModule(
            b,
            inputs.tests.policy,
            inputs.tests.inputs,
        ),
    };
}
