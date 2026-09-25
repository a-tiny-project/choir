const std = @import("std");
const build_api = @import("../root.zig");
const validation = @import("../../validation/root.zig");
const source = @import("source.zig");

pub const Spec = struct {
    owner: []const u8,
    required: []const []const u8,
    recipes: []const RecipeSpec,
};

pub const RecipeSpec = struct {
    id: []const u8,
    step: []const u8,
    class: []const u8 = "ordinary",
    runtime: []const []const u8 = &.{},
    child_zig_cache: ?[]const u8 = null,
    jobs: ?u8 = null,
    suites: []const validation.Suite,
};

pub const Catalog = struct {
    recipes: []const validation.Recipe,
    sources: []const validation.Source,
    source_roots: []const []const u8,
    owners: []const validation.plan.Owner,
};

const framework_roots = [_][]const u8{
    "build/api/build.zig",
    "build/api/build.zig.zon",
    "build/api/runner.zig",
    "build/api/src",
    "build/api/validation",
    "build/api/timing",
};

pub fn load(b: *std.Build, repository: []const u8, owner: []const u8) ?Catalog {
    std.debug.assert(repository.len != 0);
    std.debug.assert(owner.len != 0);
    const path = b.pathJoin(&.{ repository, owner, "build/validation.zon" });
    const absolute = b.root.joinString(b.allocator, path) catch @panic("OOM");
    const parent = std.fs.path.dirname(absolute).?;
    const directory = if (std.Io.Dir.cwd().statFile(b.graph.io, parent, .{})) |_| parent else |err| switch (err) {
        error.FileNotFound => std.fs.path.dirname(parent).?,
        else => std.debug.panic("validation declaration directory: {s}", .{@errorName(err)}),
    };
    b.dependOnDirectory(b.graph.cwdRelativePath(directory));
    const bytes = std.Io.Dir.cwd().readFileAlloc(b.graph.io, absolute, b.allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => std.debug.panic("validation declaration {s}: {s}", .{ owner, @errorName(err) }),
    };
    b.dependOnFileContents(b.graph.cwdRelativePath(absolute));
    const sentinel = b.allocator.dupeSentinel(u8, bytes, 0) catch @panic("OOM");
    const spec = std.zon.parse.fromSliceAlloc(Spec, b.allocator, sentinel, null, .{}) catch |err| {
        std.debug.panic("validation declaration {s}: {s}", .{ owner, @errorName(err) });
    };
    if (!std.mem.eql(u8, spec.owner, owner)) @panic("validation declaration owner mismatch");
    return configure(b, repository, spec);
}

/// Both package execution and catalog export derive the same recipe identity.
pub fn configure(b: *std.Build, repository: []const u8, spec: Spec) Catalog {
    std.debug.assert(repository.len != 0);
    std.debug.assert(spec.owner.len != 0);
    if (spec.recipes.len == 0 or spec.recipes.len > validation.plan.recipes_max) {
        @panic("invalid package validation recipe count");
    }
    const roots = b.allocator.alloc([]const u8, framework_roots.len + 3) catch @panic("OOM");
    @memcpy(roots[0..framework_roots.len], &framework_roots);
    roots[framework_roots.len] = b.pathJoin(&.{ spec.owner, "build.zig" });
    roots[framework_roots.len + 1] = b.pathJoin(&.{ spec.owner, "build.zig.zon" });
    roots[framework_roots.len + 2] = b.pathJoin(&.{ spec.owner, "build" });
    const sources = source.capture(b, repository, roots);
    const declaration = b.pathJoin(&.{ spec.owner, "build/validation.zon" });
    const declaration_hash = for (sources) |entry| {
        if (std.mem.eql(u8, entry.path, declaration)) break entry.sha256;
    } else @panic("missing package validation declaration");
    const framework_hash = b.dupe(&validation.sourceDigest(sources));
    const recipes = b.allocator.alloc(validation.Recipe, spec.recipes.len) catch @panic("OOM");
    for (spec.recipes, recipes) |entry, *recipe| {
        if (entry.suites.len == 0 or entry.suites.len > validation.max_suites) {
            @panic("invalid package validation suite count");
        }
        if (entry.runtime.len > 14) @panic("too many package validation executables");
        const runtime = b.allocator.alloc([]const u8, 2 + entry.runtime.len) catch @panic("OOM");
        runtime[0] = "zig";
        runtime[1] = "git";
        @memcpy(runtime[2..], entry.runtime);
        const base_environment = [_]validation.Environment{
            .{ .name = "HOME", .value = "/tmp" },
            .{ .name = "TMPDIR", .value = "/tmp" },
            .{ .name = "ZIG_GLOBAL_CACHE_DIR", .value = "/tmp/zig-global" },
            .{ .name = "ZIG_DEBUG_MAKER", .value = "1" },
            .{ .name = "LANG", .value = "C" },
            .{ .name = "TZ", .value = "UTC" },
            .{ .name = "NO_COLOR", .value = "1" },
        };
        const environment = b.allocator.alloc(
            validation.Environment,
            base_environment.len + @intFromBool(entry.child_zig_cache != null),
        ) catch @panic("OOM");
        @memcpy(environment[0..base_environment.len], &base_environment);
        if (entry.child_zig_cache) |path| {
            if (!std.mem.startsWith(u8, path, "/tmp/") or
                path.len <= "/tmp/".len or
                std.mem.indexOf(u8, path, "..") != null)
                @panic("child Zig cache must be below /tmp");
            environment[base_environment.len] = .{ .name = "ZIG_LOCAL_CACHE_DIR", .value = path };
        }
        const arguments = b.allocator.alloc(
            []const u8,
            10 + @as(usize, @intFromBool(entry.jobs != null)),
        ) catch @panic("OOM");
        @memcpy(arguments[0..10], &[_][]const u8{
            "build",                                  "--build-file",     b.fmt("/workspace/{s}/build.zig", .{spec.owner}),
            build_api.child_cache_directory_argument, "/tmp/zig-local",   "--prefix",
            "/tmp/zig-out",                           "-Doptimize=Debug", "-Dproduct-backend=native",
            "-Dvalidation-dir=/output",
        });
        if (entry.jobs) |jobs| {
            if (jobs == 0 or jobs > 16) @panic("invalid package validation job count");
            arguments[10] = b.fmt("-j{d}", .{jobs});
        }
        recipe.* = .{
            .id = entry.id,
            .owner = spec.owner,
            .directory = spec.owner,
            .step = entry.step,
            .class = entry.class,
            .test_cwd = "/tmp",
            .declaration = declaration,
            .declaration_sha256 = declaration_hash,
            .framework_sha256 = framework_hash,
            .argv = arguments,
            .runtime = runtime,
            .environment = environment,
            .suites = entry.suites,
        };
    }
    const owners = b.allocator.alloc(validation.plan.Owner, 1) catch @panic("OOM");
    owners[0] = .{ .path = spec.owner, .recipes = spec.required };
    _ = validation.plan.select(owners, recipes, &.{}) catch |err| {
        std.debug.panic("invalid package validation declaration: {s}", .{@errorName(err)});
    };
    return .{ .recipes = recipes, .sources = sources, .source_roots = roots, .owners = owners };
}
