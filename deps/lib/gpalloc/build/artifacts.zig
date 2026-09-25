const std = @import("std");
const graph = @import("graph.zig");

pub const Artifacts = struct {
    benchmark: *std.Build.Step.Compile,
    driver: *std.Build.Step.Compile,
    setup: *std.Build.Step.Compile,
    install_driver: *std.Build.Step,
    install_external: *std.Build.Step,
    install_contract: *std.Build.Step,
    install_preload: *std.Build.Step,
    compile_contract_tests: *std.Build.Step,
    run_external_tests: *std.Build.Step,
    run_preload_tests: *std.Build.Step,
    run_setup_tests: *std.Build.Step,
    run_driver_tests: *std.Build.Step,
};

const Installed = struct {
    executable: *std.Build.Step.Compile,
    install: *std.Build.Step,
};

pub fn add(
    b: *std.Build,
    benchmark: graph.Benchmark,
    tests: graph.Tests,
    setup: graph.Setup,
    filters: []const []const u8,
) Artifacts {
    const driver = addInstalledExecutable(b, "gpalloc-bench-driver", benchmark.driver);
    const external = addInstalledExecutable(b, "gpalloc-external-bench", benchmark.external);
    const run_external_tests = addTests(b, tests.external, filters);
    const contract_tests = b.addTest(.{
        .root_module = tests.contract,
        .filters = filters,
    });
    const contract = addInstalledExecutable(
        b,
        "gpalloc-semantic-contracts",
        benchmark.contract,
    );
    const preload = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "gpalloc_malloc",
        .root_module = benchmark.preload,
    });
    const install_preload = b.addInstallArtifact(preload, .{});
    const setup_executable = b.addExecutable(.{
        .name = "gpalloc-setup",
        .root_module = setup.executable,
    });
    const run_preload_tests = addTests(b, tests.preload, filters);
    const run_setup_tests = addTests(b, setup.tests, filters);
    const run_driver_tests = addTests(b, tests.driver, filters);
    const benchmark_tests = b.addTest(.{
        .name = "gpalloc-bench",
        .root_module = benchmark.benchmark,
        .filters = &.{"bench:"},
    });
    return .{
        .benchmark = benchmark_tests,
        .driver = driver.executable,
        .setup = setup_executable,
        .install_driver = driver.install,
        .install_external = external.install,
        .install_contract = contract.install,
        .install_preload = &install_preload.step,
        .compile_contract_tests = &contract_tests.step,
        .run_external_tests = run_external_tests,
        .run_preload_tests = run_preload_tests,
        .run_setup_tests = run_setup_tests,
        .run_driver_tests = run_driver_tests,
    };
}

fn addInstalledExecutable(
    b: *std.Build,
    name: []const u8,
    root_module: *std.Build.Module,
) Installed {
    const executable = b.addExecutable(.{
        .name = name,
        .root_module = root_module,
    });
    const install = b.addInstallArtifact(executable, .{});
    return .{
        .executable = executable,
        .install = &install.step,
    };
}

fn addTests(
    b: *std.Build,
    root_module: *std.Build.Module,
    filters: []const []const u8,
) *std.Build.Step {
    const tests = b.addTest(.{
        .root_module = root_module,
        .filters = filters,
    });
    return &b.addRunArtifact(tests).step;
}
