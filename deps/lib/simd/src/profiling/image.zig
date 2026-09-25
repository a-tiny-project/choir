const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D = simd.FixedTag(u32, 8);
const width: usize = 1_027;
const height: usize = 257;
const stride: usize = simd.imageBytesPerRowFor(
    width,
    @sizeOf(u32),
    simd.image.vector_size,
) catch unreachable;
const storage_bytes: usize = stride * height;
const mirror_count: usize = 262_157;

var storage: [storage_bytes]u8 align(simd.image.storage_alignment) = undefined;
var image: simd.Image(u32) = simd.Image(u32).empty();
var expected_scan: u64 = 0;
var expected_mirror: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    image = simd.Image(u32).initBorrowed(width, height, stride, &storage) catch
        @panic("image benchmark storage rejected");
    for (0..height) |y| {
        const row = image.mutableRow(y);
        for (row[0..width], 0..) |*value, x| {
            value.* = @intCast((y * 65_537 + x * 257) & 0xffff);
        }
    }
    expected_scan = scalarPipeline();
    expected_mirror = mirrorPipeline();
}

pub fn scalar(_: std.mem.Allocator) void {
    const observed = blk: {
        const phase = bench.phaseAt("simd.image.scalar", @src());
        defer phase.end();
        break :blk scalarPipeline();
    };
    if (observed != expected_scan) @panic("image scalar witness failed");
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.image.scalar.complete");
}

pub fn vector(_: std.mem.Allocator) void {
    const observed = blk: {
        const phase = bench.phaseAt("simd.image.u32x8", @src());
        defer phase.end();
        break :blk vectorPipeline();
    };
    if (observed != expected_scan) @panic("image vector witness failed");
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.image.u32x8.complete");
}

pub fn mirrored(_: std.mem.Allocator) void {
    const observed = blk: {
        const phase = bench.phaseAt("simd.image.mirror", @src());
        defer phase.end();
        break :blk mirrorPipeline();
    };
    if (observed != expected_mirror) @panic("image mirror witness failed");
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.image.mirror.complete");
}

fn scalarPipeline() u64 {
    var sum: u64 = 0;
    for (0..height) |y| {
        for (image.constRow(y)[0..width]) |value| sum +%= value;
    }
    return sum;
}

fn vectorPipeline() u64 {
    var sum: u64 = 0;
    for (0..height) |y| {
        const row = image.constRow(y);
        var x: usize = 0;
        while (x + D.lane_count <= width) : (x += D.lane_count) {
            sum +%= simd.reduceSum(D, simd.load(D, row[x..]));
        }
        for (row[x..width]) |value| sum +%= value;
    }
    return sum;
}

fn mirrorPipeline() u64 {
    var digest: u64 = 0xcbf2_9ce4_8422_2325;
    for (0..mirror_count) |index| {
        const coord = @as(i64, @intCast(index % 4_097)) - 2_048;
        digest = (digest ^ simd.mirror(coord, width)) *%
            0x0000_0100_0000_01b3;
    }
    return digest;
}
