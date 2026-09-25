pub fn bytes(ptr: *anyopaque, len: usize) []u8 {
    const raw: [*]u8 = @ptrCast(ptr);
    return raw[0..len];
}
