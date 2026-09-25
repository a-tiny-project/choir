const std = @import("std");
const pretty_json = @import("pretty").json;

const metadata_tag = "\"meta\":\"memtrace.coverage\"";

pub const Universe = enum {
    registered_allocator_handles,
    owned_allocator_producers_and_registered_boundaries,
    owned_allocator_producers_registered_boundaries_and_sys_memory_operations,
    process_memory_operations_during_trace_epoch,

    pub fn tag(self: Universe) []const u8 {
        return switch (self) {
            .registered_allocator_handles => "registered_allocator_handles",
            .owned_allocator_producers_and_registered_boundaries => "owned_allocator_producers_and_registered_boundaries",
            .owned_allocator_producers_registered_boundaries_and_sys_memory_operations => "owned_allocator_producers_registered_boundaries_and_sys_memory_operations",
            .process_memory_operations_during_trace_epoch => "process_memory_operations_during_trace_epoch",
        };
    }

    fn fromTag(text: []const u8) ?Universe {
        if (std.mem.eql(u8, text, "registered_allocator_handles")) {
            return .registered_allocator_handles;
        }
        if (std.mem.eql(
            u8,
            text,
            "owned_allocator_producers_and_registered_boundaries",
        )) {
            return .owned_allocator_producers_and_registered_boundaries;
        }
        if (std.mem.eql(
            u8,
            text,
            "owned_allocator_producers_registered_boundaries_and_sys_memory_operations",
        )) {
            return .owned_allocator_producers_registered_boundaries_and_sys_memory_operations;
        }
        if (std.mem.eql(
            u8,
            text,
            "process_memory_operations_during_trace_epoch",
        )) {
            return .process_memory_operations_during_trace_epoch;
        }
        return null;
    }
};

pub const Inclusion = enum {
    observed,
    proved_absent,
    isolated,
    no_memory_effect,
    unobserved,

    pub fn tag(self: Inclusion) []const u8 {
        return switch (self) {
            .observed => "observed",
            .proved_absent => "proved_absent",
            .isolated => "isolated",
            .no_memory_effect => "no_memory_effect",
            .unobserved => "opaque",
        };
    }

    fn fromTag(text: []const u8) ?Inclusion {
        if (std.mem.eql(u8, text, "observed")) return .observed;
        if (std.mem.eql(u8, text, "proved_absent")) return .proved_absent;
        if (std.mem.eql(u8, text, "isolated")) return .isolated;
        if (std.mem.eql(u8, text, "no_memory_effect")) {
            return .no_memory_effect;
        }
        if (std.mem.eql(u8, text, "opaque")) return .unobserved;
        return null;
    }
};

pub const StaticEvidence = struct {
    direct_os_memory_operations_absent: bool = false,
    unowned_allocator_producers_absent: bool = false,
    foreign_allocations_absent: bool = false,
};

pub const Manifest = struct {
    universe: Universe = .registered_allocator_handles,
    child_allocator_fast_paths: Inclusion = .unobserved,
    sys_memory_operations: Inclusion = .unobserved,
    direct_os_memory_operations: Inclusion = .unobserved,
    unowned_allocator_producers: Inclusion = .unobserved,
    foreign_allocations: Inclusion = .unobserved,
    observer_control: Inclusion = .isolated,
    zero_length_operations: Inclusion = .no_memory_effect,
    predispatch_failures: Inclusion = .no_memory_effect,
    observer_control_operations: u64 = 0,

    pub fn processComplete(self: Manifest) bool {
        return self.universe ==
            .process_memory_operations_during_trace_epoch and
            self.child_allocator_fast_paths == .observed and
            self.sys_memory_operations == .observed and
            observedOrAbsent(self.direct_os_memory_operations) and
            observedOrAbsent(self.unowned_allocator_producers) and
            observedOrAbsent(self.foreign_allocations) and
            observedOrIsolated(self.observer_control) and
            observedOrNoEffect(self.zero_length_operations) and
            observedOrNoEffect(self.predispatch_failures);
    }

    pub fn statusTag(self: Manifest) []const u8 {
        if (self.processComplete()) return "process_memory_operation_complete";
        return switch (self.universe) {
            .registered_allocator_handles => "boundary_complete",
            .owned_allocator_producers_and_registered_boundaries => "owned_producer_complete",
            .owned_allocator_producers_registered_boundaries_and_sys_memory_operations => "owned_producer_and_sys_memory_operation_complete",
            .process_memory_operations_during_trace_epoch => "process_memory_operation_incomplete",
        };
    }
};

pub fn boundaryManifest() Manifest {
    return .{};
}

pub fn ownedProducerManifest() Manifest {
    return .{
        .universe = .owned_allocator_producers_registered_boundaries_and_sys_memory_operations,
        .child_allocator_fast_paths = .observed,
        .sys_memory_operations = .observed,
    };
}

pub fn processManifest(evidence: StaticEvidence) Manifest {
    var manifest = ownedProducerManifest();
    manifest.universe = .process_memory_operations_during_trace_epoch;
    manifest.direct_os_memory_operations = if (evidence.direct_os_memory_operations_absent)
        .proved_absent
    else
        .unobserved;
    manifest.unowned_allocator_producers = if (evidence.unowned_allocator_producers_absent)
        .proved_absent
    else
        .unobserved;
    manifest.foreign_allocations = if (evidence.foreign_allocations_absent)
        .proved_absent
    else
        .unobserved;
    return manifest;
}

fn observedOrAbsent(state: Inclusion) bool {
    return state == .observed or state == .proved_absent;
}

fn observedOrIsolated(state: Inclusion) bool {
    return state == .observed or state == .isolated;
}

fn observedOrNoEffect(state: Inclusion) bool {
    return state == .observed or state == .no_memory_effect;
}

pub fn isMetadataLine(line: []const u8) bool {
    return std.mem.indexOf(u8, line, metadata_tag) != null;
}

pub fn writeMetadata(writer: *std.Io.Writer, manifest: Manifest) !void {
    var stream = pretty_json.Writer.init(writer, .minified);
    const object = try stream.object();
    try object.field("v", 3);
    try object.field("meta", "memtrace.coverage");
    try object.field("universe", manifest.universe.tag());
    try object.field("child_allocator_fast_paths", manifest.child_allocator_fast_paths.tag());
    try object.field("sys_memory_operations", manifest.sys_memory_operations.tag());
    try object.field("direct_os_memory_operations", manifest.direct_os_memory_operations.tag());
    try object.field("unowned_allocator_producers", manifest.unowned_allocator_producers.tag());
    try object.field("foreign_allocations", manifest.foreign_allocations.tag());
    try object.field("observer_control", manifest.observer_control.tag());
    try object.field("zero_length_operations", manifest.zero_length_operations.tag());
    try object.field("predispatch_failures", manifest.predispatch_failures.tag());
    try object.field("observer_control_operations", manifest.observer_control_operations);
    try object.endLine();
}

pub fn parseMetadata(allocator: std.mem.Allocator, line: []const u8) !Manifest {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch
        return error.InvalidCoverageMetadata;
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |value| value,
        else => return error.InvalidCoverageMetadata,
    };
    if (try unsigned(object, "v") != 3) return error.UnsupportedCoverageVersion;
    if (!std.mem.eql(u8, try string(object, "meta"), "memtrace.coverage")) {
        return error.InvalidCoverageMetadata;
    }
    return .{
        .universe = Universe.fromTag(try string(object, "universe")) orelse
            return error.InvalidCoverageMetadata,
        .child_allocator_fast_paths = try inclusion(object, "child_allocator_fast_paths"),
        .sys_memory_operations = try inclusion(object, "sys_memory_operations"),
        .direct_os_memory_operations = try inclusion(
            object,
            "direct_os_memory_operations",
        ),
        .unowned_allocator_producers = try inclusion(
            object,
            "unowned_allocator_producers",
        ),
        .foreign_allocations = try inclusion(object, "foreign_allocations"),
        .observer_control = try inclusion(object, "observer_control"),
        .zero_length_operations = try inclusion(object, "zero_length_operations"),
        .predispatch_failures = try inclusion(object, "predispatch_failures"),
        .observer_control_operations = try unsigned(
            object,
            "observer_control_operations",
        ),
    };
}

fn inclusion(object: std.json.ObjectMap, key: []const u8) !Inclusion {
    return Inclusion.fromTag(try string(object, key)) orelse
        error.InvalidCoverageMetadata;
}

fn string(object: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = object.get(key) orelse return error.InvalidCoverageMetadata;
    return switch (value) {
        .string => |text| text,
        else => error.InvalidCoverageMetadata,
    };
}

fn unsigned(object: std.json.ObjectMap, key: []const u8) !u64 {
    const value = object.get(key) orelse return error.InvalidCoverageMetadata;
    return switch (value) {
        .integer => |number| if (number >= 0)
            @intCast(number)
        else
            error.InvalidCoverageMetadata,
        else => error.InvalidCoverageMetadata,
    };
}

test "coverage metadata preserves the allocator boundary contract" {
    const expected = boundaryManifest();
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try writeMetadata(&output.writer, expected);
    const actual = try parseMetadata(
        std.testing.allocator,
        std.mem.trimEnd(u8, output.written(), "\n"),
    );
    try std.testing.expectEqualDeep(expected, actual);
    try std.testing.expect(!actual.processComplete());
}

test "coverage metadata preserves the owned producer contract" {
    const expected = ownedProducerManifest();
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try writeMetadata(&output.writer, expected);
    const actual = try parseMetadata(
        std.testing.allocator,
        std.mem.trimEnd(u8, output.written(), "\n"),
    );
    try std.testing.expectEqualDeep(expected, actual);
    try std.testing.expectEqualStrings(
        "owned_producer_and_sys_memory_operation_complete",
        actual.statusTag(),
    );
    try std.testing.expect(!actual.processComplete());
}

test "coverage metadata preserves the certified process contract" {
    const expected = processManifest(.{
        .direct_os_memory_operations_absent = true,
        .unowned_allocator_producers_absent = true,
        .foreign_allocations_absent = true,
    });
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try writeMetadata(&output.writer, expected);
    const actual = try parseMetadata(
        std.testing.allocator,
        std.mem.trimEnd(u8, output.written(), "\n"),
    );
    try std.testing.expectEqualDeep(expected, actual);
    try std.testing.expect(actual.processComplete());
    try std.testing.expectEqualStrings(
        "process_memory_operation_complete",
        actual.statusTag(),
    );
}

test "process coverage rejects category states with the wrong meaning" {
    var manifest = processManifest(.{
        .direct_os_memory_operations_absent = true,
        .unowned_allocator_producers_absent = true,
        .foreign_allocations_absent = true,
    });
    manifest.direct_os_memory_operations = .isolated;
    try std.testing.expect(!manifest.processComplete());
    manifest.direct_os_memory_operations = .proved_absent;
    manifest.observer_control = .no_memory_effect;
    try std.testing.expect(!manifest.processComplete());
    manifest.observer_control = .isolated;
    manifest.zero_length_operations = .proved_absent;
    try std.testing.expect(!manifest.processComplete());
}
