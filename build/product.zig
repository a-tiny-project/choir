const std = @import("std");
const build_api = @import("build_api");
const module = @import("module.zig");

pub fn add(
    b: *std.Build,
    options: build_api.ModuleOptions,
    inputs: module.Inputs,
) *std.Build.Module {
    const choir = module.createModule(b, options, inputs);
    build_api.registerModule(b, "choir", choir);
    build_api.registerModule(b, "choir_abi", choir.import_table.get("choir_abi").?);
    return choir;
}
