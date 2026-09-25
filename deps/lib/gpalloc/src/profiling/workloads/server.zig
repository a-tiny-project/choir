const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");
const touch = @import("touch.zig");

const nextWorkingSetState = touch.nextWorkingSetState;

pub fn run(allocator: std.mem.Allocator) void {
    var list_slots: [parameters.server_trace_slot_count]?[]u8 = @as([parameters.server_trace_slot_count]?[]u8, @splat(null));
    var state: u32 = 0x4f1b_7341;

    var request: usize = 0;
    while (request < parameters.server_trace_request_count) : (request += 1) {
        {
            const parse_phase = bench.phaseAt("gpalloc.phase.server_trace.parse", @src());
            defer parse_phase.end();

            const payload = allocator.alloc(u8, payloadSize(request)) catch @panic("allocation failed");
            payload[0] = @truncate(request);
            const command = allocator.alloc(u8, 40 + (request % 5) * 24) catch @panic("allocation failed");
            command[0] = @truncate(request);
            std.mem.doNotOptimizeAway(payload.ptr);
            std.mem.doNotOptimizeAway(command.ptr);
            allocator.free(command);
            allocator.free(payload);
        }

        {
            const list_phase = bench.phaseAt("gpalloc.phase.server_trace.list_update", @src());
            defer list_phase.end();

            const offset = nextWorkingSetState(&state) % parameters.server_trace_slot_count;
            if (list_slots[offset]) |old| {
                allocator.free(old);
            }
            const node = allocator.alloc(u8, listNodeSize(nextWorkingSetState(&state))) catch @panic("allocation failed");
            node[0] = @truncate(request);
            list_slots[offset] = node;
        }

        if (request % 3 == 0) {
            const response_phase = bench.phaseAt("gpalloc.phase.server_trace.response", @src());
            defer response_phase.end();

            const response = allocator.alloc(u8, 512 + (request % 17) * 64) catch @panic("allocation failed");
            response[0] = @truncate(request);
            std.mem.doNotOptimizeAway(response.ptr);
            allocator.free(response);
        }

        if (request % 128 == 127) {
            const trim_phase = bench.phaseAt("gpalloc.phase.server_trace.trim", @src());
            defer trim_phase.end();

            var trim_index: usize = request % parameters.server_trace_slot_count;
            var trimmed: usize = 0;
            while (trimmed < 32) : (trimmed += 1) {
                if (list_slots[trim_index]) |bytes| {
                    allocator.free(bytes);
                    list_slots[trim_index] = null;
                }
                trim_index = (trim_index + 17) % parameters.server_trace_slot_count;
            }
            coz.progressNamed("gpalloc.phase.server_trace.trim");
        }
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.server_trace.drain", @src());
        defer drain_phase.end();

        for (&list_slots) |*slot| {
            const bytes = slot.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            slot.* = null;
        }
    }
}

fn payloadSize(request: usize) usize {
    const sizes = [_]usize{ 64, 96, 128, 192, 256, 384, 512, 1024 };
    return sizes[(request * 3) % sizes.len];
}

fn listNodeSize(state: usize) usize {
    const sizes = [_]usize{ 32, 48, 64, 96, 128, 192, 256, 512 };
    return sizes[(state >> 4) % sizes.len];
}
