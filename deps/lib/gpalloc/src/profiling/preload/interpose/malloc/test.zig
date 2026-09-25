const malloc = @import("root.zig");
const allocation = @import("allocation.zig");
const resize = @import("resize.zig");

comptime {
    _ = malloc;
}

test "gpalloc: preload interpose malloc namespace" {
    _ = allocation;
    _ = resize;
}
