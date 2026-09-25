const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");
const touch = @import("touch.zig");

const nextWorkingSetState = touch.nextWorkingSetState;

pub fn run(allocator: std.mem.Allocator) void {
    var masks: [parameters.espresso_trace_var_count]?[]u8 =
        @as([parameters.espresso_trace_var_count]?[]u8, @splat(null));
    var covers: [parameters.espresso_trace_cover_count]?[]u8 =
        @as([parameters.espresso_trace_cover_count]?[]u8, @splat(null));
    var state: u32 = 0x6d25_2f19;

    setupMasks(allocator, &masks);
    readCover(allocator, &covers, &state);
    runOptimizationPhases(allocator, &covers, &state);
    drainTrace(allocator, &masks, &covers);
}

fn setupMasks(
    allocator: std.mem.Allocator,
    masks: *[parameters.espresso_trace_var_count]?[]u8,
) void {
    const setup_phase = bench.phaseAt("gpalloc.phase.espresso_trace.setup", @src());
    defer setup_phase.end();

    for (&masks.*, 0..) |*mask, index| {
        const bytes = allocator.alloc(u8, maskSize(index)) catch @panic("allocation failed");
        bytes[0] = @truncate(index);
        mask.* = bytes;

        if (index % 5 == 0) {
            const table = allocator.alloc(u8, 24 + (index % 7) * 16) catch
                @panic("allocation failed");
            table[0] = @truncate(index);
            std.mem.doNotOptimizeAway(table.ptr);
            allocator.free(table);
        }
    }
    coz.progressNamed("gpalloc.phase.espresso_trace.setup");
}

fn readCover(
    allocator: std.mem.Allocator,
    covers: *[parameters.espresso_trace_cover_count]?[]u8,
    state: *u32,
) void {
    const read_phase = bench.phaseAt("gpalloc.phase.espresso_trace.read_cover", @src());
    defer read_phase.end();

    var cube_index: usize = 0;
    while (cube_index < parameters.espresso_trace_cube_count) : (cube_index += 1) {
        const cube = allocator.alloc(
            u8,
            cubeSize(cube_index, nextWorkingSetState(state)),
        ) catch @panic("allocation failed");
        cube[0] = @truncate(cube_index);
        const slot = (cube_index * 17) % covers.len;
        if (covers.*[slot]) |old| {
            std.mem.doNotOptimizeAway(old.ptr);
            allocator.free(old);
        }
        covers.*[slot] = cube;

        if (cube_index % 4 == 0) {
            const label = allocator.alloc(u8, labelSize(cube_index)) catch
                @panic("allocation failed");
            label[0] = @truncate(cube_index);
            std.mem.doNotOptimizeAway(label.ptr);
            allocator.free(label);
        }
    }
    coz.progressNamed("gpalloc.phase.espresso_trace.read_cover");
}

fn runOptimizationPhases(
    allocator: std.mem.Allocator,
    covers: *[parameters.espresso_trace_cover_count]?[]u8,
    state: *u32,
) void {
    var phase: usize = 0;
    while (phase < parameters.espresso_trace_phase_count) : (phase += 1) {
        var temps: [parameters.espresso_trace_temp_count]?[]u8 =
            @as([parameters.espresso_trace_temp_count]?[]u8, @splat(null));

        {
            const expand_phase = bench.phaseAt("gpalloc.phase.espresso_trace.expand", @src());
            defer expand_phase.end();

            for (&temps, 0..) |*temp, index| {
                var family = allocator.alloc(
                    u8,
                    coverSize(index, phase, nextWorkingSetState(state)),
                ) catch @panic("allocation failed");
                family[0] = @truncate(index + phase);
                if ((index + phase) % 5 == 0) {
                    family = allocator.realloc(
                        family,
                        family.len + appendGrowth(index, phase),
                    ) catch @panic("realloc failed");
                    family[0] = @truncate(index + phase);
                }
                temp.* = family;
            }
            coz.progressNamed("gpalloc.phase.espresso_trace.expand");
        }

        {
            const append_phase = bench.phaseAt("gpalloc.phase.espresso_trace.append", @src());
            defer append_phase.end();

            for (&temps, 0..) |*temp, index| {
                const family = temp.* orelse continue;
                if ((index + phase) % 3 == 0) {
                    const slot = (index * 11 + phase * 7) % covers.len;
                    if (covers.*[slot]) |old| {
                        std.mem.doNotOptimizeAway(old.ptr);
                        allocator.free(old);
                    }
                    covers.*[slot] = family;
                    temp.* = null;
                    continue;
                }
                if ((index + phase) % 7 == 0) {
                    const clone = allocator.alloc(u8, family.len) catch @panic("allocation failed");
                    clone[0] = @truncate(index);
                    std.mem.doNotOptimizeAway(clone.ptr);
                    allocator.free(clone);
                }
                std.mem.doNotOptimizeAway(family.ptr);
                allocator.free(family);
                temp.* = null;
            }
            coz.progressNamed("gpalloc.phase.espresso_trace.append");
        }

        {
            const sparse_phase =
                bench.phaseAt("gpalloc.phase.espresso_trace.sparse_matrix", @src());
            defer sparse_phase.end();

            var rows: [parameters.espresso_trace_sparse_row_count]?[]u8 =
                @as([parameters.espresso_trace_sparse_row_count]?[]u8, @splat(null));
            var elements: [parameters.espresso_trace_matrix_element_count]?[]u8 =
                @as([parameters.espresso_trace_matrix_element_count]?[]u8, @splat(null));

            for (&rows, 0..) |*row, index| {
                var bytes = allocator.alloc(u8, sparseRowSize(index, phase)) catch
                    @panic("allocation failed");
                bytes[0] = @truncate(index + phase);
                if ((index + phase) % 6 == 0) {
                    bytes = allocator.realloc(bytes, bytes.len + 64) catch
                        @panic("realloc failed");
                    bytes[0] = @truncate(index + phase);
                }
                row.* = bytes;
            }

            for (&elements, 0..) |*element, index| {
                const bytes = allocator.alloc(u8, matrixElementSize(index, phase)) catch
                    @panic("allocation failed");
                bytes[0] = @truncate(index + phase);
                element.* = bytes;
            }

            for (&elements) |*element| {
                const bytes = element.* orelse continue;
                std.mem.doNotOptimizeAway(bytes.ptr);
                allocator.free(bytes);
                element.* = null;
            }
            for (&rows) |*row| {
                const bytes = row.* orelse continue;
                std.mem.doNotOptimizeAway(bytes.ptr);
                allocator.free(bytes);
                row.* = null;
            }
            coz.progressNamed("gpalloc.phase.espresso_trace.sparse_matrix");
        }

        {
            const reduce_phase = bench.phaseAt("gpalloc.phase.espresso_trace.irredundant", @src());
            defer reduce_phase.end();

            var index: usize = phase;
            while (index < covers.len) : (index += 5) {
                const cover = covers.*[index] orelse continue;
                if ((index + phase) % 2 == 0) {
                    const resized = allocator.realloc(
                        cover,
                        reducedCoverSize(cover.len, index, phase),
                    ) catch @panic("realloc failed");
                    resized[0] = @truncate(index + phase);
                    covers.*[index] = resized;
                    continue;
                }
                std.mem.doNotOptimizeAway(cover.ptr);
                allocator.free(cover);
                covers.*[index] = null;
            }
            coz.progressNamed("gpalloc.phase.espresso_trace.irredundant");
        }
    }
}

fn drainTrace(
    allocator: std.mem.Allocator,
    masks: *[parameters.espresso_trace_var_count]?[]u8,
    covers: *[parameters.espresso_trace_cover_count]?[]u8,
) void {
    const drain_phase = bench.phaseAt("gpalloc.phase.espresso_trace.drain", @src());
    defer drain_phase.end();

    for (&covers.*) |*cover| {
        const bytes = cover.* orelse continue;
        std.mem.doNotOptimizeAway(bytes.ptr);
        allocator.free(bytes);
        cover.* = null;
    }
    for (&masks.*) |*mask| {
        const bytes = mask.* orelse continue;
        std.mem.doNotOptimizeAway(bytes.ptr);
        allocator.free(bytes);
        mask.* = null;
    }
}

fn maskSize(index: usize) usize {
    return 16 + (2 + (index % 12)) * @sizeOf(u32);
}

fn cubeSize(index: usize, state: usize) usize {
    const word_count = 2 + ((index * 7 + state * 3) % 22);
    return word_count * @sizeOf(u32);
}

fn labelSize(index: usize) usize {
    return 12 + (index % 9) * 8;
}

fn coverSize(index: usize, phase: usize, state: usize) usize {
    const cube_count = 4 + ((index * 5 + phase * 7 + state) % 48);
    const word_count = 2 + ((index * 11 + phase * 3) % 18);
    return 24 + cube_count * word_count * @sizeOf(u32);
}

fn appendGrowth(index: usize, phase: usize) usize {
    const extra_cubes = 1 + ((index * 3 + phase * 5) % 24);
    const word_count = 2 + ((index + phase * 7) % 16);
    return extra_cubes * word_count * @sizeOf(u32);
}

fn sparseRowSize(index: usize, phase: usize) usize {
    const element_capacity = 2 + ((index * 5 + phase * 11) % 18);
    return 32 + element_capacity * @sizeOf(usize);
}

fn matrixElementSize(index: usize, phase: usize) usize {
    const sizes = [_]usize{ 24, 32, 40, 48, 64, 80, 96, 128 };
    return sizes[(index * 13 + phase * 7) % sizes.len];
}

fn reducedCoverSize(current: usize, index: usize, phase: usize) usize {
    const retained = current / 2 + 24 + ((index * 17 + phase * 19) % 192);
    return @max(@as(usize, 32), retained);
}
