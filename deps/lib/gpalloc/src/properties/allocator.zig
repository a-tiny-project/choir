const std = @import("std");
const hypothesis = @import("hypothesis");
const gpalloc = @import("gpalloc");

const draw = @import("draw.zig");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const GpAllocator = gpalloc.GpAllocator;
const max_small_size = gpalloc.max_small_size;
const size_class = gpalloc.class;
const assert = std.debug.assert;

const Range = struct {
    start: usize,
    end: usize,
    alignment: Alignment = .@"1",
};

const AllocationRecord = struct {
    slice: []u8,
    fill: u8,
};

const fine_large_max = 128 * 1024;
const medium_large_min = 320 * 1024;
const medium_large_max = 512 * 1024;
const huge_large_min = 4 * 1024 * 1024 + 1;
const huge_large_max = 4 * 1024 * 1024 + 64 * 1024;

const representative_lengths = [_]usize{
    16,
    max_small_size + 1,
    medium_large_min,
    huge_large_min,
};

pub fn settings() hypothesis.Settings {
    return hypothesis.Settings.quick()
        .withSeed(0x71A1_10C)
        .withDatabase("zig-out/hypothesis-failures/gpalloc")
        .withSeedFromEnv();
}

const drawUsize = draw.drawUsize;
const drawAlignment = draw.drawAlignment;

fn drawAllocationLen(conjecture: *hypothesis.ConjectureData) !usize {
    const variant = try drawUsize(conjecture, 0, 15, 0);
    return switch (variant) {
        0...7 => try drawUsize(conjecture, 1, max_small_size, 1),
        8...11 => try drawUsize(conjecture, max_small_size + 1, fine_large_max, max_small_size + 1),
        12...13 => try drawUsize(conjecture, medium_large_min, medium_large_max, medium_large_min),
        else => try drawUsize(conjecture, huge_large_min, huge_large_max, huge_large_min),
    };
}

fn expectDisjoint(ranges: []const Range) !void {
    for (ranges, 0..) |left, index| {
        for (ranges[index + 1 ..]) |right| {
            try std.testing.expect(left.end <= right.start or right.end <= left.start);
        }
    }
}

fn fillSampled(bytes: []u8, fill: u8) void {
    if (bytes.len <= 4096) {
        @memset(bytes, fill);
        return;
    }
    @memset(bytes[0..4096], fill);
    const middle_start = bytes.len / 2 - 128;
    @memset(bytes[middle_start .. middle_start + 256], fill);
    @memset(bytes[bytes.len - 256 ..], fill);
}

fn expectSampled(bytes: []const u8, fill: u8) !void {
    if (bytes.len <= 4096) {
        try expectRange(bytes, fill);
        return;
    }
    try expectRange(bytes[0..4096], fill);
    const middle_start = bytes.len / 2 - 128;
    try expectRange(bytes[middle_start .. middle_start + 256], fill);
    try expectRange(bytes[bytes.len - 256 ..], fill);
}

fn expectRange(bytes: []const u8, fill: u8) !void {
    for (bytes) |byte| {
        try std.testing.expectEqual(fill, byte);
    }
}

fn appendFilledRecord(
    active: *std.ArrayList(AllocationRecord),
    property_allocator: Allocator,
    tiny_allocator: Allocator,
    len: usize,
    fill: u8,
) !void {
    const slice = try tiny_allocator.alloc(u8, len);
    fillSampled(slice, fill);
    try active.append(property_allocator, .{ .slice = slice, .fill = fill });
}

fn isSmallLen(len: usize) bool {
    return len <= max_small_size;
}

pub const AlignmentProperty = struct {
    pub fn property(
        conjecture: *hypothesis.ConjectureData,
        property_allocator: Allocator,
    ) !void {
        var heap = GpAllocator.init(property_allocator, .{});
        defer heap.deinit();
        const tiny_allocator = heap.allocator();

        var ranges: std.ArrayList(Range) = .empty;
        defer ranges.deinit(property_allocator);
        defer {
            for (ranges.items) |range| {
                const ptr: [*]u8 = @ptrFromInt(range.start);
                const len = range.end - range.start;
                tiny_allocator.rawFree(ptr[0..len], range.alignment, @returnAddress());
            }
        }

        const count = try drawUsize(conjecture, 1, 96, 12);
        var index: usize = 0;
        while (index < count) : (index += 1) {
            const alignment = try drawAlignment(conjecture);
            const len = try drawUsize(conjecture, 1, max_small_size + 4096, 1);
            const ptr = tiny_allocator.rawAlloc(len, alignment, @returnAddress()) orelse return error.OutOfMemory;
            const slice = ptr[0..len];
            @memset(slice, @truncate(index));

            try std.testing.expect(std.mem.isAligned(@intFromPtr(ptr), alignment.toByteUnits()));
            try ranges.append(property_allocator, .{
                .start = @intFromPtr(ptr),
                .end = @intFromPtr(ptr) + len,
                .alignment = alignment,
            });
        }

        try expectDisjoint(ranges.items);
    }
};

pub const StateProperty = struct {
    pub fn property(
        conjecture: *hypothesis.ConjectureData,
        property_allocator: Allocator,
    ) !void {
        var heap = GpAllocator.init(property_allocator, .{});
        defer heap.deinit();
        const tiny_allocator = heap.allocator();

        var active: std.ArrayList(AllocationRecord) = .empty;
        defer active.deinit(property_allocator);
        defer {
            for (active.items) |record| {
                tiny_allocator.free(record.slice);
            }
        }

        for (representative_lengths, 0..) |len, index| {
            try appendFilledRecord(&active, property_allocator, tiny_allocator, len, @intCast(0x80 + index));
        }

        const steps = try drawUsize(conjecture, 1, 64, 16);
        var step: usize = 0;
        while (step < steps) : (step += 1) {
            const op = try drawUsize(conjecture, 0, 99, 0);
            if ((op < 45 and active.items.len < 6) or active.items.len == 0) {
                const len = try drawAllocationLen(conjecture);
                const fill: u8 = @intCast(step & 0xff);
                try appendFilledRecord(&active, property_allocator, tiny_allocator, len, fill);
            } else if (op < 80) {
                const slot = try drawUsize(conjecture, 0, active.items.len - 1, 0);
                var record = &active.items[slot];
                const old_len = record.slice.len;
                const new_len = try drawAllocationLen(conjecture);
                const resized = try tiny_allocator.realloc(record.slice, new_len);
                const prefix_len = @min(old_len, new_len);
                record.slice = resized;
                try expectRange(resized[0..@min(prefix_len, 4096)], record.fill);
                fillSampled(resized, record.fill);
            } else {
                const slot = try drawUsize(conjecture, 0, active.items.len - 1, 0);
                tiny_allocator.free(active.items[slot].slice);
                _ = active.swapRemove(slot);
            }

            var ranges: std.ArrayList(Range) = .empty;
            defer ranges.deinit(property_allocator);
            for (active.items) |record| {
                try expectSampled(record.slice, record.fill);
                try ranges.append(property_allocator, .{
                    .start = @intFromPtr(record.slice.ptr),
                    .end = @intFromPtr(record.slice.ptr) + record.slice.len,
                });
            }
            try expectDisjoint(ranges.items);
        }
    }
};

const StatsModel = struct {
    small_allocations: u64 = 0,
    small_frees: u64 = 0,
    large_allocations: u64 = 0,
    large_frees: u64 = 0,
    active_small_bytes: usize = 0,
    active_large_bytes: usize = 0,

    fn allocate(model: *StatsModel, len: usize) void {
        if (isSmallLen(len)) {
            model.small_allocations += 1;
            model.active_small_bytes += len;
        } else {
            model.large_allocations += 1;
            model.active_large_bytes += len;
        }
    }

    fn free(model: *StatsModel, len: usize) void {
        if (isSmallLen(len)) {
            model.small_frees += 1;
            model.active_small_bytes -= len;
        } else {
            model.large_frees += 1;
            model.active_large_bytes -= len;
        }
    }

    fn resize(model: *StatsModel, old_len: usize, new_len: usize) void {
        assert(isSmallLen(old_len) == isSmallLen(new_len));
        if (isSmallLen(old_len)) {
            if (new_len > old_len) {
                model.active_small_bytes += new_len - old_len;
            } else {
                model.active_small_bytes -= old_len - new_len;
            }
        } else {
            if (new_len > old_len) {
                model.active_large_bytes += new_len - old_len;
            } else {
                model.active_large_bytes -= old_len - new_len;
            }
        }
    }
};

fn expectStats(heap: *GpAllocator, model: StatsModel) !void {
    const actual = heap.stats();
    try std.testing.expectEqual(model.small_allocations, actual.small_allocations);
    try std.testing.expectEqual(model.small_frees, actual.small_frees);
    try std.testing.expectEqual(model.large_allocations, actual.large_allocations);
    try std.testing.expectEqual(model.large_frees, actual.large_frees);
    try std.testing.expectEqual(model.active_small_bytes, actual.active_small_bytes);
    try std.testing.expectEqual(model.active_large_bytes, actual.active_large_bytes);
}

pub const StatsTraceProperty = struct {
    pub fn property(
        conjecture: *hypothesis.ConjectureData,
        property_allocator: Allocator,
    ) !void {
        var heap = GpAllocator.init(property_allocator, .{ .collect_stats = true });
        defer heap.deinit();
        const tiny_allocator = heap.allocator();

        var active: std.ArrayList(AllocationRecord) = .empty;
        defer active.deinit(property_allocator);
        defer {
            for (active.items) |record| {
                tiny_allocator.free(record.slice);
            }
        }

        var model: StatsModel = .{};
        for (representative_lengths, 0..) |len, index| {
            try appendFilledRecord(&active, property_allocator, tiny_allocator, len, @intCast(0x40 + index));
            model.allocate(len);
        }
        try expectStats(&heap, model);

        const steps = try drawUsize(conjecture, 1, 96, 16);
        var step: usize = 0;
        while (step < steps) : (step += 1) {
            const op = try drawUsize(conjecture, 0, 99, 0);
            if ((op < 50 and active.items.len < 8) or active.items.len == 0) {
                const len = try drawAllocationLen(conjecture);
                const fill: u8 = @intCast(step & 0xff);
                try appendFilledRecord(&active, property_allocator, tiny_allocator, len, fill);
                model.allocate(len);
            } else if (op < 75) {
                const slot = try drawUsize(conjecture, 0, active.items.len - 1, 0);
                var record = &active.items[slot];
                const old_len = record.slice.len;
                const min_len = if (isSmallLen(old_len)) @as(usize, 1) else max_small_size + 1;
                if (old_len > min_len) {
                    const new_len = try drawUsize(conjecture, min_len, old_len, min_len);
                    const expect_in_place = if (isSmallLen(old_len))
                        size_class.indexFor(new_len, .@"1").? == size_class.indexFor(old_len, .@"1").?
                    else
                        true;
                    const resized = tiny_allocator.resize(record.slice, new_len);
                    try std.testing.expectEqual(expect_in_place, resized);
                    if (resized) {
                        record.slice = record.slice[0..new_len];
                        model.resize(old_len, new_len);
                    }
                }
            } else {
                const slot = try drawUsize(conjecture, 0, active.items.len - 1, 0);
                const record = active.items[slot];
                tiny_allocator.free(record.slice);
                model.free(record.slice.len);
                _ = active.swapRemove(slot);
            }
            try expectStats(&heap, model);
        }

        while (active.items.len != 0) {
            const record = active.pop().?;
            tiny_allocator.free(record.slice);
            model.free(record.slice.len);
            try expectStats(&heap, model);
        }
    }
};

test "property: allocations are aligned and disjoint" {
    try hypothesis.checkNamed(AlignmentProperty, "gpalloc-alignment", settings());
}

test "property: allocator operations preserve active ranges" {
    try hypothesis.checkNamed(StateProperty, "gpalloc-state", settings());
}

test "property: stats match generated allocator traces" {
    try hypothesis.checkNamed(StatsTraceProperty, "gpalloc-stats", settings());
}
