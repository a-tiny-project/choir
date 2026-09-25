const align_module = @import("align.zig");
pub const errno = @import("errno.zig");
pub const info = @import("info.zig");
const malloc_module = @import("malloc/root.zig");

pub const aligned_alloc = align_module.aligned_alloc;
pub const calloc = malloc_module.calloc;
pub const free = malloc_module.free;
pub const mallinfo2 = info.mallinfo2;
pub const malloc = malloc_module.malloc;
pub const malloc_info = info.malloc_info;
pub const malloc_usable_size = info.malloc_usable_size;
pub const memalign = align_module.memalign;
pub const posix_memalign = align_module.posix_memalign;
pub const pvalloc = align_module.pvalloc;
pub const realloc = malloc_module.realloc;
pub const reallocarray = malloc_module.reallocarray;
pub const valloc = align_module.valloc;
