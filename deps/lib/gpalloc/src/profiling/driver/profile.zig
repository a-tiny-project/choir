const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;

const options = @import("options.zig");

pub const Runtime = struct {
    file: coz.ProfileFile = .{},
    runtime: coz.Runtime = .{},
    source_patterns: [1][]const u8 = undefined,
};

pub fn start(
    runtime: *Runtime,
    allocator: std.mem.Allocator,
    parsed: options.Options,
) !void {
    if (parsed.coz_profile_path) |path| {
        try runtime.file.open(path);
        errdefer runtime.file.close();
    }

    var source_scope: coz.debug_info.Scope = .{};
    if (parsed.coz_source_pattern) |pattern| {
        runtime.source_patterns[0] = pattern;
        source_scope = .{ .patterns = runtime.source_patterns[0..] };
    }

    const runtime_options: coz.RuntimeOptions = .{
        .profile_writer = runtime.file.interface(),
        .start_experiment_worker = parsed.coz_experiments,
        .experiment_duration_ns = parsed.coz_experiment_duration_ns,
        .source_scope = source_scope,
        .resolve_sample_locations = parsed.coz_experiments,
    };

    if (parsed.coz_profile_path != null or parsed.coz_experiments) {
        try runtime.runtime.start(allocator, runtime_options);
    } else {
        _ = try runtime.runtime.startIfAvailable(allocator, runtime_options);
    }
}

pub fn deinit(runtime: *Runtime) void {
    runtime.runtime.shutdown();
    runtime.file.close();
}
