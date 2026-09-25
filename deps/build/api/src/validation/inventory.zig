const std = @import("std");
const validation = @import("../../validation/root.zig");
const declaration = @import("declaration.zig");
const infrastructure = @import("infrastructure.zig");
const manifest = @import("manifest.zig");
const source = @import("source.zig");
const root_set = @import("roots.zig");

/// Root dependencies and the canonical tool catalog enumerate package identities.
/// Each package manifest owns its edges; inert fixture fronts never become owners.
pub fn collect(b: *std.Build, repository: []const u8, tool_catalog: []const u8) declaration.Catalog {
    std.debug.assert(repository.len != 0);
    return load(b, repository, tool_catalog) catch |err| {
        std.debug.panic("validation package inventory: {s}", .{@errorName(err)});
    };
}

pub fn load(
    b: *std.Build,
    repository: []const u8,
    tool_catalog: []const u8,
) !declaration.Catalog {
    std.debug.assert(repository.len != 0);
    const cwd = try std.process.currentPathAlloc(b.graph.io, b.allocator);
    const root = try std.fs.path.resolve(b.allocator, &.{ cwd, try b.root.joinString(b.allocator, repository) });
    var pending: [validation.plan.owners_max][]const u8 = undefined;
    pending[0] = ".";
    var count: usize = 1;
    var cursor: usize = 0;
    var owners: std.ArrayList(validation.plan.Owner) = .empty;
    var recipes: std.ArrayList(validation.Recipe) = .empty;
    var roots: std.ArrayList([]const u8) = .empty;
    var root_dependencies: []const []const u8 = &.{};
    var root_fixture_parents: std.ArrayList([]const u8) = .empty;
    try root_set.add(b.allocator, &roots, tool_catalog);
    const catalog_path = b.pathJoin(&.{ root, tool_catalog });
    b.dependOnFileContents(b.graph.cwdRelativePath(catalog_path));
    const catalog_bytes = try std.Io.Dir.cwd().readFileAlloc(
        b.graph.io,
        catalog_path,
        b.allocator,
        .limited(manifest.bytes_max),
    );
    const catalog_sentinel = try b.allocator.dupeSentinel(u8, catalog_bytes, 0);
    const tool_roots = try manifest.toolRoots(b.allocator, catalog_sentinel);
    for (tool_roots) |owner| {
        var present = false;
        for (pending[0..count]) |existing| {
            if (std.mem.eql(u8, owner, existing)) {
                present = true;
                break;
            }
        }
        if (present) continue;
        if (count == pending.len) return error.ValidationPlanCapacityExceeded;
        pending[count] = owner;
        count += 1;
    }
    while (cursor < count) : (cursor += 1) {
        const owner = pending[cursor];
        const manifest_path = if (cursor == 0) "build.zig.zon" else b.pathJoin(&.{ owner, "build.zig.zon" });
        try root_set.add(b.allocator, &roots, manifest_path);
        const absolute = b.pathJoin(&.{ root, manifest_path });
        b.dependOnFileContents(b.graph.cwdRelativePath(absolute));
        const bytes = try std.Io.Dir.cwd().readFileAlloc(
            b.graph.io,
            absolute,
            b.allocator,
            .limited(manifest.bytes_max),
        );
        const sentinel = try b.allocator.dupeSentinel(u8, bytes, 0);
        const paths = try manifest.dependencies(b.allocator, sentinel);
        var dependencies: std.ArrayList([]const u8) = .empty;
        for (paths) |path| {
            const resolved = try std.fs.path.resolve(b.allocator, &.{ root, owner, path });
            const relative = try std.fs.path.relative(b.allocator, cwd, null, root, resolved);
            if (std.fs.path.isAbsolute(relative) or std.mem.eql(u8, relative, "..") or
                std.mem.startsWith(u8, relative, "../")) return error.ValidationDependencyOutsideRepository;
            if (std.mem.eql(u8, relative, ".") or relative.len == 0) continue;
            if (fixtureParent(relative)) |parent| {
                if (cursor == 0) try root_fixture_parents.append(b.allocator, parent);
                continue;
            }
            var found = false;
            for (pending[0..count]) |existing| {
                if (std.mem.eql(u8, existing, relative)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                if (count == pending.len) return error.ValidationPlanCapacityExceeded;
                pending[count] = relative;
                count += 1;
            }
            try dependencies.append(b.allocator, relative);
        }
        if (cursor == 0) {
            root_dependencies = try dependencies.toOwnedSlice(b.allocator);
            continue;
        }
        const package = declaration.load(b, repository, owner);
        if (package) |metadata| {
            if (recipes.items.len + metadata.recipes.len > validation.plan.recipes_max) {
                return error.ValidationPlanCapacityExceeded;
            }
            try recipes.appendSlice(b.allocator, metadata.recipes);
            for (metadata.source_roots) |path| try root_set.add(b.allocator, &roots, path);
        }
        try owners.append(b.allocator, .{
            .path = owner,
            .dependencies = try dependencies.toOwnedSlice(b.allocator),
            .recipes = if (package) |metadata| metadata.owners[0].recipes else &.{},
        });
    }
    if (infrastructure.load(b, repository, owners.items)) |metadata| {
        var infrastructure_dependencies: std.ArrayList([]const u8) = .empty;
        try infrastructure_dependencies.appendSlice(b.allocator, root_dependencies);
        for (root_fixture_parents.items) |parent| {
            for (metadata.owners) |declared| {
                if (std.mem.eql(u8, parent, declared.path)) {
                    try infrastructure_dependencies.append(b.allocator, parent);
                    break;
                }
            }
        }
        const framework_root = for (root_dependencies) |dependency| {
            if (std.mem.eql(u8, dependency, "build/api")) break dependency;
        } else return error.ValidationFrameworkDependencyMissing;
        const tool_dependencies = try b.allocator.alloc([]const u8, tool_roots.len + 1);
        @memcpy(tool_dependencies[0..tool_roots.len], tool_roots);
        tool_dependencies[tool_roots.len] = framework_root;
        if (recipes.items.len + metadata.recipes.len > validation.plan.recipes_max or
            owners.items.len + metadata.owners.len > validation.plan.owners_max)
            return error.ValidationPlanCapacityExceeded;
        try recipes.appendSlice(b.allocator, metadata.recipes);
        for (metadata.source_roots) |path| try root_set.add(b.allocator, &roots, path);
        for (metadata.owners, metadata.dependency_sources) |declared, dependency_source| {
            var owner = declared;
            owner.dependencies = switch (dependency_source) {
                .root_manifest => infrastructure_dependencies.items,
                .tool_catalog => tool_dependencies,
            };
            try owners.append(b.allocator, owner);
        }
    }
    _ = try validation.plan.select(owners.items, recipes.items, &.{});
    return .{
        .recipes = try recipes.toOwnedSlice(b.allocator),
        .owners = try owners.toOwnedSlice(b.allocator),
        .sources = source.capture(b, repository, roots.items),
        .source_roots = try roots.toOwnedSlice(b.allocator),
    };
}

fn fixtureParent(path: []const u8) ?[]const u8 {
    const marker = std.mem.indexOf(u8, path, "/fixture") orelse return null;
    const suffix = path[marker + "/fixture".len ..];
    if (suffix.len != 0 and suffix[0] != '/') return null;
    return path[0..marker];
}
