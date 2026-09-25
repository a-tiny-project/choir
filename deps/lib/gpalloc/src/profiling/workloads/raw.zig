const std = @import("std");

pub const RawRecord = struct {
    ptr: [*]u8,
    len: usize,
    alignment: std.mem.Alignment,
};
