const std = @import("std");
const accounting = @import("../root.zig").accounting;
const errno = @import("errno.zig");
const heap = @import("../heap/root.zig");

pub fn malloc_usable_size(ptr: ?*anyopaque) callconv(.c) usize {
    return heap.usableSize(ptr);
}

pub fn mallinfo2() callconv(.c) accounting.Mallinfo2 {
    return .{
        .uordblks = accounting.requestedBytesSnapshot(),
    };
}

pub fn malloc_info(options: c_int, stream: ?*anyopaque) callconv(.c) c_int {
    _ = stream orelse {
        errno.set(errno.posix_einval);
        return -1;
    };
    if (options != 0) {
        errno.set(errno.posix_einval);
        return -1;
    }
    errno.set(errno.posix_enosys);
    return -1;
}

test "malloc usable size returns zero for null" {
    try std.testing.expectEqual(@as(usize, 0), malloc_usable_size(null));
}

test "malloc_info rejects libc-owned file streams" {
    const stream: *anyopaque = @ptrFromInt(1);
    try std.testing.expectEqual(@as(c_int, -1), malloc_info(0, stream));
    try std.testing.expectEqual(@as(c_int, errno.posix_enosys), errno.current());
}

test "mallinfo2 reports live requested bytes" {
    const malloc = @import("malloc/root.zig");
    const align_module = @import("align.zig");
    const before = mallinfo2();
    var fast = malloc.malloc(160) orelse return error.OutOfMemory;
    const aligned = align_module.aligned_alloc(64, 256) orelse {
        malloc.free(fast);
        return error.OutOfMemory;
    };
    const after_alloc = mallinfo2();
    try std.testing.expect(after_alloc.uordblks >= before.uordblks + 416);

    const resized = malloc.realloc(fast, 80) orelse {
        malloc.free(fast);
        malloc.free(aligned);
        return error.OutOfMemory;
    };
    fast = resized;
    const after_realloc = mallinfo2();
    try std.testing.expect(after_realloc.uordblks >= before.uordblks + 336);

    malloc.free(fast);
    malloc.free(aligned);
    const after_free = mallinfo2();
    try std.testing.expect(after_free.uordblks <= after_realloc.uordblks);
}

test "mallinfo2 activates accounting without charging older allocations" {
    const malloc = @import("malloc/root.zig");
    accounting.resetForTest();

    const early = malloc.malloc(64) orelse return error.OutOfMemory;
    const first = mallinfo2();
    try std.testing.expectEqual(@as(usize, 0), first.uordblks);

    const counted = malloc.malloc(96) orelse {
        malloc.free(early);
        return error.OutOfMemory;
    };
    const after_counted = mallinfo2();
    try std.testing.expectEqual(@as(usize, 96), after_counted.uordblks);

    malloc.free(early);
    const after_early_free = mallinfo2();
    try std.testing.expectEqual(@as(usize, 96), after_early_free.uordblks);

    malloc.free(counted);
    const after_counted_free = mallinfo2();
    try std.testing.expectEqual(@as(usize, 0), after_counted_free.uordblks);
}

test "realloc after mallinfo2 starts accounting older allocation" {
    const malloc = @import("malloc/root.zig");
    accounting.resetForTest();

    const early = malloc.malloc(64) orelse return error.OutOfMemory;
    const first = mallinfo2();
    try std.testing.expectEqual(@as(usize, 0), first.uordblks);

    const resized = malloc.realloc(early, 80) orelse {
        malloc.free(early);
        return error.OutOfMemory;
    };
    const after_realloc = mallinfo2();
    try std.testing.expectEqual(@as(usize, 80), after_realloc.uordblks);

    malloc.free(resized);
    const after_free = mallinfo2();
    try std.testing.expectEqual(@as(usize, 0), after_free.uordblks);
}
