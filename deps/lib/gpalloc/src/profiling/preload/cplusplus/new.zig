const heap = @import("../heap/root.zig");

pub fn _Znwm(size: usize) callconv(.c) *anyopaque {
    return heap.allocateFastOrTrap(size);
}

pub fn _Znam(size: usize) callconv(.c) *anyopaque {
    return heap.allocateFastOrTrap(size);
}

pub fn _ZnwmSt11align_val_t(size: usize, alignment: usize) callconv(.c) *anyopaque {
    return heap.allocateOrTrap(size, alignment);
}

pub fn _ZnamSt11align_val_t(size: usize, alignment: usize) callconv(.c) *anyopaque {
    return heap.allocateOrTrap(size, alignment);
}

pub fn _ZnwmRKSt9nothrow_t(size: usize, _: *const anyopaque) callconv(.c) ?*anyopaque {
    return heap.allocateFast(size);
}

pub fn _ZnamRKSt9nothrow_t(size: usize, _: *const anyopaque) callconv(.c) ?*anyopaque {
    return heap.allocateFast(size);
}

pub fn _ZnwmSt11align_val_tRKSt9nothrow_t(
    size: usize,
    alignment: usize,
    _: *const anyopaque,
) callconv(.c) ?*anyopaque {
    return heap.allocate(size, alignment);
}

pub fn _ZnamSt11align_val_tRKSt9nothrow_t(
    size: usize,
    alignment: usize,
    _: *const anyopaque,
) callconv(.c) ?*anyopaque {
    return heap.allocate(size, alignment);
}
