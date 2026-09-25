const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const D32 = simd.FixedTag(u32, 8);
const D64 = simd.FixedTag(u64, 4);
const max_values: usize = 129;

pub const Hash32Property = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const key: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const input: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const other: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const range: u32 = @intCast(try data.drawInteger(1, std.math.maxInt(u32), 1));
        const length: usize = @intCast(try data.drawInteger(0, max_values, 0));
        const triple = simd.Triple32.initKey(key);
        const weak = simd.WeakTwoMul.initKey(key);
        const expected = triple.hash(input);
        const vector = triple.oneVec(D32, @splat(input));
        try std.testing.expect(@reduce(.And, vector == @as(D32.Vector, @splat(expected))));
        const reduced = simd.lemireMod(input, range);
        try std.testing.expectEqual(
            @as(u32, @truncate((@as(u64, input) * @as(u64, range)) >> 32)),
            reduced,
        );
        try std.testing.expect(reduced < range);
        if (input != other) {
            try std.testing.expect(triple.hash(input) != triple.hash(other));
            try std.testing.expect(weak.hash(input) != weak.hash(other));
        }

        var source: [max_values]u32 = undefined;
        var output: [max_values]u32 = undefined;
        var in_place: [max_values]u32 = undefined;
        for (source[0..length], 0..) |*value, index| value.* = input +% @as(u32, @intCast(index));
        @memcpy(in_place[0..length], source[0..length]);
        simd.hashArray(D32, triple, source[0..length], output[0..length]);
        simd.hashArrayInPlace(D32, triple, in_place[0..length]);
        try std.testing.expectEqualSlices(u32, output[0..length], in_place[0..length]);
        for (source[0..length], output[0..length]) |value, actual| {
            try std.testing.expectEqual(triple.hash(value), actual);
        }

        const Masked = simd.MaskedTriple32(13);
        const masked = Masked.initKey(key & Masked.mask);
        const masked_input = input & Masked.mask;
        const masked_other = other & Masked.mask;
        const masked_output = masked.hash(masked_input);
        try std.testing.expect(masked_output <= Masked.mask);
        if (masked_input != masked_other) {
            try std.testing.expect(masked_output != masked.hash(masked_other));
        }
    }
};

pub const Hash64Property = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const key = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const input = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const other = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const moremur = simd.Moremur.initKey(key);
        const expected = moremur.hash(input);
        const vector = moremur.oneVec(D64, @splat(input));
        try std.testing.expect(@reduce(.And, vector == @as(D64.Vector, @splat(expected))));
        if (input != other) try std.testing.expect(moremur.hash(input) != moremur.hash(other));

        const Masked = simd.MaskedMoremur(47);
        const masked = Masked.initKey(key & Masked.mask);
        const masked_input = input & Masked.mask;
        const masked_other = other & Masked.mask;
        const masked_output = masked.hash(masked_input);
        try std.testing.expect(masked_output <= Masked.mask);
        if (masked_input != masked_other) {
            try std.testing.expect(masked_output != masked.hash(masked_other));
        }
    }
};

pub const SeedAndDistinctProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const key: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const length: usize = @intCast(try data.drawInteger(0, max_values, 0));
        const engine = simd.AesCtrEngine.initDeterministic();
        const triple = simd.Triple32.initSeed(&engine, seed);
        const moremur = simd.Moremur.initSeed(&engine, seed);
        const generated = engine.generate(seed, 0);
        try std.testing.expectEqual(@as(u32, @truncate(generated)), triple.key());
        try std.testing.expectEqual(generated, moremur.key());
        var narrow: [max_values]u32 = undefined;
        var wide: [max_values]u64 = undefined;
        simd.fillRandomDistinct(u32, key, narrow[0..length]);
        simd.fillRandomDistinct(u64, key, wide[0..length]);
        for (narrow[0..length], wide[0..length], 0..) |value, widened, index| {
            try std.testing.expectEqual(@as(u64, value), widened);
            for (narrow[0..index]) |prior| try std.testing.expect(value != prior);
        }
    }
};

test "property: u32 hashes preserve scalar vector array and masked bijections" {
    try hypothesis.checkNamed(Hash32Property, "simd-hash-u32", run.settings());
}

test "property: u64 hashes preserve scalar vector and masked bijections" {
    try hypothesis.checkNamed(Hash64Property, "simd-hash-u64", run.settings());
}

test "property: hash seeding and distinct fills retain exact permutations" {
    try hypothesis.checkNamed(SeedAndDistinctProperty, "simd-hash-seed-distinct", run.settings());
}
