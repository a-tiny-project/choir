const std = @import("std");
const hypothesis = @import("hypothesis");
const deadalloc = @import("deadalloc");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const Config = deadalloc.Config;
const DeadAllocator = deadalloc.DeadAllocator;
const Mode = deadalloc.Mode;

const class_sizes = deadalloc.class_sizes;
const max_issues = deadalloc.max_issues;
const max_small_size = deadalloc.max_small_size;
const min_alignment = deadalloc.min_alignment;
const page_size = deadalloc.page_size;

const PropertyRange = struct {
    start: usize,
    end: usize,
};

const PropertyRecord = struct {
    slice: []u8,
    fill: u8,
};

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

fn drawPropertyMode(conjecture: *hypothesis.ConjectureData) !Mode {
    return switch (try drawPropertyUsize(conjecture, 0, 2, 0)) {
        0 => .diehard,
        1 => .dieharder,
        else => .exterminator,
    };
}

fn propertyClassSizeFor(len: usize, alignment: Alignment) usize {
    const requested_len = @max(len, min_alignment);
    const requested_alignment = @max(alignment.toByteUnits(), min_alignment);
    for (class_sizes) |class_size| {
        if (class_size >= requested_len and class_size >= requested_alignment) return class_size;
    }
    return len;
}

fn expectPropertyRangesDisjoint(ranges: []const PropertyRange) !void {
    for (ranges, 0..) |left, index| {
        for (ranges[index + 1 ..]) |right| {
            try std.testing.expect(left.end <= right.start or right.end <= left.start);
        }
    }
}

fn propertyActiveBytes(records: []const PropertyRecord) usize {
    var total: usize = 0;
    for (records) |record| total += record.slice.len;
    return total;
}

pub const AllocatorStateProperty = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, allocator: Allocator) !void {
        const mode = try drawPropertyMode(conjecture);
        var heap = DeadAllocator.init(allocator, .{
            .mode = mode,
            .seed = 0x51a7e + @as(u64, @backingInt(mode)),
            .min_chunk_blocks = 8,
            .thread_safe = false,
            .diagnostics = .{ .enabled = true, .red_zone_bytes = 16, .quarantine_epochs = 4 },
        });
        defer heap.deinit();
        const dead_allocator = heap.allocator();

        var active: std.ArrayList(PropertyRecord) = .empty;
        defer active.deinit(allocator);
        defer {
            for (active.items) |record| dead_allocator.free(record.slice);
        }

        const steps = try drawPropertyUsize(conjecture, 1, 96, 16);
        var step: usize = 0;
        while (step < steps) : (step += 1) {
            const op = try drawPropertyUsize(conjecture, 0, 99, 0);
            if (op < 55 or active.items.len == 0) {
                const len = try drawPropertyUsize(conjecture, 1, 4096, 1);
                const fill: u8 = @intCast(step & 0xff);
                const slice = try dead_allocator.alloc(u8, len);
                @memset(slice, fill);
                try active.append(allocator, .{ .slice = slice, .fill = fill });
            } else if (op < 80) {
                const slot = try drawPropertyUsize(conjecture, 0, active.items.len - 1, 0);
                var record = &active.items[slot];
                const old_len = record.slice.len;
                const new_len = try drawPropertyUsize(conjecture, 1, 4096, 1);
                const resized = try dead_allocator.realloc(record.slice, new_len);
                const prefix_len = @min(old_len, new_len);
                for (resized[0..prefix_len]) |byte| try std.testing.expectEqual(record.fill, byte);
                @memset(resized, record.fill);
                record.slice = resized;
            } else {
                const slot = try drawPropertyUsize(conjecture, 0, active.items.len - 1, 0);
                dead_allocator.free(active.items[slot].slice);
                _ = active.swapRemove(slot);
            }

            var ranges: std.ArrayList(PropertyRange) = .empty;
            defer ranges.deinit(allocator);
            for (active.items) |record| {
                for (record.slice) |byte| try std.testing.expectEqual(record.fill, byte);
                try ranges.append(allocator, .{
                    .start = @intFromPtr(record.slice.ptr),
                    .end = @intFromPtr(record.slice.ptr) + record.slice.len,
                });
            }
            try expectPropertyRangesDisjoint(ranges.items);

            const report = heap.report();
            try std.testing.expectEqual(active.items.len, report.live_allocations);
            try std.testing.expectEqual(propertyActiveBytes(active.items), report.live_bytes);
            try std.testing.expectEqual(active.items.len, report.leak_count);
            if (active.items.len == 0) {
                try std.testing.expect(report.leak_issue == null);
            } else {
                const issue = report.leak_issue.?;
                try std.testing.expectEqual(.leak, issue.kind);
                try std.testing.expect(issue.requested_len > 0);
                var matches_active = false;
                for (active.items) |record| {
                    if (@intFromPtr(record.slice.ptr) == issue.address and record.slice.len == issue.requested_len) {
                        matches_active = true;
                        break;
                    }
                }
                try std.testing.expect(matches_active);
            }
            try std.testing.expectEqual(@as(usize, 0), report.counters.issueCount());
        }

        try std.testing.expectEqual(@as(usize, 0), heap.report().counters.invalid_free);
        try std.testing.expectEqual(@as(usize, 0), heap.report().counters.double_free);
        try std.testing.expectEqual(@as(usize, 0), heap.report().counters.buffer_overflow);
    }
};

pub const DiagnosticFaultProperty = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, allocator: Allocator) !void {
        const mode = try drawPropertyMode(conjecture);
        var heap = DeadAllocator.init(allocator, .{
            .mode = mode,
            .seed = 0xfa17_5eed + @as(u64, @backingInt(mode)),
            .min_chunk_blocks = 8,
            .thread_safe = false,
            .diagnostics = .{ .enabled = true, .red_zone_bytes = 16, .quarantine_epochs = 4 },
        });
        defer heap.deinit();
        const dead_allocator = heap.allocator();

        const len = try drawPropertyUsize(conjecture, 2, 512, 8);
        const fault = try drawPropertyUsize(conjecture, 0, 10, 0);
        switch (fault) {
            0 => {
                var stack_byte: u8 = 0;
                dead_allocator.rawFree((&stack_byte)[0..1], .@"1", @returnAddress());
                try std.testing.expectEqual(@as(usize, 1), heap.report().counters.invalid_free);
            },
            1 => {
                const allocation = try dead_allocator.alloc(u8, len);
                dead_allocator.free(allocation);
                dead_allocator.free(allocation);
                try std.testing.expectEqual(@as(usize, 1), heap.report().counters.double_free);
            },
            2 => {
                const ptr = dead_allocator.rawAlloc(len, .@"1", @returnAddress()) orelse return error.OutOfMemory;
                ptr[len] = 0xee;
                dead_allocator.rawFree(ptr[0..len], .@"1", @returnAddress());
                try std.testing.expectEqual(@as(usize, 1), heap.report().counters.buffer_overflow);
            },
            else => {
                if (fault == 10) {
                    var stack_byte: u8 = 0x5a;
                    const remapped = dead_allocator.rawRemap((&stack_byte)[0..1], .@"1", len, @returnAddress());
                    try std.testing.expect(remapped == null);

                    const report = heap.report();
                    try std.testing.expectEqual(@as(usize, 1), report.counters.invalid_free);
                    try std.testing.expectEqual(@as(usize, 0), report.live_allocations);
                    return;
                }

                if (fault == 9) {
                    const ptr = dead_allocator.rawAlloc(len, .@"1", @returnAddress()) orelse return error.OutOfMemory;
                    dead_allocator.rawFree(ptr[1..len], .@"1", @returnAddress());

                    const report = heap.report();
                    const issue = report.last_issue.?;
                    try std.testing.expectEqual(@as(usize, 1), report.counters.invalid_free);
                    try std.testing.expectEqual(@as(usize, 1), report.live_allocations);
                    try std.testing.expectEqual(.invalid_free, issue.kind);
                    try std.testing.expectEqual(@intFromPtr(ptr) + 1, issue.address);
                    try std.testing.expectEqual(@as(usize, 1), issue.offset);
                    try std.testing.expectEqual(len - 1, issue.requested_len);
                    try std.testing.expect(issue.block_size >= len);
                    try std.testing.expect(issue.allocation_id != 0);
                    try std.testing.expect(issue.allocation_return_address != 0);

                    dead_allocator.rawFree(ptr[0..len], .@"1", @returnAddress());
                    return;
                }

                if (fault == 8) {
                    const allocation = try dead_allocator.alloc(u8, len);
                    const address = @intFromPtr(allocation.ptr);
                    dead_allocator.free(allocation);

                    const stale: [*]u8 = @ptrFromInt(address);
                    stale[0] = 0xdf;

                    const report = heap.report();
                    const issue = report.last_issue.?;
                    try std.testing.expectEqual(@as(usize, 1), report.counters.use_after_free);
                    try std.testing.expectEqual(.use_after_free, issue.kind);
                    try std.testing.expectEqual(@as(usize, 0), issue.offset);
                    try std.testing.expect(issue.allocation_id != 0);
                    try std.testing.expect(issue.free_return_address != 0);
                    return;
                }

                if (fault == 7) {
                    const ptr = dead_allocator.rawAlloc(len, .@"1", @returnAddress()) orelse return error.OutOfMemory;
                    ptr[len] = 0xee;

                    const first = heap.report();
                    const second = heap.report();
                    try std.testing.expectEqual(@as(usize, 1), first.counters.buffer_overflow);
                    try std.testing.expectEqual(@as(usize, 1), second.counters.buffer_overflow);
                    return;
                }

                if (fault == 6) {
                    const ptr = dead_allocator.rawAlloc(len, .@"1", @returnAddress()) orelse return error.OutOfMemory;
                    const block_size = propertyClassSizeFor(len + 16, .@"1");
                    const offset = try drawPropertyUsize(conjecture, len, block_size - 1, len);
                    dead_allocator.rawFree(ptr[0..len], .@"1", @returnAddress());

                    ptr[offset] = 0xdf;

                    const report = heap.report();
                    const issue = report.last_issue.?;
                    try std.testing.expectEqual(@as(usize, 1), report.counters.use_after_free);
                    try std.testing.expectEqual(.use_after_free, issue.kind);
                    try std.testing.expectEqual(offset, issue.offset);
                    try std.testing.expect(issue.allocation_id != 0);
                    try std.testing.expect(issue.free_return_address != 0);
                    return;
                }

                if (fault == 5) {
                    const ptr = dead_allocator.rawAlloc(len, .@"1", @returnAddress()) orelse return error.OutOfMemory;
                    ptr[len] = 0xee;
                    try std.testing.expect(dead_allocator.rawResize(ptr[0..len], .@"1", len + 1, @returnAddress()));
                    try std.testing.expectEqual(@as(usize, 1), heap.report().counters.buffer_overflow);
                    return;
                }

                if (fault == 4) {
                    const allocation = try dead_allocator.alloc(u8, len);
                    const address = @intFromPtr(allocation.ptr);
                    dead_allocator.free(allocation);

                    const stale: [*]u8 = @ptrFromInt(address);
                    stale[0] = 0xdf;

                    const first = heap.report();
                    const second = heap.report();
                    try std.testing.expectEqual(@as(usize, 1), first.counters.use_after_free);
                    try std.testing.expectEqual(@as(usize, 1), second.counters.use_after_free);
                    return;
                }

                const ptr = dead_allocator.rawAlloc(len, .@"1", @returnAddress()) orelse return error.OutOfMemory;
                dead_allocator.rawFree(ptr[0 .. len - 1], .@"1", @returnAddress());
                try std.testing.expectEqual(@as(usize, 1), heap.report().counters.size_mismatch);
            },
        }
    }
};

pub const AlignmentProperty = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, allocator: Allocator) !void {
        var heap = DeadAllocator.init(allocator, .{
            .mode = .diehard,
            .seed = 0xa119_4ed,
            .min_chunk_blocks = 8,
            .thread_safe = false,
        });
        defer heap.deinit();
        const dead_allocator = heap.allocator();

        var ranges: std.ArrayList(PropertyRange) = .empty;
        defer ranges.deinit(allocator);
        defer {
            for (ranges.items) |range| {
                const ptr: [*]u8 = @ptrFromInt(range.start);
                dead_allocator.rawFree(ptr[0 .. range.end - range.start], .@"1", @returnAddress());
            }
        }

        const count = try drawPropertyUsize(conjecture, 1, 64, 8);
        var index: usize = 0;
        while (index < count) : (index += 1) {
            const alignment_shift = try drawPropertyUsize(conjecture, 0, 12, 0);
            const alignment = Alignment.fromByteUnits(@as(usize, 1) << @as(u6, @intCast(alignment_shift)));
            const len = try drawPropertyUsize(conjecture, 1, 8192, 1);
            const ptr = dead_allocator.rawAlloc(len, alignment, @returnAddress()) orelse return error.OutOfMemory;
            try std.testing.expect(std.mem.isAligned(@intFromPtr(ptr), alignment.toByteUnits()));
            try ranges.append(allocator, .{
                .start = @intFromPtr(ptr),
                .end = @intFromPtr(ptr) + len,
            });
        }

        try expectPropertyRangesDisjoint(ranges.items);
    }
};

pub const LargeAllocationProperty = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, allocator: Allocator) !void {
        var heap = DeadAllocator.init(allocator, .{
            .mode = .dieharder,
            .seed = 0xd1e4_a110,
            .thread_safe = false,
        });
        defer heap.deinit();
        const dead_allocator = heap.allocator();

        const len = max_small_size + try drawPropertyUsize(conjecture, 1, page_size - 1, 1);
        const rounded_len = std.mem.alignForward(usize, len, page_size);
        const ptr = dead_allocator.rawAlloc(len, .@"1", @returnAddress()) orelse return error.OutOfMemory;
        try std.testing.expect(std.mem.isAligned(@intFromPtr(ptr), page_size));
        try std.testing.expect(dead_allocator.rawResize(ptr[0..len], .@"1", rounded_len, @returnAddress()));
        dead_allocator.rawFree(ptr[0..rounded_len], .@"1", @returnAddress());
        try std.testing.expectEqual(@as(usize, 0), heap.report().live_allocations);
    }
};

pub const InteriorFreeProperty = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, allocator: Allocator) !void {
        var heap = DeadAllocator.init(allocator, .{
            .mode = .dieharder,
            .seed = 0x91e_0a11,
            .thread_safe = false,
            .diagnostics = .{ .enabled = true, .red_zone_bytes = 16 },
        });
        defer heap.deinit();
        const dead_allocator = heap.allocator();

        const len = try drawPropertyUsize(conjecture, 2, 2048, 8);
        const block_size = propertyClassSizeFor(len + 16, .@"1");
        const offset = try drawPropertyUsize(conjecture, 1, block_size - 1, 1);
        const ptr = dead_allocator.rawAlloc(len, .@"1", @returnAddress()) orelse return error.OutOfMemory;

        dead_allocator.rawFree((ptr + offset)[0..1], .@"1", @returnAddress());

        const report = heap.report();
        const issue = report.last_issue.?;
        try std.testing.expectEqual(@as(usize, 1), report.counters.invalid_free);
        try std.testing.expectEqual(@as(usize, 1), report.live_allocations);
        try std.testing.expectEqual(.invalid_free, issue.kind);
        try std.testing.expectEqual(@intFromPtr(ptr) + offset, issue.address);
        try std.testing.expectEqual(offset, issue.offset);
        try std.testing.expectEqual(@as(usize, 1), issue.requested_len);
        try std.testing.expect(issue.allocation_id != 0);

        dead_allocator.rawFree(ptr[0..len], .@"1", @returnAddress());
    }
};

pub const RawRemapProperty = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, allocator: Allocator) !void {
        const mode = try drawPropertyMode(conjecture);
        var heap = DeadAllocator.init(allocator, .{
            .mode = mode,
            .seed = 0x4e4d_a9 + @as(u64, @backingInt(mode)),
            .min_chunk_blocks = 8,
            .thread_safe = false,
            .diagnostics = .{ .enabled = true, .red_zone_bytes = 16, .quarantine_epochs = 4 },
        });
        defer heap.deinit();
        const dead_allocator = heap.allocator();

        const alignment_shift = try drawPropertyUsize(conjecture, 0, 8, 0);
        const alignment = Alignment.fromByteUnits(@as(usize, 1) << @as(u6, @intCast(alignment_shift)));
        const old_len = try drawPropertyUsize(conjecture, 1, 512, 8);
        const old_block_size = propertyClassSizeFor(old_len + 16, alignment);
        const relocates = try drawPropertyUsize(conjecture, 0, 1, 0) == 1;
        const new_len = if (relocates)
            old_block_size + try drawPropertyUsize(conjecture, 1, 4096, 1)
        else
            try drawPropertyUsize(conjecture, 1, old_block_size - 16, @min(old_len, old_block_size - 16));

        const ptr = dead_allocator.rawAlloc(old_len, alignment, @returnAddress()) orelse return error.OutOfMemory;
        var index: usize = 0;
        while (index < old_len) : (index += 1) {
            ptr[index] = @truncate(index *% 131 +% old_len);
        }

        const remapped = dead_allocator.rawRemap(ptr[0..old_len], alignment, new_len, @returnAddress()) orelse return error.OutOfMemory;
        const prefix_len = @min(old_len, new_len);
        index = 0;
        while (index < prefix_len) : (index += 1) {
            try std.testing.expectEqual(@as(u8, @truncate(index *% 131 +% old_len)), remapped[index]);
        }
        try std.testing.expect(std.mem.isAligned(@intFromPtr(remapped), alignment.toByteUnits()));

        const live_report = heap.report();
        try std.testing.expectEqual(@as(usize, 1), live_report.live_allocations);
        try std.testing.expectEqual(new_len, live_report.live_bytes);
        try std.testing.expectEqual(@as(usize, 1), live_report.leak_count);
        try std.testing.expectEqual(@as(usize, 0), live_report.counters.issueCount());

        dead_allocator.rawFree(remapped[0..new_len], alignment, @returnAddress());
        try std.testing.expect(heap.report().isClean());
    }
};

pub const DiagnosticHistoryProperty = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, allocator: Allocator) !void {
        var heap = DeadAllocator.init(allocator, .{
            .mode = .exterminator,
            .seed = 0x155e_109,
            .min_chunk_blocks = 8,
            .thread_safe = false,
            .diagnostics = .{ .enabled = true },
        });
        defer heap.deinit();
        const dead_allocator = heap.allocator();

        const count = try drawPropertyUsize(conjecture, 1, max_issues + 16, max_issues);
        var stack_byte: u8 = 0;
        var index: usize = 0;
        while (index < count) : (index += 1) {
            dead_allocator.rawFree((&stack_byte)[0..1], .@"1", @returnAddress());
        }

        const report = heap.report();
        const issues = report.issueSlice();
        const retained = @min(count, max_issues);
        try std.testing.expectEqual(count, report.counters.invalid_free);
        try std.testing.expectEqual(retained, issues.len);
        try std.testing.expectEqual(count - retained, report.issues.dropped);
        for (issues) |issue| {
            try std.testing.expectEqual(.invalid_free, issue.kind);
            try std.testing.expectEqual(@intFromPtr(&stack_byte), issue.address);
        }
    }
};

pub const LeakIssueProperty = struct {
    pub fn property(conjecture: *hypothesis.ConjectureData, allocator: Allocator) !void {
        var heap = DeadAllocator.init(allocator, .{
            .mode = .exterminator,
            .seed = 0x1ea_5eed,
            .min_chunk_blocks = 8,
            .thread_safe = false,
            .diagnostics = .{ .enabled = true },
        });
        defer heap.deinit();
        const dead_allocator = heap.allocator();

        var allocations: std.ArrayList([]u8) = .empty;
        defer allocations.deinit(allocator);
        defer {
            for (allocations.items) |allocation| dead_allocator.free(allocation);
        }

        const count = try drawPropertyUsize(conjecture, 1, max_issues + 16, max_issues);
        var expected_bytes: usize = 0;
        var index: usize = 0;
        while (index < count) : (index += 1) {
            const len = try drawPropertyUsize(conjecture, 1, 512, 8);
            const allocation = try dead_allocator.alloc(u8, len);
            @memset(allocation, @as(u8, @truncate(index)));
            try allocations.append(allocator, allocation);
            expected_bytes += len;
        }

        const report = heap.report();
        const issues = report.issueSlice();
        const retained = @min(count, max_issues);
        var leak_issues: usize = 0;
        for (issues) |issue| {
            try std.testing.expectEqual(.leak, issue.kind);
            try std.testing.expect(issue.requested_len > 0);
            try std.testing.expect(issue.allocation_id != 0);
            leak_issues += 1;
        }

        try std.testing.expectEqual(count, report.live_allocations);
        try std.testing.expectEqual(count, report.leak_count);
        try std.testing.expectEqual(expected_bytes, report.live_bytes);
        try std.testing.expectEqual(retained, leak_issues);
        try std.testing.expectEqual(count - retained, report.issues.dropped);
        try std.testing.expect(report.leak_issue != null);
    }
};

test "property: allocator operations preserve active ranges" {
    try hypothesis.checkNamed(AllocatorStateProperty, "deadalloc-state", settings());
}

test "property: diagnostics classify generated allocation faults" {
    try hypothesis.checkNamed(DiagnosticFaultProperty, "deadalloc-diagnostics", settings());
}

test "property: allocations satisfy requested alignment" {
    try hypothesis.checkNamed(AlignmentProperty, "deadalloc-alignment", settings());
}

test "property: dieharder large allocations are page granular" {
    try hypothesis.checkNamed(LargeAllocationProperty, "deadalloc-dieharder-large", settings());
}

test "property: dieharder interior frees retain allocation context" {
    try hypothesis.checkNamed(InteriorFreeProperty, "deadalloc-dieharder-interior-free", settings());
}

test "property: raw remap preserves prefixes and ownership" {
    try hypothesis.checkNamed(RawRemapProperty, "deadalloc-raw-remap", settings());
}

test "property: diagnostic issue history is bounded and ordered" {
    try hypothesis.checkNamed(DiagnosticHistoryProperty, "deadalloc-diagnostic-history", settings());
}

test "property: leak issues are bounded and structured" {
    try hypothesis.checkNamed(LeakIssueProperty, "deadalloc-leak-issues", settings());
}
