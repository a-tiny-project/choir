const std = @import("std");
const build_api = @import("build_api");

pub const Policies = struct {
    requested: build_api.ModuleOptions,
    tsan: build_api.ModuleOptions,
    benchmark: build_api.ModuleOptions,
};

pub const Configuration = struct {
    targets: build_api.Targets,
    policies: Policies,
    test_filters: []const []const u8,
};

pub fn resolve(b: *std.Build) Configuration {
    const targets = build_api.standardTargets(b);
    const target = targets.product;
    const optimize = b.standardOptimizeOption(.{});
    return .{
        .targets = targets,
        .policies = .{
            .requested = .{
                .target = target,
                .optimize = optimize,
                .sanitize_thread = false,
            },
            .tsan = .{
                .target = target,
                .optimize = optimize,
                .sanitize_thread = true,
            },
            .benchmark = .{
                .target = target,
                .optimize = .fast,
                .sanitize_thread = false,
            },
        },
        .test_filters = build_api.focusedTestFilters(b),
    };
}

pub fn tracyEnabled(b: *std.Build) bool {
    return b.option(
        bool,
        "tracy",
        "Enable Tracy instrumentation in the benchmark stack",
    ) orelse false;
}
