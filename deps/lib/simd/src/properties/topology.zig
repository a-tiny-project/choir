const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const max_generated_lps: usize = 96;

pub const RemapProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, allocator: Allocator) !void {
        const count: usize = @intCast(try data.drawInteger(1, max_generated_lps, 0));
        const lps_per_package: usize = @intCast(try data.drawInteger(1, 24, 0));
        const smt_width: usize = @intCast(try data.drawInteger(1, 4, 0));
        const cores_per_cluster: usize = @intCast(try data.drawInteger(1, 8, 0));
        var records: [max_generated_lps]simd.topology.ProcessorRecord = undefined;
        for (records[0..count], 0..) |*record, lp| {
            const package = lp / lps_per_package;
            const package_lp = lp % lps_per_package;
            const core = package_lp / smt_width;
            record.* = .{
                .package_id = 0x1000 + package * 17,
                .cluster_id = 0x9000 + package * 29 + core / cores_per_cluster,
                .core_id = 0x5000 + package * 31 + core,
                .node = @intCast(package % 4),
            };
        }
        var topology = try simd.ProcessorTopology.initFromRecords(
            allocator,
            records[0..count],
        );
        defer topology.deinit(allocator);
        try std.testing.expectEqual(count, topology.lps.len);

        var cluster_union = simd.LogicalProcessorSet{};
        var core_union = simd.LogicalProcessorSet{};
        var cluster_total: usize = 0;
        var core_total: usize = 0;
        for (topology.packages) |package| {
            try std.testing.expect(package.clusters.len >= 1);
            try std.testing.expect(package.clusters.len <= package.cores.len);
            for (package.clusters) |cluster| {
                cluster_total += cluster.lps.count();
                addSet(&cluster_union, &cluster.lps);
            }
            for (package.cores) |core| {
                core_total += core.lps.count();
                addSet(&core_union, &core.lps);
            }
        }
        try std.testing.expectEqual(count, cluster_total);
        try std.testing.expectEqual(count, core_total);
        try std.testing.expectEqual(count, cluster_union.count());
        try std.testing.expectEqual(count, core_union.count());
        for (topology.lps, 0..) |lp, index| {
            try std.testing.expect(lp.package < topology.packages.len);
            const package = topology.packages[lp.package];
            try std.testing.expect(lp.cluster < package.clusters.len);
            try std.testing.expect(lp.core < package.cores.len);
            var prior_siblings: usize = 0;
            for (topology.lps[0..index]) |prior| {
                if (prior.package == lp.package and prior.core == lp.core) {
                    prior_siblings += 1;
                }
            }
            try std.testing.expectEqual(prior_siblings, lp.smt);
        }
    }
};

pub const CpuListProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const low: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const high: u32 = @intCast(try data.drawInteger(0, std.math.maxInt(u32), 0));
        const expected = @as(u64, high) << 32 | low;
        var buffer: [512]u8 = undefined;
        const text = encodeCpuList(expected, &buffer);
        var actual = simd.LogicalProcessorSet{};
        try std.testing.expect(simd.topology.testing.parseCpuList(
            text,
            63,
            .{},
            &actual,
        ));
        try std.testing.expectEqual(expected, actual.get64());
        try std.testing.expectEqual(@as(usize, @popCount(expected)), actual.count());
    }
};

pub const CacheProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const line_log2: u4 = @intCast(try data.drawInteger(5, 10, 0));
        const line = @as(u16, 1) << line_log2;
        const associativity: u16 = @intCast(try data.drawInteger(2, 128, 0));
        const set_factor: u32 = @intCast(try data.drawInteger(1, 2048, 0));
        const sets = set_factor * 32;
        const size_kib: u32 = @intCast(
            @as(u64, line) * associativity * sets / 1024,
        );
        var cache = simd.ProcessorCache{
            .size_kib = size_kib,
            .bytes_per_line = line,
            .associativity = associativity,
            .cores_sharing = 1,
        };
        try std.testing.expect(simd.topology.testing.computeCacheSets(&cache));
        try std.testing.expectEqual(sets, cache.sets);
        cache.sets = sets - 1;
        try std.testing.expect(!simd.topology.testing.computeCacheSets(&cache));
        cache.sets = sets + 1;
        try std.testing.expect(simd.topology.testing.computeCacheSets(&cache));
        cache.sets += 1;
        try std.testing.expect(!simd.topology.testing.computeCacheSets(&cache));
    }
};

const SetAdder = struct {
    target: *simd.LogicalProcessorSet,

    pub fn call(self: *@This(), lp: usize) void {
        self.target.set(lp);
    }
};

fn addSet(target: *simd.LogicalProcessorSet, source: *const simd.LogicalProcessorSet) void {
    var add = SetAdder{ .target = target };
    source.foreach(&add);
}

fn encodeCpuList(bits: u64, buffer: *[512]u8) []const u8 {
    if (bits == 0) {
        buffer[0] = '\n';
        return buffer[0..1];
    }
    var used: usize = 0;
    var bit: usize = 0;
    var first_term = true;
    while (bit < 64) {
        if (bits & (@as(u64, 1) << @intCast(bit)) == 0) {
            bit += 1;
            continue;
        }
        const first = bit;
        var last = bit;
        while (last + 1 < 64 and
            bits & (@as(u64, 1) << @intCast(last + 1)) != 0) last += 1;
        if (!first_term) {
            buffer[used] = ',';
            used += 1;
        }
        first_term = false;
        used += writeUnsigned(buffer[used..], first);
        if (last != first) {
            buffer[used] = '-';
            used += 1;
            used += writeUnsigned(buffer[used..], last);
        }
        bit = last + 1;
    }
    buffer[used] = '\n';
    return buffer[0 .. used + 1];
}

fn writeUnsigned(buffer: []u8, value: usize) usize {
    const written = std.fmt.bufPrint(buffer, "{d}", .{value}) catch unreachable;
    return written.len;
}

test "property: topology remapping preserves dense coverage and SMT order" {
    try hypothesis.checkNamed(RemapProperty, "simd-topology-remap", run.settings());
}

test "property: topology CPU-list parsing matches an independent bit model" {
    try hypothesis.checkNamed(CpuListProperty, "simd-topology-cpu-list", run.settings());
}

test "property: topology cache sets follow per-core geometry" {
    try hypothesis.checkNamed(CacheProperty, "simd-topology-cache-sets", run.settings());
}
