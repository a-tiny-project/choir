const interpose = @import("root.zig");
const align_module = @import("align.zig");
const errno = @import("errno.zig");
const info = @import("info.zig");
const malloc_module = @import("malloc/test.zig");

comptime {
    _ = interpose;
}

test "gpalloc: preload interpose namespace" {
    _ = align_module;
    _ = errno;
    _ = info;
    _ = malloc_module;
}
