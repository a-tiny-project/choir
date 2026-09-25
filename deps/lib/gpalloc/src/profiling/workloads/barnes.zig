const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");
const touch = @import("touch.zig");

const touchSparse = touch.sparse;

pub fn run(allocator: std.mem.Allocator) void {
    var params: [parameters.barnes_trace_param_count]?[]u8 =
        @as([parameters.barnes_trace_param_count]?[]u8, @splat(null));
    var cell_tabs: [parameters.barnes_trace_process_count]?[]u8 =
        @as([parameters.barnes_trace_process_count]?[]u8, @splat(null));
    var leaf_tabs: [parameters.barnes_trace_process_count]?[]u8 =
        @as([parameters.barnes_trace_process_count]?[]u8, @splat(null));

    var global: ?[]u8 = null;
    var cell_lock: ?[]u8 = null;
    var body_tab: ?[]u8 = null;
    var body_ptrs: ?[]u8 = null;
    var cell_ptrs: ?[]u8 = null;
    var leaf_ptrs: ?[]u8 = null;

    {
        const setup_phase = bench.phaseAt("gpalloc.phase.barnes_trace.setup", @src());
        defer setup_phase.end();

        global = allocator.alloc(u8, parameters.barnes_trace_global_bytes) catch @panic("allocation failed");
        cell_lock = allocator.alloc(u8, parameters.barnes_trace_cell_lock_bytes) catch @panic("allocation failed");
        touchSparse(global.?, 0x10);
        touchSparse(cell_lock.?, 0x11);

        for (&params, 0..) |*param, index| {
            const bytes = allocator.alloc(u8, 16 + (index % 5) * 8) catch @panic("allocation failed");
            bytes[0] = @truncate(index);
            param.* = bytes;
        }
        coz.progressNamed("gpalloc.phase.barnes_trace.setup");
    }

    {
        const input_phase = bench.phaseAt("gpalloc.phase.barnes_trace.input", @src());
        defer input_phase.end();

        body_tab = allocator.alloc(u8, parameters.barnes_trace_body_count * parameters.barnes_trace_body_bytes) catch @panic("allocation failed");
        touchSparse(body_tab.?, 0x20);
        coz.progressNamed("gpalloc.phase.barnes_trace.input");
    }

    {
        const table_phase = bench.phaseAt("gpalloc.phase.barnes_trace.tab_init", @src());
        defer table_phase.end();

        for (&cell_tabs, 0..) |*tab, index| {
            const bytes = allocator.alloc(u8, barnesCellTabSize()) catch @panic("allocation failed");
            touchSparse(bytes, 0x30 + index);
            tab.* = bytes;
        }
        for (&leaf_tabs, 0..) |*tab, index| {
            const bytes = allocator.alloc(u8, barnesLeafTabSize()) catch @panic("allocation failed");
            touchSparse(bytes, 0x40 + index);
            tab.* = bytes;
        }

        body_ptrs = allocator.alloc(u8, barnesBodyPointerTableSize()) catch @panic("allocation failed");
        cell_ptrs = allocator.alloc(u8, barnesCellPointerTableSize()) catch @panic("allocation failed");
        leaf_ptrs = allocator.alloc(u8, barnesLeafPointerTableSize()) catch @panic("allocation failed");
        touchSparse(body_ptrs.?, 0x50);
        touchSparse(cell_ptrs.?, 0x51);
        touchSparse(leaf_ptrs.?, 0x52);
        coz.progressNamed("gpalloc.phase.barnes_trace.tab_init");
    }

    var step: usize = 0;
    while (step < parameters.barnes_trace_step_count) : (step += 1) {
        {
            const tree_phase = bench.phaseAt("gpalloc.phase.barnes_trace.tree_build", @src());
            defer tree_phase.end();

            for (cell_tabs, 0..) |maybe_tab, index| {
                const tab = maybe_tab orelse continue;
                touchSparse(tab[0..barnesActiveCellBytes(step, index)], step + index);
            }
            for (leaf_tabs, 0..) |maybe_tab, index| {
                const tab = maybe_tab orelse continue;
                touchSparse(tab[0..barnesActiveLeafBytes(step, index)], step + index + 17);
            }
            coz.progressNamed("gpalloc.phase.barnes_trace.tree_build");
        }

        {
            const partition_phase = bench.phaseAt("gpalloc.phase.barnes_trace.partition", @src());
            defer partition_phase.end();

            touchSparse(body_ptrs.?, step + 0x60);
            touchSparse(cell_ptrs.?, step + 0x61);
            touchSparse(leaf_ptrs.?, step + 0x62);
            coz.progressNamed("gpalloc.phase.barnes_trace.partition");
        }

        {
            const force_phase = bench.phaseAt("gpalloc.phase.barnes_trace.force", @src());
            defer force_phase.end();

            touchSparse(body_tab.?, step + 0x70);
            coz.progressNamed("gpalloc.phase.barnes_trace.force");
        }
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.barnes_trace.drain", @src());
        defer drain_phase.end();

        if (leaf_ptrs) |bytes| {
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
        }
        if (cell_ptrs) |bytes| {
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
        }
        if (body_ptrs) |bytes| {
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
        }
        for (&leaf_tabs) |*tab| {
            const bytes = tab.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            tab.* = null;
        }
        for (&cell_tabs) |*tab| {
            const bytes = tab.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            tab.* = null;
        }
        if (body_tab) |bytes| {
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
        }
        for (&params) |*param| {
            const bytes = param.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            param.* = null;
        }
        if (cell_lock) |bytes| {
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
        }
        if (global) |bytes| {
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
        }
    }
}

fn barnesLeafCount() usize {
    return parameters.barnes_trace_body_count * parameters.barnes_trace_fleaves;
}

fn barnesCellCount() usize {
    return barnesLeafCount() * parameters.barnes_trace_fcells;
}

fn barnesLeafCountPerProcess() usize {
    return barnesLeafCount() / parameters.barnes_trace_process_count;
}

fn barnesCellCountPerProcess() usize {
    return barnesCellCount() / parameters.barnes_trace_process_count;
}

fn barnesCellTabSize() usize {
    return barnesCellCountPerProcess() * parameters.barnes_trace_cell_bytes;
}

fn barnesLeafTabSize() usize {
    return barnesLeafCountPerProcess() * parameters.barnes_trace_leaf_bytes;
}

fn barnesBodyPointerTableSize() usize {
    const max_body_pointers = (parameters.barnes_trace_body_count + barnesLeafCount() * parameters.barnes_trace_bodies_per_leaf) / parameters.barnes_trace_process_count;
    return parameters.barnes_trace_process_count * max_body_pointers * @sizeOf(usize);
}

fn barnesCellPointerTableSize() usize {
    return barnesCellCount() * @sizeOf(usize);
}

fn barnesLeafPointerTableSize() usize {
    return barnesLeafCount() * @sizeOf(usize);
}

fn barnesActiveCellBytes(step: usize, process_index: usize) usize {
    const count = barnesCellCountPerProcess();
    const active = 1 + ((step + 1) * (process_index + 2) * count) / (parameters.barnes_trace_step_count * (parameters.barnes_trace_process_count + 1));
    return @min(count, active) * parameters.barnes_trace_cell_bytes;
}

fn barnesActiveLeafBytes(step: usize, process_index: usize) usize {
    const count = barnesLeafCountPerProcess();
    const active = 1 + ((step + 1) * (process_index + 2) * count) / (parameters.barnes_trace_step_count * (parameters.barnes_trace_process_count + 1));
    return @min(count, active) * parameters.barnes_trace_leaf_bytes;
}
