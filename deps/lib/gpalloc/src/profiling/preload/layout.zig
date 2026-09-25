const std = @import("std");
const gpalloc = @import("gpalloc");
const accounting = @import("accounting.zig");

pub const c_alignment = 16;
pub const fast_header_magic: u64 = 0x5441_4641_5354_0001;
pub const extended_header_magic: u64 = 0x5441_4558_5444_0001;
pub const prefix_size = @sizeOf(HeaderPrefix);
pub const extended_header_size = @sizeOf(ExtendedHeader);
pub const fast_min_total_len = prefix_size + c_alignment;
pub const fast_small_requested_limit = gpalloc.max_small_size - prefix_size;

pub const HeaderPrefix = extern struct {
    magic: u64,
    value: usize,
};

pub const ExtendedHeader = extern struct {
    magic: u64,
    base_addr: usize,
    total_len: usize,
    requested_len: usize,
    requested_alignment: usize,
};

pub const Metadata = union(enum) {
    fast: *HeaderPrefix,
    extended: *ExtendedHeader,
    foreign,
};

pub fn fastTotalAllocationLen(requested_size: usize) ?usize {
    if (!accounting.validRequestedSize(requested_size)) return null;
    const total_len = std.math.add(usize, @max(requested_size, 1), prefix_size) catch
        return null;
    return @max(total_len, fast_min_total_len);
}

pub fn extendedTotalAllocationLen(allocation_size: usize, alignment: usize) ?usize {
    if (!accounting.validRequestedSize(allocation_size)) return null;
    const metadata_len = std.math.add(usize, extended_header_size, prefix_size) catch
        return null;
    const aligned_payload = std.math.add(usize, allocation_size, alignment - 1) catch
        return null;
    return std.math.add(usize, aligned_payload, metadata_len) catch return null;
}

pub fn metadataFromPrefix(prefix: *HeaderPrefix) Metadata {
    if (prefix.magic == fast_header_magic) return .{ .fast = prefix };
    if (prefix.magic == extended_header_magic) {
        const header: *ExtendedHeader = @ptrFromInt(prefix.value);
        if (header.magic == extended_header_magic) return .{ .extended = header };
    }
    return .foreign;
}

pub fn metadataFromUserPointer(ptr: *anyopaque) Metadata {
    return metadataFromPrefix(prefixFromUserPointer(ptr));
}

pub fn prefixFromUserPointer(ptr: *anyopaque) *HeaderPrefix {
    return @ptrFromInt(@intFromPtr(ptr) - prefix_size);
}

pub fn validAlignment(alignment: usize) bool {
    return alignment != 0 and std.math.isPowerOfTwo(alignment);
}

pub fn memalignAlignment(alignment: usize) ?usize {
    const requested_alignment = @max(alignment, @sizeOf(*anyopaque));
    if (std.math.isPowerOfTwo(requested_alignment)) return requested_alignment;
    return std.math.ceilPowerOfTwo(usize, requested_alignment) catch null;
}

pub fn alignForwardSize(size: usize, alignment: usize) ?usize {
    const mask = alignment - 1;
    const biased = std.math.add(usize, size, mask) catch return null;
    return biased & ~mask;
}
