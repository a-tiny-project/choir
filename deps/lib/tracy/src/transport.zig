const std = @import("std");
const pretty_json = @import("pretty").json;

const assert = std.debug.assert;

pub const schema = "tracy.flight/v0";

pub const OverflowPolicy = enum {
    overwrite_oldest,
    stop_when_full,

    pub fn tag(self: OverflowPolicy) []const u8 {
        return switch (self) {
            .overwrite_oldest => "overwrite_oldest",
            .stop_when_full => "stop_when_full",
        };
    }
};

pub const State = enum {
    accepting,
    full,

    pub fn tag(self: State) []const u8 {
        return switch (self) {
            .accepting => "accepting",
            .full => "full",
        };
    }
};

pub const Report = struct {
    policy: OverflowPolicy,
    state: State,
    capacity_bytes: usize,
    retained_bytes: usize,
    event_capacity_bytes: usize,
    writer_capacity_bytes: usize,
    observed_events: u64,
    stored_events: u64,
    retained_events: usize,
    overwritten_events: u64,
    dropped_events: u64,
    oversized_events: u64,
    partial_event_bytes: usize,
    discarding_oversized_event: bool,

    pub fn valid(self: Report) bool {
        if (self.capacity_bytes == 0) return false;
        if (self.event_capacity_bytes == 0) return false;
        if (self.writer_capacity_bytes == 0) return false;
        if (self.retained_bytes > self.capacity_bytes) return false;
        if (self.partial_event_bytes > self.event_capacity_bytes) return false;
        if (self.discarding_oversized_event and self.partial_event_bytes != 0) return false;
        const retained_events = std.math.cast(u64, self.retained_events) orelse return false;
        const retained_and_overwritten = retained_events +| self.overwritten_events;
        if (retained_and_overwritten != self.stored_events) return false;
        const rejected_events = self.dropped_events +| self.oversized_events;
        const accounted_events = self.stored_events +| rejected_events;
        if (accounted_events != self.observed_events) return false;
        if (self.policy == .overwrite_oldest and self.dropped_events != 0) return false;
        if (self.policy == .stop_when_full and self.overwritten_events != 0) return false;
        if (self.state == .full and self.policy != .stop_when_full) return false;
        return true;
    }

    pub fn writeJson(self: Report, writer: *std.Io.Writer) !void {
        assert(self.valid());
        var stream = pretty_json.Writer.init(writer, .minified);
        const object = try stream.object();
        try self.writeFields(object);
        try object.end();
    }

    pub fn writeFields(self: Report, object: pretty_json.Object) !void {
        assert(self.valid());
        try object.field("schema", schema);
        try object.field("policy", self.policy.tag());
        try object.field("state", self.state.tag());
        try object.field("capacity_bytes", self.capacity_bytes);
        try object.field("retained_bytes", self.retained_bytes);
        try object.field("event_capacity_bytes", self.event_capacity_bytes);
        try object.field("writer_capacity_bytes", self.writer_capacity_bytes);
        try object.field("observed_events", self.observed_events);
        try object.field("stored_events", self.stored_events);
        try object.field("retained_events", self.retained_events);
        try object.field("overwritten_events", self.overwritten_events);
        try object.field("dropped_events", self.dropped_events);
        try object.field("oversized_events", self.oversized_events);
        try object.field("partial_event_bytes", self.partial_event_bytes);
        try object.field("discarding_oversized_event", self.discarding_oversized_event);
    }

    pub fn writeJsonl(self: Report, writer: *std.Io.Writer) !void {
        try self.writeJson(writer);
        try writer.writeByte('\n');
    }
};

pub fn parseLine(allocator: std.mem.Allocator, line: []const u8) !Report {
    const text = std.mem.trim(u8, line, " \t\r\n");
    if (text.len == 0) return error.InvalidFlightReport;
    var tree = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        return error.InvalidFlightReport;
    };
    defer tree.deinit();
    const object = switch (tree.value) {
        .object => |object| object,
        else => return error.InvalidFlightReport,
    };
    const actual_schema = try jsonString(object, "schema");
    if (!std.mem.eql(u8, actual_schema, schema)) return error.UnsupportedTraceSchema;
    const result: Report = .{
        .policy = try jsonEnum(OverflowPolicy, object, "policy"),
        .state = try jsonEnum(State, object, "state"),
        .capacity_bytes = try jsonUsize(object, "capacity_bytes"),
        .retained_bytes = try jsonUsize(object, "retained_bytes"),
        .event_capacity_bytes = try jsonUsize(object, "event_capacity_bytes"),
        .writer_capacity_bytes = try jsonUsize(object, "writer_capacity_bytes"),
        .observed_events = try jsonU64(object, "observed_events"),
        .stored_events = try jsonU64(object, "stored_events"),
        .retained_events = try jsonUsize(object, "retained_events"),
        .overwritten_events = try jsonU64(object, "overwritten_events"),
        .dropped_events = try jsonU64(object, "dropped_events"),
        .oversized_events = try jsonU64(object, "oversized_events"),
        .partial_event_bytes = try jsonUsize(object, "partial_event_bytes"),
        .discarding_oversized_event = try jsonBool(object, "discarding_oversized_event"),
    };
    if (!result.valid()) return error.InvalidFlightReport;
    return result;
}

fn jsonString(object: std.json.ObjectMap, key: []const u8) ![]const u8 {
    return switch (object.get(key) orelse return error.InvalidFlightReport) {
        .string => |text| text,
        else => error.InvalidFlightReport,
    };
}

fn jsonEnum(comptime T: type, object: std.json.ObjectMap, key: []const u8) !T {
    return std.meta.stringToEnum(T, try jsonString(object, key)) orelse
        error.InvalidFlightReport;
}

fn jsonU64(object: std.json.ObjectMap, key: []const u8) !u64 {
    return switch (object.get(key) orelse return error.InvalidFlightReport) {
        .integer => |value| if (value < 0) error.InvalidFlightReport else @intCast(value),
        .number_string => |value| std.fmt.parseInt(u64, value, 10) catch
            error.InvalidFlightReport,
        else => error.InvalidFlightReport,
    };
}

fn jsonUsize(object: std.json.ObjectMap, key: []const u8) !usize {
    return std.math.cast(usize, try jsonU64(object, key)) orelse
        error.InvalidFlightReport;
}

fn jsonBool(object: std.json.ObjectMap, key: []const u8) !bool {
    return switch (object.get(key) orelse return error.InvalidFlightReport) {
        .bool => |value| value,
        else => error.InvalidFlightReport,
    };
}

test "transport report round trips" {
    const expected: Report = .{
        .policy = .stop_when_full,
        .state = .full,
        .capacity_bytes = 64,
        .retained_bytes = 32,
        .event_capacity_bytes = 16,
        .writer_capacity_bytes = 8,
        .observed_events = 7,
        .stored_events = 5,
        .retained_events = 5,
        .overwritten_events = 0,
        .dropped_events = 2,
        .oversized_events = 0,
        .partial_event_bytes = 0,
        .discarding_oversized_event = false,
    };
    var line = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer line.deinit();
    try expected.writeJsonl(&line.writer);
    const actual = try parseLine(std.testing.allocator, line.written());
    try std.testing.expectEqualDeep(expected, actual);
}

test "transport report rejects malformed rows" {
    try std.testing.expectError(
        error.UnsupportedTraceSchema,
        parseLine(std.testing.allocator, "{\"schema\":\"future/v0\"}"),
    );
    try std.testing.expectError(
        error.InvalidFlightReport,
        parseLine(std.testing.allocator, "{\"schema\":\"tracy.flight/v0\"}"),
    );
}
