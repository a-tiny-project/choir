const std = @import("std");
const build_api = @import("build_api");

pub fn registered(
    b: *std.Build,
    policy: build_api.ModuleOptions,
    enabled: bool,
) *std.Build.Module {
    return b.addModule(
        "alloc_observe",
        policy.createOptions(b, "src/root.zig", &.{
            .{
                .name = "build_options",
                .module = optionsModule(b, enabled),
            },
        }),
    );
}

pub fn testing(
    b: *std.Build,
    policy: build_api.ModuleOptions,
    enabled: bool,
) *std.Build.Module {
    return b.createModule(policy.createOptions(b, "src/test.zig", &.{
        .{
            .name = "build_options",
            .module = optionsModule(b, enabled),
        },
    }));
}

fn optionsModule(b: *std.Build, enabled: bool) *std.Build.Module {
    const options = b.addOptions();
    options.addOption(bool, "allocation_observation_enabled", enabled);
    return options.createModule();
}
