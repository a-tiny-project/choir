const std = @import("std");

pub const Series = std.StringArrayHashMapUnmanaged(std.ArrayListUnmanaged(u64));

pub const Dataset = struct {
    wall: Series = .empty,
    rss: Series = .empty,
    allocators: std.StringArrayHashMapUnmanaged(void) = .empty,
    runs: u32 = 0,

    pub fn medians(self: *const Dataset, workload: []const u8) []const u64 {
        return seriesValues(&self.wall, workload);
    }

    pub fn rssMedians(self: *const Dataset, workload: []const u8) []const u64 {
        return seriesValues(&self.rss, workload);
    }
};

pub fn seriesValues(series: *const Series, workload: []const u8) []const u64 {
    const values = series.getPtr(workload) orelse return &.{};
    return values.items;
}

pub fn parse(arena: std.mem.Allocator, bytes: []const u8) !Dataset {
    var dataset: Dataset = .{};
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        const value = std.json.parseFromSliceLeaky(std.json.Value, arena, trimmed, .{}) catch continue;
        const object = switch (value) {
            .object => |object| object,
            else => continue,
        };
        const event = stringField(object, "event") orelse continue;
        if (std.mem.eql(u8, event, "run_start")) {
            dataset.runs += 1;
            if (stringField(object, "allocator")) |label| {
                const owned = try arena.dupe(u8, label);
                try dataset.allocators.put(arena, owned, {});
            }
            continue;
        }
        if (!std.mem.eql(u8, event, "summary")) continue;
        const workload = stringField(object, "workload") orelse continue;
        if (integerField(object, "median_ns")) |median_ns| {
            try appendSeries(arena, &dataset.wall, workload, median_ns);
        }
        if (integerField(object, "median_max_rss_kib")) |median_kib| {
            try appendSeries(arena, &dataset.rss, workload, median_kib);
        }
    }
    return dataset;
}

fn appendSeries(
    arena: std.mem.Allocator,
    series: *Series,
    workload: []const u8,
    value: u64,
) !void {
    const entry = try series.getOrPut(arena, workload);
    if (!entry.found_existing) {
        entry.key_ptr.* = try arena.dupe(u8, workload);
        entry.value_ptr.* = .empty;
    }
    try entry.value_ptr.append(arena, value);
}

fn stringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .string => |text| text,
        else => null,
    };
}

fn integerField(object: std.json.ObjectMap, name: []const u8) ?u64 {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .integer => |signed| if (signed < 0) null else @intCast(signed),
        .float => |real| if (real < 0) null else @intFromFloat(real),
        else => null,
    };
}

test "parse collects per-workload medians across runs" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const dataset = try parse(arena,
        \\{"event":"run_start","allocator":"gpalloc","warmup":3}
        \\{"event":"sample","workload":"small_churn","ns":12}
        \\{"event":"summary","workload":"small_churn","median_ns":100}
        \\{"event":"summary","workload":"redis_trace","median_ns":900}
        \\{"event":"run_end","benches":2}
        \\{"event":"run_start","allocator":"gpalloc","warmup":3}
        \\{"event":"summary","workload":"small_churn","median_ns":110}
        \\not json
        \\
    );
    try std.testing.expectEqual(@as(u32, 2), dataset.runs);
    try std.testing.expectEqual(@as(usize, 1), dataset.allocators.count());
    try std.testing.expectEqualSlices(u64, &.{ 100, 110 }, dataset.medians("small_churn"));
    try std.testing.expectEqualSlices(u64, &.{900}, dataset.medians("redis_trace"));
    try std.testing.expectEqual(@as(usize, 0), dataset.medians("missing").len);
    try std.testing.expectEqual(@as(usize, 0), dataset.rss.count());
}

test "parse collects rss series from external summaries" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const dataset = try parse(arena,
        \\{"event":"run_start","allocator":"libc"}
        \\{"event":"summary","workload":"cfrac","median_ns":100,"median_max_rss_kib":4096}
        \\{"event":"run_start","allocator":"libc"}
        \\{"event":"summary","workload":"cfrac","median_ns":102,"median_max_rss_kib":4224}
    );
    try std.testing.expectEqualSlices(u64, &.{ 100, 102 }, dataset.medians("cfrac"));
    try std.testing.expectEqualSlices(u64, &.{ 4096, 4224 }, dataset.rssMedians("cfrac"));
}

test "parse tolerates float medians and skips malformed rows" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const dataset = try parse(arena,
        \\{"event":"summary","workload":"w","median_ns":99.0}
        \\{"event":"summary","workload":"w"}
        \\{"event":"summary","median_ns":1}
        \\[1,2,3]
    );
    try std.testing.expectEqualSlices(u64, &.{99}, dataset.medians("w"));
}
