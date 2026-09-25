const allocate_module = @import("allocate.zig");
const free_module = @import("free.zig");
const memory = @import("memory.zig");
const metadata = @import("metadata.zig");
const resize_module = @import("resize.zig");

pub const Resize = resize_module.Resize;

pub const allocate = allocate_module.allocate;
pub const allocateFast = allocate_module.allocateFast;
pub const allocateFastOrTrap = allocate_module.allocateFastOrTrap;
pub const allocateOrTrap = allocate_module.allocateOrTrap;
pub const bytes = memory.bytes;
pub const deallocate = free_module.deallocate;
pub const resize = resize_module.resize;
pub const usableSize = metadata.usableSize;
