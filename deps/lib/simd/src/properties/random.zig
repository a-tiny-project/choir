const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const D = simd.FixedTag(u64, 4);
const Generator = simd.VectorXoshiro(D);
const Cached = simd.CachedXoshiro(D, 16);
const max_values: usize = 129;

pub const XoshiroProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const length: usize = @intCast(try data.drawInteger(0, max_values, 0));
        const thread_number = try data.drawInteger(0, 3, 0);
        var generator = Generator.initThread(seed, thread_number);
        const initial_state = generator.getState();
        var output: [max_values]u64 = undefined;
        generator.fill(output[0..length]);
        const final_state = generator.getState();
        generator.setState(initial_state);
        var replay: [max_values]u64 = undefined;
        generator.fill(replay[0..length]);
        try std.testing.expectEqualSlices(u64, output[0..length], replay[0..length]);
        try std.testing.expectEqual(final_state, generator.getState());

        var scalar = simd.Xoshiro.init(seed);
        var scalar_stream: u64 = 0;
        while (scalar_stream < thread_number) : (scalar_stream += 1) {
            scalar.longJump();
        }
        var streams: [D.lane_count]simd.Xoshiro = undefined;
        inline for (0..D.lane_count) |lane| {
            streams[lane] = scalar;
            scalar.jump();
        }
        for (output[0..length], 0..) |actual, index| {
            try std.testing.expectEqual(streams[index % D.lane_count].next(), actual);
        }

        var uniform_generator = Generator.initThread(seed, thread_number);
        var uniform_output: [max_values]f64 = undefined;
        uniform_generator.fillUniform(uniform_output[0..length]);
        try std.testing.expectEqual(final_state, uniform_generator.getState());
        var uniform_scalar = simd.Xoshiro.init(seed);
        var uniform_stream: u64 = 0;
        while (uniform_stream < thread_number) : (uniform_stream += 1) {
            uniform_scalar.longJump();
        }
        var uniform_streams: [D.lane_count]simd.Xoshiro = undefined;
        inline for (0..D.lane_count) |lane| {
            uniform_streams[lane] = uniform_scalar;
            uniform_scalar.jump();
        }
        for (uniform_output[0..length], 0..) |actual, index| {
            try std.testing.expectEqual(
                uniform_streams[index % D.lane_count].uniform(),
                actual,
            );
        }
    }
};

pub const CachedProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const seed = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const length: usize = @intCast(try data.drawInteger(0, max_values, 0));
        var cached = Cached.init(seed);
        var generator = Generator.init(seed);
        var expected: [max_values]u64 = undefined;
        generator.fill(expected[0..length]);
        for (expected[0..length]) |value| try std.testing.expectEqual(value, cached.next());
    }
};

pub const AesCounterProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const key0 = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const key1 = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const stream_id = try data.drawInteger(0, std.math.maxInt(u64), 0);
        const counter = try data.drawInteger(0, std.math.maxInt(u64) - 8, 0);
        const engine = simd.AesCtrEngine.initKey(.{ key0, key1 });
        try std.testing.expectEqual(
            engine.generate(stream_id, counter),
            engine.generate(stream_id, counter),
        );
        var stream = simd.RngStream.init(&engine, stream_id);
        stream.counter = counter;
        for (0..8) |offset| {
            try std.testing.expectEqual(
                engine.generate(stream_id, counter + offset),
                stream.next(),
            );
        }
        stream = simd.RngStream.init(&engine, stream_id);
        for (0..8) |_| {
            const value = simd.randomNormalizedFloat(&stream);
            try std.testing.expect(value >= -1 and value < 1);
        }
    }
};

test "property: vector xoshiro replays state and interleaves scalar streams" {
    try hypothesis.checkNamed(XoshiroProperty, "simd-random-xoshiro-streams", run.settings());
}

test "property: cached xoshiro preserves vector stream order across refills" {
    try hypothesis.checkNamed(CachedProperty, "simd-random-xoshiro-cache", run.settings());
}

test "property: AES counter addressing is pure and stream counters advance exactly" {
    try hypothesis.checkNamed(AesCounterProperty, "simd-random-aes-counter", run.settings());
}
