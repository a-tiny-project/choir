const std = @import("std");
const coz = @import("coz");
const hypothesis = @import("hypothesis");

const profile = coz.profile;

pub const files = [_][]const u8{
    "src/work.zig",
    "src/other.zig",
    "lib/coz/src/analysis.zig",
    "quote\"file.zig",
    "path\\file.zig",
};

pub const point_names = [_][]const u8{
    "items",
    "request",
    "compile\nphase",
    "query\tcache",
    "point\x00name",
};

pub const virtual_speedups = [_]f64{
    0,
    0.25,
    0.5,
    0.75,
    1.0,
};

pub const edge_u64_values = [_]u64{
    0,
    1,
    7,
    42,
    std.math.maxInt(i64),
    @as(u64, @intCast(std.math.maxInt(i64))) + 1,
    std.math.maxInt(u64),
};

pub fn settings() hypothesis.Settings {
    return hypothesis.Settings.quick()
        .withSeed(0x434f_5a20_5052_4f46)
        .withDatabase("zig-out/hypothesis-failures/coz");
}

pub fn drawUsize(data: *hypothesis.ConjectureData, min: usize, max: usize, shrink_towards: usize) !usize {
    return @intCast(try data.drawInteger(
        @intCast(min),
        @intCast(max),
        @intCast(shrink_towards),
    ));
}

pub fn drawSmallU64(data: *hypothesis.ConjectureData, min: u64, max: u64, shrink_towards: u64) !u64 {
    return try data.drawInteger(min, max, shrink_towards);
}

pub fn drawEdgeU64(data: *hypothesis.ConjectureData) !u64 {
    return edge_u64_values[try drawUsize(data, 0, edge_u64_values.len - 1, 0)];
}

pub fn drawLocation(data: *hypothesis.ConjectureData) !profile.Location {
    return .{
        .file = files[try drawUsize(data, 0, files.len - 1, 0)],
        .line = if (try data.drawBoolean()) try drawSmallU64(data, 1, 512, 10) else try drawEdgeU64(data),
    };
}

pub fn drawEvent(data: *hypothesis.ConjectureData) !profile.Event {
    return switch (try drawUsize(data, 0, 5, 1)) {
        0 => .{ .startup = .{ .timestamp_ns = try drawEdgeU64(data) } },
        1 => .{ .experiment = .{
            .selected = try drawLocation(data),
            .virtual_speedup = virtual_speedups[try drawUsize(data, 0, virtual_speedups.len - 1, 0)],
            .duration_ns = try drawSmallU64(data, 1, 5000, 100),
            .selected_samples = try drawSmallU64(data, 0, 32, 1),
        } },
        2 => .{ .throughput = .{
            .name = point_names[try drawUsize(data, 0, point_names.len - 1, 0)],
            .delta = try drawSmallU64(data, 0, 256, 8),
        } },
        3 => .{ .latency = .{
            .name = point_names[try drawUsize(data, 0, point_names.len - 1, 1)],
            .arrivals = try drawSmallU64(data, 0, 256, 8),
            .departures = try drawSmallU64(data, 0, 256, 8),
            .outstanding = try drawSmallU64(data, 0, 64, 1),
        } },
        4 => .{ .runtime = .{ .duration_ns = try drawEdgeU64(data) } },
        else => .{ .sample = .{
            .location = try drawLocation(data),
            .count = try drawEdgeU64(data),
        } },
    };
}

pub fn drawEvents(
    data: *hypothesis.ConjectureData,
    allocator: std.mem.Allocator,
) ![]profile.Event {
    var events: std.ArrayList(profile.Event) = .empty;
    errdefer events.deinit(allocator);

    try appendSeedEvents(&events, allocator);

    const count = try drawUsize(data, 0, 40, 8);
    var index: usize = 0;
    while (index < count) : (index += 1) {
        try events.append(allocator, try drawEvent(data));
    }
    try events.append(allocator, .{ .sampling = try drawSampling(data) });

    return try events.toOwnedSlice(allocator);
}

fn drawSampling(data: *hypothesis.ConjectureData) !profile.Sampling {
    const sample_record_count = try drawSmallU64(data, 0, 64, 8);
    const lost_record_count = try drawSmallU64(data, 0, 4, 0);
    const lost_samples_record_count = try drawSmallU64(data, 0, 4, 0);
    const throttle_record_count = try drawSmallU64(data, 0, 4, 0);
    const unthrottle_record_count = try drawSmallU64(data, 0, 4, 0);
    const known = sample_record_count + lost_record_count + lost_samples_record_count +
        throttle_record_count + unthrottle_record_count;
    return .{
        .record_count = known + try drawSmallU64(data, 0, 8, 0),
        .sample_record_count = sample_record_count,
        .lost_record_count = lost_record_count,
        .lost_event_count = try drawSmallU64(data, 0, 16, 0),
        .lost_samples_record_count = lost_samples_record_count,
        .lost_samples_count = try drawSmallU64(data, 0, 16, 0),
        .throttle_record_count = throttle_record_count,
        .unthrottle_record_count = unthrottle_record_count,
        .loss_counter = switch (try drawUsize(data, 0, 2, 0)) {
            0 => .{ .available = try drawSmallU64(data, 0, 16, 0) },
            1 => .unsupported,
            else => .read_failed,
        },
        .terminal_status = switch (try drawUsize(data, 0, 3, 0)) {
            0 => .complete,
            1 => .not_started,
            2 => .stop_failed,
            else => .drain_failed,
        },
    };
}

fn appendSeedEvents(events: *std.ArrayList(profile.Event), allocator: std.mem.Allocator) !void {
    try events.append(allocator, .{ .startup = .{ .timestamp_ns = std.math.maxInt(u64) } });
    try events.append(allocator, .{ .experiment = .{
        .selected = .{ .file = "src/work.zig", .line = 10 },
        .virtual_speedup = 0,
        .duration_ns = 100,
        .selected_samples = 2,
    } });
    try events.append(allocator, .{ .throughput = .{
        .name = "items",
        .delta = 10,
    } });
    try events.append(allocator, .{ .experiment = .{
        .selected = .{ .file = "src/work.zig", .line = 10 },
        .virtual_speedup = 0.5,
        .duration_ns = 80,
        .selected_samples = 3,
    } });
    try events.append(allocator, .{ .throughput = .{
        .name = "items",
        .delta = 10,
    } });
    try events.append(allocator, .{ .experiment = .{
        .selected = .{ .file = "src/work.zig", .line = 20 },
        .virtual_speedup = 0,
        .duration_ns = 120,
        .selected_samples = 2,
    } });
    try events.append(allocator, .{ .latency = .{
        .name = "request",
        .arrivals = 12,
        .departures = 10,
        .outstanding = 6,
    } });
    try events.append(allocator, .{ .experiment = .{
        .selected = .{ .file = "src/work.zig", .line = 20 },
        .virtual_speedup = 0.5,
        .duration_ns = 90,
        .selected_samples = 3,
    } });
    try events.append(allocator, .{ .latency = .{
        .name = "request",
        .arrivals = 12,
        .departures = 12,
        .outstanding = 4,
    } });
}
