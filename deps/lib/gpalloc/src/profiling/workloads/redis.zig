const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");
const touch = @import("touch.zig");

const nextWorkingSetState = touch.nextWorkingSetState;

const ListRecord = struct {
    node: ?[]u8 = null,
    listpack: ?[]u8 = null,
};

const query_buffer_sizes = [_]usize{ 96, 128, 192, 256, 384, 512, 768, 1024 };
const command_arg_sizes = [_]usize{ 16, 24, 32, 40, 48, 64, 96, 128 };
const quicklist_node_sizes = [_]usize{ 48, 64, 80, 96, 128 };
const listpack_sizes = [_]usize{
    128, 192, 256, 384, 512, 768, 1024, 1536, 2048, 4096, 8192,
};
const listpack_growth_sizes = [_]usize{ 64, 128, 192, 256, 384, 512, 1024 };
const range_cursor_sizes = [_]usize{ 64, 96, 128, 192, 256, 384 };
const reply_buffer_sizes = [_]usize{ 256, 384, 512, 768, 1024, 1536, 2048, 4096 };
const reply_growth_sizes = [_]usize{ 128, 256, 512, 768, 1024 };
const bulk_string_sizes = [_]usize{ 24, 32, 48, 64, 96, 128, 192 };

pub fn run(allocator: std.mem.Allocator) void {
    var list_slots: [parameters.redis_trace_slot_count]ListRecord =
        @as([parameters.redis_trace_slot_count]ListRecord, @splat(.{}));
    var state: u32 = 0x6a09_e667;

    var request: usize = 0;
    while (request < parameters.redis_trace_request_count) : (request += 1) {
        parseCommandTrace(allocator, request);
        updateLists(allocator, &list_slots, &state, request);
        readList(allocator, &list_slots, &state, request);
        replyTrace(allocator, request);
        if (request % 128 == 127) trimLists(allocator, &list_slots, request);
    }

    drainLists(allocator, &list_slots);
}

fn parseCommandTrace(allocator: std.mem.Allocator, request: usize) void {
    const parse_phase = bench.phaseAt("gpalloc.phase.redis_trace.parse", @src());
    defer parse_phase.end();

    const query = allocator.alloc(
        u8,
        selectedSize(query_buffer_sizes, request * 5),
    ) catch @panic("allocation failed");
    touch.edges(query, request);
    const argv = allocator.alloc(
        u8,
        parameters.redis_trace_arg_count * @sizeOf(usize),
    ) catch @panic("allocation failed");
    touch.edges(argv, request + 0x10);

    var args: [parameters.redis_trace_arg_count]?[]u8 =
        @as([parameters.redis_trace_arg_count]?[]u8, @splat(null));
    for (&args, 0..) |*arg, index| {
        const bytes = allocator.alloc(
            u8,
            selectedSize(command_arg_sizes, request + index * 3),
        ) catch
            @panic("allocation failed");
        touch.edges(bytes, request + index);
        arg.* = bytes;
    }

    var index = args.len;
    while (index > 0) {
        index -= 1;
        const bytes = args[index] orelse continue;
        std.mem.doNotOptimizeAway(bytes.ptr);
        allocator.free(bytes);
        args[index] = null;
    }

    allocator.free(argv);
    allocator.free(query);
    coz.progressNamed("gpalloc.phase.redis_trace.parse");
}

fn updateLists(
    allocator: std.mem.Allocator,
    list_slots: *[parameters.redis_trace_slot_count]ListRecord,
    state: *u32,
    request: usize,
) void {
    const update_phase = bench.phaseAt("gpalloc.phase.redis_trace.list_update", @src());
    defer update_phase.end();

    var pipe: usize = 0;
    while (pipe < parameters.redis_trace_pipeline_count) : (pipe += 1) {
        const slot = nextWorkingSetState(state) % parameters.redis_trace_slot_count;
        freeRecord(allocator, &list_slots.*[slot]);
        list_slots.*[slot] = allocateListRecord(allocator, state, request, pipe);
    }
    coz.progressNamed("gpalloc.phase.redis_trace.list_update");
}

fn allocateListRecord(
    allocator: std.mem.Allocator,
    state: *u32,
    request: usize,
    pipe: usize,
) ListRecord {
    const node = allocator.alloc(
        u8,
        selectedSize(quicklist_node_sizes, request + pipe * 7),
    ) catch
        @panic("allocation failed");
    touch.edges(node, request + pipe * 17);

    var listpack = allocator.alloc(
        u8,
        selectedSize(
            listpack_sizes,
            request * 7 + pipe * 11 + nextWorkingSetState(state),
        ),
    ) catch @panic("allocation failed");
    if ((request + pipe) % 3 == 0) {
        listpack = allocator.realloc(
            listpack,
            listpack.len + selectedSize(listpack_growth_sizes, request + pipe * 5),
        ) catch @panic("realloc failed");
    }
    touch.sparse(listpack, request * 31 + pipe);

    return .{ .node = node, .listpack = listpack };
}

fn readList(
    allocator: std.mem.Allocator,
    list_slots: *[parameters.redis_trace_slot_count]ListRecord,
    state: *u32,
    request: usize,
) void {
    const read_phase = bench.phaseAt("gpalloc.phase.redis_trace.list_read", @src());
    defer read_phase.end();

    const slot = nextWorkingSetState(state) % parameters.redis_trace_slot_count;
    if (list_slots.*[slot].listpack) |listpack| touch.edges(listpack, request);
    const range = allocator.alloc(u8, selectedSize(range_cursor_sizes, request * 11)) catch
        @panic("allocation failed");
    touch.edges(range, request);
    allocator.free(range);
    coz.progressNamed("gpalloc.phase.redis_trace.list_read");
}

fn replyTrace(allocator: std.mem.Allocator, request: usize) void {
    const reply_phase = bench.phaseAt("gpalloc.phase.redis_trace.reply", @src());
    defer reply_phase.end();

    var reply = allocator.alloc(
        u8,
        selectedSize(reply_buffer_sizes, request * 13),
    ) catch @panic("allocation failed");
    if (request % 4 == 0) {
        reply = allocator.realloc(
            reply,
            reply.len + selectedSize(reply_growth_sizes, request * 3),
        ) catch
            @panic("realloc failed");
    }
    touch.sparse(reply, request);

    var bulks: [parameters.redis_trace_pipeline_count / 4]?[]u8 =
        @as([(parameters.redis_trace_pipeline_count / 4)]?[]u8, @splat(null));
    for (&bulks, 0..) |*bulk, index| {
        const bytes = allocator.alloc(
            u8,
            selectedSize(bulk_string_sizes, request + index * 5),
        ) catch
            @panic("allocation failed");
        touch.edges(bytes, request + index * 23);
        bulk.* = bytes;
    }
    for (&bulks) |*bulk| {
        const bytes = bulk.* orelse continue;
        std.mem.doNotOptimizeAway(bytes.ptr);
        allocator.free(bytes);
        bulk.* = null;
    }

    allocator.free(reply);
    coz.progressNamed("gpalloc.phase.redis_trace.reply");
}

fn trimLists(
    allocator: std.mem.Allocator,
    list_slots: *[parameters.redis_trace_slot_count]ListRecord,
    request: usize,
) void {
    const trim_phase = bench.phaseAt("gpalloc.phase.redis_trace.trim", @src());
    defer trim_phase.end();

    var index = request % parameters.redis_trace_slot_count;
    var trimmed: usize = 0;
    while (trimmed < parameters.redis_trace_trim_count) : (trimmed += 1) {
        freeRecord(allocator, &list_slots.*[index]);
        index = (index + 19) % parameters.redis_trace_slot_count;
    }
    coz.progressNamed("gpalloc.phase.redis_trace.trim");
}

fn drainLists(
    allocator: std.mem.Allocator,
    list_slots: *[parameters.redis_trace_slot_count]ListRecord,
) void {
    const drain_phase = bench.phaseAt("gpalloc.phase.redis_trace.drain", @src());
    defer drain_phase.end();

    for (&list_slots.*) |*slot| freeRecord(allocator, slot);
    coz.progressNamed("gpalloc.phase.redis_trace.drain");
}

fn freeRecord(allocator: std.mem.Allocator, record: *ListRecord) void {
    if (record.listpack) |bytes| {
        std.mem.doNotOptimizeAway(bytes.ptr);
        allocator.free(bytes);
        record.listpack = null;
    }
    if (record.node) |bytes| {
        std.mem.doNotOptimizeAway(bytes.ptr);
        allocator.free(bytes);
        record.node = null;
    }
}

fn selectedSize(comptime sizes: anytype, index: usize) usize {
    return sizes[index % sizes.len];
}
