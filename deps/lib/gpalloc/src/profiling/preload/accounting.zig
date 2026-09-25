const std = @import("std");

const accounted_value_bit: usize = @as(usize, 1) << (@bitSizeOf(usize) - 1);
const requested_size_mask: usize = accounted_value_bit - 1;

pub const Mallinfo2 = extern struct {
    arena: usize = 0,
    ordblks: usize = 0,
    smblks: usize = 0,
    hblks: usize = 0,
    hblkhd: usize = 0,
    usmblks: usize = 0,
    fsmblks: usize = 0,
    uordblks: usize = 0,
    fordblks: usize = 0,
    keepcost: usize = 0,
};

var live_requested_bytes = std.atomic.Value(usize).init(0);
var live_accounting_active = std.atomic.Value(bool).init(false);

pub fn validRequestedSize(size: usize) bool {
    return size <= requested_size_mask;
}

pub fn encodeRequestedValue(size: usize, accounted: bool) usize {
    return size | if (accounted) accounted_value_bit else 0;
}

pub fn requestedSizeFromValue(value: usize) usize {
    return if (accountedFromValue(value)) value & requested_size_mask else value;
}

pub fn accountedFromValue(value: usize) bool {
    return (value & accounted_value_bit) != 0;
}

pub fn recordAllocation(size: usize) bool {
    const active = live_accounting_active.load(.monotonic);
    if (!active) return false;
    if (size != 0) _ = live_requested_bytes.fetchAdd(size, .monotonic);
    return true;
}

pub fn recordDeallocation(size: usize, accounted: bool) void {
    if (!accounted) return;
    if (size != 0) _ = live_requested_bytes.fetchSub(size, .monotonic);
}

pub fn recordResize(old_size: usize, new_size: usize, accounted: bool) bool {
    if (!accounted) return recordAllocation(new_size);
    if (new_size > old_size) {
        _ = recordAllocation(new_size - old_size);
    } else {
        recordDeallocation(old_size - new_size, true);
    }
    return true;
}

pub fn requestedBytesSnapshot() usize {
    live_accounting_active.store(true, .monotonic);
    return live_requested_bytes.load(.monotonic);
}

pub fn resetForTest() void {
    live_requested_bytes.store(0, .monotonic);
    live_accounting_active.store(false, .monotonic);
}
