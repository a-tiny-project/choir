const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const detection_count: usize = 4096;
const selection_count: usize = 65_536;
const cached_selection_count: usize = 262_144;

var selection_masks: [selection_count]simd.TargetMask = undefined;
var expected_detection: u64 = 0;
var expected_selection: u64 = 0;
var expected_cached_selection: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    const selectable = simd.Target.avx3.bit() | simd.Target.avx2.bit() |
        simd.Target.sse4.bit() | simd.Target.ssse3.bit() |
        simd.Target.sse2.bit() | simd.Target.emu128.bit();
    for (&selection_masks, 0..) |*mask, index| {
        const mixed = @as(u64, @intCast(index)) *% 0x9e37_79b9_7f4a_7c15 +%
            0xd1b5_4a32_d192_ed03;
        mask.* = mixed & selectable | simd.Target.emu128.bit();
    }
    expected_detection = detectMany();
    expected_selection = selectMany();
    expected_cached_selection = selectCachedMany();
}

pub fn detection(_: std.mem.Allocator) void {
    const phase = bench.phaseAt("simd.target.detect", @src());
    const digest = detectMany();
    phase.end();
    if (digest != expected_detection) @panic("target detection benchmark witness failed");
    std.mem.doNotOptimizeAway(&digest);
    bench.coz.progressNamed("simd.target.detect.complete");
}

pub fn selection(_: std.mem.Allocator) void {
    const phase = bench.phaseAt("simd.target.select", @src());
    const digest = selectMany();
    phase.end();
    if (digest != expected_selection) @panic("target selection benchmark witness failed");
    std.mem.doNotOptimizeAway(&digest);
    bench.coz.progressNamed("simd.target.select.complete");
}

pub fn cachedSelection(_: std.mem.Allocator) void {
    const phase = bench.phaseAt("simd.target.select.cached", @src());
    const digest = selectCachedMany();
    phase.end();
    if (digest != expected_cached_selection) @panic("cached target benchmark witness failed");
    std.mem.doNotOptimizeAway(&digest);
    bench.coz.progressNamed("simd.target.select.cached.complete");
}

fn detectMany() u64 {
    var digest: u64 = 0xcbf2_9ce4_8422_2325;
    for (0..detection_count) |index| {
        digest ^= simd.detectTargets() +% @as(u64, @intCast(index));
        digest *%= 0x0000_0100_0000_01b3;
    }
    return digest;
}

fn selectMany() u64 {
    const Fn = *const fn (u64) u64;
    const Entry = simd.TargetFunction(Fn);
    const entries = [_]Entry{
        .{ .target = .avx3, .implementation = dispatchAvx3 },
        .{ .target = .avx2, .implementation = dispatchAvx2 },
        .{ .target = .sse4, .implementation = dispatchSse4 },
        .{ .target = .ssse3, .implementation = dispatchSsse3 },
        .{ .target = .sse2, .implementation = dispatchSse2 },
    };
    var runtime = simd.TargetRuntime.init(.emu128);
    var digest: u64 = 0xcbf2_9ce4_8422_2325;
    for (selection_masks, 0..) |mask, index| {
        runtime.setSupportedTargetsForTest(mask);
        const selected = simd.selectTargetFunction(
            &runtime,
            simd.Target.emu128.bit(),
            &entries,
            @as(Fn, dispatchFallback),
        );
        digest ^= selected(@intCast(index));
        digest *%= 0x0000_0100_0000_01b3;
    }
    return digest;
}

fn selectCachedMany() u64 {
    const Fn = *const fn (u64) u64;
    const Entry = simd.TargetFunction(Fn);
    const entries = [_]Entry{
        .{ .target = .avx3, .implementation = dispatchAvx3 },
        .{ .target = .avx2, .implementation = dispatchAvx2 },
        .{ .target = .sse4, .implementation = dispatchSse4 },
        .{ .target = .ssse3, .implementation = dispatchSsse3 },
        .{ .target = .sse2, .implementation = dispatchSse2 },
    };
    var runtime = simd.TargetRuntime.init(.emu128);
    runtime.setSupportedTargetsForTest(simd.Target.avx2.bit());
    var digest: u64 = 0xcbf2_9ce4_8422_2325;
    for (0..cached_selection_count) |index| {
        const selected = simd.selectTargetFunction(
            &runtime,
            simd.Target.emu128.bit(),
            &entries,
            @as(Fn, dispatchFallback),
        );
        digest ^= selected(@intCast(index));
        digest *%= 0x0000_0100_0000_01b3;
    }
    return digest;
}

fn dispatchAvx3(value: u64) u64 {
    return value +% 3;
}

fn dispatchAvx2(value: u64) u64 {
    return value +% 2;
}

fn dispatchSse4(value: u64) u64 {
    return value +% 4;
}

fn dispatchSsse3(value: u64) u64 {
    return value +% 13;
}

fn dispatchSse2(value: u64) u64 {
    return value +% 12;
}

fn dispatchFallback(value: u64) u64 {
    return value;
}
