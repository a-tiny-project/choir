const std = @import("std");
const memtrace = @import("memtrace");

pub const small_allocations: usize = 1024;
pub const large_allocations: usize = 8192;
pub const live_batch_size: usize = 256;

pub const State = struct {
    small: []const u8,
    large: []const u8,
};

const scopes = [_][]const u8{
    "root/parse",
    "root/lower",
    "root/execute",
    "root/report",
};

const Allocation = struct {
    id: u64,
    address: usize,
    len: usize,
    scope: []const u8,
    return_address: usize,
};

var state: ?State = null;

pub fn get() *const State {
    if (state) |*built| return built;
    @panic("memtrace profiling corpus not built");
}

pub fn reset() void {
    state = null;
}

pub fn build(arena: std.mem.Allocator) !void {
    var output = std.Io.Writer.Allocating.init(arena);
    var seq: u64 = 1;
    try writeEvent(&output.writer, .{
        .seq = seq,
        .kind = .allocator,
        .allocator_id = 1,
        .retains_freed_memory = false,
    }, "heap", "root");
    seq += 1;

    var small_end: usize = 0;
    for (0..large_allocations / live_batch_size) |batch| {
        const base = batch * live_batch_size;
        for (0..live_batch_size) |offset| {
            try writeAllocation(&output.writer, &seq, allocationAt(base + offset));
        }
        for (0..live_batch_size) |step| {
            try writeFree(&output.writer, &seq, allocationAt(base + freeIndex(batch, step)));
        }
        if (base + live_batch_size == small_allocations) small_end = output.written().len;
    }

    const bytes = output.written();
    state = .{
        .small = bytes[0..small_end],
        .large = bytes,
    };
}

fn allocationAt(index: usize) Allocation {
    return .{
        .id = @intCast(index + 1),
        .address = 0x1000 + index * 128,
        .len = 16 + (index % 16) * 8,
        .scope = scopes[index % scopes.len],
        .return_address = 0x100000 + (index % 32) * 16,
    };
}

fn freeIndex(batch: usize, step: usize) usize {
    return switch (batch % 3) {
        0 => live_batch_size - 1 - step,
        1 => step,
        2 => @bitReverse(@as(u8, @intCast(step))),
        else => unreachable,
    };
}

fn writeAllocation(writer: *std.Io.Writer, seq: *u64, allocation: Allocation) !void {
    try writeEvent(writer, .{
        .seq = seq.*,
        .kind = .alloc,
        .allocator_id = 1,
        .allocation_id = allocation.id,
        .address = allocation.address,
        .len = allocation.len,
        .alignment = 8,
        .return_address = allocation.return_address,
        .live_bytes = allocation.len,
    }, null, allocation.scope);
    seq.* += 1;
}

fn writeFree(writer: *std.Io.Writer, seq: *u64, allocation: Allocation) !void {
    try writeEvent(writer, .{
        .seq = seq.*,
        .kind = .free,
        .allocator_id = 1,
        .allocation_id = allocation.id,
        .address = allocation.address,
        .old_len = allocation.len,
        .len = allocation.len,
        .return_address = allocation.return_address,
    }, null, allocation.scope);
    seq.* += 1;
}

fn writeEvent(writer: *std.Io.Writer, event: memtrace.Event, label: ?[]const u8, scope: ?[]const u8) !void {
    try event.writeJsonLine(writer, label, scope);
}

test "memtrace profiling corpus has deterministic event counts" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    try build(arena_state.allocator());
    defer reset();

    try std.testing.expectEqual(1 + small_allocations * 2, std.mem.count(u8, get().small, "\n"));
    try std.testing.expectEqual(1 + large_allocations * 2, std.mem.count(u8, get().large, "\n"));
    const first_free = std.mem.indexOf(u8, get().large, "\"kind\":\"free\"").?;
    try std.testing.expectEqual(live_batch_size, std.mem.count(u8, get().large[0..first_free], "\"kind\":\"alloc\""));
}
