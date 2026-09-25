const std = @import("std");
const errno = @import("../root.zig").errno;
const heap = @import("../../heap/root.zig");
const info = @import("../root.zig").info;
const layout = @import("../../root.zig").layout;

pub fn malloc(size: usize) callconv(.c) ?*anyopaque {
    return heap.allocateFast(size) orelse errno.fail(errno.posix_enomem);
}

pub fn free(ptr: ?*anyopaque) callconv(.c) void {
    heap.deallocate(ptr);
}

pub fn calloc(count: usize, size: usize) callconv(.c) ?*anyopaque {
    const total = std.math.mul(usize, count, size) catch return errno.fail(errno.posix_enomem);
    const ptr = heap.allocateFast(total) orelse return errno.fail(errno.posix_enomem);
    @memset(heap.bytes(ptr, total), 0);
    return ptr;
}

test "calloc rejects overflowing element counts" {
    try std.testing.expect(calloc(std.math.maxInt(usize) / 2 + 2, 2) == null);

    const ptr = calloc(4, 8) orelse return error.OutOfMemory;
    defer free(ptr);

    for (heap.bytes(ptr, 32)) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "malloc rejects impossible sizes and remains usable" {
    try std.testing.expect(malloc(std.math.maxInt(usize)) == null);

    const ptr = malloc(16) orelse return error.OutOfMemory;
    defer free(ptr);
    @memset(heap.bytes(ptr, 16), 0x45);
}

test "malloc allocation failures set errno" {
    errno.set(0);
    try std.testing.expect(malloc(std.math.maxInt(usize)) == null);
    try std.testing.expectEqual(@as(c_int, errno.posix_enomem), errno.current());

    errno.set(0);
    try std.testing.expect(calloc(std.math.maxInt(usize) / 2 + 2, 2) == null);
    try std.testing.expectEqual(@as(c_int, errno.posix_enomem), errno.current());
}

test "free operations preserve errno" {
    errno.set(errno.posix_einval);
    free(null);
    try std.testing.expectEqual(@as(c_int, errno.posix_einval), errno.current());

    const ptr = malloc(32) orelse return error.OutOfMemory;
    @memset(heap.bytes(ptr, 32), 0x6c);
    errno.set(errno.posix_enomem);
    free(ptr);
    try std.testing.expectEqual(@as(c_int, errno.posix_enomem), errno.current());
}

test "malloc zero keeps requested usable size" {
    const ptr = malloc(0) orelse return error.OutOfMemory;
    defer free(ptr);

    try std.testing.expectEqual(@as(usize, 0), info.malloc_usable_size(ptr));
}

test "zero-size allocation calls keep freeable requested size" {
    const count_zero = calloc(0, 64) orelse return error.OutOfMemory;
    defer free(count_zero);
    try std.testing.expectEqual(@as(usize, 0), info.malloc_usable_size(count_zero));

    const size_zero = calloc(64, 0) orelse return error.OutOfMemory;
    defer free(size_zero);
    try std.testing.expectEqual(@as(usize, 0), info.malloc_usable_size(size_zero));
}

test "fast allocation entry points preserve C alignment with the smallest metadata floor" {
    const ptr = malloc(1) orelse return error.OutOfMemory;
    defer free(ptr);

    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(ptr) % layout.c_alignment);

    const calloc_ptr = calloc(3, 17) orelse return error.OutOfMemory;
    defer free(calloc_ptr);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(calloc_ptr) % layout.c_alignment);

    try std.testing.expectEqual(@as(usize, 32), layout.fastTotalAllocationLen(0).?);
    try std.testing.expectEqual(@as(usize, 32), layout.fastTotalAllocationLen(16).?);
    try std.testing.expectEqual(@as(usize, 33), layout.fastTotalAllocationLen(17).?);
}
