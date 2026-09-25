const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;

pub const MaskProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var remaining = (try drawU64(data)) & simd.target.all_targets;
        var prior_bit: u6 = 0;
        var first = true;
        var count: usize = 0;
        while (remaining != 0) {
            const expected = independentBest(remaining).?;
            const actual = simd.target.bestTarget(remaining).?;
            try std.testing.expectEqual(expected, actual);
            try std.testing.expectEqualStrings(expected.name(), simd.targetName(expected.bit()));
            const bit_index: u6 = @backingInt(actual);
            if (!first) try std.testing.expect(bit_index > prior_bit);
            first = false;
            prior_bit = bit_index;
            count += 1;
            remaining &= remaining - 1;
        }
        try std.testing.expect(count <= simd.target.target_count);
    }
};

pub const RuntimeProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        var detected = (try drawU64(data)) & simd.target.all_targets;
        if (detected == 0) detected = simd.Target.sse4.bit();
        const disabled = (try drawU64(data)) & simd.target.all_targets;
        const use_mock = try data.drawBoolean();
        var mocked = (try drawU64(data)) & simd.target.all_targets;
        if (use_mock and mocked == 0) mocked = simd.Target.scalar.bit();
        if (!use_mock) mocked = 0;
        const generated = (try drawU64(data)) & simd.target.all_targets;
        var runtime = simd.TargetRuntime.init(.avx2);
        runtime.disableTargets(disabled);
        runtime.setSupportedTargetsForTest(mocked);

        var expected_supported = (if (mocked == 0) detected else mocked) & ~disabled;
        if (expected_supported == 0) expected_supported = simd.Target.avx2.bit();
        try std.testing.expectEqual(expected_supported, runtime.supportedTargets(detected));
        const expected_target = independentBest(expected_supported & generated) orelse .emu128;
        try std.testing.expectEqual(
            expected_target,
            runtime.dispatchedTarget(detected, generated),
        );
        try std.testing.expect(runtime.chosen.isInitialized());
        runtime.disableTargets(disabled ^ simd.Target.sse4.bit());
        try std.testing.expect(!runtime.chosen.isInitialized());
    }
};

pub const DispatchProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const Fn = *const fn (u32) u32;
        const Entry = simd.TargetFunction(Fn);
        const entries = [_]Entry{
            .{ .target = .avx3, .implementation = dispatchAvx3 },
            .{ .target = .avx2, .implementation = dispatchAvx2 },
            .{ .target = .sse4, .implementation = dispatchSse4 },
        };
        const source = try drawU64(data);
        var detected: simd.TargetMask = 0;
        if (source & 1 != 0) detected |= simd.Target.avx3.bit();
        if (source & 2 != 0) detected |= simd.Target.avx2.bit();
        if (source & 4 != 0) detected |= simd.Target.sse4.bit();
        detected |= simd.Target.emu128.bit();
        const disabled = (try drawU64(data)) &
            (simd.Target.avx3.bit() | simd.Target.avx2.bit() | simd.Target.sse4.bit());
        var runtime = simd.TargetRuntime.init(.emu128);
        runtime.disableTargets(disabled);
        const selected = simd.selectTargetFunction(
            &runtime,
            detected,
            &entries,
            @as(Fn, dispatchFallback),
        );
        const available = detected & ~disabled;
        const expected: u32 = if (available & simd.Target.avx3.bit() != 0)
            3
        else if (available & simd.Target.avx2.bit() != 0)
            2
        else if (available & simd.Target.sse4.bit() != 0)
            4
        else
            0;
        try std.testing.expectEqual(expected, selected(0));
    }
};

fn independentBest(mask: simd.TargetMask) ?simd.Target {
    for (simd.target_catalog) |target| if (mask & target.bit() != 0) return target;
    return null;
}

fn dispatchAvx3(_: u32) u32 {
    return 3;
}

fn dispatchAvx2(_: u32) u32 {
    return 2;
}

fn dispatchSse4(_: u32) u32 {
    return 4;
}

fn dispatchFallback(_: u32) u32 {
    return 0;
}

fn drawU64(data: *hypothesis.ConjectureData) !u64 {
    const low: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
    const high: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
    return @as(u64, high) << 32 | low;
}

test "property: target masks enumerate in pinned preference order" {
    try hypothesis.checkNamed(MaskProperty, "simd-target-mask-order", run.settings());
}

test "property: target runtime matches an independent mask state model" {
    try hypothesis.checkNamed(RuntimeProperty, "simd-target-runtime-model", run.settings());
}

test "property: target function selection follows the best shared entry" {
    try hypothesis.checkNamed(DispatchProperty, "simd-target-function-model", run.settings());
}
