const std = @import("std");
const preload = @import("../root.zig");
const accounting = preload.accounting;
const layout = preload.layout;
const state = @import("state.zig");

pub fn deallocate(ptr: ?*anyopaque) void {
    const user_ptr = ptr orelse return;
    const prefix = layout.prefixFromUserPointer(user_ptr);
    if (prefix.magic == layout.fast_header_magic) {
        deallocateFast(prefix);
        return;
    }
    deallocatePrefixed(prefix);
}

pub fn deallocateFast(header: *layout.HeaderPrefix) void {
    const requested_size = accounting.requestedSizeFromValue(header.value);
    const accounted = accounting.accountedFromValue(header.value);
    accounting.recordDeallocation(requested_size, accounted);
    header.magic = 0;
    const base: [*]u8 = @ptrCast(header);
    if (requested_size <= layout.fast_small_requested_limit) {
        state.allocator.rawFreeThreadCachedSmallBlock(base, state.preload_ret_addr);
        return;
    }
    const total_len = layout.fastTotalAllocationLen(requested_size) orelse return;
    state.allocator.rawFree(
        base[0..total_len],
        std.mem.Alignment.fromByteUnits(layout.c_alignment),
        state.preload_ret_addr,
    );
}

pub fn deallocateExtended(header: *layout.ExtendedHeader) void {
    accounting.recordDeallocation(
        accounting.requestedSizeFromValue(header.requested_len),
        accounting.accountedFromValue(header.requested_len),
    );
    header.magic = 0;
    const base: [*]u8 = @ptrFromInt(header.base_addr);
    const allocation = base[0..header.total_len];
    state.allocator.rawFree(
        allocation,
        std.mem.Alignment.fromByteUnits(layout.c_alignment),
        state.preload_ret_addr,
    );
}

fn deallocatePrefixed(prefix: *layout.HeaderPrefix) void {
    switch (layout.metadataFromPrefix(prefix)) {
        .fast => |header| deallocateFast(header),
        .extended => |header| deallocateExtended(header),
        .foreign => {},
    }
}
