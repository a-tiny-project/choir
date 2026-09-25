const namespace_owner = @import("root.zig");

test {
    @import("std").testing.refAllDecls(namespace_owner);
}
