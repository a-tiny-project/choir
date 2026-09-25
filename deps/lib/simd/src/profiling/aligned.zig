const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const allocation_items: usize = 65_536;
const vector_items: usize = 4_096;
const shape = [4]usize{ 16, 16, 16, 16 };
const view_items: usize = 16 * 16 * 16 * 16;

var view_storage: [view_items]u32 align(simd.alignment) = undefined;
var view: simd.AlignedView(u32, 4) = undefined;
var expected_view_digest: u64 = 0;
var expected_vector_digest: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    view = simd.AlignedView(u32, 4).initFor(&view_storage, shape, 16) catch
        @panic("aligned view benchmark storage rejected");
    expected_view_digest = 0;
    for (&view_storage, 0..) |*value, index| {
        value.* = @intCast((index * 65_537 + 257) & 0xffff_ffff);
        expected_view_digest +%= value.*;
    }
    expected_vector_digest = 0;
    for (0..vector_items) |index| {
        expected_vector_digest +%= vectorValue(index);
    }
}

pub fn allocationLifecycle(allocator: std.mem.Allocator) void {
    var allocation = blk: {
        const phase = bench.phaseAt("simd.aligned.allocation", @src());
        defer phase.end();
        break :blk simd.AlignedAllocation(u64).init(allocator, allocation_items) catch
            @panic("aligned allocation benchmark failed");
    };
    allocation.values[0] = 0x0123_4567_89ab_cdef;
    allocation.values[allocation.values.len - 1] = 0xfedc_ba98_7654_3210;
    if (!simd.isAligned(allocation.values.ptr)) {
        @panic("aligned allocation benchmark witness failed");
    }
    std.mem.doNotOptimizeAway(&allocation.values);
    allocation.deinit(allocator);
    bench.coz.progressNamed("simd.aligned.allocation.complete");
}

pub fn rowTraversal(_: std.mem.Allocator) void {
    var observed: u64 = 0;
    {
        const phase = bench.phaseAt("simd.aligned.rows", @src());
        defer phase.end();
        for (0..shape[0]) |d0| {
            for (0..shape[1]) |d1| {
                for (0..shape[2]) |d2| {
                    const row = view.constRow(.{ d0, d1, d2 }) catch unreachable;
                    for (row) |value| observed +%= value;
                }
            }
        }
    }
    if (observed != expected_view_digest) @panic("aligned row benchmark witness failed");
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.aligned.rows.complete");
}

pub fn vectorGrowth(allocator: std.mem.Allocator) void {
    var vector = simd.AlignedVector(u64).initCapacity(allocator, 0) catch
        @panic("aligned vector benchmark initialization failed");
    var observed: u64 = 0;
    {
        const phase = bench.phaseAt("simd.aligned.vector-growth", @src());
        defer phase.end();
        for (0..vector_items) |index| {
            const value = vectorValue(index);
            vector.append(allocator, value) catch
                @panic("aligned vector benchmark growth failed");
            observed +%= value;
        }
    }
    if (observed != expected_vector_digest or vector.len() != vector_items) {
        @panic("aligned vector benchmark witness failed");
    }
    std.mem.doNotOptimizeAway(vector.constItems());
    vector.deinit(allocator);
    bench.coz.progressNamed("simd.aligned.vector-growth.complete");
}

fn vectorValue(index: usize) u64 {
    return @as(u64, @intCast(index)) *% 0x9e37_79b9_7f4a_7c15 +% 0x1000_0001;
}
