const std = @import("std");
const errno = @import("errno.zig");
const heap = @import("../heap/root.zig");
const info = @import("info.zig");
const layout = @import("../root.zig").layout;

pub fn aligned_alloc(alignment: usize, size: usize) callconv(.c) ?*anyopaque {
    if (!layout.validAlignment(alignment)) return errno.fail(errno.posix_einval);
    if (size % alignment != 0) return errno.fail(errno.posix_einval);
    return heap.allocate(size, alignment) orelse errno.fail(errno.posix_enomem);
}

pub fn posix_memalign(out_ptr: *?*anyopaque, alignment: usize, size: usize) callconv(.c) c_int {
    if (!layout.validAlignment(alignment) or alignment % @sizeOf(*anyopaque) != 0) {
        return errno.posix_einval;
    }
    const ptr = heap.allocate(size, alignment) orelse {
        return errno.posix_enomem;
    };
    out_ptr.* = ptr;
    return 0;
}

pub fn memalign(alignment: usize, size: usize) callconv(.c) ?*anyopaque {
    const normalized_alignment = layout.memalignAlignment(alignment) orelse
        return errno.fail(errno.posix_einval);
    return heap.allocate(size, normalized_alignment) orelse errno.fail(errno.posix_enomem);
}

pub fn valloc(size: usize) callconv(.c) ?*anyopaque {
    return heap.allocate(size, std.heap.page_size_min) orelse errno.fail(errno.posix_enomem);
}

pub fn pvalloc(size: usize) callconv(.c) ?*anyopaque {
    const rounded_size = layout.alignForwardSize(size, std.heap.page_size_min) orelse
        return errno.fail(errno.posix_enomem);
    return heap.allocate(rounded_size, std.heap.page_size_min) orelse errno.fail(errno.posix_enomem);
}

test "over-aligned allocations keep extended metadata" {
    const ptr = aligned_alloc(64, 256) orelse return error.OutOfMemory;
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(ptr) % 64);
    try std.testing.expectEqual(@as(usize, 256), info.malloc_usable_size(ptr));

    const grown = @import("malloc/root.zig").realloc(ptr, 512) orelse return error.OutOfMemory;
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(grown) % 64);
    try std.testing.expectEqual(@as(usize, 512), info.malloc_usable_size(grown));
    @import("malloc/root.zig").free(grown);
}

test "aligned_alloc rejects invalid alignment" {
    try std.testing.expect(aligned_alloc(24, 96) == null);

    const ptr = aligned_alloc(64, 128) orelse return error.OutOfMemory;
    defer @import("malloc/root.zig").free(ptr);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(ptr) % 64);
    try std.testing.expectEqual(@as(usize, 128), info.malloc_usable_size(ptr));
}

test "aligned allocation failures set errno" {
    errno.set(0);
    try std.testing.expect(aligned_alloc(24, 96) == null);
    try std.testing.expectEqual(@as(c_int, errno.posix_einval), errno.current());

    errno.set(0);
    try std.testing.expect(memalign(std.math.maxInt(usize), std.heap.page_size_min) == null);
    try std.testing.expectEqual(@as(c_int, errno.posix_einval), errno.current());
}

test "memalign rounds non-power-of-two alignment" {
    const small = memalign(24, 96) orelse return error.OutOfMemory;
    defer @import("malloc/root.zig").free(small);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(small) % 32);

    const rounded = memalign(257, 10) orelse return error.OutOfMemory;
    defer @import("malloc/root.zig").free(rounded);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(rounded) % 512);

    const zero = memalign(@sizeOf(*anyopaque), 0) orelse return error.OutOfMemory;
    defer @import("malloc/root.zig").free(zero);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(zero) % @sizeOf(*anyopaque));
    try std.testing.expectEqual(@as(usize, 0), info.malloc_usable_size(zero));
}

test "pvalloc returns page aligned rounded storage" {
    const ptr = pvalloc(513) orelse return error.OutOfMemory;
    defer @import("malloc/root.zig").free(ptr);

    const page_size = std.heap.page_size_min;
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(ptr) % page_size);
    try std.testing.expect(info.malloc_usable_size(ptr) >= page_size);
    @memset(heap.bytes(ptr, 513), 0x7d);
    for (heap.bytes(ptr, 513)) |byte| {
        try std.testing.expectEqual(@as(u8, 0x7d), byte);
    }
}

test "posix_memalign failures leave output pointer unchanged" {
    const sentinel: *anyopaque = @ptrFromInt(1);
    var out: ?*anyopaque = sentinel;

    try std.testing.expectEqual(@as(c_int, errno.posix_einval), posix_memalign(&out, 24, 257));
    try std.testing.expectEqual(sentinel, out.?);
}

test "posix_memalign returns status and preserves failure output" {
    const malloc = @import("malloc/root.zig");
    const invalid_sentinel: *anyopaque = @ptrFromInt(1);
    var invalid_out: ?*anyopaque = invalid_sentinel;
    errno.set(errno.posix_enomem);
    try std.testing.expectEqual(@as(c_int, errno.posix_einval), posix_memalign(&invalid_out, 24, 257));
    try std.testing.expectEqual(invalid_sentinel, invalid_out.?);
    try std.testing.expectEqual(@as(c_int, errno.posix_enomem), errno.current());

    const huge_sentinel: *anyopaque = @ptrFromInt(1);
    var huge_out: ?*anyopaque = huge_sentinel;
    errno.set(errno.posix_einval);
    try std.testing.expectEqual(
        @as(c_int, errno.posix_enomem),
        posix_memalign(&huge_out, 16, std.math.maxInt(usize)),
    );
    try std.testing.expectEqual(huge_sentinel, huge_out.?);

    var success_out: ?*anyopaque = null;
    errno.set(errno.posix_einval);
    try std.testing.expectEqual(@as(c_int, 0), posix_memalign(&success_out, 64, 128));
    const ptr = success_out orelse return error.OutOfMemory;
    defer malloc.free(ptr);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(ptr) % 64);
    try std.testing.expectEqual(@as(c_int, errno.posix_einval), errno.current());

    var zero_out: ?*anyopaque = @ptrFromInt(1);
    errno.set(errno.posix_enomem);
    try std.testing.expectEqual(@as(c_int, 0), posix_memalign(&zero_out, 64, 0));
    try std.testing.expectEqual(@as(c_int, errno.posix_enomem), errno.current());
    if (zero_out) |zero_ptr| {
        defer malloc.free(zero_ptr);
        try std.testing.expectEqual(@as(usize, 0), @intFromPtr(zero_ptr) % 64);
        try std.testing.expectEqual(@as(usize, 0), info.malloc_usable_size(zero_ptr));
    }
}
