const std = @import("std");
const observe = @import("alloc_observe");
const pretty_json = @import("pretty").json;

pub const format_version: u32 = 3;

pub const Layer = enum {
    backing_boundary,
    logical_allocator,
    physical_page,

    pub fn tag(self: Layer) []const u8 {
        return @tagName(self);
    }

    pub fn fromTag(text: []const u8) ?Layer {
        return std.meta.stringToEnum(Layer, text);
    }
};

pub const LayerFilter = enum {
    backing,
    logical,
    physical,
    all,

    pub fn includes(self: LayerFilter, layer: Layer) bool {
        return switch (self) {
            .backing => layer == .backing_boundary,
            .logical => layer == .logical_allocator,
            .physical => layer == .physical_page,
            .all => true,
        };
    }

    pub fn tag(self: LayerFilter) []const u8 {
        return @tagName(self);
    }

    pub fn fromTag(text: []const u8) ?LayerFilter {
        return std.meta.stringToEnum(LayerFilter, text);
    }
};

pub const Kind = enum {
    trace_start,
    trace_stop,
    allocator,
    scope_enter,
    scope_exit,
    alloc,
    free,
    release,
    resize,
    remap,
    lifecycle,
    map,
    unmap,
    protect,
    discard,
    decommit,
    snapshot,
    census,
    advise,

    pub fn tag(self: Kind) []const u8 {
        return switch (self) {
            .trace_start => "trace.start",
            .trace_stop => "trace.stop",
            .allocator => "allocator",
            .scope_enter => "scope.enter",
            .scope_exit => "scope.exit",
            .alloc => "alloc",
            .free => "free",
            .release => "release",
            .resize => "resize",
            .remap => "remap",
            .lifecycle => "lifecycle",
            .map => "map",
            .unmap => "unmap",
            .protect => "protect",
            .discard => "discard",
            .decommit => "decommit",
            .advise => "advise",
            .snapshot => "snapshot",
            .census => "census",
        };
    }

    pub fn fromTag(text: []const u8) ?Kind {
        if (std.mem.eql(u8, text, "trace.start")) return .trace_start;
        if (std.mem.eql(u8, text, "trace.stop")) return .trace_stop;
        if (std.mem.eql(u8, text, "allocator")) return .allocator;
        if (std.mem.eql(u8, text, "scope.enter")) return .scope_enter;
        if (std.mem.eql(u8, text, "scope.exit")) return .scope_exit;
        if (std.mem.eql(u8, text, "alloc")) return .alloc;
        if (std.mem.eql(u8, text, "free")) return .free;
        if (std.mem.eql(u8, text, "release")) return .release;
        if (std.mem.eql(u8, text, "resize")) return .resize;
        if (std.mem.eql(u8, text, "remap")) return .remap;
        if (std.mem.eql(u8, text, "lifecycle")) return .lifecycle;
        if (std.mem.eql(u8, text, "map")) return .map;
        if (std.mem.eql(u8, text, "unmap")) return .unmap;
        if (std.mem.eql(u8, text, "protect")) return .protect;
        if (std.mem.eql(u8, text, "discard")) return .discard;
        if (std.mem.eql(u8, text, "decommit")) return .decommit;
        if (std.mem.eql(u8, text, "advise")) return .advise;
        if (std.mem.eql(u8, text, "snapshot")) return .snapshot;
        if (std.mem.eql(u8, text, "census")) return .census;
        return null;
    }

    pub fn isMemoryOperation(self: Kind) bool {
        return switch (self) {
            .alloc,
            .free,
            .release,
            .resize,
            .remap,
            .map,
            .unmap,
            .protect,
            .discard,
            .decommit,
            .advise,
            => true,
            else => false,
        };
    }
};

pub const Event = struct {
    seq: u64 = 0,
    kind: Kind,
    allocator_id: u32 = 0,
    allocation_id: u64 = 0,
    scope_id: u32 = 0,
    label_id: u32 = 0,
    address: usize = 0,
    old_address: usize = 0,
    len: usize = 0,
    old_len: usize = 0,
    alignment: u32 = 0,
    return_address: usize = 0,
    stack_id: u32 = 0,
    succeeded: bool = true,
    tracked: bool = true,
    live_bytes: usize = 0,
    recording_failures: u64 = 0,
    retains_freed_memory: bool = false,
    layer: Layer = .backing_boundary,
    operation_id: u64 = 0,
    parent_operation_id: u64 = 0,
    producer_id: u64 = 0,
    producer: observe.Producer = .boundary,
    generation: u64 = 0,
    owner_cookie: usize = 0,
    lifecycle_disposition: observe.LifecycleDisposition = .none,
    lifecycle_reason: observe.LifecycleReason = .none,
    lifecycle_instrumented: bool = false,
    observation_prefix_complete: bool = true,

    pub fn writeJsonLine(
        self: Event,
        writer: *std.Io.Writer,
        label_text: ?[]const u8,
        scope_text: ?[]const u8,
    ) !void {
        var stream = pretty_json.Writer.init(writer, .minified);
        const object = try stream.object();
        try object.field("v", format_version);
        try object.field("seq", self.seq);
        try object.field("kind", self.kind.tag());
        if (self.allocator_id != 0) try object.field("allocator_id", self.allocator_id);
        if (self.allocation_id != 0) try object.field("allocation_id", self.allocation_id);
        if (self.scope_id != 0) try object.field("scope_id", self.scope_id);
        if (self.address != 0) try object.field("address", self.address);
        if (self.old_address != 0 and self.old_address != self.address) {
            try object.field("old_address", self.old_address);
        }
        if (self.len != 0) try object.field("len", self.len);
        if (self.old_len != 0) try object.field("old_len", self.old_len);
        if (self.alignment != 0) try object.field("alignment", self.alignment);
        if (self.return_address != 0) try object.field("return_address", self.return_address);
        if (self.stack_id != 0) try object.field("stack_id", self.stack_id);
        if (!self.succeeded) try object.field("succeeded", false);
        if (!self.tracked) try object.field("tracked", false);
        if (self.recording_failures != 0) {
            try object.field("recording_failures", self.recording_failures);
        }
        if (self.retains_freed_memory) try object.field("retains_freed_memory", true);
        if (self.layer != .backing_boundary) try object.field("layer", self.layer.tag());
        if (self.operation_id != 0) try object.field("operation_id", self.operation_id);
        if (self.parent_operation_id != 0) {
            try object.field("parent_operation_id", self.parent_operation_id);
        }
        if (self.producer_id != 0) try object.field("producer_id", self.producer_id);
        if (self.producer != .boundary) try object.field("producer", @tagName(self.producer));
        if (self.generation != 0) try object.field("generation", self.generation);
        if (self.owner_cookie != 0) try object.field("owner_cookie", self.owner_cookie);
        if (self.lifecycle_disposition != .none) {
            try object.field(
                "lifecycle_disposition",
                @tagName(self.lifecycle_disposition),
            );
        }
        if (self.lifecycle_reason != .none) {
            try object.field("lifecycle_reason", @tagName(self.lifecycle_reason));
        }
        if (self.lifecycle_instrumented) {
            try object.field("lifecycle_instrumented", true);
        }
        if (!self.observation_prefix_complete) {
            try object.field("observation_prefix_complete", false);
        }
        if (label_text) |text| try object.field("label", text);
        if (scope_text) |text| try object.field("scope", text);
        try object.endLine();
    }
};

pub const ReplayEvent = struct {
    seq: ?u64 = null,
    kind: Kind,
    allocator_id: u32 = 0,
    allocation_id: u64 = 0,
    scope_id: u32 = 0,
    address: u64 = 0,
    old_address: u64 = 0,
    len: usize = 0,
    old_len: usize = 0,
    alignment: u32 = 0,
    return_address: u64 = 0,
    stack_id: u32 = 0,
    succeeded: bool = true,
    tracked: bool = true,
    recording_failures: u64 = 0,
    scope: []const u8 = "root",
    retains_freed_memory: bool = false,
    layer: Layer = .backing_boundary,
    operation_id: u64 = 0,
    parent_operation_id: u64 = 0,
    producer_id: u64 = 0,
    producer: observe.Producer = .boundary,
    generation: u64 = 0,
    owner_cookie: u64 = 0,
    lifecycle_disposition: observe.LifecycleDisposition = .none,
    lifecycle_reason: observe.LifecycleReason = .none,
    lifecycle_instrumented: bool = false,
    observation_prefix_complete: bool = true,
};

const CanonicalCursor = struct {
    line: []const u8,
    index: usize = 0,

    fn expect(self: *CanonicalCursor, expected: []const u8) !void {
        if (!std.mem.startsWith(u8, self.line[self.index..], expected)) return error.UnsupportedFastEvent;
        self.index += expected.len;
    }

    fn consume(self: *CanonicalCursor, expected: []const u8) bool {
        if (!std.mem.startsWith(u8, self.line[self.index..], expected)) return false;
        self.index += expected.len;
        return true;
    }

    fn unsigned(self: *CanonicalCursor) !u64 {
        var value: u64 = 0;
        var digits: usize = 0;
        while (self.index < self.line.len and self.line[self.index] >= '0' and self.line[self.index] <= '9') : (self.index += 1) {
            const digit: u64 = self.line[self.index] - '0';
            if (digits == 19) {
                if (value > std.math.maxInt(u64) / 10 or
                    (value == std.math.maxInt(u64) / 10 and digit > std.math.maxInt(u64) % 10)) return error.InvalidEventJson;
            } else if (digits > 19) {
                return error.UnsupportedFastEvent;
            }
            value = value * 10 + digit;
            digits += 1;
        }
        if (digits == 0) return error.UnsupportedFastEvent;
        return value;
    }

    fn skipUnsigned(self: *CanonicalCursor) !void {
        const start = self.index;
        while (self.index < self.line.len and self.line[self.index] >= '0' and self.line[self.index] <= '9') : (self.index += 1) {}
        if (self.index == start) return error.UnsupportedFastEvent;
    }

    fn string(self: *CanonicalCursor) ![]const u8 {
        try self.expect("\"");
        const start = self.index;
        while (self.index < self.line.len) : (self.index += 1) {
            switch (self.line[self.index]) {
                '"' => {
                    const value = self.line[start..self.index];
                    self.index += 1;
                    return value;
                },
                '\\' => return error.UnsupportedFastEvent,
                else => {},
            }
        }
        return error.InvalidEventJson;
    }

    fn boolean(self: *CanonicalCursor) !bool {
        if (self.consume("true")) return true;
        if (self.consume("false")) return false;
        return error.UnsupportedFastEvent;
    }

    fn finish(self: *CanonicalCursor) !void {
        try self.expect("}");
        if (self.index != self.line.len) return error.UnsupportedFastEvent;
    }
};

pub fn parseReplayFast(line: []const u8) !ReplayEvent {
    return parseSparseCanonical(line) catch |sparse_err| switch (sparse_err) {
        error.UnsupportedFastEvent => parseCanonical(line) catch |dense_err| switch (dense_err) {
            error.UnsupportedFastEvent => parseFlat(line),
            else => return dense_err,
        },
        else => return sparse_err,
    };
}

fn parseSparseCanonical(line: []const u8) !ReplayEvent {
    var cursor = CanonicalCursor{ .line = line };
    try cursor.expect("{\"v\":");
    const version = try cursor.unsigned();
    if (version != format_version) return error.UnsupportedTraceVersion;
    try cursor.expect(",\"seq\":");
    const seq = try cursor.unsigned();
    try cursor.expect(",\"kind\":");
    const kind = Kind.fromTag(try cursor.string()) orelse
        return error.InvalidEventJson;
    const allocator_id = if (cursor.consume(",\"allocator_id\":"))
        std.math.cast(u32, try cursor.unsigned()) orelse
            return error.InvalidEventJson
    else
        0;
    const allocation_id = if (cursor.consume(",\"allocation_id\":"))
        try cursor.unsigned()
    else
        0;
    const scope_id = if (cursor.consume(",\"scope_id\":"))
        std.math.cast(u32, try cursor.unsigned()) orelse
            return error.InvalidEventJson
    else
        0;
    const address = if (cursor.consume(",\"address\":"))
        try cursor.unsigned()
    else
        0;
    const old_address = if (cursor.consume(",\"old_address\":"))
        try cursor.unsigned()
    else
        address;
    const len = if (cursor.consume(",\"len\":"))
        std.math.cast(usize, try cursor.unsigned()) orelse
            return error.InvalidEventJson
    else
        0;
    const old_len = if (cursor.consume(",\"old_len\":"))
        std.math.cast(usize, try cursor.unsigned()) orelse
            return error.InvalidEventJson
    else
        0;
    const alignment = if (cursor.consume(",\"alignment\":"))
        std.math.cast(u32, try cursor.unsigned()) orelse
            return error.InvalidEventJson
    else
        0;
    const return_address = if (cursor.consume(",\"return_address\":"))
        try cursor.unsigned()
    else
        0;
    const stack_id = if (cursor.consume(",\"stack_id\":"))
        std.math.cast(u32, try cursor.unsigned()) orelse
            return error.InvalidEventJson
    else
        0;
    const succeeded = if (cursor.consume(",\"succeeded\":"))
        try cursor.boolean()
    else
        true;
    const tracked = if (cursor.consume(",\"tracked\":"))
        try cursor.boolean()
    else
        true;
    const recording_failures =
        if (cursor.consume(",\"recording_failures\":"))
            try cursor.unsigned()
        else
            0;
    const retains_freed_memory =
        if (cursor.consume(",\"retains_freed_memory\":"))
            try cursor.boolean()
        else
            false;
    const layer = if (cursor.consume(",\"layer\":"))
        Layer.fromTag(try cursor.string()) orelse
            return error.InvalidEventJson
    else
        .backing_boundary;
    const operation_id = if (cursor.consume(",\"operation_id\":"))
        try cursor.unsigned()
    else
        0;
    const parent_operation_id =
        if (cursor.consume(",\"parent_operation_id\":"))
            try cursor.unsigned()
        else
            0;
    const producer_id = if (cursor.consume(",\"producer_id\":"))
        try cursor.unsigned()
    else
        0;
    const producer = if (cursor.consume(",\"producer\":"))
        std.meta.stringToEnum(observe.Producer, try cursor.string()) orelse
            return error.InvalidEventJson
    else
        .boundary;
    const generation = if (cursor.consume(",\"generation\":"))
        try cursor.unsigned()
    else
        0;
    const owner_cookie = if (cursor.consume(",\"owner_cookie\":"))
        try cursor.unsigned()
    else
        0;
    const lifecycle_disposition =
        if (cursor.consume(",\"lifecycle_disposition\":"))
            std.meta.stringToEnum(
                observe.LifecycleDisposition,
                try cursor.string(),
            ) orelse return error.InvalidEventJson
        else
            .none;
    const lifecycle_reason =
        if (cursor.consume(",\"lifecycle_reason\":"))
            std.meta.stringToEnum(
                observe.LifecycleReason,
                try cursor.string(),
            ) orelse return error.InvalidEventJson
        else
            .none;
    const lifecycle_instrumented =
        if (cursor.consume(",\"lifecycle_instrumented\":"))
            try cursor.boolean()
        else
            false;
    const observation_prefix_complete =
        if (cursor.consume(",\"observation_prefix_complete\":"))
            try cursor.boolean()
        else
            true;
    if (cursor.consume(",\"label\":")) _ = try cursor.string();
    const scope = if (cursor.consume(",\"scope\":"))
        try cursor.string()
    else
        "";
    try cursor.finish();
    return .{
        .seq = seq,
        .kind = kind,
        .allocator_id = allocator_id,
        .allocation_id = allocation_id,
        .scope_id = scope_id,
        .address = address,
        .old_address = old_address,
        .len = len,
        .old_len = old_len,
        .alignment = alignment,
        .return_address = return_address,
        .stack_id = stack_id,
        .succeeded = succeeded,
        .tracked = tracked,
        .recording_failures = recording_failures,
        .scope = scope,
        .retains_freed_memory = retains_freed_memory,
        .layer = layer,
        .operation_id = operation_id,
        .parent_operation_id = parent_operation_id,
        .producer_id = producer_id,
        .producer = producer,
        .generation = generation,
        .owner_cookie = owner_cookie,
        .lifecycle_disposition = lifecycle_disposition,
        .lifecycle_reason = lifecycle_reason,
        .lifecycle_instrumented = lifecycle_instrumented,
        .observation_prefix_complete = observation_prefix_complete,
    };
}

pub fn replayFromJsonObject(object: std.json.ObjectMap) !ReplayEvent {
    const version = try jsonU64(object.get("v") orelse return error.InvalidEventJson);
    if (version != format_version) return error.UnsupportedTraceVersion;

    const kind_text = try jsonString(object.get("kind") orelse return error.InvalidEventJson);
    const kind = Kind.fromTag(kind_text) orelse return error.InvalidEventJson;
    const allocator_id = std.math.cast(
        u32,
        try jsonU64Default(object, "allocator_id", 0),
    ) orelse return error.InvalidEventJson;
    const allocation_id = try jsonU64Default(object, "allocation_id", 0);
    const address = try jsonU64Default(object, "address", 0);
    const scope_id = std.math.cast(
        u32,
        try jsonU64Default(object, "scope_id", 0),
    ) orelse return error.InvalidEventJson;
    const len = std.math.cast(
        usize,
        try jsonU64Default(object, "len", 0),
    ) orelse return error.InvalidEventJson;
    const old_len = std.math.cast(
        usize,
        try jsonU64Default(object, "old_len", 0),
    ) orelse return error.InvalidEventJson;
    return .{
        .seq = try jsonOptionalU64(object, "seq"),
        .kind = kind,
        .allocator_id = allocator_id,
        .allocation_id = allocation_id,
        .scope_id = scope_id,
        .address = address,
        .old_address = try jsonU64Default(object, "old_address", address),
        .len = len,
        .old_len = old_len,
        .alignment = std.math.cast(
            u32,
            try jsonU64Default(object, "alignment", 0),
        ) orelse return error.InvalidEventJson,
        .return_address = try jsonU64Default(object, "return_address", 0),
        .stack_id = std.math.cast(
            u32,
            try jsonU64Default(object, "stack_id", 0),
        ) orelse return error.InvalidEventJson,
        .succeeded = try jsonBoolDefault(object, "succeeded", true),
        .tracked = try jsonBoolDefault(object, "tracked", true),
        .recording_failures = try jsonU64Default(
            object,
            "recording_failures",
            0,
        ),
        .scope = try jsonStringDefault(object, "scope", ""),
        .retains_freed_memory = try jsonBoolDefault(object, "retains_freed_memory", false),
        .layer = Layer.fromTag(
            try jsonStringDefault(
                object,
                "layer",
                Layer.backing_boundary.tag(),
            ),
        ) orelse return error.InvalidEventJson,
        .operation_id = try jsonU64Default(object, "operation_id", 0),
        .parent_operation_id = try jsonU64Default(
            object,
            "parent_operation_id",
            0,
        ),
        .producer_id = try jsonU64Default(object, "producer_id", 0),
        .producer = std.meta.stringToEnum(
            observe.Producer,
            try jsonStringDefault(object, "producer", "boundary"),
        ) orelse return error.InvalidEventJson,
        .generation = try jsonU64Default(object, "generation", 0),
        .owner_cookie = try jsonU64Default(object, "owner_cookie", 0),
        .lifecycle_disposition = std.meta.stringToEnum(
            observe.LifecycleDisposition,
            try jsonStringDefault(
                object,
                "lifecycle_disposition",
                "none",
            ),
        ) orelse return error.InvalidEventJson,
        .lifecycle_reason = std.meta.stringToEnum(
            observe.LifecycleReason,
            try jsonStringDefault(object, "lifecycle_reason", "none"),
        ) orelse return error.InvalidEventJson,
        .lifecycle_instrumented = try jsonBoolDefault(
            object,
            "lifecycle_instrumented",
            false,
        ),
        .observation_prefix_complete = try jsonBoolDefault(
            object,
            "observation_prefix_complete",
            true,
        ),
    };
}

fn parseCanonical(line: []const u8) !ReplayEvent {
    var cursor = CanonicalCursor{ .line = line };
    try cursor.expect("{\"v\":");
    const version = try cursor.unsigned();
    if (version != format_version) return error.UnsupportedTraceVersion;
    try cursor.expect(",\"seq\":");
    const seq = try cursor.unsigned();
    try cursor.expect(",\"kind\":");
    const kind = Kind.fromTag(try cursor.string()) orelse return error.InvalidEventJson;
    try cursor.expect(",\"allocator_id\":");
    const allocator_id = std.math.cast(u32, try cursor.unsigned()) orelse return error.InvalidEventJson;
    try cursor.expect(",\"allocation_id\":");
    const allocation_id = try cursor.unsigned();
    try cursor.expect(",\"scope_id\":");
    const scope_id = std.math.cast(u32, try cursor.unsigned()) orelse
        return error.InvalidEventJson;
    try cursor.expect(",\"label_id\":");
    try cursor.skipUnsigned();
    try cursor.expect(",\"address\":");
    const address = try cursor.unsigned();
    try cursor.expect(",\"old_address\":");
    const old_address = try cursor.unsigned();
    try cursor.expect(",\"len\":");
    const len = std.math.cast(usize, try cursor.unsigned()) orelse return error.InvalidEventJson;
    try cursor.expect(",\"old_len\":");
    const old_len = std.math.cast(usize, try cursor.unsigned()) orelse return error.InvalidEventJson;
    try cursor.expect(",\"alignment\":");
    const alignment = std.math.cast(u32, try cursor.unsigned()) orelse
        return error.InvalidEventJson;
    try cursor.expect(",\"return_address\":");
    const return_address = try cursor.unsigned();
    const stack_id = if (cursor.consume(",\"stack_id\":"))
        std.math.cast(u32, try cursor.unsigned()) orelse
            return error.InvalidEventJson
    else
        0;
    try cursor.expect(",\"succeeded\":");
    const succeeded = try cursor.boolean();
    const tracked = if (cursor.consume(",\"tracked\":"))
        try cursor.boolean()
    else
        true;
    try cursor.expect(",\"live_bytes\":");
    try cursor.skipUnsigned();
    try cursor.expect(",\"recording_failures\":");
    const recording_failures = try cursor.unsigned();
    try cursor.expect(",\"retains_freed_memory\":");
    const retains_freed_memory = try cursor.boolean();
    const layer = if (cursor.consume(",\"layer\":"))
        Layer.fromTag(try cursor.string()) orelse
            return error.InvalidEventJson
    else
        .backing_boundary;
    const operation_id = if (cursor.consume(",\"operation_id\":"))
        try cursor.unsigned()
    else
        0;
    const parent_operation_id = if (cursor.consume(",\"parent_operation_id\":"))
        try cursor.unsigned()
    else
        0;
    const producer_id = if (cursor.consume(",\"producer_id\":"))
        try cursor.unsigned()
    else
        0;
    const producer = if (cursor.consume(",\"producer\":"))
        std.meta.stringToEnum(observe.Producer, try cursor.string()) orelse
            return error.InvalidEventJson
    else
        .boundary;
    const generation = if (cursor.consume(",\"generation\":"))
        try cursor.unsigned()
    else
        0;
    const owner_cookie = if (cursor.consume(",\"owner_cookie\":"))
        try cursor.unsigned()
    else
        0;
    const lifecycle_disposition =
        if (cursor.consume(",\"lifecycle_disposition\":"))
            std.meta.stringToEnum(
                observe.LifecycleDisposition,
                try cursor.string(),
            ) orelse return error.InvalidEventJson
        else
            .none;
    const lifecycle_reason =
        if (cursor.consume(",\"lifecycle_reason\":"))
            std.meta.stringToEnum(
                observe.LifecycleReason,
                try cursor.string(),
            ) orelse return error.InvalidEventJson
        else
            .none;
    const lifecycle_instrumented =
        if (cursor.consume(",\"lifecycle_instrumented\":"))
            try cursor.boolean()
        else
            false;
    const observation_prefix_complete =
        if (cursor.consume(",\"observation_prefix_complete\":"))
            try cursor.boolean()
        else
            true;
    if (cursor.consume(",\"label\":")) _ = try cursor.string();
    const scope = if (cursor.consume(",\"scope\":")) try cursor.string() else "";
    try cursor.finish();
    return .{
        .seq = seq,
        .kind = kind,
        .allocator_id = allocator_id,
        .allocation_id = allocation_id,
        .scope_id = scope_id,
        .address = address,
        .old_address = old_address,
        .len = len,
        .old_len = old_len,
        .alignment = alignment,
        .return_address = return_address,
        .stack_id = stack_id,
        .succeeded = succeeded,
        .tracked = tracked,
        .recording_failures = recording_failures,
        .scope = scope,
        .retains_freed_memory = retains_freed_memory,
        .layer = layer,
        .operation_id = operation_id,
        .parent_operation_id = parent_operation_id,
        .producer_id = producer_id,
        .producer = producer,
        .generation = generation,
        .owner_cookie = owner_cookie,
        .lifecycle_disposition = lifecycle_disposition,
        .lifecycle_reason = lifecycle_reason,
        .lifecycle_instrumented = lifecycle_instrumented,
        .observation_prefix_complete = observation_prefix_complete,
    };
}

fn parseFlat(line: []const u8) !ReplayEvent {
    const version = try jsonU64Flat(line, "\"v\":", null);
    if (version != format_version) return error.UnsupportedTraceVersion;

    const kind_text = try jsonStringFlat(line, "\"kind\":", null);
    const kind = Kind.fromTag(kind_text) orelse return error.InvalidEventJson;
    const allocator_id = std.math.cast(
        u32,
        try jsonU64Flat(line, "\"allocator_id\":", 0),
    ) orelse return error.InvalidEventJson;
    const allocation_id = try jsonU64Flat(line, "\"allocation_id\":", 0);
    const address = try jsonU64Flat(line, "\"address\":", 0);
    const seq = try jsonU64Flat(line, "\"seq\":", 0);
    const scope_id = std.math.cast(
        u32,
        try jsonU64Flat(line, "\"scope_id\":", 0),
    ) orelse return error.InvalidEventJson;
    const len = std.math.cast(
        usize,
        try jsonU64Flat(line, "\"len\":", 0),
    ) orelse return error.InvalidEventJson;
    const old_len = std.math.cast(
        usize,
        try jsonU64Flat(line, "\"old_len\":", 0),
    ) orelse return error.InvalidEventJson;
    return .{
        .seq = if (seq == 0) null else seq,
        .kind = kind,
        .allocator_id = allocator_id,
        .allocation_id = allocation_id,
        .scope_id = scope_id,
        .address = address,
        .old_address = try jsonU64Flat(line, "\"old_address\":", address),
        .len = len,
        .old_len = old_len,
        .alignment = std.math.cast(
            u32,
            try jsonU64Flat(line, "\"alignment\":", 0),
        ) orelse return error.InvalidEventJson,
        .return_address = try jsonU64Flat(line, "\"return_address\":", 0),
        .stack_id = std.math.cast(
            u32,
            try jsonU64Flat(line, "\"stack_id\":", 0),
        ) orelse return error.InvalidEventJson,
        .succeeded = try jsonBoolFlat(line, "\"succeeded\":", true),
        .tracked = try jsonBoolFlat(line, "\"tracked\":", true),
        .recording_failures = try jsonU64Flat(
            line,
            "\"recording_failures\":",
            0,
        ),
        .scope = try jsonStringFlat(line, "\"scope\":", ""),
        .retains_freed_memory = try jsonBoolFlat(line, "\"retains_freed_memory\":", false),
        .layer = Layer.fromTag(
            try jsonStringFlat(
                line,
                "\"layer\":",
                Layer.backing_boundary.tag(),
            ),
        ) orelse return error.InvalidEventJson,
        .operation_id = try jsonU64Flat(line, "\"operation_id\":", 0),
        .parent_operation_id = try jsonU64Flat(
            line,
            "\"parent_operation_id\":",
            0,
        ),
        .producer_id = try jsonU64Flat(line, "\"producer_id\":", 0),
        .producer = std.meta.stringToEnum(
            observe.Producer,
            try jsonStringFlat(line, "\"producer\":", "boundary"),
        ) orelse return error.InvalidEventJson,
        .generation = try jsonU64Flat(line, "\"generation\":", 0),
        .owner_cookie = try jsonU64Flat(line, "\"owner_cookie\":", 0),
        .lifecycle_disposition = std.meta.stringToEnum(
            observe.LifecycleDisposition,
            try jsonStringFlat(
                line,
                "\"lifecycle_disposition\":",
                "none",
            ),
        ) orelse return error.InvalidEventJson,
        .lifecycle_reason = std.meta.stringToEnum(
            observe.LifecycleReason,
            try jsonStringFlat(line, "\"lifecycle_reason\":", "none"),
        ) orelse return error.InvalidEventJson,
        .lifecycle_instrumented = try jsonBoolFlat(
            line,
            "\"lifecycle_instrumented\":",
            false,
        ),
        .observation_prefix_complete = try jsonBoolFlat(
            line,
            "\"observation_prefix_complete\":",
            true,
        ),
    };
}

fn jsonU64Flat(line: []const u8, needle: []const u8, default: ?u64) !u64 {
    const start = std.mem.indexOf(u8, line, needle) orelse return default orelse return error.UnsupportedFastEvent;
    var index = start + needle.len;
    if (index >= line.len) return error.InvalidEventJson;
    const first = line[index];
    if (first < '0' or first > '9') return error.UnsupportedFastEvent;
    while (index < line.len and line[index] >= '0' and line[index] <= '9') : (index += 1) {}
    return std.fmt.parseUnsigned(u64, line[start + needle.len .. index], 10) catch error.InvalidEventJson;
}

fn jsonBoolFlat(line: []const u8, needle: []const u8, default: ?bool) !bool {
    const start = std.mem.indexOf(u8, line, needle) orelse return default orelse return error.UnsupportedFastEvent;
    const index = start + needle.len;
    if (std.mem.startsWith(u8, line[index..], "true")) return true;
    if (std.mem.startsWith(u8, line[index..], "false")) return false;
    return error.UnsupportedFastEvent;
}

fn jsonStringFlat(line: []const u8, needle: []const u8, default: ?[]const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, line, needle) orelse return default orelse return error.UnsupportedFastEvent;
    var index = start + needle.len;
    if (index >= line.len or line[index] != '"') return error.UnsupportedFastEvent;
    index += 1;
    const text_start = index;
    while (index < line.len) : (index += 1) {
        switch (line[index]) {
            '"' => return line[text_start..index],
            '\\' => return error.UnsupportedFastEvent,
            else => {},
        }
    }
    return error.InvalidEventJson;
}

fn jsonString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        else => error.InvalidEventJson,
    };
}

fn jsonStringDefault(object: std.json.ObjectMap, key: []const u8, default: []const u8) ![]const u8 {
    const value = object.get(key) orelse return default;
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

fn jsonOptionalU64(object: std.json.ObjectMap, key: []const u8) !?u64 {
    const value = object.get(key) orelse return null;
    return try jsonU64(value);
}

fn jsonBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |actual| actual,
        else => error.InvalidEventJson,
    };
}

fn jsonBoolDefault(object: std.json.ObjectMap, key: []const u8, default: bool) !bool {
    const value = object.get(key) orelse return default;
    return try jsonBool(value);
}

test "event json line includes identities and omits default fields" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try (Event{
        .seq = 7,
        .kind = .alloc,
        .allocation_id = 9,
        .scope_id = 3,
        .label_id = 2,
        .address = 128,
        .len = 64,
        .alignment = 8,
        .live_bytes = 64,
    }).writeJsonLine(&out.writer, "phase", "root/phase");

    const line = out.written();
    try std.testing.expect(std.mem.indexOf(u8, line, "\"kind\":\"alloc\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"label\":\"phase\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"scope\":\"root/phase\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"alignment\":8") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"live_bytes\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"retains_freed_memory\"") == null);
}

test "replay parser consumes sparse event writer output" {
    var bytes = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer bytes.deinit();
    try (Event{
        .seq = 19,
        .kind = .remap,
        .allocator_id = 7,
        .allocation_id = 11,
        .address = 8192,
        .old_address = 4096,
        .len = 96,
        .old_len = 64,
        .alignment = 16,
        .return_address = 0xabc,
        .live_bytes = 128,
        .retains_freed_memory = true,
    }).writeJsonLine(&bytes.writer, "heap", "root/phase");

    const line = std.mem.trimEnd(u8, bytes.written(), "\n");
    const parsed = try parseReplayFast(line);
    try std.testing.expectEqual(@as(?u64, 19), parsed.seq);
    try std.testing.expectEqual(Kind.remap, parsed.kind);
    try std.testing.expectEqual(@as(u32, 7), parsed.allocator_id);
    try std.testing.expectEqual(@as(u64, 11), parsed.allocation_id);
    try std.testing.expectEqual(@as(u64, 8192), parsed.address);
    try std.testing.expectEqual(@as(u64, 4096), parsed.old_address);
    try std.testing.expectEqual(@as(usize, 96), parsed.len);
    try std.testing.expectEqual(@as(usize, 64), parsed.old_len);
    try std.testing.expectEqual(@as(u32, 16), parsed.alignment);
    try std.testing.expectEqual(@as(u64, 0xabc), parsed.return_address);
    try std.testing.expectEqualStrings("root/phase", parsed.scope);
    try std.testing.expect(parsed.retains_freed_memory);
}

test "lifecycle identity round trips through sparse event writer" {
    var bytes = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer bytes.deinit();
    try (Event{
        .seq = 23,
        .kind = .lifecycle,
        .allocator_id = 4,
        .return_address = 0xdef,
        .layer = .logical_allocator,
        .operation_id = 31,
        .producer_id = 9,
        .producer = .arena,
        .generation = 5,
        .owner_cookie = 0x1234,
        .lifecycle_disposition = .invalidate,
        .lifecycle_reason = .reset,
    }).writeJsonLine(&bytes.writer, null, "root");

    const line = std.mem.trimEnd(u8, bytes.written(), "\n");
    const parsed = try parseReplayFast(line);
    try std.testing.expectEqual(Kind.lifecycle, parsed.kind);
    try std.testing.expectEqual(Layer.logical_allocator, parsed.layer);
    try std.testing.expectEqual(@as(u64, 5), parsed.generation);
    try std.testing.expectEqual(@as(u64, 0x1234), parsed.owner_cookie);
    try std.testing.expectEqual(
        observe.LifecycleDisposition.invalidate,
        parsed.lifecycle_disposition,
    );
    try std.testing.expectEqual(
        observe.LifecycleReason.reset,
        parsed.lifecycle_reason,
    );
}
