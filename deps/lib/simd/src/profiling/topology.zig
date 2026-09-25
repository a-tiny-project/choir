const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const record_count: usize = 256;
const affinity_reads: usize = 4096;
const cache_reads: usize = 262_144;

var records: [record_count]simd.topology.ProcessorRecord = undefined;
var expected_affinity: usize = 0;
var expected_cache_digest: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (&records, 0..) |*record, lp| {
        const package = lp / 64;
        const local = lp % 64;
        const core = local / 2;
        record.* = .{
            .package_id = 0x1000 + package,
            .cluster_id = 0x2000 + package * 4 + core / 8,
            .core_id = 0x3000 + package * 32 + core,
            .node = @intCast(package / 2),
        };
    }
    var current_affinity = simd.LogicalProcessorSet{};
    expected_affinity = if (simd.getThreadAffinity(&current_affinity))
        current_affinity.count()
    else
        0;
    expected_cache_digest = cacheDigest();
}

pub fn assembly(allocator: std.mem.Allocator) void {
    const phase = bench.phaseAt("simd.topology.assembly", @src());
    var topology = simd.ProcessorTopology.initFromRecords(allocator, &records) catch
        @panic("topology assembly benchmark failed");
    phase.end();
    if (topology.lps.len != record_count or topology.packages.len != 4) {
        @panic("topology assembly benchmark witness failed");
    }
    std.mem.doNotOptimizeAway(&topology.packages);
    topology.deinit(allocator);
    bench.coz.progressNamed("simd.topology.assembly.complete");
}

pub fn affinity(_: std.mem.Allocator) void {
    var digest: usize = 0;
    const phase = bench.phaseAt("simd.topology.affinity", @src());
    for (0..affinity_reads) |_| {
        var lps = simd.LogicalProcessorSet{};
        if (simd.getThreadAffinity(&lps)) digest +%= lps.count();
    }
    phase.end();
    if (digest != expected_affinity *% affinity_reads) {
        @panic("topology affinity benchmark witness failed");
    }
    std.mem.doNotOptimizeAway(&digest);
    bench.coz.progressNamed("simd.topology.affinity.complete");
}

pub fn cachedCaches(_: std.mem.Allocator) void {
    var digest: u64 = 0;
    const phase = bench.phaseAt("simd.topology.caches", @src());
    for (0..cache_reads) |_| digest +%= cacheDigest();
    phase.end();
    if (digest != expected_cache_digest *% cache_reads) {
        @panic("topology cache benchmark witness failed");
    }
    std.mem.doNotOptimizeAway(&digest);
    bench.coz.progressNamed("simd.topology.caches.complete");
}

fn cacheDigest() u64 {
    const caches = simd.dataCaches() orelse return 0;
    var digest: u64 = 0;
    for (caches[1..4], 1..) |cache, level| {
        digest +%= @as(u64, cache.size_kib) * level;
        digest +%= cache.sets;
        digest +%= cache.bytes_per_line;
        digest +%= cache.associativity;
        digest +%= cache.cores_sharing;
    }
    return digest;
}
