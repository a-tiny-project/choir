const std = @import("std");
const build_api = @import("build_api");

pub const ProfilingModules = struct {
    alloc_phase: *std.Build.Module,
    sys: *std.Build.Module,
    pretty: *std.Build.Module,
    pretty_usage: *std.Build.Module,
    bench: *std.Build.Module,
    gpalloc: *std.Build.Module,
    profile_build_options: *std.Build.Module,
};

pub const BenchInputs = struct {
    bench: *std.Build.Module,
    gpalloc: *std.Build.Module,
    sys: *std.Build.Module,
};

pub const SetupInputs = struct {
    pretty: *std.Build.Module,
    pretty_usage: *std.Build.Module,
    sys: *std.Build.Module,
};

pub fn createBenchModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    inputs: BenchInputs,
) *std.Build.Module {
    return b.createModule(options.createOptions(b, "src/profiling/test.zig", &.{
        .{ .name = "bench", .module = inputs.bench },
        .{ .name = "gpalloc", .module = inputs.gpalloc },
        .{ .name = "sys", .module = inputs.sys },
    }));
}

pub fn createWorkloadsModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
) *std.Build.Module {
    return b.createModule(options.createOptions(b, "src/profiling/workloads/root.zig", &.{
        .{ .name = "bench", .module = modules.bench },
        .{ .name = "gpalloc", .module = modules.gpalloc },
        .{ .name = "sys", .module = modules.sys },
    }));
}

pub fn createDriverModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
    workloads_mod: *std.Build.Module,
) *std.Build.Module {
    return createDriverModuleAt(
        b,
        options,
        modules,
        workloads_mod,
        "src/profiling/driver/root.zig",
    );
}

pub fn createDriverTestModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
    workloads_mod: *std.Build.Module,
) *std.Build.Module {
    return createDriverModuleAt(
        b,
        options,
        modules,
        workloads_mod,
        "src/profiling/driver/test.zig",
    );
}

fn createDriverModuleAt(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
    workloads_mod: *std.Build.Module,
    root_source_file: []const u8,
) *std.Build.Module {
    return b.createModule(options.createOptions(b, root_source_file, &.{
        .{ .name = "alloc_phase", .module = modules.alloc_phase },
        .{ .name = "bench", .module = modules.bench },
        .{ .name = "pretty", .module = modules.pretty },
        .{ .name = "pretty_usage", .module = modules.pretty_usage },
        .{ .name = "profile_build_options", .module = modules.profile_build_options },
        .{ .name = "sys", .module = modules.sys },
        .{ .name = "gpalloc", .module = modules.gpalloc },
        .{ .name = "workloads", .module = workloads_mod },
    }));
}

pub fn createContractModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
) *std.Build.Module {
    return createContractModuleAt(
        b,
        options,
        modules,
        "src/profiling/contract/root.zig",
    );
}

pub fn createContractTestModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
) *std.Build.Module {
    return createContractModuleAt(
        b,
        options,
        modules,
        "src/profiling/contract/test.zig",
    );
}

fn createContractModuleAt(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
    root_source_file: []const u8,
) *std.Build.Module {
    return b.createModule(options.createOptions(b, root_source_file, &.{
        .{ .name = "pretty", .module = modules.pretty },
        .{ .name = "pretty_usage", .module = modules.pretty_usage },
        .{ .name = "sys", .module = modules.sys },
        .{ .name = "gpalloc", .module = modules.gpalloc },
    }));
}

pub fn createPreloadModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
) *std.Build.Module {
    return createPreloadModuleAt(
        b,
        options,
        modules,
        "src/profiling/preload/root.zig",
    );
}

pub fn createPreloadTestModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
) *std.Build.Module {
    return createPreloadModuleAt(
        b,
        options,
        modules,
        "src/profiling/preload/test.zig",
    );
}

fn createPreloadModuleAt(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
    root_source_file: []const u8,
) *std.Build.Module {
    return b.createModule(options.createOptions(b, root_source_file, &.{
        .{ .name = "sys", .module = modules.sys },
        .{ .name = "gpalloc", .module = modules.gpalloc },
    }));
}

pub fn createExternalModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
) *std.Build.Module {
    return createExternalModuleAt(
        b,
        options,
        modules,
        "src/profiling/external/root.zig",
    );
}

pub fn createExternalTestModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
) *std.Build.Module {
    return createExternalModuleAt(
        b,
        options,
        modules,
        "src/profiling/external/test.zig",
    );
}

fn createExternalModuleAt(
    b: *std.Build,
    options: build_api.ModuleOptions,
    modules: ProfilingModules,
    root_source_file: []const u8,
) *std.Build.Module {
    return b.createModule(options.createOptions(b, root_source_file, &.{
        .{ .name = "bench", .module = modules.bench },
        .{ .name = "pretty", .module = modules.pretty },
        .{ .name = "pretty_usage", .module = modules.pretty_usage },
        .{ .name = "profile_build_options", .module = modules.profile_build_options },
        .{ .name = "sys", .module = modules.sys },
    }));
}

pub fn createSetupModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    inputs: SetupInputs,
) *std.Build.Module {
    return createSetupModuleAt(
        b,
        options,
        inputs,
        "src/profiling/setup/root.zig",
    );
}

pub fn createSetupTestModule(
    b: *std.Build,
    options: build_api.ModuleOptions,
    inputs: SetupInputs,
) *std.Build.Module {
    return createSetupModuleAt(
        b,
        options,
        inputs,
        "src/profiling/setup/test.zig",
    );
}

fn createSetupModuleAt(
    b: *std.Build,
    options: build_api.ModuleOptions,
    inputs: SetupInputs,
    root_source_file: []const u8,
) *std.Build.Module {
    return b.createModule(options.createOptions(b, root_source_file, &.{
        .{ .name = "pretty", .module = inputs.pretty },
        .{ .name = "pretty_usage", .module = inputs.pretty_usage },
        .{ .name = "sys", .module = inputs.sys },
    }));
}
