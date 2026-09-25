const heap = @import("../heap/root.zig");

pub fn _ZdlPv(ptr: ?*anyopaque) callconv(.c) void {
    heap.deallocate(ptr);
}

pub fn _ZdaPv(ptr: ?*anyopaque) callconv(.c) void {
    heap.deallocate(ptr);
}

pub fn _ZdlPvm(ptr: ?*anyopaque, _: usize) callconv(.c) void {
    heap.deallocate(ptr);
}

pub fn _ZdaPvm(ptr: ?*anyopaque, _: usize) callconv(.c) void {
    heap.deallocate(ptr);
}

pub fn _ZdlPvSt11align_val_t(ptr: ?*anyopaque, _: usize) callconv(.c) void {
    heap.deallocate(ptr);
}

pub fn _ZdaPvSt11align_val_t(ptr: ?*anyopaque, _: usize) callconv(.c) void {
    heap.deallocate(ptr);
}

pub fn _ZdlPvSt11align_val_tRKSt9nothrow_t(
    ptr: ?*anyopaque,
    _: usize,
    _: *const anyopaque,
) callconv(.c) void {
    heap.deallocate(ptr);
}

pub fn _ZdaPvSt11align_val_tRKSt9nothrow_t(
    ptr: ?*anyopaque,
    _: usize,
    _: *const anyopaque,
) callconv(.c) void {
    heap.deallocate(ptr);
}

pub fn _ZdlPvmSt11align_val_t(ptr: ?*anyopaque, _: usize, _: usize) callconv(.c) void {
    heap.deallocate(ptr);
}

pub fn _ZdaPvmSt11align_val_t(ptr: ?*anyopaque, _: usize, _: usize) callconv(.c) void {
    heap.deallocate(ptr);
}
