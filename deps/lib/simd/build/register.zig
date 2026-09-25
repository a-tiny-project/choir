const std = @import("std");
const bench_build = @import("bench");
const build_api = @import("build_api");

pub fn build(b: *std.Build) void {
    const target = build_api.standardTargets(b).product;
    const optimize = b.standardOptimizeOption(.{});
    const module_options = build_api.ModuleOptions{
        .target = target,
        .optimize = optimize,
    };
    const bench_module_options = build_api.ModuleOptions{
        .target = target,
        .optimize = .fast,
    };
    const test_filters = build_api.focusedTestFilters(b);
    const hypothesis_dep = b.dependency("hypothesis", .{
        .target = module_options.target,
        .optimize = module_options.optimize,
    });
    const alloc_phase_dep = b.dependency("alloc_phase", .{
        .target = module_options.target,
        .optimize = module_options.optimize,
    });
    const benchmark_alloc_phase_dep = b.dependency("alloc_phase", .{
        .target = bench_module_options.target,
        .optimize = bench_module_options.optimize,
    });
    const sys_dep = b.dependency("sys", .{
        .target = module_options.target,
        .optimize = module_options.optimize,
    });
    const bench_dep = bench_build.dependency(
        b,
        bench_module_options.target,
        bench_module_options.optimize,
        bench_build.dependencyOptions(b),
    );
    const benchmark_sys_dep = b.dependency("sys", .{
        .target = bench_module_options.target,
        .optimize = bench_module_options.optimize,
    });
    const sys_mod = sysModule(sys_dep, module_options.target.result);
    const benchmark_sys_mod = sysModule(
        benchmark_sys_dep,
        bench_module_options.target.result,
    );

    const simd_mod = b.addModule(
        "simd",
        module_options.createOptions(b, "src/root.zig", &.{
            .{ .name = "alloc_phase", .module = alloc_phase_dep.module("alloc_phase") },
            .{ .name = "sys", .module = sys_mod },
        }),
    );
    const simd_test_mod = b.createModule(
        module_options.createOptions(b, "src/test.zig", &.{
            .{ .name = "alloc_phase", .module = alloc_phase_dep.module("alloc_phase") },
            .{ .name = "sys", .module = sys_mod },
        }),
    );
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "simd",
        .root_module = simd_mod,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = simd_test_mod,
        .filters = test_filters,
    });
    const run_tests = b.addRunArtifact(tests);
    const browserish_identity_check = addBrowserishIdentityCheck(b);
    const test_step = b.step("test", "Run SIMD unit and conformance tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&browserish_identity_check.step);

    const property_mod = b.createModule(module_options.createOptions(
        b,
        "src/properties/test.zig",
        &.{
            .{ .name = "hypothesis", .module = hypothesis_dep.module("hypothesis") },
            .{ .name = "simd", .module = simd_mod },
        },
    ));
    const pbt_tests = b.addTest(.{
        .root_module = property_mod,
        .filters = test_filters,
    });
    const run_pbt_tests = b.addRunArtifact(pbt_tests);
    const pbt_step = b.step("pbt", "Run SIMD property tests");
    pbt_step.dependOn(&run_pbt_tests.step);

    const simd_bench_mod = b.createModule(bench_module_options.createOptions(
        b,
        "src/root.zig",
        &.{
            .{
                .name = "alloc_phase",
                .module = benchmark_alloc_phase_dep.module("alloc_phase"),
            },
            .{ .name = "sys", .module = benchmark_sys_mod },
        },
    ));
    const profiling_mod = b.createModule(bench_module_options.createOptions(
        b,
        "src/profiling/test.zig",
        &.{
            .{ .name = "bench", .module = bench_dep.module("bench") },
            .{ .name = "simd", .module = simd_bench_mod },
            .{ .name = "sys", .module = benchmark_sys_mod },
        },
    ));
    const bench_tests = b.addTest(.{
        .name = "simd-bench",
        .root_module = profiling_mod,
        .filters = &.{"bench:"},
    });
    const run_bench = std.Build.Step.Run.create(b, "run SIMD benchmarks");
    run_bench.addArtifactArg(bench_tests);
    run_bench.stdio = .inherit;
    const bench_step = b.step("bench", "Run SIMD benchmarks");
    bench_step.dependOn(&run_bench.step);
    const install_bench = b.addInstallArtifact(bench_tests, .{});
    const bench_bin_step = b.step("bench-bin", "Install SIMD benchmark binary");
    bench_bin_step.dependOn(&install_bench.step);
}

fn sysModule(
    dependency: *std.Build.Dependency,
    target: std.Target,
) *std.Build.Module {
    return dependency.module(if (target.cpu.arch.isWasm() and
        target.os.tag == .freestanding)
        "sys_no_libc"
    else
        "sys");
}

fn addBrowserishIdentityCheck(
    b: *std.Build,
) *std.Build.Step.Compile {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const options = build_api.ModuleOptions{
        .target = target,
        .optimize = .safe,
    };
    const alloc_phase = b.dependency("alloc_phase", .{
        .target = target,
        .optimize = options.optimize,
    }).module("alloc_phase");
    const sys_dependency = b.dependency("sys", .{
        .target = target,
        .optimize = options.optimize,
    });
    const sys = sysModule(sys_dependency, target.result);
    const simd = b.createModule(options.createOptions(b, "src/root.zig", &.{
        .{ .name = "alloc_phase", .module = alloc_phase },
        .{ .name = "sys", .module = sys },
    }));
    const probe = b.createModule(options.createOptions(
        b,
        "src/browserish/test.zig",
        &.{
            .{ .name = "simd", .module = simd },
            .{ .name = "sys", .module = sys },
        },
    ));
    return b.addObject(.{
        .name = "simd_browserish_identity",
        .root_module = probe,
    });
}
