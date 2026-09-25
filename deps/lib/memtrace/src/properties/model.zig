pub const Model = struct {
    events: u64 = 0,
    allocations: u64 = 0,
    frees: u64 = 0,
    live_allocations: usize = 0,
    allocated_bytes: usize = 0,
    freed_bytes: usize = 0,
    live_bytes: usize = 0,
    high_water_live_bytes: usize = 0,
    retained_bytes: usize = 0,
    high_water_retained_bytes: usize = 0,
    retains_freed_memory: bool = false,

    pub fn event(model: *Model) void {
        model.events += 1;
    }

    pub fn allocation(model: *Model, len: usize) void {
        model.events += 1;
        model.allocations += 1;
        model.live_allocations += 1;
        model.allocated_bytes += len;
        model.live_bytes += len;
        model.high_water_live_bytes = @max(model.high_water_live_bytes, model.live_bytes);
        model.retained_bytes += len;
        model.high_water_retained_bytes = @max(model.high_water_retained_bytes, model.retained_bytes);
    }

    pub fn free(model: *Model, len: usize) void {
        model.events += 1;
        model.frees += 1;
        model.live_allocations -= 1;
        model.freed_bytes += len;
        model.live_bytes -= len;
        if (!model.retains_freed_memory) model.retained_bytes -= len;
    }

    pub fn resize(model: *Model, old_len: usize, new_len: usize) void {
        model.events += 1;
        if (new_len >= old_len) {
            const delta = new_len - old_len;
            model.allocated_bytes += delta;
            model.live_bytes += delta;
            model.high_water_live_bytes = @max(model.high_water_live_bytes, model.live_bytes);
            model.retained_bytes += delta;
            model.high_water_retained_bytes = @max(model.high_water_retained_bytes, model.retained_bytes);
        } else {
            const delta = old_len - new_len;
            model.freed_bytes += delta;
            model.live_bytes -= delta;
            if (!model.retains_freed_memory) model.retained_bytes -= delta;
        }
    }
};
