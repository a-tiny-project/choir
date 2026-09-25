const std = @import("std");
const hypothesis = @import("hypothesis");
const memtrace = @import("memtrace");
const data = @import("data.zig");
const model = @import("model.zig");

pub const Property = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, property_allocator: std.mem.Allocator) !void {
        const use_allocation_ids = try conjecture.drawBoolean();
        var expected = model.Model{ .retains_freed_memory = try conjecture.drawBoolean() };
        var bytes = std.Io.Writer.Allocating.init(property_allocator);
        defer bytes.deinit();

        try writeEvent(&bytes.writer, &expected, .{
            .kind = .allocator,
            .allocator_id = 0,
            .retains_freed_memory = expected.retains_freed_memory,
        }, 0);

        var slots = @as([8]data.Slot, @splat(.{}));
        var active_count: usize = 0;
        var next_id: u64 = 1;
        var generation: usize = 1;
        const steps = try data.drawUsize(conjecture, 1, 96, 12);
        var step: usize = 0;
        while (step < steps) : (step += 1) {
            const op = try data.drawUsize(conjecture, 0, 99, 0);
            if (op < 42 or active_count == 0) {
                const slot_index = data.firstInactive(&slots);
                if (slots[slot_index].active) continue;
                const len = try data.drawUsize(conjecture, 1, 512, 8);
                const scope_index = try data.drawUsize(conjecture, 0, data.scope_names.len - 1, 0);
                const allocation_id = if (use_allocation_ids) next_id else 0;
                if (use_allocation_ids) next_id += 1;
                const address = data.nextAddress(generation, slot_index);
                generation += 1;
                slots[slot_index] = .{
                    .active = true,
                    .allocation_id = allocation_id,
                    .address = address,
                    .len = len,
                    .scope_index = scope_index,
                };
                try (memtrace.Event{
                    .kind = .alloc,
                    .allocator_id = 0,
                    .allocation_id = allocation_id,
                    .address = address,
                    .len = len,
                }).writeJsonLine(&bytes.writer, null, data.scope_names[scope_index]);
                expected.allocation(len);
                active_count += 1;
            } else if (op < 68) {
                const slot_index = try data.drawActiveSlot(conjecture, &slots, active_count);
                var slot = &slots[slot_index];
                const old_len = slot.len;
                const new_len = try data.drawUsize(conjecture, 1, 768, 8);
                try (memtrace.Event{
                    .kind = .resize,
                    .allocator_id = 0,
                    .allocation_id = slot.allocation_id,
                    .address = slot.address,
                    .old_len = old_len,
                    .len = new_len,
                }).writeJsonLine(&bytes.writer, null, data.scope_names[slot.scope_index]);
                expected.resize(old_len, new_len);
                slot.len = new_len;
            } else if (op < 84) {
                const slot_index = try data.drawActiveSlot(conjecture, &slots, active_count);
                var slot = &slots[slot_index];
                const old_address = slot.address;
                const old_len = slot.len;
                const new_len = try data.drawUsize(conjecture, 1, 768, 8);
                const new_address = data.nextAddress(generation, slot_index);
                generation += 1;
                try (memtrace.Event{
                    .kind = .remap,
                    .allocator_id = 0,
                    .allocation_id = slot.allocation_id,
                    .old_address = old_address,
                    .address = new_address,
                    .old_len = old_len,
                    .len = new_len,
                }).writeJsonLine(&bytes.writer, null, data.scope_names[slot.scope_index]);
                expected.resize(old_len, new_len);
                slot.address = new_address;
                slot.len = new_len;
            } else {
                const slot_index = try data.drawActiveSlot(conjecture, &slots, active_count);
                const slot = slots[slot_index];
                try (memtrace.Event{
                    .kind = .free,
                    .allocator_id = 0,
                    .allocation_id = slot.allocation_id,
                    .address = slot.address,
                    .old_len = slot.len,
                    .len = slot.len,
                }).writeJsonLine(&bytes.writer, null, data.scope_names[slot.scope_index]);
                expected.free(slot.len);
                slots[slot_index] = .{};
                active_count -= 1;
            }
        }

        var analyzer = memtrace.Analyzer.init(property_allocator);
        defer analyzer.deinit();
        try analyzer.ingestJsonlBytes(bytes.written());

        try std.testing.expectEqual(expected.events, analyzer.events);
        try std.testing.expectEqual(expected.allocations, analyzer.counters.allocations);
        try std.testing.expectEqual(expected.frees, analyzer.counters.frees);
        try std.testing.expectEqual(expected.live_allocations, analyzer.counters.live_allocations);
        try std.testing.expectEqual(expected.allocated_bytes, analyzer.counters.allocated_bytes);
        try std.testing.expectEqual(expected.freed_bytes, analyzer.counters.freed_bytes);
        try std.testing.expectEqual(expected.live_bytes, analyzer.counters.live_bytes);
        try std.testing.expectEqual(expected.high_water_live_bytes, analyzer.counters.high_water_live_bytes);
        try std.testing.expectEqual(expected.retained_bytes, analyzer.counters.retained_bytes);
        try std.testing.expectEqual(expected.high_water_retained_bytes, analyzer.counters.high_water_retained_bytes);

        var summary = std.Io.Writer.Allocating.init(property_allocator);
        defer summary.deinit();
        try analyzer.writeSummaryJsonl(&summary.writer, .{ .top = data.scope_names.len, .include_zero_live = true });
        try std.testing.expect(std.mem.indexOf(u8, summary.written(), "\"kind\":\"summary\"") != null);
    }
};

fn writeEvent(writer: *std.Io.Writer, expected: *model.Model, event: memtrace.Event, scope_index: usize) !void {
    try event.writeJsonLine(writer, null, data.scope_names[scope_index]);
    expected.event();
}

test "property: analyzer replay matches generated allocation model" {
    try hypothesis.checkNamed(Property, "memtrace-analyzer-replay", data.settings());
}

test "canonical replay parses the u64 boundary" {
    var bytes = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer bytes.deinit();
    try (memtrace.Event{
        .kind = .alloc,
        .allocation_id = std.math.maxInt(u64),
    }).writeJsonLine(&bytes.writer, null, "root");

    const line = std.mem.trimEnd(u8, bytes.written(), "\n");
    const parsed = try memtrace.event.parseReplayFast(line);
    try std.testing.expectEqual(std.math.maxInt(u64), parsed.allocation_id);

    const overflow = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        line,
        "\"allocation_id\":18446744073709551615",
        "\"allocation_id\":18446744073709551616",
    );
    defer std.testing.allocator.free(overflow);
    try std.testing.expectError(error.InvalidEventJson, memtrace.event.parseReplayFast(overflow));

    const leading = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        line,
        "\"allocation_id\":18446744073709551615",
        "\"allocation_id\":000000000000000000001",
    );
    defer std.testing.allocator.free(leading);
    try std.testing.expectEqual(@as(u64, 1), (try memtrace.event.parseReplayFast(leading)).allocation_id);
}
