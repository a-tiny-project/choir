const std = @import("std");
const allocation = @import("allocation.zig");
const errno = @import("../root.zig").errno;
const heap = @import("../../heap/root.zig");
const info = @import("../root.zig").info;
const layout = @import("../../root.zig").layout;

pub fn realloc(ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    return switch (heap.resize(ptr, size)) {
        .pointer => |new_ptr| new_ptr,
        .freed => null,
        .invalid => errno.fail(errno.posix_einval),
        .no_memory => errno.fail(errno.posix_enomem),
    };
}

pub fn reallocarray(ptr: ?*anyopaque, count: usize, size: usize) callconv(.c) ?*anyopaque {
    const total = std.math.mul(usize, count, size) catch return errno.fail(errno.posix_enomem);
    return realloc(ptr, total);
}

test "realloc keeps the pointer inside the same size class" {
    const initial = allocation.malloc(200) orelse return error.OutOfMemory;
    @memset(heap.bytes(initial, 24), 0xc4);

    const same_class = realloc(initial, 192) orelse return error.OutOfMemory;
    try std.testing.expectEqual(initial, same_class);
    try std.testing.expectEqual(@as(usize, 192), info.malloc_usable_size(same_class));

    const shrunk = realloc(same_class, 24) orelse return error.OutOfMemory;
    try std.testing.expect(initial != shrunk);
    try std.testing.expectEqual(@as(usize, 24), info.malloc_usable_size(shrunk));
    for (heap.bytes(shrunk, 24)) |byte| {
        try std.testing.expectEqual(@as(u8, 0xc4), byte);
    }

    const grown = realloc(shrunk, 128) orelse return error.OutOfMemory;
    try std.testing.expectEqual(@as(usize, 128), info.malloc_usable_size(grown));
    for (heap.bytes(grown, 24)) |byte| {
        try std.testing.expectEqual(@as(u8, 0xc4), byte);
    }

    allocation.free(grown);
}

test "reallocarray preserves prefix and rejects overflow" {
    const initial = allocation.malloc(64) orelse return error.OutOfMemory;
    @memset(heap.bytes(initial, 64), 0xa5);

    const grown = reallocarray(initial, 16, 64) orelse {
        allocation.free(initial);
        return error.OutOfMemory;
    };
    defer allocation.free(grown);

    try std.testing.expectEqual(@as(usize, 1024), info.malloc_usable_size(grown));
    for (heap.bytes(grown, 64)) |byte| {
        try std.testing.expectEqual(@as(u8, 0xa5), byte);
    }
    @memset(heap.bytes(grown, 1024), 0x3c);
    try std.testing.expect(reallocarray(null, std.math.maxInt(usize) / 2 + 2, 2) == null);
}

test "resize failures set errno and preserve original allocations" {
    const ptr = allocation.malloc(64) orelse return error.OutOfMemory;
    defer allocation.free(ptr);
    @memset(heap.bytes(ptr, 64), 0xa9);

    errno.set(0);
    try std.testing.expect(realloc(ptr, std.math.maxInt(usize)) == null);
    try std.testing.expectEqual(@as(c_int, errno.posix_enomem), errno.current());
    for (heap.bytes(ptr, 64)) |byte| {
        try std.testing.expectEqual(@as(u8, 0xa9), byte);
    }

    errno.set(0);
    try std.testing.expect(reallocarray(null, std.math.maxInt(usize) / 2 + 2, 2) == null);
    try std.testing.expectEqual(@as(c_int, errno.posix_enomem), errno.current());
}

test "realloc zero frees and returns null" {
    const ptr = allocation.malloc(64) orelse return error.OutOfMemory;
    @memset(heap.bytes(ptr, 64), 0x5a);

    try std.testing.expect(realloc(ptr, 0) == null);

    const next = allocation.malloc(32) orelse return error.OutOfMemory;
    defer allocation.free(next);
    @memset(heap.bytes(next, 32), 0x33);
}

test "realloc zero preserves errno" {
    const ptr = allocation.malloc(48) orelse return error.OutOfMemory;
    @memset(heap.bytes(ptr, 48), 0x2f);
    errno.set(errno.posix_einval);
    try std.testing.expect(realloc(ptr, 0) == null);
    try std.testing.expectEqual(@as(c_int, errno.posix_einval), errno.current());
}

test "realloc null zero keeps requested usable size" {
    const realloc_zero = realloc(null, 0) orelse return error.OutOfMemory;
    defer allocation.free(realloc_zero);
    try std.testing.expectEqual(@as(usize, 0), info.malloc_usable_size(realloc_zero));
}

test "resize entry points preserve C alignment" {
    const realloc_ptr = realloc(null, 37) orelse return error.OutOfMemory;
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(realloc_ptr) % layout.c_alignment);
    const grown_ptr = realloc(realloc_ptr, 53) orelse {
        allocation.free(realloc_ptr);
        return error.OutOfMemory;
    };
    defer allocation.free(grown_ptr);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(grown_ptr) % layout.c_alignment);

    const array_ptr = reallocarray(null, 5, 11) orelse return error.OutOfMemory;
    defer allocation.free(array_ptr);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(array_ptr) % layout.c_alignment);
}
