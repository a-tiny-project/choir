const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");
const profile = @import("profile.zig");
const touch = @import("touch.zig");

const Profile = profile.Profile;
const touchEdges = touch.edges;
const touchSparse = touch.sparse;

pub const Memtable = struct {
    arenas: [parameters.rocksdb_trace_arena_block_count]?[]u8 = @as([parameters.rocksdb_trace_arena_block_count]?[]u8, @splat(null)),
    metadata: [parameters.rocksdb_trace_metadata_count]?[]u8 = @as([parameters.rocksdb_trace_metadata_count]?[]u8, @splat(null)),
};

pub fn create(
    comptime active_profile: Profile,
    allocator: std.mem.Allocator,
    memtable: *Memtable,
    seed: usize,
) void {
    const create_phase = bench.phaseAt(profile.phase(active_profile, "memtable_create"), @src());
    defer create_phase.end();

    for (&memtable.metadata, 0..) |*record, index| {
        const bytes = allocator.alloc(u8, profile.size(active_profile, metadataSize(index, seed))) catch @panic("allocation failed");
        touchEdges(bytes, index + seed * 17);
        record.* = bytes;
    }
    coz.progressNamed(profile.phase(active_profile, "memtable_create"));
}

pub fn fill(
    comptime active_profile: Profile,
    allocator: std.mem.Allocator,
    memtable: *Memtable,
    seed: usize,
) void {
    const fill_phase = bench.phaseAt(profile.phase(active_profile, "memtable_fill"), @src());
    defer fill_phase.end();

    for (&memtable.arenas, 0..) |*record, index| {
        if (index % 4 == 0) writeBatchChurn(active_profile, allocator, seed * 101 + index);
        const bytes = allocator.alloc(u8, profile.size(active_profile, parameters.rocksdb_trace_arena_block_bytes)) catch @panic("allocation failed");
        touchSparse(bytes, seed * 131 + index);
        record.* = bytes;
    }
    coz.progressNamed(profile.phase(active_profile, "memtable_fill"));
}

pub fn flushAndDrop(
    comptime active_profile: Profile,
    allocator: std.mem.Allocator,
    memtable: *Memtable,
    seed: usize,
) void {
    var flush_blocks: [parameters.rocksdb_trace_flush_block_count]?[]u8 =
        @as([parameters.rocksdb_trace_flush_block_count]?[]u8, @splat(null));

    {
        const flush_phase = bench.phaseAt(profile.phase(active_profile, "flush"), @src());
        defer flush_phase.end();

        for (&flush_blocks, 0..) |*block, index| {
            const bytes = allocator.alloc(u8, profile.size(active_profile, flushBlockSize(index, seed))) catch @panic("allocation failed");
            touchSparse(bytes, seed * 257 + index);
            block.* = bytes;
        }

        var manifests: [6]?[]u8 = @as([6]?[]u8, @splat(null));
        for (&manifests, 0..) |*manifest, index| {
            const bytes = allocator.alloc(u8, profile.size(active_profile, manifestEditSize(index, seed))) catch @panic("allocation failed");
            touchEdges(bytes, seed + index);
            manifest.* = bytes;
        }
        for (&manifests) |*manifest| {
            const bytes = manifest.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            manifest.* = null;
        }
        coz.progressNamed(profile.phase(active_profile, "flush"));
    }

    {
        const drop_phase = bench.phaseAt(profile.phase(active_profile, "drop_memtable"), @src());
        defer drop_phase.end();

        var block_index = flush_blocks.len;
        while (block_index > 0) {
            block_index -= 1;
            const bytes = flush_blocks[block_index] orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            flush_blocks[block_index] = null;
        }

        for (&memtable.arenas) |*record| {
            const bytes = record.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            record.* = null;
        }
        for (&memtable.metadata) |*record| {
            const bytes = record.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            record.* = null;
        }
        coz.progressNamed(profile.phase(active_profile, "drop_memtable"));
    }
}

pub fn active(memtable: *const Memtable) bool {
    for (&memtable.arenas) |*record| {
        if (record.* != null) return true;
    }
    for (&memtable.metadata) |*record| {
        if (record.* != null) return true;
    }
    return false;
}

fn writeBatchChurn(comptime active_profile: Profile, allocator: std.mem.Allocator, seed: usize) void {
    const batch_phase = bench.phaseAt(profile.phase(active_profile, "write_batch"), @src());
    defer batch_phase.end();

    var batches: [parameters.rocksdb_trace_batch_count]?[]u8 = @as([parameters.rocksdb_trace_batch_count]?[]u8, @splat(null));
    for (&batches, 0..) |*batch, index| {
        const logical_size = batchSize(index, seed);
        var bytes = allocator.alloc(u8, profile.size(active_profile, logical_size)) catch @panic("allocation failed");
        if ((index + seed) % 3 == 0) {
            bytes = allocator.realloc(bytes, profile.size(active_profile, logical_size + batchGrowth(index, seed))) catch @panic("realloc failed");
        }
        touchEdges(bytes, index + seed);
        batch.* = bytes;
    }

    var index = batches.len;
    while (index > 0) {
        index -= 1;
        const bytes = batches[index] orelse continue;
        std.mem.doNotOptimizeAway(bytes.ptr);
        allocator.free(bytes);
        batches[index] = null;
    }
    coz.progressNamed(profile.phase(active_profile, "write_batch"));
}

fn metadataSize(index: usize, seed: usize) usize {
    const sizes = [_]usize{ 48, 80, 128, 192, 320, 512, 768, 1152 };
    return sizes[(index * 5 + seed * 3) % sizes.len];
}

fn batchSize(index: usize, seed: usize) usize {
    const sizes = [_]usize{ 128, 160, 192, 256, 320, 384, 512, 640 };
    return sizes[(index * 7 + seed) % sizes.len];
}

fn batchGrowth(index: usize, seed: usize) usize {
    const sizes = [_]usize{ 64, 96, 128, 192, 256 };
    return sizes[(index + seed * 5) % sizes.len];
}

fn flushBlockSize(index: usize, seed: usize) usize {
    const sizes = [_]usize{ 4096, 4096, 8192, 8192, 12 * 1024, 16 * 1024, 24 * 1024, 32 * 1024 };
    return sizes[(index * 3 + seed) % sizes.len];
}

fn manifestEditSize(index: usize, seed: usize) usize {
    const sizes = [_]usize{ 256, 384, 512, 768, 1024, 1536 };
    return sizes[(index + seed) % sizes.len];
}
