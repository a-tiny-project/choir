const capacity = @import("capacity.zig");
const storage = @import("storage.zig");

pub const default_limits: Limits = .{ .file_bytes = 16 * 1024 * 1024 };

pub const Capacity = capacity.Capacity;
pub const Exhaustion = storage.Exhaustion;
pub const exactLimitsForFile = storage.exactLimitsForFile;
pub const Limits = capacity.Limits;
pub const Status = storage.Status;
pub const Storage = storage.Storage;
