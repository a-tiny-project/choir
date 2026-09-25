const std = @import("std");
const artifacts = @import("artifacts.zig");

pub fn add(
    b: *std.Build,
    registered: artifacts.Artifacts,
    test_step: *std.Build.Step,
) void {
    const run_benchmark = std.Build.Step.Run.create(b, "run gpalloc benchmarks");
    run_benchmark.addArtifactArg(registered.benchmark);
    run_benchmark.stdio = .inherit;
    const benchmark_step = b.step("bench", "Run gpalloc benchmarks");
    benchmark_step.dependOn(&run_benchmark.step);

    const install_benchmark = b.addInstallArtifact(registered.benchmark, .{});
    const benchmark_binary_step = b.step(
        "bench-bin",
        "Install the gpalloc benchmark binary",
    );
    benchmark_binary_step.dependOn(&install_benchmark.step);

    const driver_step = b.step(
        "bench-driver",
        "Build the standalone gpalloc benchmark driver",
    );
    driver_step.dependOn(registered.install_driver);

    const external_step = b.step(
        "external-bench",
        "Build the external mimalloc-bench runner",
    );
    external_step.dependOn(registered.install_external);
    test_step.dependOn(registered.run_external_tests);

    const contract_step = b.step(
        "semantic-contracts",
        "Build the native gpalloc semantic contract probe",
    );
    contract_step.dependOn(registered.install_contract);
    test_step.dependOn(registered.compile_contract_tests);

    const preload_step = b.step("preload", "Build the LD_PRELOAD allocator library");
    preload_step.dependOn(registered.install_preload);
    const preload_test_step = b.step(
        "preload-test",
        "Run LD_PRELOAD allocator unit tests",
    );
    preload_test_step.dependOn(registered.run_preload_tests);
    test_step.dependOn(registered.run_preload_tests);
    test_step.dependOn(registered.run_setup_tests);
    test_step.dependOn(registered.run_driver_tests);

    const run_setup = b.addRunArtifact(registered.setup);
    run_setup.stdio = .inherit;
    run_setup.addPassthruArgs();
    const setup_step = b.step(
        "allocator-suite",
        "Install external allocator comparison suite",
    );
    setup_step.dependOn(&run_setup.step);

    const run_driver = b.addRunArtifact(registered.driver);
    run_driver.addPassthruArgs();
    const compare_step = b.step(
        "bench-compare",
        "Run the standalone gpalloc benchmark driver",
    );
    compare_step.dependOn(&run_driver.step);
}
