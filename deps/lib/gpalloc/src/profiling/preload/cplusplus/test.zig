const std = @import("std");
const cplusplus = @import("root.zig");
const delete_module = @import("delete.zig");
const new_module = @import("new.zig");
const interpose = @import("../interpose/root.zig");

const _ZdaPvSt11align_val_tRKSt9nothrow_t =
    cplusplus._ZdaPvSt11align_val_tRKSt9nothrow_t;
const _ZdaPvm = cplusplus._ZdaPvm;
const _ZdlPv = cplusplus._ZdlPv;
const _ZdlPvmSt11align_val_t = cplusplus._ZdlPvmSt11align_val_t;
const _Znam = cplusplus._Znam;
const _ZnamSt11align_val_tRKSt9nothrow_t =
    cplusplus._ZnamSt11align_val_tRKSt9nothrow_t;
const _Znwm = cplusplus._Znwm;
const _ZnwmSt11align_val_t = cplusplus._ZnwmSt11align_val_t;

test "gpalloc: preload cplusplus namespace" {
    _ = delete_module;
    _ = new_module;
}

test "C++ operator aliases use fast metadata" {
    const scalar = _Znwm(48);
    try std.testing.expectEqual(@as(usize, 48), interpose.malloc_usable_size(scalar));
    _ZdlPv(scalar);

    const array = _Znam(96);
    try std.testing.expectEqual(@as(usize, 96), interpose.malloc_usable_size(array));
    _ZdaPvm(array, 96);
}

test "C++ aligned operator aliases use extended metadata" {
    const scalar = _ZnwmSt11align_val_t(80, 128);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(scalar) % 128);
    try std.testing.expectEqual(@as(usize, 80), interpose.malloc_usable_size(scalar));
    _ZdlPvmSt11align_val_t(scalar, 80, 128);

    const nothrow_token: usize = 0;
    const array = _ZnamSt11align_val_tRKSt9nothrow_t(
        144,
        256,
        @ptrCast(&nothrow_token),
    ) orelse return error.OutOfMemory;
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(array) % 256);
    try std.testing.expectEqual(@as(usize, 144), interpose.malloc_usable_size(array));
    _ZdaPvSt11align_val_tRKSt9nothrow_t(array, 256, @ptrCast(&nothrow_token));
}
