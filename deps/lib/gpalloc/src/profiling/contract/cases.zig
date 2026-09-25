const std = @import("std");
const sys = @import("sys");

const cross_thread_count = 64;

const ThreadWork = struct {
    allocator: std.mem.Allocator,
    records: *[cross_thread_count][]u8,
};

pub fn run(allocator: std.mem.Allocator, case_id: []const u8) !void {
    if (std.mem.eql(u8, case_id, "native-alloc-roundtrip")) return allocRoundtrip(allocator);
    if (std.mem.eql(u8, case_id, "native-aligned-alloc")) return alignedAlloc(allocator);
    if (std.mem.eql(u8, case_id, "native-realloc-grow-preserve"))
        return reallocGrowPreserve(allocator);
    if (std.mem.eql(u8, case_id, "native-realloc-shrink-preserve"))
        return reallocShrinkPreserve(allocator);
    if (std.mem.eql(u8, case_id, "native-resize-shrink-preserve"))
        return resizeShrinkPreserve(allocator);
    if (std.mem.eql(u8, case_id, "native-cross-thread-free")) return crossThreadFree(allocator);
    return error.UnknownCase;
}

fn allocRoundtrip(allocator: std.mem.Allocator) !void {
    const sizes = [_]usize{ 1, 16, 64, 4096, 65536 };
    for (sizes, 0..) |len, index| {
        const bytes = try allocator.alloc(u8, len);
        defer allocator.free(bytes);
        fill(bytes, 17 + index);
        try check(bytes, 17 + index);
    }
}

fn alignedAlloc(allocator: std.mem.Allocator) !void {
    const alignments = [_]usize{ 16, 64, 256 };
    inline for (alignments, 0..) |alignment, index| {
        const bytes = try allocator.alignedAlloc(u8, .fromByteUnits(alignment), 257 + index);
        defer allocator.free(bytes);
        if (@intFromPtr(bytes.ptr) % alignment != 0) return error.ContractFailed;
        fill(bytes, 47 + index);
        try check(bytes, 47 + index);
    }
}

fn reallocGrowPreserve(allocator: std.mem.Allocator) !void {
    var bytes = try allocator.alloc(u8, 64);
    fill(bytes, 73);
    bytes = try allocator.realloc(bytes, 4096);
    defer allocator.free(bytes);
    try check(bytes[0..64], 73);
    fill(bytes[64..], 91);
    try check(bytes[64..], 91);
}

fn reallocShrinkPreserve(allocator: std.mem.Allocator) !void {
    var bytes = try allocator.alloc(u8, 4096);
    fill(bytes, 113);
    bytes = try allocator.realloc(bytes, 128);
    defer allocator.free(bytes);
    try check(bytes, 113);
}

fn resizeShrinkPreserve(allocator: std.mem.Allocator) !void {
    var bytes = try allocator.alloc(u8, 256);
    defer allocator.free(bytes);
    fill(bytes, 131);
    if (!allocator.resize(bytes, 64)) return error.ContractFailed;
    bytes = bytes[0..64];
    try check(bytes, 131);
}

fn crossThreadFree(allocator: std.mem.Allocator) !void {
    var records: [cross_thread_count][]u8 = undefined;
    var allocated: usize = 0;
    errdefer for (records[0..allocated]) |record| allocator.free(record);
    for (&records, 0..) |*record, index| {
        record.* = try allocator.alloc(u8, 24 + (index % 11) * 13);
        allocated += 1;
        fill(record.*, 191 + index);
        try check(record.*, 191 + index);
    }
    var work: ThreadWork = .{ .allocator = allocator, .records = &records };
    const thread = try sys.thread.spawn(freeThreadWork, .{&work});
    thread.join();
}

fn freeThreadWork(work: *ThreadWork) void {
    for (work.records.*) |record| work.allocator.free(record);
}

fn fill(bytes: []u8, seed: usize) void {
    for (bytes, 0..) |*byte, index| byte.* = pattern(seed, index);
}

fn check(bytes: []const u8, seed: usize) !void {
    for (bytes, 0..) |byte, index| {
        if (byte != pattern(seed, index)) return error.ContractFailed;
    }
}

fn pattern(seed: usize, index: usize) u8 {
    return @truncate((seed + index * 33 + (index >> 3)) & 0xff);
}
