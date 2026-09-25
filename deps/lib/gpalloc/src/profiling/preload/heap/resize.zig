const std = @import("std");
const preload = @import("../root.zig");
const accounting = preload.accounting;
const layout = preload.layout;
const allocate_module = @import("allocate.zig");
const free_module = @import("free.zig");
const memory = @import("memory.zig");
const state = @import("state.zig");

pub const Resize = union(enum) {
    pointer: *anyopaque,
    freed,
    invalid,
    no_memory,
};

pub fn resize(ptr: ?*anyopaque, size: usize) Resize {
    const old_ptr = ptr orelse {
        const new_ptr = allocate_module.allocateFast(size) orelse return .no_memory;
        return .{ .pointer = new_ptr };
    };
    if (size == 0) {
        free_module.deallocate(old_ptr);
        return .freed;
    }

    return switch (layout.metadataFromUserPointer(old_ptr)) {
        .fast => |old_header| resizeFast(old_ptr, old_header, size),
        .extended => |old_header| resizeExtended(old_ptr, old_header, size),
        .foreign => .invalid,
    };
}

fn resizeFast(
    old_ptr: *anyopaque,
    old_header: *layout.HeaderPrefix,
    size: usize,
) Resize {
    const old_size = accounting.requestedSizeFromValue(old_header.value);
    const old_accounted = accounting.accountedFromValue(old_header.value);
    const new_total_len = layout.fastTotalAllocationLen(size) orelse return .no_memory;
    const old_total_len = layout.fastTotalAllocationLen(old_size) orelse return .no_memory;
    if (resizeFastInPlace(
        old_header,
        old_size,
        old_accounted,
        size,
        old_total_len,
        new_total_len,
    )) {
        return .{ .pointer = old_ptr };
    }

    return moveFastAllocation(old_ptr, old_header, old_size, size);
}

fn resizeFastInPlace(
    old_header: *layout.HeaderPrefix,
    old_size: usize,
    old_accounted: bool,
    size: usize,
    old_total_len: usize,
    new_total_len: usize,
) bool {
    const old_base: [*]u8 = @ptrCast(old_header);
    const old_allocation = old_base[0..old_total_len];
    if (!state.allocator.rawResize(
        old_allocation,
        std.mem.Alignment.fromByteUnits(layout.c_alignment),
        new_total_len,
        state.preload_ret_addr,
    )) {
        return false;
    }

    const accounted = accounting.recordResize(old_size, size, old_accounted);
    old_header.value = accounting.encodeRequestedValue(size, accounted);
    return true;
}

fn moveFastAllocation(
    old_ptr: *anyopaque,
    old_header: *layout.HeaderPrefix,
    old_size: usize,
    size: usize,
) Resize {
    const new_ptr = allocate_module.allocateFast(size) orelse return .no_memory;
    const copy_len = @min(size, old_size);
    @memcpy(memory.bytes(new_ptr, copy_len), memory.bytes(old_ptr, copy_len));
    free_module.deallocateFast(old_header);
    return .{ .pointer = new_ptr };
}

fn resizeExtended(
    old_ptr: *anyopaque,
    old_header: *layout.ExtendedHeader,
    size: usize,
) Resize {
    const old_size = accounting.requestedSizeFromValue(old_header.requested_len);
    const old_accounted = accounting.accountedFromValue(old_header.requested_len);
    const new_allocation_size = @max(size, 1);
    const new_total_len = layout.extendedTotalAllocationLen(
        new_allocation_size,
        old_header.requested_alignment,
    ) orelse return .no_memory;
    if (resizeExtendedInPlace(
        old_header,
        old_size,
        old_accounted,
        size,
        new_total_len,
    )) {
        return .{ .pointer = old_ptr };
    }

    return moveExtendedAllocation(old_ptr, old_header, old_size, size);
}

fn resizeExtendedInPlace(
    old_header: *layout.ExtendedHeader,
    old_size: usize,
    old_accounted: bool,
    size: usize,
    new_total_len: usize,
) bool {
    const old_base: [*]u8 = @ptrFromInt(old_header.base_addr);
    const old_allocation = old_base[0..old_header.total_len];
    if (!state.allocator.rawResize(
        old_allocation,
        std.mem.Alignment.fromByteUnits(layout.c_alignment),
        new_total_len,
        state.preload_ret_addr,
    )) {
        return false;
    }

    const accounted = accounting.recordResize(old_size, size, old_accounted);
    old_header.total_len = new_total_len;
    old_header.requested_len = accounting.encodeRequestedValue(size, accounted);
    return true;
}

fn moveExtendedAllocation(
    old_ptr: *anyopaque,
    old_header: *layout.ExtendedHeader,
    old_size: usize,
    size: usize,
) Resize {
    const new_ptr = allocate_module.allocate(size, old_header.requested_alignment) orelse
        return .no_memory;
    const copy_len = @min(size, old_size);
    @memcpy(memory.bytes(new_ptr, copy_len), memory.bytes(old_ptr, copy_len));
    free_module.deallocateExtended(old_header);
    return .{ .pointer = new_ptr };
}
