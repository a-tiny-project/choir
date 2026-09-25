const std = @import("std");
const bench_build = @import("bench");
const build_api = @import("build_api");

pub fn add(
    b: *std.Build,
    policy: build_api.ModuleOptions,
    isa: *std.Build.Module,
) void {
    const bench = bench_build.dependency(
        b,
        policy.target,
        policy.optimize,
        bench_build.dependencyOptions(b),
    );
    const profiling = b.createModule(policy.createOptions(
        b,
        "src/profiling/test.zig",
        &.{
            .{ .name = "bench", .module = bench.module("bench") },
            .{ .name = "isa", .module = isa },
        },
    ));
    const artifact = b.addTest(.{
        .name = "isa-bench",
        .root_module = profiling,
        .filters = &.{"bench:"},
    });
    const run = std.Build.Step.Run.create(b, "run ISA decode benchmarks");
    run.addArtifactArg(artifact);
    run.stdio = .inherit;
    const step = b.step("bench", "Run ISA compiler/K0-shaped decode benchmarks");
    step.dependOn(&run.step);
    const install = b.addInstallArtifact(artifact, .{});
    const bin = b.step(
        "bench-bin",
        "Install the ISA compiler/K0-shaped decode benchmark binary",
    );
    bin.dependOn(&install.step);
}
