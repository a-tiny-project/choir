const std = @import("std");
const coz = @import("coz");
const hypothesis = @import("hypothesis");
const data = @import("data.zig");
const expect = @import("expect.zig");

const profile = coz.profile;
const analysis = coz.analysis;

pub const Property = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, property_allocator: std.mem.Allocator) !void {
        const events = try data.drawEvents(conjecture, property_allocator);
        defer property_allocator.free(events);

        for (events) |item| {
            try expectJsonRoundtrip(property_allocator, item);
        }

        var direct = try directSummary(property_allocator, events);
        defer direct.deinit(property_allocator);

        const bytes = try writeJsonLines(property_allocator, events);
        defer property_allocator.free(bytes);

        var replayed = try analysis.summarizeJsonLines(
            property_allocator,
            bytes,
            .{ .min_delta = 1, .min_points = 1 },
        );
        defer replayed.deinit(property_allocator);

        try expect.summaryEqual(direct, replayed);
        try expect.summaryInvariants(replayed);
    }
};

fn expectJsonRoundtrip(allocator: std.mem.Allocator, item: profile.Event) !void {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try item.writeJsonLine(&out.writer);
    const bytes = try out.toOwnedSlice();
    defer allocator.free(bytes);

    var parsed = try profile.parseJsonLine(allocator, bytes);
    defer parsed.deinit(allocator);

    try expect.eventEqual(item, parsed.event);
}

fn writeJsonLines(allocator: std.mem.Allocator, events: []const profile.Event) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    for (events) |item| {
        try item.writeJsonLine(&out.writer);
    }
    return try out.toOwnedSlice();
}

fn directSummary(allocator: std.mem.Allocator, events: []const profile.Event) !analysis.Summary {
    var accumulator: analysis.Accumulator = .{};
    defer accumulator.deinit(allocator);

    for (events) |item| {
        try accumulator.observe(allocator, item);
    }

    return try accumulator.summarize(allocator, .{ .min_delta = 1, .min_points = 1 });
}

test "property: profile JSONL replay preserves analysis summary" {
    try hypothesis.checkNamed(Property, "coz-profile-analysis-replay", data.settings());
}
