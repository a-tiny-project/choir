const std = @import("std");
const choir = @import("choir");

pub fn main() !void {
    try exerciseContext();
}

test "Choir initializes a consumer context" {
    try exerciseContext();
}

fn exerciseContext() !void {
    var heap: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(heap.deinit() == .ok);
    const allocator = heap.allocator();
    var context = try choir.Context.init(allocator, choir.Context.Limits.testing);
    defer context.deinit(allocator);
    try context.allowUnregistered();
}
