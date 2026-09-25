const preload = @import("../root.zig");
const accounting = preload.accounting;
const layout = preload.layout;

pub fn usableSize(ptr: ?*anyopaque) usize {
    const user_ptr = ptr orelse return 0;
    return switch (layout.metadataFromUserPointer(user_ptr)) {
        .fast => |header| accounting.requestedSizeFromValue(header.value),
        .extended => |header| accounting.requestedSizeFromValue(header.requested_len),
        .foreign => 0,
    };
}
