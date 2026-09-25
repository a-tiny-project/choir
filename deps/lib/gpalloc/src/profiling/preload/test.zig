const preload = @import("root.zig");
const accounting = preload.accounting;
const cplusplus = @import("cplusplus/test.zig");
const exports = preload.exports;
const heap = @import("heap/test.zig");
const interpose = @import("interpose/test.zig");
const layout = preload.layout;

test "gpalloc preload package namespace" {
    _ = accounting;
    _ = cplusplus;
    _ = exports;
    _ = heap;
    _ = interpose;
    _ = layout;
}
