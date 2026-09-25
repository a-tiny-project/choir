const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const max_size: usize = 4096;
const sparse_count: usize = 64;
const Flat = simd.BitSet(max_size);
const Atomic = simd.AtomicBitSet(max_size);
const Sparse = simd.BitSet4096(max_size);

var flat = Flat{};
var atomic = Atomic{};
var sparse = Sparse{};
var expected: u64 = 0;

const Digest = struct {
    value: u64 = 0xcbf2_9ce4_8422_2325,

    pub fn call(self: *@This(), index: usize) void {
        self.value = (self.value ^ @as(u64, @intCast(index))) *% 0x0000_0100_0000_01b3;
    }
};

pub fn prepare(_: std.mem.Allocator) void {
    flat = .{};
    atomic = .{};
    sparse = .{};
    for (0..sparse_count) |index| {
        const selected = index * 61;
        flat.set(selected);
        atomic.set(selected);
        sparse.set(selected);
    }
    expected = iterate(Sparse, &sparse);
}

pub fn flatSparse(_: std.mem.Allocator) void {
    const observed = blk: {
        const phase = bench.phaseAt("simd.bitset.flat-sparse", @src());
        defer phase.end();
        break :blk iterate(Flat, &flat);
    };
    if (observed != expected) @panic("flat bit set iteration witness failed");
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.bitset.flat-sparse.complete");
}

pub fn atomicSparse(_: std.mem.Allocator) void {
    const observed = blk: {
        const phase = bench.phaseAt("simd.bitset.atomic-sparse", @src());
        defer phase.end();
        break :blk iterate(Atomic, &atomic);
    };
    if (observed != expected) @panic("atomic bit set iteration witness failed");
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.bitset.atomic-sparse.complete");
}

pub fn hierarchicalSparse(_: std.mem.Allocator) void {
    const observed = blk: {
        const phase = bench.phaseAt("simd.bitset.hierarchical-sparse", @src());
        defer phase.end();
        break :blk iterate(Sparse, &sparse);
    };
    if (observed != expected) @panic("hierarchical bit set iteration witness failed");
    std.mem.doNotOptimizeAway(&observed);
    bench.coz.progressNamed("simd.bitset.hierarchical-sparse.complete");
}

fn iterate(comptime Set: type, set: *const Set) u64 {
    var digest = Digest{};
    set.foreach(&digest);
    return digest.value;
}
