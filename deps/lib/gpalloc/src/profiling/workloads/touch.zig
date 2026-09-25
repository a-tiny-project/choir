const std = @import("std");

pub fn sparse(bytes: []u8, seed: usize) void {
    if (bytes.len == 0) return;
    bytes[0] = @truncate(seed);
    var index: usize = 4096 + seed % 97;
    while (index < bytes.len) : (index += 4096) {
        bytes[index] = @truncate(index + seed);
    }
    bytes[bytes.len - 1] = @truncate(bytes.len + seed);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub fn edges(bytes: []u8, seed: usize) void {
    bytes[0] = @truncate(seed);
    bytes[bytes.len - 1] = @truncate(bytes.len + seed);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub fn nextWorkingSetState(state: *u32) usize {
    state.* = state.* *% 1_664_525 +% 1_013_904_223;
    return state.*;
}
