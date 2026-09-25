const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const max_size: usize = 257;

const Digest = struct {
    value: u64 = 0xcbf2_9ce4_8422_2325,
    count: usize = 0,

    pub fn call(self: *@This(), index: usize) void {
        self.value = (self.value ^ @as(u64, @intCast(index))) *% 0x0000_0100_0000_01b3;
        self.count += 1;
    }
};

fn verifyModel(comptime Set: type, set: *const Set, model: *const [max_size]bool) !void {
    var expected = Digest{};
    var expected_first = max_size;
    var expected_first0 = max_size;
    for (model, 0..) |present, index| {
        try std.testing.expectEqual(present, set.get(index));
        if (present) {
            expected.call(index);
            if (expected_first == max_size) expected_first = index;
        } else if (expected_first0 == max_size) {
            expected_first0 = index;
        }
    }
    try std.testing.expectEqual(expected.count, set.count());
    try std.testing.expectEqual(expected.count != 0, set.any());
    try std.testing.expectEqual(expected.count == max_size, set.all());
    if (expected_first != max_size) try std.testing.expectEqual(expected_first, set.first());
    if (expected_first0 != max_size) try std.testing.expectEqual(expected_first0, set.first0());
    var observed = Digest{};
    set.foreach(&observed);
    try std.testing.expectEqual(expected.count, observed.count);
    try std.testing.expectEqual(expected.value, observed.value);
}

pub const MutationProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const Flat = simd.BitSet(max_size);
        const Atomic = simd.AtomicBitSet(max_size);
        const Sparse = simd.BitSet4096(max_size);
        var flat = Flat{};
        var atomic = Atomic{};
        var sparse = Sparse{};
        var model: [max_size]bool = @splat(false);
        const operation_count: usize = @intCast(try data.drawInteger(0, 512, 0));
        for (0..operation_count) |_| {
            const index: usize = @intCast(try data.drawInteger(0, max_size - 1, 0));
            const present = try data.drawBoolean();
            if (present) {
                flat.set(index);
                atomic.set(index);
                sparse.set(index);
            } else {
                flat.clear(index);
                atomic.clear(index);
                sparse.clear(index);
            }
            model[index] = present;
        }
        try verifyModel(Flat, &flat, &model);
        try verifyModel(Atomic, &atomic, &model);
        try verifyModel(Sparse, &sparse, &model);
    }
};

pub const WordImportProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const first_low: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const first_high: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const second_low: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const second_high: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const first = @as(u64, first_high) << 32 | first_low;
        const second = @as(u64, second_high) << 32 | second_low;
        const expected = first | second;
        var word = simd.BitSet64{};
        var sparse = simd.DefaultBitSet4096{};
        word.setNonzeroBitsFrom64(first);
        word.setNonzeroBitsFrom64(second);
        sparse.setNonzeroBitsFrom64(first);
        sparse.setNonzeroBitsFrom64(second);
        try std.testing.expectEqual(expected, word.get64());
        try std.testing.expectEqual(expected, sparse.get64());
        try std.testing.expectEqual(@as(usize, @popCount(expected)), word.count());
        try std.testing.expectEqual(word.count(), sparse.count());
        try std.testing.expectEqual(expected != 0, word.any());
        try std.testing.expectEqual(expected == std.math.maxInt(u64), word.all());
        if (expected != 0) try std.testing.expectEqual(@as(usize, @ctz(expected)), word.first());
        if (expected != std.math.maxInt(u64)) {
            try std.testing.expectEqual(@as(usize, @ctz(~expected)), word.first0());
        }
    }
};

test "property: fixed atomic and sparse bit sets match a scalar mutation model" {
    try hypothesis.checkNamed(MutationProperty, "simd-bitset-mutation-model", run.settings());
}

test "property: bit set word imports are monotone unions" {
    try hypothesis.checkNamed(WordImportProperty, "simd-bitset-word-union", run.settings());
}
