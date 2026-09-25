const hypothesis = @import("hypothesis");

pub const scope_names = [_][]const u8{
    "root",
    "root/compile",
    "root/eval",
    "root/render",
};

pub const Slot = struct {
    active: bool = false,
    allocation_id: u64 = 0,
    address: usize = 0,
    len: usize = 0,
    scope_index: usize = 0,
};

pub fn settings() hypothesis.Settings {
    return hypothesis.Settings.quick()
        .withSeed(0x4d45_4d54_5241_4345)
        .withDatabase("zig-out/hypothesis-failures/memtrace");
}

pub fn drawUsize(conjecture: *hypothesis.ConjectureData, min: usize, max: usize, shrink_towards: usize) !usize {
    return @intCast(try conjecture.drawInteger(
        @intCast(min),
        @intCast(max),
        @intCast(shrink_towards),
    ));
}

pub fn drawActiveSlot(conjecture: *hypothesis.ConjectureData, slots: []const Slot, active_count: usize) !usize {
    var ordinal = try drawUsize(conjecture, 0, active_count - 1, 0);
    for (slots, 0..) |slot, index| {
        if (!slot.active) continue;
        if (ordinal == 0) return index;
        ordinal -= 1;
    }
    return error.NoActiveSlot;
}

pub fn firstInactive(slots: []const Slot) usize {
    for (slots, 0..) |slot, index| {
        if (!slot.active) return index;
    }
    return 0;
}

pub fn nextAddress(generation: usize, slot: usize) usize {
    return 0x1000 + generation * 0x1000 + slot * 0x80;
}
