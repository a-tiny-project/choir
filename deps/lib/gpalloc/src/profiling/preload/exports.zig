const cplusplus = @import("cplusplus/root.zig");
const interpose = @import("interpose/root.zig");

comptime {
    @export(&interpose.malloc, .{ .name = "malloc" });
    @export(&interpose.free, .{ .name = "free" });
    @export(&interpose.calloc, .{ .name = "calloc" });
    @export(&interpose.realloc, .{ .name = "realloc" });
    @export(&interpose.reallocarray, .{ .name = "reallocarray" });
    @export(&cplusplus._Znwm, .{ .name = "_Znwm" });
    @export(&cplusplus._Znam, .{ .name = "_Znam" });
    @export(&cplusplus._ZnwmSt11align_val_t, .{ .name = "_ZnwmSt11align_val_t" });
    @export(&cplusplus._ZnamSt11align_val_t, .{ .name = "_ZnamSt11align_val_t" });
    @export(&cplusplus._ZnwmRKSt9nothrow_t, .{ .name = "_ZnwmRKSt9nothrow_t" });
    @export(&cplusplus._ZnamRKSt9nothrow_t, .{ .name = "_ZnamRKSt9nothrow_t" });
    @export(&cplusplus._ZnwmSt11align_val_tRKSt9nothrow_t, .{
        .name = "_ZnwmSt11align_val_tRKSt9nothrow_t",
    });
    @export(&cplusplus._ZnamSt11align_val_tRKSt9nothrow_t, .{
        .name = "_ZnamSt11align_val_tRKSt9nothrow_t",
    });
    @export(&cplusplus._ZdlPv, .{ .name = "_ZdlPv" });
    @export(&cplusplus._ZdaPv, .{ .name = "_ZdaPv" });
    @export(&cplusplus._ZdlPvm, .{ .name = "_ZdlPvm" });
    @export(&cplusplus._ZdaPvm, .{ .name = "_ZdaPvm" });
    @export(&cplusplus._ZdlPvSt11align_val_t, .{ .name = "_ZdlPvSt11align_val_t" });
    @export(&cplusplus._ZdaPvSt11align_val_t, .{ .name = "_ZdaPvSt11align_val_t" });
    @export(&cplusplus._ZdlPvSt11align_val_tRKSt9nothrow_t, .{
        .name = "_ZdlPvSt11align_val_tRKSt9nothrow_t",
    });
    @export(&cplusplus._ZdaPvSt11align_val_tRKSt9nothrow_t, .{
        .name = "_ZdaPvSt11align_val_tRKSt9nothrow_t",
    });
    @export(&cplusplus._ZdlPvmSt11align_val_t, .{ .name = "_ZdlPvmSt11align_val_t" });
    @export(&cplusplus._ZdaPvmSt11align_val_t, .{ .name = "_ZdaPvmSt11align_val_t" });
    @export(&interpose.aligned_alloc, .{ .name = "aligned_alloc" });
    @export(&interpose.posix_memalign, .{ .name = "posix_memalign" });
    @export(&interpose.memalign, .{ .name = "memalign" });
    @export(&interpose.valloc, .{ .name = "valloc" });
    @export(&interpose.pvalloc, .{ .name = "pvalloc" });
    @export(&interpose.malloc_usable_size, .{ .name = "malloc_usable_size" });
    @export(&interpose.mallinfo2, .{ .name = "mallinfo2" });
    @export(&interpose.malloc_info, .{ .name = "malloc_info" });
}

test {
    _ = cplusplus;
    _ = interpose;
}
