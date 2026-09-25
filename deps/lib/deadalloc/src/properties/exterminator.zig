const std = @import("std");
const hypothesis = @import("hypothesis");
const deadalloc = @import("deadalloc");

const RepairPolicy = deadalloc.RepairPolicy;

pub fn settings() hypothesis.Settings {
    return hypothesis.Settings.quick()
        .withSeed(0xde47_a110)
        .withDatabase("zig-out/hypothesis-failures/deadalloc");
}

fn drawPropertyUsize(conjecture: *hypothesis.ConjectureData, min: usize, max: usize, shrink_towards: usize) !usize {
    return @intCast(try conjecture.drawInteger(
        @intCast(min),
        @intCast(max),
        @intCast(shrink_towards),
    ));
}

pub const RepairPolicyProperty = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, allocator: std.mem.Allocator) !void {
        _ = allocator;

        const red_zone_bytes = try drawPropertyUsize(conjecture, 0, 2048, 16);
        const quarantine_epochs: u64 = @intCast(try drawPropertyUsize(conjecture, 0, 8192, 16));
        const buffer_overflow = try drawPropertyUsize(conjecture, 0, 1, 0);
        const use_after_free = try drawPropertyUsize(conjecture, 0, 1, 0);
        const double_free = try drawPropertyUsize(conjecture, 0, 1, 0);
        const alloc_site = try drawPropertyUsize(conjecture, 1, 4096, 1);
        const free_site = try drawPropertyUsize(conjecture, 4097, 8192, 4097);
        const requested_len = try drawPropertyUsize(conjecture, 1, 256, 16);
        const overflow_extra = try drawPropertyUsize(conjecture, 0, 64, 0);

        const current: RepairPolicy = .{
            .red_zone_bytes = red_zone_bytes,
            .quarantine_epochs = quarantine_epochs,
        };
        var report: deadalloc.Report = .{
            .counters = .{
                .buffer_overflow = buffer_overflow,
                .use_after_free = use_after_free,
                .double_free = double_free,
            },
        };
        if (buffer_overflow > 0) {
            report.issues.append(.{
                .kind = .buffer_overflow,
                .offset = requested_len + overflow_extra,
                .requested_len = requested_len,
                .allocation_return_address = alloc_site,
            });
        }
        if (use_after_free > 0 or double_free > 0) {
            report.issues.append(.{
                .kind = if (use_after_free > 0) .use_after_free else .double_free,
                .allocation_return_address = alloc_site,
                .free_return_address = free_site,
            });
        }
        const repaired = RepairPolicy.fromReport(report, current);

        if (buffer_overflow == 0) {
            try std.testing.expectEqual(current.red_zone_bytes, repaired.red_zone_bytes);
        } else if (current.red_zone_bytes == 0) {
            try std.testing.expectEqual(@as(usize, 16), repaired.red_zone_bytes);
        } else if (current.red_zone_bytes < 1024) {
            try std.testing.expectEqual(@min(current.red_zone_bytes * 2, 1024), repaired.red_zone_bytes);
        } else {
            try std.testing.expectEqual(current.red_zone_bytes, repaired.red_zone_bytes);
        }

        if (use_after_free == 0 and double_free == 0) {
            try std.testing.expectEqual(current.quarantine_epochs, repaired.quarantine_epochs);
        } else if (current.quarantine_epochs == 0) {
            try std.testing.expectEqual(@as(u64, 1), repaired.quarantine_epochs);
        } else if (current.quarantine_epochs < 4096) {
            try std.testing.expectEqual(@min(current.quarantine_epochs * 2, 4096), repaired.quarantine_epochs);
        } else {
            try std.testing.expectEqual(current.quarantine_epochs, repaired.quarantine_epochs);
        }

        if (buffer_overflow == 0) {
            try std.testing.expectEqual(@as(usize, 0), repaired.repairs.overflowPadding(alloc_site));
        } else {
            try std.testing.expectEqual(overflow_extra + 1, repaired.repairs.overflowPadding(alloc_site));
        }

        if (use_after_free == 0 and double_free == 0) {
            try std.testing.expectEqual(@as(u64, 0), repaired.repairs.lifeExtension(alloc_site, free_site));
        } else {
            try std.testing.expectEqual(@as(u64, 1), repaired.repairs.lifeExtension(alloc_site, free_site));
        }
    }
};

test "property: repair policy grows diagnostics monotonically" {
    try hypothesis.checkNamed(RepairPolicyProperty, "deadalloc-repair-policy", settings());
}
