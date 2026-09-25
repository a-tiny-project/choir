const std = @import("std");
const preload = @import("../root.zig");
const accounting = preload.accounting;
const layout = preload.layout;
const state = @import("state.zig");

pub fn allocate(requested_size: usize, requested_alignment: usize) ?*anyopaque {
    const allocation_size = @max(requested_size, 1);
    const alignment = @max(requested_alignment, layout.c_alignment);
    if (!layout.validAlignment(alignment)) return null;
    if (alignment <= layout.c_alignment) return allocateFast(requested_size);

    return allocateExtended(requested_size, allocation_size, alignment);
}

pub fn allocateFast(requested_size: usize) ?*anyopaque {
    const total_len = layout.fastTotalAllocationLen(requested_size) orelse return null;
    const base = state.allocator.rawAlloc(
        total_len,
        std.mem.Alignment.fromByteUnits(layout.c_alignment),
        state.preload_ret_addr,
    ) orelse return null;
    const header: *layout.HeaderPrefix = @ptrCast(@alignCast(base));
    const accounted = accounting.recordAllocation(requested_size);
    header.* = .{
        .magic = layout.fast_header_magic,
        .value = accounting.encodeRequestedValue(requested_size, accounted),
    };
    return @ptrFromInt(@intFromPtr(base) + layout.prefix_size);
}

pub fn allocateFastOrTrap(requested_size: usize) *anyopaque {
    return allocateFast(requested_size) orelse @trap();
}

pub fn allocateOrTrap(requested_size: usize, requested_alignment: usize) *anyopaque {
    return allocate(requested_size, requested_alignment) orelse @trap();
}

fn allocateExtended(requested_size: usize, allocation_size: usize, alignment: usize) ?*anyopaque {
    const total_len = layout.extendedTotalAllocationLen(allocation_size, alignment) orelse
        return null;

    const base = state.allocator.rawAlloc(
        total_len,
        std.mem.Alignment.fromByteUnits(layout.c_alignment),
        state.preload_ret_addr,
    ) orelse return null;
    const user_addr = std.mem.alignForward(
        usize,
        @intFromPtr(base) + layout.extended_header_size + layout.prefix_size,
        alignment,
    );
    const header: *layout.ExtendedHeader = @ptrCast(@alignCast(base));
    const accounted = accounting.recordAllocation(requested_size);
    header.* = .{
        .magic = layout.extended_header_magic,
        .base_addr = @intFromPtr(base),
        .total_len = total_len,
        .requested_len = accounting.encodeRequestedValue(requested_size, accounted),
        .requested_alignment = alignment,
    };
    const prefix: *layout.HeaderPrefix = @ptrFromInt(user_addr - layout.prefix_size);
    prefix.* = .{
        .magic = layout.extended_header_magic,
        .value = @intFromPtr(header),
    };
    return @ptrFromInt(user_addr);
}
