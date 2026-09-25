const heap = @import("root.zig");
const allocate_module = @import("allocate.zig");
const free_module = @import("free.zig");
const memory = @import("memory.zig");
const metadata = @import("metadata.zig");
const resize_module = @import("resize.zig");

comptime {
    _ = heap;
}

test "gpalloc: preload heap namespace" {
    _ = allocate_module;
    _ = free_module;
    _ = memory;
    _ = metadata;
    _ = resize_module;
}
