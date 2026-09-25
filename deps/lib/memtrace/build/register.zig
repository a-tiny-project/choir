const std = @import("std");
const configuration = @import("configuration.zig");
const deps = @import("deps.zig");
const module = @import("module.zig");
const product = @import("product.zig");
const tests = @import("tests.zig");

pub fn build(b: *std.Build) void {
    const config = configuration.resolve(b);
    const dependencies = deps.core(b, config);
    const memtrace = module.library(b, config.policy, dependencies);
    product.library(b, memtrace);
    const unit = tests.unit(b, config, module.unit(b, config.policy, dependencies));
    const corpus = b.createModule(config.policy.createOptions(b, "src/profiling/test.zig", &.{
        .{ .name = "memtrace", .module = memtrace },
    }));
    const corpus_tests = b.addTest(.{ .root_module = corpus, .filters = config.test_filters });
    const run_corpus = b.addRunArtifact(corpus_tests);
    unit.dependOn(&run_corpus.step);

    if (!config.browserish) {
        const cli = module.cli(b, config.policy, memtrace, dependencies.sys);
        product.cli(b, cli);
    }

    const hypothesis = deps.hypothesis(b, config.policy);
    const properties = module.properties(b, config.policy, hypothesis, memtrace);
    tests.properties(b, config, properties);
}
