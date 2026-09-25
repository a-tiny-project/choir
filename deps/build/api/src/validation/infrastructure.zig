const std = @import("std");
const validation = @import("../../validation/root.zig");
const source = @import("source.zig");

pub const declaration_path = "build/api/validation/infrastructure.zon";

pub const OwnerSpec = struct {
    path: []const u8,
    id: []const u8,
    step: []const u8,
    suite: []const u8,
    dependencies: DependencySource,
};

pub const DependencySource = enum { root_manifest, tool_catalog };

pub const Catalog = struct {
    recipes: []const validation.Recipe,
    sources: []const validation.Source,
    source_roots: []const []const u8,
    owners: []const validation.plan.Owner,
    dependency_sources: []const DependencySource,
};

const Manifest = struct {
    root_options: []const []const u8,
    owners: []const OwnerSpec,
};

const source_roots = [_][]const u8{
    "build.zig",
    "build.zig.zon",
    "toolcatalogtest.zig",
    "build/root.zig",
    "build/api/build.zig",
    "build/api/build.zig.zon",
    "build/api/runner.zig",
    "build/api/src",
    "build/api/validation",
    "build/packages/audit/register",
    "build/packages/audit/fixture/lane-roster.tsv",
    "build/packages/register.zig",
    "build/packages/root.zig",
    "build/tools/package/catalog.zon",
    "build/tools/package/register.zig",
    "build/tools/package/root.zig",
};

pub fn load(
    b: *std.Build,
    repository: []const u8,
    package_roots: []const validation.plan.Owner,
) ?Catalog {
    const path = b.pathJoin(&.{ repository, declaration_path });
    const absolute = b.root.joinString(b.allocator, path) catch @panic("OOM");
    const parent = std.fs.path.dirname(absolute).?;
    b.dependOnDirectory(b.graph.cwdRelativePath(parent));
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        b.graph.io,
        absolute,
        b.allocator,
        .limited(1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => std.debug.panic("infrastructure declaration: {s}", .{@errorName(err)}),
    };
    b.dependOnFileContents(b.graph.cwdRelativePath(absolute));
    const sentinel = b.allocator.dupeSentinel(u8, bytes, 0) catch @panic("OOM");
    const manifest = std.zon.parse.fromSliceAlloc(
        Manifest,
        b.allocator,
        sentinel,
        null,
        .{},
    ) catch |err| {
        std.debug.panic("infrastructure declaration: {s}", .{@errorName(err)});
    };
    var package_paths: std.ArrayList([]const u8) = .empty;
    for (package_roots) |package| {
        package_paths.append(b.allocator, package.path) catch @panic("OOM");
    }
    validateRoots(manifest.owners, package_paths.items) catch |err| {
        std.debug.panic("infrastructure owners: {s}", .{@errorName(err)});
    };
    const sources = source.capture(b, repository, &source_roots);
    const declaration_hash = for (sources) |entry| {
        if (std.mem.eql(u8, entry.path, declaration_path)) break entry.sha256;
    } else @panic("missing infrastructure declaration source");
    const framework_hash = b.dupe(&validation.sourceDigest(sources));
    const recipes = b.allocator.alloc(
        validation.Recipe,
        manifest.owners.len,
    ) catch @panic("OOM");
    const owners = b.allocator.alloc(
        validation.plan.Owner,
        manifest.owners.len,
    ) catch @panic("OOM");
    const dependency_sources = b.allocator.alloc(
        DependencySource,
        manifest.owners.len,
    ) catch @panic("OOM");
    for (manifest.owners, 0..) |spec, index| {
        const recipe = &recipes[index];
        const owner = &owners[index];
        dependency_sources[index] = spec.dependencies;
        const suite = b.allocator.alloc(validation.Suite, 1) catch @panic("OOM");
        suite[0] = .{
            .id = spec.suite,
            .backend = "native",
            .selection_artifact = b.fmt("{s}.selection.json", .{spec.suite}),
            .result_artifact = b.fmt("{s}.result.json", .{spec.suite}),
        };
        const base_argv: []const []const u8 = &.{
            "build",
            "--build-file",
            "/workspace/build.zig",
            "--cache-dir",
            "/tmp/zig-local",
            "--prefix",
            "/tmp/zig-out",
            "-Doptimize=Debug",
            "-Dproduct-backend=native",
            "-Dvalidation-dir=/output",
            "-j1",
        };
        const argv = b.allocator.alloc([]const u8, base_argv.len + manifest.root_options.len) catch @panic("OOM");
        @memcpy(argv[0..base_argv.len], base_argv);
        @memcpy(argv[base_argv.len..], manifest.root_options);
        recipe.* = .{
            .id = spec.id,
            .owner = spec.path,
            .directory = ".",
            .step = spec.step,
            .class = "ordinary",
            .test_cwd = "/tmp",
            .declaration = declaration_path,
            .declaration_sha256 = declaration_hash,
            .framework_sha256 = framework_hash,
            .argv = argv,
            .runtime = &.{ "zig", "git" },
            .environment = &.{
                .{ .name = "HOME", .value = "/tmp" },
                .{ .name = "TMPDIR", .value = "/tmp" },
                .{ .name = "ZIG_GLOBAL_CACHE_DIR", .value = "/tmp/zig-global" },
                .{ .name = "ZIG_LOCAL_CACHE_DIR", .value = "/tmp/zig-child" },
                .{ .name = "ZIG_DEBUG_MAKER", .value = "1" },
                .{ .name = "LANG", .value = "C" },
                .{ .name = "TZ", .value = "UTC" },
                .{ .name = "NO_COLOR", .value = "1" },
            },
            .suites = suite,
        };
        const required = b.allocator.alloc([]const u8, 1) catch @panic("OOM");
        required[0] = spec.id;
        owner.* = .{ .path = spec.path, .recipes = required };
    }
    _ = validation.plan.select(owners, recipes, &.{}) catch |err| {
        std.debug.panic("infrastructure validation plan: {s}", .{@errorName(err)});
    };
    return .{
        .recipes = recipes,
        .owners = owners,
        .sources = sources,
        .source_roots = &source_roots,
        .dependency_sources = dependency_sources,
    };
}

pub fn validateRoots(specs: []const OwnerSpec, package_roots: []const []const u8) !void {
    for (specs, 0..) |spec, index| {
        if (spec.id.len == 0 or spec.step.len == 0 or spec.suite.len == 0 or
            std.mem.eql(u8, spec.path, ".") or std.mem.eql(u8, spec.path, "build") or
            std.mem.eql(u8, spec.path, "build/") or
            !validPath(spec.path)) return error.InvalidInfrastructureOwner;
        for (specs[0..index]) |prior| {
            if (overlaps(spec.path, prior.path)) return error.OverlappingInfrastructureOwner;
        }
        for (package_roots) |package_root| {
            if (overlaps(spec.path, package_root)) return error.InfrastructureOverlapsPackage;
        }
    }
}

fn validPath(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or
            std.mem.eql(u8, part, ".") or
            std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

fn overlaps(a: []const u8, b: []const u8) bool {
    if (std.mem.eql(u8, a, b)) return true;
    return std.mem.startsWith(u8, a, b) and a.len > b.len and a[b.len] == '/' or
        std.mem.startsWith(u8, b, a) and b.len > a.len and b[a.len] == '/';
}

test "infrastructure roots reject broad paths and package overlap" {
    const entry = OwnerSpec{
        .path = "build/packages",
        .id = "build-packages.test",
        .step = "package-registry-test",
        .suite = "build-packages-check",
        .dependencies = .root_manifest,
    };
    try validateRoots(&.{entry}, &.{"lib/smt"});
    for ([_][]const u8{ ".", "build/", "build", "lib/smt/sub" }) |path| {
        var invalid = entry;
        invalid.path = path;
        try std.testing.expectError(
            if (std.mem.eql(u8, path, "lib/smt/sub"))
                error.InfrastructureOverlapsPackage
            else
                error.InvalidInfrastructureOwner,
            validateRoots(&.{invalid}, &.{"lib/smt"}),
        );
    }
}
