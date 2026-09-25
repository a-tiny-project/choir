const std = @import("std");
const pretty_json = @import("pretty").json;

pub const schema = "tracy.event/v0";
pub const format_version: u32 = 0;

pub const Kind = enum {
    start,
    stop,
    zone_begin,
    zone_end,
    zone_text,
    zone_name,
    zone_color,
    zone_value,
    frame,
    message,
    app_info,
    plot_config,
    plot,
    alloc,
    free,
    thread_name,
    fiber_enter,
    fiber_leave,
    fiber_name,
    gpu_context,
    gpu_context_name,
    gpu_zone_begin,
    gpu_zone_end,
    gpu_time,
    gpu_calibration,
    gpu_time_sync,
    gpu_annotation,
    gpu_annotation_name,
    thread_context,
    thread_pid,
    cpu_topology,
    sys_time,
    sys_power,
    hw_sample,
    sample,
    sample_frame,
    context_switch,
    thread_wakeup,
    lock_announce,
    lock_terminate,
    lock_wait,
    lock_obtain,
    lock_release,
    lock_shared_wait,
    lock_shared_obtain,
    lock_shared_release,
    lock_mark,
    lock_name,

    pub fn tag(self: Kind) []const u8 {
        return switch (self) {
            .start => "start",
            .stop => "stop",
            .zone_begin => "zone.begin",
            .zone_end => "zone.end",
            .zone_text => "zone.text",
            .zone_name => "zone.name",
            .zone_color => "zone.color",
            .zone_value => "zone.value",
            .frame => "frame",
            .message => "message",
            .app_info => "app.info",
            .plot_config => "plot.config",
            .plot => "plot",
            .alloc => "alloc",
            .free => "free",
            .thread_name => "thread.name",
            .fiber_enter => "fiber.enter",
            .fiber_leave => "fiber.leave",
            .fiber_name => "fiber.name",
            .gpu_context => "gpu.context",
            .gpu_context_name => "gpu.context.name",
            .gpu_zone_begin => "gpu.zone.begin",
            .gpu_zone_end => "gpu.zone.end",
            .gpu_time => "gpu.time",
            .gpu_calibration => "gpu.calibration",
            .gpu_time_sync => "gpu.time_sync",
            .gpu_annotation => "gpu.annotation",
            .gpu_annotation_name => "gpu.annotation.name",
            .thread_context => "thread.context",
            .thread_pid => "thread.pid",
            .cpu_topology => "cpu.topology",
            .sys_time => "sys.time",
            .sys_power => "sys.power",
            .hw_sample => "hw.sample",
            .sample => "sample",
            .sample_frame => "sample.frame",
            .context_switch => "context.switch",
            .thread_wakeup => "thread.wakeup",
            .lock_announce => "lock.announce",
            .lock_terminate => "lock.terminate",
            .lock_wait => "lock.wait",
            .lock_obtain => "lock.obtain",
            .lock_release => "lock.release",
            .lock_shared_wait => "lock.shared.wait",
            .lock_shared_obtain => "lock.shared.obtain",
            .lock_shared_release => "lock.shared.release",
            .lock_mark => "lock.mark",
            .lock_name => "lock.name",
        };
    }

    pub fn fromTag(text: []const u8) ?Kind {
        if (std.mem.eql(u8, text, "start")) return .start;
        if (std.mem.eql(u8, text, "stop")) return .stop;
        if (std.mem.eql(u8, text, "zone.begin")) return .zone_begin;
        if (std.mem.eql(u8, text, "zone.end")) return .zone_end;
        if (std.mem.eql(u8, text, "zone.text")) return .zone_text;
        if (std.mem.eql(u8, text, "zone.name")) return .zone_name;
        if (std.mem.eql(u8, text, "zone.color")) return .zone_color;
        if (std.mem.eql(u8, text, "zone.value")) return .zone_value;
        if (std.mem.eql(u8, text, "frame")) return .frame;
        if (std.mem.eql(u8, text, "message")) return .message;
        if (std.mem.eql(u8, text, "app.info")) return .app_info;
        if (std.mem.eql(u8, text, "plot.config")) return .plot_config;
        if (std.mem.eql(u8, text, "plot")) return .plot;
        if (std.mem.eql(u8, text, "alloc")) return .alloc;
        if (std.mem.eql(u8, text, "free")) return .free;
        if (std.mem.eql(u8, text, "thread.name")) return .thread_name;
        if (std.mem.eql(u8, text, "fiber.enter")) return .fiber_enter;
        if (std.mem.eql(u8, text, "fiber.leave")) return .fiber_leave;
        if (std.mem.eql(u8, text, "fiber.name")) return .fiber_name;
        if (std.mem.eql(u8, text, "gpu.context")) return .gpu_context;
        if (std.mem.eql(u8, text, "gpu.context.name")) return .gpu_context_name;
        if (std.mem.eql(u8, text, "gpu.zone.begin")) return .gpu_zone_begin;
        if (std.mem.eql(u8, text, "gpu.zone.end")) return .gpu_zone_end;
        if (std.mem.eql(u8, text, "gpu.time")) return .gpu_time;
        if (std.mem.eql(u8, text, "gpu.calibration")) return .gpu_calibration;
        if (std.mem.eql(u8, text, "gpu.time_sync")) return .gpu_time_sync;
        if (std.mem.eql(u8, text, "gpu.annotation")) return .gpu_annotation;
        if (std.mem.eql(u8, text, "gpu.annotation.name")) return .gpu_annotation_name;
        if (std.mem.eql(u8, text, "thread.context")) return .thread_context;
        if (std.mem.eql(u8, text, "thread.pid")) return .thread_pid;
        if (std.mem.eql(u8, text, "cpu.topology")) return .cpu_topology;
        if (std.mem.eql(u8, text, "sys.time")) return .sys_time;
        if (std.mem.eql(u8, text, "sys.power")) return .sys_power;
        if (std.mem.eql(u8, text, "hw.sample")) return .hw_sample;
        if (std.mem.eql(u8, text, "sample")) return .sample;
        if (std.mem.eql(u8, text, "sample.frame")) return .sample_frame;
        if (std.mem.eql(u8, text, "context.switch")) return .context_switch;
        if (std.mem.eql(u8, text, "thread.wakeup")) return .thread_wakeup;
        if (std.mem.eql(u8, text, "lock.announce")) return .lock_announce;
        if (std.mem.eql(u8, text, "lock.terminate")) return .lock_terminate;
        if (std.mem.eql(u8, text, "lock.wait")) return .lock_wait;
        if (std.mem.eql(u8, text, "lock.obtain")) return .lock_obtain;
        if (std.mem.eql(u8, text, "lock.release")) return .lock_release;
        if (std.mem.eql(u8, text, "lock.shared.wait")) return .lock_shared_wait;
        if (std.mem.eql(u8, text, "lock.shared.obtain")) return .lock_shared_obtain;
        if (std.mem.eql(u8, text, "lock.shared.release")) return .lock_shared_release;
        if (std.mem.eql(u8, text, "lock.mark")) return .lock_mark;
        if (std.mem.eql(u8, text, "lock.name")) return .lock_name;
        return null;
    }
};

pub const TraceEvent = struct {
    seq: u64 = 0,
    kind: Kind,
    time_ns: u64 = 0,
    thread: u64 = 0,
    id: u64 = 0,
    name: ?[]const u8 = null,
    text: ?[]const u8 = null,
    function: ?[]const u8 = null,
    file: ?[]const u8 = null,
    line: u32 = 0,
    column: u32 = 0,
    color: ?u32 = null,
    value_u64: ?u64 = null,
    value_i64: ?i64 = null,
    value_f64: ?f64 = null,
    address: u64 = 0,
    size: u64 = 0,
    depth: u32 = 0,
    cpu: ?u32 = null,
    prev_thread: u64 = 0,
    next_thread: u64 = 0,
    target_thread: u64 = 0,
    pid: u64 = 0,
    previous_cstate: ?u32 = null,
    prev_priority: ?i64 = null,
    next_priority: ?i64 = null,
    group_hint: ?i64 = null,
    gpu_context: ?u32 = null,
    gpu_query: ?u32 = null,
    gpu_time: ?i64 = null,
    gpu_period: ?f64 = null,
    gpu_cpu_delta_ns: ?i64 = null,
    gpu_context_type: ?[]const u8 = null,
    gpu_has_calibration: bool = false,
    gpu_serial: bool = false,
    gpu_annotation_id: ?i64 = null,
    cpu_package: ?u32 = null,
    cpu_die: ?u32 = null,
    cpu_core: ?u32 = null,
    power_delta_uj: ?u64 = null,
    hw_sample_kind: ?[]const u8 = null,
    plot_kind: ?[]const u8 = null,
    plot_unit: ?[]const u8 = null,
    plot_step: bool = false,
    plot_fill: bool = false,
    lock_kind: ?[]const u8 = null,
    sample_kind: ?[]const u8 = null,
    context_reason: ?[]const u8 = null,
    context_state: ?[]const u8 = null,

    pub fn writeJsonLine(self: TraceEvent, writer: *std.Io.Writer) !void {
        var stream = pretty_json.Writer.init(writer, .minified);
        const object = try stream.object();
        try object.field("schema", schema);
        try object.field("v", format_version);
        try object.field("seq", self.seq);
        try object.field("kind", self.kind.tag());
        try object.field("time_ns", self.time_ns);
        try object.field("thread", self.thread);
        if (self.id != 0) try object.field("id", self.id);
        if (self.name) |name| try object.field("name", name);
        if (self.text) |text| try object.field("text", text);
        if (self.function) |function| try object.field("function", function);
        if (self.file) |file| try object.field("file", file);
        if (self.line != 0) try object.field("line", self.line);
        if (self.column != 0) try object.field("column", self.column);
        if (self.color) |color| try object.field("color", color);
        if (self.value_u64) |value| try object.field("value_u64", value);
        if (self.value_i64) |value| try object.field("value_i64", value);
        if (self.value_f64) |value| {
            if (std.math.isFinite(value)) try object.field("value_f64", value);
        }
        if (self.address != 0) try object.field("address", self.address);
        if (self.size != 0) try object.field("size", self.size);
        if (self.depth != 0) try object.field("depth", self.depth);
        if (self.cpu) |cpu| try object.field("cpu", cpu);
        if (self.prev_thread != 0) try object.field("prev_thread", self.prev_thread);
        if (self.next_thread != 0) try object.field("next_thread", self.next_thread);
        if (self.target_thread != 0) try object.field("target_thread", self.target_thread);
        if (self.pid != 0) try object.field("pid", self.pid);
        if (self.previous_cstate) |previous_cstate| try object.field("previous_cstate", previous_cstate);
        if (self.prev_priority) |prev_priority| try object.field("prev_priority", prev_priority);
        if (self.next_priority) |next_priority| try object.field("next_priority", next_priority);
        if (self.group_hint) |group_hint| try object.field("group_hint", group_hint);
        if (self.gpu_context) |gpu_context| try object.field("gpu_context", gpu_context);
        if (self.gpu_query) |gpu_query| try object.field("gpu_query", gpu_query);
        if (self.gpu_time) |gpu_time| try object.field("gpu_time", gpu_time);
        if (self.gpu_period) |gpu_period| {
            if (std.math.isFinite(gpu_period)) try object.field("gpu_period", gpu_period);
        }
        if (self.gpu_cpu_delta_ns) |value| try object.field("gpu_cpu_delta_ns", value);
        if (self.gpu_context_type) |value| try object.field("gpu_context_type", value);
        if (self.gpu_has_calibration) try object.field("gpu_has_calibration", true);
        if (self.gpu_serial) try object.field("gpu_serial", true);
        if (self.gpu_annotation_id) |value| try object.field("gpu_annotation_id", value);
        if (self.cpu_package) |value| try object.field("cpu_package", value);
        if (self.cpu_die) |value| try object.field("cpu_die", value);
        if (self.cpu_core) |value| try object.field("cpu_core", value);
        if (self.power_delta_uj) |value| try object.field("power_delta_uj", value);
        if (self.hw_sample_kind) |value| try object.field("hw_sample_kind", value);
        if (self.plot_kind) |value| try object.field("plot_kind", value);
        if (self.plot_unit) |value| try object.field("plot_unit", value);
        if (self.plot_step) try object.field("plot_step", true);
        if (self.plot_fill) try object.field("plot_fill", true);
        if (self.lock_kind) |value| try object.field("lock_kind", value);
        if (self.sample_kind) |value| try object.field("sample_kind", value);
        if (self.context_reason) |value| try object.field("context_reason", value);
        if (self.context_state) |value| try object.field("context_state", value);
        try object.endLine();
    }
};

pub const Parsed = struct {
    tree: std.json.Parsed(std.json.Value),
    kind: Kind,
    seq: u64 = 0,
    time_ns: u64 = 0,
    thread: u64 = 0,
    id: u64 = 0,
    name: ?[]const u8 = null,
    text: ?[]const u8 = null,
    function: ?[]const u8 = null,
    file: ?[]const u8 = null,
    line: u32 = 0,
    column: u32 = 0,
    color: ?u32 = null,
    value_u64: ?u64 = null,
    value_i64: ?i64 = null,
    value_f64: ?f64 = null,
    address: u64 = 0,
    size: u64 = 0,
    depth: u32 = 0,
    cpu: ?u32 = null,
    prev_thread: u64 = 0,
    next_thread: u64 = 0,
    target_thread: u64 = 0,
    pid: u64 = 0,
    previous_cstate: ?u32 = null,
    prev_priority: ?i64 = null,
    next_priority: ?i64 = null,
    group_hint: ?i64 = null,
    gpu_context: ?u32 = null,
    gpu_query: ?u32 = null,
    gpu_time: ?i64 = null,
    gpu_period: ?f64 = null,
    gpu_cpu_delta_ns: ?i64 = null,
    gpu_context_type: ?[]const u8 = null,
    gpu_has_calibration: bool = false,
    gpu_serial: bool = false,
    gpu_annotation_id: ?i64 = null,
    cpu_package: ?u32 = null,
    cpu_die: ?u32 = null,
    cpu_core: ?u32 = null,
    power_delta_uj: ?u64 = null,
    hw_sample_kind: ?[]const u8 = null,
    plot_kind: ?[]const u8 = null,
    plot_unit: ?[]const u8 = null,
    plot_step: bool = false,
    plot_fill: bool = false,
    lock_kind: ?[]const u8 = null,
    sample_kind: ?[]const u8 = null,
    context_reason: ?[]const u8 = null,
    context_state: ?[]const u8 = null,

    pub fn deinit(self: *Parsed) void {
        self.tree.deinit();
        self.* = undefined;
    }
};

pub fn parseLine(allocator: std.mem.Allocator, line: []const u8) !Parsed {
    const text = std.mem.trim(u8, line, " \t\r\n");
    if (text.len == 0) return error.EmptyEventLine;
    var tree = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        return error.InvalidEventJson;
    };
    errdefer tree.deinit();
    const object = switch (tree.value) {
        .object => |object| object,
        else => return error.InvalidEventJson,
    };
    if (object.get("schema")) |value| {
        const actual_schema = try jsonString(value);
        if (!std.mem.eql(u8, actual_schema, schema)) return error.UnsupportedTraceSchema;
    }
    const version = try jsonU64(object.get("v") orelse return error.InvalidEventJson);
    if (version != format_version) return error.UnsupportedTraceVersion;
    const kind_text = try jsonString(object.get("kind") orelse return error.InvalidEventJson);
    return .{
        .tree = tree,
        .kind = Kind.fromTag(kind_text) orelse return error.InvalidEventJson,
        .seq = try jsonU64Default(object, "seq", 0),
        .time_ns = try jsonU64Default(object, "time_ns", 0),
        .thread = try jsonU64Default(object, "thread", 0),
        .id = try jsonU64Default(object, "id", 0),
        .name = try jsonStringOptional(object, "name"),
        .text = try jsonStringOptional(object, "text"),
        .function = try jsonStringOptional(object, "function"),
        .file = try jsonStringOptional(object, "file"),
        .line = @intCast(try jsonU64Default(object, "line", 0)),
        .column = @intCast(try jsonU64Default(object, "column", 0)),
        .color = try jsonU32Optional(object, "color"),
        .value_u64 = try jsonU64Optional(object, "value_u64"),
        .value_i64 = try jsonI64Optional(object, "value_i64"),
        .value_f64 = try jsonF64Optional(object, "value_f64"),
        .address = try jsonU64Default(object, "address", 0),
        .size = try jsonU64Default(object, "size", 0),
        .depth = @intCast(try jsonU64Default(object, "depth", 0)),
        .cpu = try jsonU32Optional(object, "cpu"),
        .prev_thread = try jsonU64Default(object, "prev_thread", 0),
        .next_thread = try jsonU64Default(object, "next_thread", 0),
        .target_thread = try jsonU64Default(object, "target_thread", 0),
        .pid = try jsonU64Default(object, "pid", 0),
        .previous_cstate = try jsonU32Optional(object, "previous_cstate"),
        .prev_priority = try jsonI64Optional(object, "prev_priority"),
        .next_priority = try jsonI64Optional(object, "next_priority"),
        .group_hint = try jsonI64Optional(object, "group_hint"),
        .gpu_context = try jsonU32Optional(object, "gpu_context"),
        .gpu_query = try jsonU32Optional(object, "gpu_query"),
        .gpu_time = try jsonI64Optional(object, "gpu_time"),
        .gpu_period = try jsonF64Optional(object, "gpu_period"),
        .gpu_cpu_delta_ns = try jsonI64Optional(object, "gpu_cpu_delta_ns"),
        .gpu_context_type = try jsonStringOptional(object, "gpu_context_type"),
        .gpu_has_calibration = try jsonBoolDefault(object, "gpu_has_calibration", false),
        .gpu_serial = try jsonBoolDefault(object, "gpu_serial", false),
        .gpu_annotation_id = try jsonI64Optional(object, "gpu_annotation_id"),
        .cpu_package = try jsonU32Optional(object, "cpu_package"),
        .cpu_die = try jsonU32Optional(object, "cpu_die"),
        .cpu_core = try jsonU32Optional(object, "cpu_core"),
        .power_delta_uj = try jsonU64Optional(object, "power_delta_uj"),
        .hw_sample_kind = try jsonStringOptional(object, "hw_sample_kind"),
        .plot_kind = try jsonStringOptional(object, "plot_kind"),
        .plot_unit = try jsonStringOptional(object, "plot_unit"),
        .plot_step = try jsonBoolDefault(object, "plot_step", false),
        .plot_fill = try jsonBoolDefault(object, "plot_fill", false),
        .lock_kind = try jsonStringOptional(object, "lock_kind"),
        .sample_kind = try jsonStringOptional(object, "sample_kind"),
        .context_reason = try jsonStringOptional(object, "context_reason"),
        .context_state = try jsonStringOptional(object, "context_state"),
    };
}

fn jsonString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        else => error.InvalidEventJson,
    };
}

fn jsonStringOptional(object: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const value = object.get(key) orelse return null;
    return try jsonString(value);
}

fn jsonU64(value: std.json.Value) !u64 {
    return switch (value) {
        .integer => |integer| if (integer < 0) error.InvalidEventJson else @intCast(integer),
        else => error.InvalidEventJson,
    };
}

fn jsonU64Default(object: std.json.ObjectMap, key: []const u8, default: u64) !u64 {
    const value = object.get(key) orelse return default;
    return try jsonU64(value);
}

fn jsonU64Optional(object: std.json.ObjectMap, key: []const u8) !?u64 {
    const value = object.get(key) orelse return null;
    return try jsonU64(value);
}

fn jsonU32Optional(object: std.json.ObjectMap, key: []const u8) !?u32 {
    const value = object.get(key) orelse return null;
    return @intCast(try jsonU64(value));
}

fn jsonI64(value: std.json.Value) !i64 {
    return switch (value) {
        .integer => |integer| @intCast(integer),
        else => error.InvalidEventJson,
    };
}

fn jsonI64Optional(object: std.json.ObjectMap, key: []const u8) !?i64 {
    const value = object.get(key) orelse return null;
    return try jsonI64(value);
}

fn jsonF64(value: std.json.Value) !f64 {
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| float,
        else => error.InvalidEventJson,
    };
}

fn jsonF64Optional(object: std.json.ObjectMap, key: []const u8) !?f64 {
    const value = object.get(key) orelse return null;
    return try jsonF64(value);
}

fn jsonBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |boolean| boolean,
        else => error.InvalidEventJson,
    };
}

fn jsonBoolDefault(object: std.json.ObjectMap, key: []const u8, default: bool) !bool {
    const value = object.get(key) orelse return default;
    return try jsonBool(value);
}

test "event json parses written zone begin" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try (TraceEvent{
        .seq = 7,
        .kind = .zone_begin,
        .time_ns = 100,
        .thread = 2,
        .id = 9,
        .name = "phase",
        .function = "run",
        .file = "run.zig",
        .line = 12,
        .color = 0x44aa88,
    }).writeJsonLine(&out.writer);

    var parsed = try parseLine(std.testing.allocator, out.written());
    defer parsed.deinit();
    try std.testing.expectEqual(Kind.zone_begin, parsed.kind);
    try std.testing.expectEqual(@as(u64, 9), parsed.id);
    try std.testing.expectEqualStrings("phase", parsed.name.?);
    try std.testing.expectEqualStrings("run.zig", parsed.file.?);
    try std.testing.expectEqual(@as(?u32, 0x44aa88), parsed.color);
}

test "event json parses sample frame metadata" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try (TraceEvent{
        .seq = 8,
        .kind = .sample_frame,
        .time_ns = 120,
        .thread = 3,
        .id = 4,
        .depth = 2,
        .name = "leaf",
        .function = "run",
        .file = "run.zig",
        .line = 14,
        .sample_kind = "cpu",
    }).writeJsonLine(&out.writer);

    var parsed = try parseLine(std.testing.allocator, out.written());
    defer parsed.deinit();
    try std.testing.expectEqual(Kind.sample_frame, parsed.kind);
    try std.testing.expectEqual(@as(u32, 2), parsed.depth);
    try std.testing.expectEqualStrings("cpu", parsed.sample_kind.?);
}

test "event json parses context switch metadata" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try (TraceEvent{
        .seq = 9,
        .kind = .context_switch,
        .time_ns = 150,
        .thread = 3,
        .cpu = 0,
        .prev_thread = 10,
        .next_thread = 11,
        .previous_cstate = 1,
        .prev_priority = 8,
        .next_priority = 9,
        .context_reason = "WrPreempted",
        .context_state = "Ready",
    }).writeJsonLine(&out.writer);

    var parsed = try parseLine(std.testing.allocator, out.written());
    defer parsed.deinit();
    try std.testing.expectEqual(Kind.context_switch, parsed.kind);
    try std.testing.expectEqual(@as(?u32, 0), parsed.cpu);
    try std.testing.expectEqual(@as(u64, 10), parsed.prev_thread);
    try std.testing.expectEqual(@as(u64, 11), parsed.next_thread);
    try std.testing.expectEqual(@as(?u32, 1), parsed.previous_cstate);
    try std.testing.expectEqual(@as(?i64, 8), parsed.prev_priority);
    try std.testing.expectEqual(@as(?i64, 9), parsed.next_priority);
    try std.testing.expectEqualStrings("WrPreempted", parsed.context_reason.?);
    try std.testing.expectEqualStrings("Ready", parsed.context_state.?);
}

test "event json parses fiber metadata" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try (TraceEvent{
        .seq = 10,
        .kind = .fiber_enter,
        .time_ns = 200,
        .thread = 42,
        .id = 9,
        .name = "job.apply",
        .group_hint = 3,
    }).writeJsonLine(&out.writer);

    var parsed = try parseLine(std.testing.allocator, out.written());
    defer parsed.deinit();
    try std.testing.expectEqual(Kind.fiber_enter, parsed.kind);
    try std.testing.expectEqual(@as(u64, 9), parsed.id);
    try std.testing.expectEqual(@as(u64, 42), parsed.thread);
    try std.testing.expectEqualStrings("job.apply", parsed.name.?);
    try std.testing.expectEqual(@as(?i64, 3), parsed.group_hint);
}

test "event json parses gpu metadata" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try (TraceEvent{
        .seq = 11,
        .kind = .gpu_context,
        .time_ns = 300,
        .thread = 4,
        .name = "render",
        .gpu_context = 2,
        .gpu_time = 1000,
        .gpu_period = 2.0,
        .gpu_context_type = "vulkan",
        .gpu_has_calibration = true,
        .gpu_serial = true,
    }).writeJsonLine(&out.writer);

    var parsed = try parseLine(std.testing.allocator, out.written());
    defer parsed.deinit();
    try std.testing.expectEqual(Kind.gpu_context, parsed.kind);
    try std.testing.expectEqual(@as(?u32, 2), parsed.gpu_context);
    try std.testing.expectEqual(@as(?i64, 1000), parsed.gpu_time);
    try std.testing.expectEqual(@as(?f64, 2.0), parsed.gpu_period);
    try std.testing.expectEqualStrings("vulkan", parsed.gpu_context_type.?);
    try std.testing.expect(parsed.gpu_has_calibration);
    try std.testing.expect(parsed.gpu_serial);
}

test "event json parses system metadata" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try (TraceEvent{
        .seq = 12,
        .kind = .hw_sample,
        .time_ns = 400,
        .thread = 9,
        .cpu = 3,
        .address = 0x1234,
        .pid = 77,
        .cpu_package = 1,
        .cpu_die = 2,
        .cpu_core = 4,
        .power_delta_uj = 500,
        .hw_sample_kind = "cache-miss",
    }).writeJsonLine(&out.writer);

    var parsed = try parseLine(std.testing.allocator, out.written());
    defer parsed.deinit();
    try std.testing.expectEqual(Kind.hw_sample, parsed.kind);
    try std.testing.expectEqual(@as(u64, 9), parsed.thread);
    try std.testing.expectEqual(@as(?u32, 3), parsed.cpu);
    try std.testing.expectEqual(@as(u64, 0x1234), parsed.address);
    try std.testing.expectEqual(@as(u64, 77), parsed.pid);
    try std.testing.expectEqual(@as(?u32, 1), parsed.cpu_package);
    try std.testing.expectEqual(@as(?u32, 2), parsed.cpu_die);
    try std.testing.expectEqual(@as(?u32, 4), parsed.cpu_core);
    try std.testing.expectEqual(@as(?u64, 500), parsed.power_delta_uj);
    try std.testing.expectEqualStrings("cache-miss", parsed.hw_sample_kind.?);
}
