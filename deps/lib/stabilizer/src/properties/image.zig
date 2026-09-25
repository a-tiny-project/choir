const std = @import("std");
const hypothesis = @import("hypothesis");
const stabilizer = @import("stabilizer");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const default_shuffle_slots = stabilizer.default_shuffle_slots;
const default_region_size = stabilizer.default_region_size;
const code_alignment = stabilizer.code_alignment;
const stack_alignment = stabilizer.stack_alignment;
const rerandomize_interval_ms = stabilizer.rerandomize_interval_ms;
const max_stack_pad_unit = stabilizer.max_stack_pad_unit;

const Reference = stabilizer.Reference;
const Marsaglia = stabilizer.Marsaglia;
const StackPads = stabilizer.StackPads;
const ShuffleAllocator = stabilizer.ShuffleAllocator;
const sizeClass = stabilizer.sizeClass;
const FunctionId = stabilizer.FunctionId;
const LocationId = stabilizer.LocationId;
const FunctionOptions = stabilizer.FunctionOptions;
const FunctionEntryState = stabilizer.FunctionEntryState;
const FunctionLocation = stabilizer.FunctionLocation;
const CodeRandomizer = stabilizer.CodeRandomizer;
const Runtime = stabilizer.Runtime;

fn settings() hypothesis.Settings {
    return hypothesis.Settings.quick()
        .withSeed(0x57ab_11e5)
        .withDatabase("zig-out/hypothesis-failures/stabilizer");
}

fn drawUsize(data: *hypothesis.ConjectureData, min: usize, max: usize, shrink_towards: usize) !usize {
    return @intCast(try data.drawInteger(
        @intCast(min),
        @intCast(max),
        @intCast(shrink_towards),
    ));
}

fn drawAlignment(data: *hypothesis.ConjectureData) !Alignment {
    const shift = try drawUsize(data, 0, 8, 0);
    return .fromByteUnits(@as(usize, 1) << @as(u6, @intCast(shift)));
}

test "code randomizer copies function image bytes through relocation" {
    var code = CodeRandomizer.init(std.testing.allocator, .{ .shuffle_slots = 4 }, 55);
    defer code.deinit();

    const function = try code.registerFunctionImage(.{
        .code = &.{ 0xaa, 0xbb, 0xcc },
        .table = &.{ 0x10, 0x20 },
        .table_adjacent = true,
    });
    const first = try code.relocate(function);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb, 0xcc, 0x10, 0x20 }, first.contents);

    first.contents[1] = 0xee;
    const second = try code.relocate(function);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xee, 0xcc, 0x10, 0x20 }, second.contents);
}

test "code randomizer keeps non-adjacent relocation table out of location image" {
    var code = CodeRandomizer.init(std.testing.allocator, .{ .shuffle_slots = 4 }, 55);
    defer code.deinit();

    const function = try code.registerFunctionImage(.{
        .code = &.{ 0xaa, 0xbb, 0xcc },
        .table = &.{ 0x10, 0x20 },
        .table_adjacent = false,
    });
    const location = try code.relocate(function);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb, 0xcc }, location.contents);
}

const CodeImageProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, allocator: Allocator) !void {
        var code = CodeRandomizer.init(allocator, .{
            .shuffle_slots = 16,
            .alignment = code_alignment,
        }, 0x494d_4147);
        defer code.deinit();

        const code_len = try drawUsize(data, 1, 64, 4);
        const image_code = try allocator.alloc(u8, code_len);
        defer allocator.free(image_code);
        for (image_code, 0..) |*byte, index| byte.* = @truncate(index);

        const table_words = try drawUsize(data, 1, 8, 2);
        const table = try allocator.alloc(u8, table_words * @sizeOf(usize));
        defer allocator.free(table);
        @memset(table, 0);

        const slot_count = try drawUsize(data, 0, table_words, 1);
        var slots_buffer: [8]usize = undefined;
        var slot_index: usize = 0;
        while (slot_index < slot_count) : (slot_index += 1) {
            slots_buffer[slot_index] = slot_index * @sizeOf(usize);
        }

        const function = try code.registerFunctionImage(.{
            .code = image_code,
            .table = table,
            .table_adjacent = true,
            .stack_pad_unit = 0,
            .stack_pad_table_offsets = slots_buffer[0..slot_count],
        });
        const location = try code.relocate(function);
        try std.testing.expectEqual(code_len + table.len, location.contents.len);
        if (slot_count > 0) {
            const address = code.stackPadAddress(function).?;
            slot_index = 0;
            while (slot_index < slot_count) : (slot_index += 1) {
                const offset = code_len + slots_buffer[slot_index];
                try std.testing.expectEqual(
                    address,
                    std.mem.readInt(usize, location.contents[offset..][0..@sizeOf(usize)], .little),
                );
            }
        } else {
            try std.testing.expect(code.stackPadAddress(function) == null);
        }
    }
};

test "pbt: code image relocation patches stack pad tables" {
    try hypothesis.checkNamed(CodeImageProperty, "stabilizer-code-image", settings());
}
