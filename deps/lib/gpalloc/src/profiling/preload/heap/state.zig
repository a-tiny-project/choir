const sys = @import("sys");
const gpalloc = @import("gpalloc");

pub const preload_ret_addr: usize = 0;

pub var allocator: gpalloc.GpAllocator = gpalloc.GpAllocator.init(
    sys.allocator.preloadBackingAllocator(),
    .{},
);
