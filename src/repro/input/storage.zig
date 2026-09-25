const std = @import("std");
const alloc_phase = @import("alloc_phase");
const capacity_mod = @import("capacity.zig");

pub const Exhaustion = error{
    ReproducerInputStorageInUse,
    ReproducerInputCapacityExceeded,
};

pub const Status = struct {
    phase: alloc_phase.capacity.Phase,
    in_use: bool,
    terminal: bool,
    file_bytes: usize,
    storage_bytes: usize,
    loaded_file_bytes: usize,
    high_water_file_bytes: usize,
    rejected_file_count: u64,
};

pub fn exactLimitsForFile(
    file_bytes: u64,
    maximum: capacity_mod.Limits,
) Exhaustion!capacity_mod.Limits {
    const exact = std.math.cast(usize, file_bytes) orelse
        return error.ReproducerInputCapacityExceeded;
    if (exact > maximum.file_bytes) return error.ReproducerInputCapacityExceeded;
    return .{ .file_bytes = exact };
}

const Spec = struct {
    pub const Limits: type = capacity_mod.Limits;
    pub const Capacity: type = capacity_mod.Capacity;
    pub const Exhaustion: type = @import("storage.zig").Exhaustion;
    pub const Status: type = @import("storage.zig").Status;
    pub const DeriveError: type = capacity_mod.DeriveError;
    pub const acquisition: alloc_phase.input.Acquisition = .{ .file = true };
    pub const overload: alloc_phase.input.Overload = .terminal;
    pub const limit_field = "file_bytes";
    pub const loaded_field = "loaded_file_bytes";
    pub const high_water_field = "high_water_file_bytes";
    pub const rejected_field = "rejected_file_count";
    pub const in_use_error: @import("storage.zig").Exhaustion =
        error.ReproducerInputStorageInUse;
    pub const capacity_error: @import("storage.zig").Exhaustion =
        error.ReproducerInputCapacityExceeded;

    pub const claim: alloc_phase.capacity.Declaration = .{
        .source = .{
            .id = "choir.pass_reproducer_input_storage",
            .kind = .phase_static,
            .limit_source = .caller,
            .storage = .{
                .covered = &.{
                    .{
                        .id = "one_pass_reproducer_file_and_overload_lookahead_region",
                        .lifetime = .steady,
                        .detail = "one pass reproducer file and overload-lookahead region",
                    },
                },
                .excluded = &.{
                    "reproducer parser output and owned field copies",
                    "Choir registry, IR context, pass manager, worker, and replay storage",
                    "process arguments, file path, report rendering, stdout, and stderr storage",
                    "filesystem implementation, kernel file state, and terminal teardown",
                },
            },
            .capacity = .{
                .inputs = &.{
                    alloc_phase.capacity.bindInput(Limits, "file_bytes", "file_bytes"),
                },
                .type_selectors = &.{},
                .nodes = &.{
                    .{ .input = 0 },
                    .{ .constant = 1 },
                    .{ .add = .{ .left = 0, .right = 1 } },
                },
                .assertions = &.{.{
                    .scope = .closure_total,
                    .measure = .retained,
                    .relation = .exact,
                    .expression = 2,
                }},
            },
            .overload = .{
                .kind = .terminal,
                .detail = "stat preflight or max plus one byte ends acquisition before reproducer parsing or replay",
            },
            .risks = .{
                .transitive = .{
                    .status = .witnessed,
                    .detail = "activated file reads use only the preacquired region before synchronous parser consumption",
                },
                .foreign = .{
                    .status = .excluded,
                    .detail = "filesystem implementation and kernel file state remain outside pass reproducer input storage",
                },
            },
            .obligations = &.{
                .{ .key = "choir_pass_reproducer_input_capacity", .role = .capacity_model },
                .{ .key = "choir_pass_reproducer_input_preflight", .role = .overload },
                .{ .key = "choir_pass_reproducer_input_file_boundary_overload", .role = .overload },
                .{ .key = "choir_pass_reproducer_input_file_boundary_transitive_risk", .role = .transitive_risk },
                .{ .key = "choir_pass_reproducer_input_file_boundary_foreign_risk", .role = .foreign_risk },
                .{ .key = "choir_pass_reproducer_input_byte_boundary", .role = .custom },
                .{ .key = "choir_pass_reproducer_input_command_composition", .role = .custom },
                .{ .key = "choir_pass_reproducer_input_root", .role = .custom },
            },
        },
        .bindings = .{},
    };
};

pub const Storage = alloc_phase.input.OneRegion(Spec);

test "Choir pass reproducer input maps files beyond lookahead to capacity exhaustion" {
    comptime {
        alloc_phase.capacity.record(
            alloc_phase.capacity.witness(Storage, "choir_pass_reproducer_input_capacity"),
        );
    }

    comptime {
        alloc_phase.capacity.record(
            alloc_phase.capacity.witness(Storage, "choir_pass_reproducer_input_file_boundary_overload"),
        );
    }
    comptime {
        alloc_phase.capacity.record(
            alloc_phase.capacity.witness(Storage, "choir_pass_reproducer_input_file_boundary_transitive_risk"),
        );
    }
    comptime {
        alloc_phase.capacity.record(
            alloc_phase.capacity.witness(Storage, "choir_pass_reproducer_input_file_boundary_foreign_risk"),
        );
    }

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.Options.debug_io;
    var storage = try Storage.init(std.testing.allocator, .{ .file_bytes = 5 });
    defer storage.deinit(std.testing.allocator);
    storage.activate();
    try temporary.dir.writeFile(
        io,
        .{ .sub_path = "pass.choirrepro", .data = "abcde" },
    );
    const exact = try storage.readFile(temporary.dir, io, "pass.choirrepro");
    try std.testing.expectEqualStrings("abcde", exact);
    storage.release();
    try temporary.dir.writeFile(
        io,
        .{ .sub_path = "pass.choirrepro", .data = "abcdefgh" },
    );
    try std.testing.expectError(
        error.ReproducerInputCapacityExceeded,
        storage.readFile(temporary.dir, io, "pass.choirrepro"),
    );
    try std.testing.expect(storage.status().terminal);
}

comptime {
    alloc_phase.capacity.requireAllocatorRejectingOwnerShape(Storage);
}
