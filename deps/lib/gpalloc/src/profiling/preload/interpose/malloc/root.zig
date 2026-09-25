const allocation = @import("allocation.zig");
const resize = @import("resize.zig");

pub const calloc = allocation.calloc;
pub const free = allocation.free;
pub const malloc = allocation.malloc;
pub const realloc = resize.realloc;
pub const reallocarray = resize.reallocarray;
