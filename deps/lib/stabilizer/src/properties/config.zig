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

test "defaults match upstream stabilizer runtime constants" {
    try std.testing.expectEqual(Reference.data_shuffle, default_shuffle_slots);
    try std.testing.expectEqual(Reference.code_shuffle, default_shuffle_slots);
    try std.testing.expectEqual(Reference.data_size, default_region_size);
    try std.testing.expectEqual(Reference.code_size, default_region_size);
    try std.testing.expectEqual(Reference.code_align, code_alignment);
    try std.testing.expectEqual(Reference.stack_align, stack_alignment);
    try std.testing.expectEqual(Reference.interval_ms, rerandomize_interval_ms);
    try std.testing.expect((stabilizer.HeapConfig{}).pointer_validation);
}

test "size classes are powers of two" {
    try std.testing.expectEqual(@as(usize, 16), try sizeClass(1, 16));
    try std.testing.expectEqual(@as(usize, 16), try sizeClass(16, 16));
    try std.testing.expectEqual(@as(usize, 32), try sizeClass(17, 16));
}
