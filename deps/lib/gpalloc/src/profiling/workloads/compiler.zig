const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");

const Record = struct {
    bytes: []u8,
};

pub fn run(allocator: std.mem.Allocator) void {
    var interned: [parameters.compiler_trace_module_count][parameters.compiler_trace_intern_count]?[]u8 =
        @as([parameters.compiler_trace_module_count][parameters.compiler_trace_intern_count]?[]u8, @splat(@as([parameters.compiler_trace_intern_count]?[]u8, @splat(null))));

    var module_index: usize = 0;
    while (module_index < parameters.compiler_trace_module_count) : (module_index += 1) {
        {
            const parse_phase = bench.phaseAt("gpalloc.phase.compiler_trace.parse", @src());
            defer parse_phase.end();

            var temps: [parameters.compiler_trace_temp_count]?[]u8 = @as([parameters.compiler_trace_temp_count]?[]u8, @splat(null));
            for (&temps, 0..) |*temp, index| {
                const bytes = allocator.alloc(u8, tempSize(index, module_index)) catch @panic("allocation failed");
                bytes[0] = @truncate(index + module_index);
                temp.* = bytes;
            }
            for (&temps) |*temp| {
                const bytes = temp.* orelse continue;
                std.mem.doNotOptimizeAway(bytes.ptr);
                allocator.free(bytes);
                temp.* = null;
            }
        }

        {
            const intern_phase = bench.phaseAt("gpalloc.phase.compiler_trace.intern", @src());
            defer intern_phase.end();

            for (&interned[module_index], 0..) |*symbol, index| {
                const bytes = allocator.alloc(u8, internSize(index, module_index)) catch @panic("allocation failed");
                bytes[0] = @truncate(index);
                symbol.* = bytes;
            }
        }

        {
            const lower_phase = bench.phaseAt("gpalloc.phase.compiler_trace.lower", @src());
            defer lower_phase.end();

            var nodes: [parameters.compiler_trace_node_count]Record = undefined;
            for (&nodes, 0..) |*node, index| {
                const bytes = allocator.alloc(u8, nodeSize(index, module_index)) catch @panic("allocation failed");
                bytes[0] = @truncate(index + module_index);
                node.* = .{ .bytes = bytes };
            }
            for (&nodes, 0..) |*node, index| {
                if (index % 5 != 0) continue;
                const resized = allocator.realloc(node.bytes, nodeSize(index + 17, module_index) + 64) catch @panic("realloc failed");
                std.mem.doNotOptimizeAway(resized.ptr);
                node.bytes = resized;
            }
            for (nodes) |node| {
                std.mem.doNotOptimizeAway(node.bytes.ptr);
                allocator.free(node.bytes);
            }
        }

        {
            const emit_phase = bench.phaseAt("gpalloc.phase.compiler_trace.emit", @src());
            defer emit_phase.end();

            const object = allocator.alloc(u8, 32 * 1024 + module_index * 4096) catch @panic("allocation failed");
            object[0] = @truncate(module_index);
            const index = allocator.alloc(u8, 4096 + module_index * 257) catch @panic("allocation failed");
            index[0] = @truncate(module_index);
            std.mem.doNotOptimizeAway(object.ptr);
            std.mem.doNotOptimizeAway(index.ptr);
            allocator.free(index);
            allocator.free(object);
        }

        coz.progressNamed("gpalloc.phase.compiler_trace.module");
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.compiler_trace.drain", @src());
        defer drain_phase.end();

        for (&interned) |*module| {
            for (module) |*symbol| {
                const bytes = symbol.* orelse continue;
                std.mem.doNotOptimizeAway(bytes.ptr);
                allocator.free(bytes);
                symbol.* = null;
            }
        }
    }
}

fn tempSize(index: usize, module_index: usize) usize {
    const sizes = [_]usize{ 24, 40, 56, 72, 96, 128, 192, 256 };
    return sizes[(index + module_index * 3) % sizes.len];
}

fn internSize(index: usize, module_index: usize) usize {
    return 12 + ((index * 17 + module_index * 11) % 96);
}

fn nodeSize(index: usize, module_index: usize) usize {
    const sizes = [_]usize{ 48, 64, 96, 128, 192, 256, 384, 512 };
    return sizes[(index * 5 + module_index * 7) % sizes.len];
}
