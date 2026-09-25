const std = @import("std");
const artifacts = @import("artifacts.zig");
const configuration = @import("configuration.zig");
const deps = @import("deps.zig");
const graph = @import("graph.zig");
const product = @import("product.zig");
const steps = @import("steps.zig");
const tests = @import("tests.zig");

pub fn build(b: *std.Build) void {
    const config = configuration.resolve(b);
    const requested = deps.resolveRequested(b, config.policies.requested);
    const gpalloc = product.add(b, config.policies.requested, .{
        .pretty = requested.pretty,
        .sys = requested.sys,
    });
    const test_step = tests.add(
        b,
        config.policies,
        requested,
        gpalloc,
        config.test_filters,
    );

    const tracy_enabled = configuration.tracyEnabled(b);
    const benchmark_inputs = deps.resolveProfiling(
        b,
        config.policies.benchmark,
        tracy_enabled,
        null,
    );
    const benchmark = graph.createBenchmark(
        b,
        config.policies.benchmark,
        benchmark_inputs,
    );
    const test_inputs = deps.resolveProfiling(
        b,
        config.policies.requested,
        tracy_enabled,
        requested.sys,
    );
    const profiling_tests = graph.createTests(
        b,
        config.policies.requested,
        test_inputs,
        gpalloc,
    );
    const setup_inputs = deps.resolveSetups(
        b,
        config.targets.host,
        config.policies.requested.optimize,
    );
    const setup = graph.createSetup(b, setup_inputs);
    const registered = artifacts.add(
        b,
        benchmark,
        profiling_tests,
        setup,
        config.test_filters,
    );
    steps.add(b, registered, test_step);
}
