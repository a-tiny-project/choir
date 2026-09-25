const std = @import("std");
const preload_layout = @import("layout.zig");
const raw_record = @import("raw.zig");

pub const Header = preload_layout.Header;
pub const magic = preload_layout.magic;
pub const alignment_bytes = preload_layout.alignment_bytes;
pub const header_bytes = preload_layout.header_bytes;
pub const min_total_len = preload_layout.min_total_len;

pub fn totalLen(user_len: usize) usize {
    const prefixed_len = @max(user_len, 1) + header_bytes;
    return @max(prefixed_len, min_total_len);
}

pub fn alloc(
    allocator: std.mem.Allocator,
    alignment: std.mem.Alignment,
    user_len: usize,
    salt: usize,
) raw_record.RawRecord {
    const full_len = totalLen(user_len);
    const ptr = allocator.rawAlloc(full_len, alignment, @returnAddress()) orelse @panic("allocation failed");
    if (@intFromPtr(ptr) % alignment_bytes != 0) @panic("misaligned allocation");
    const header: *Header = @ptrCast(@alignCast(ptr));
    header.* = .{ .magic = magic, .value = user_len };
    const bytes = ptr[header_bytes .. header_bytes + user_len];
    if (bytes.len != 0) {
        bytes[0] = @truncate(salt);
        bytes[bytes.len - 1] = @truncate(bytes.len + salt);
        std.mem.doNotOptimizeAway(bytes.ptr);
    }
    return .{ .ptr = ptr, .len = full_len, .alignment = alignment };
}

pub fn free(allocator: std.mem.Allocator, record: raw_record.RawRecord) void {
    const header: *Header = @ptrCast(@alignCast(record.ptr));
    if (header.magic != magic) @panic("invalid preload allocation");
    const full_len = totalLen(header.value);
    if (full_len != record.len) @panic("invalid preload length");
    header.magic = 0;
    std.mem.doNotOptimizeAway(record.ptr);
    allocator.rawFree(record.ptr[0..record.len], record.alignment, @returnAddress());
}

pub fn payload(record: raw_record.RawRecord) []u8 {
    const header: *Header = @ptrCast(@alignCast(record.ptr));
    if (header.magic != magic) @panic("invalid preload allocation");
    return record.ptr[header_bytes .. header_bytes + header.value];
}
