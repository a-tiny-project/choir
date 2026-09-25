const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D = simd.FixedTag(i32, 8);
const value_count: usize = 262_157;

var input: [value_count]i32 = undefined;
var output: [value_count]i32 = undefined;
var expected_count: usize = 0;
var expected_checksum: u64 = 0;

const Bytes = simd.ScalableTag(u8);
const equality_bytes: usize = 3_707_696;
pub const equality_std_name = "simd equality std u8 x3707696";
pub const equality_vector_name = "simd equality vector u8 x3707696";
const std_equality_gap = bench.floor.Gap{
    .cause = "bitcast_chunk_load_rebuilt_byte_by_byte",
    .issue = "tiny-" ++ "4405tys2",
};

var equality_left: [equality_bytes]u8 = undefined;
var equality_right: [equality_bytes]u8 = undefined;

const order_key_count: usize = 4096;
const order_key_bytes: usize = 9;
pub const order_keys_std_name = "simd order std u8 keys 9B x8190";
pub const order_keys_vector_name = "simd order vector u8 keys 9B x8190";
pub const order_span_std_name = "simd order std u8 x3707696";
pub const order_span_vector_name = "simd order vector u8 x3707696";

var order_keys: [order_key_count][order_key_bytes]u8 = undefined;
var expected_order_checksum: u64 = 0;
var expected_span_order: std.math.Order = .eq;

const uniform_page_bytes: usize = 4096;
const uniform_page_count: usize = 64;
pub const uniform_std_name = "simd all-equal std u8 zero pages 4096B x64";
pub const uniform_vector_name = "simd all-equal vector u8 zero pages 4096B x64";

var uniform_pages: [uniform_page_count][uniform_page_bytes]u8 = undefined;

const Keep = struct {
    pub fn call(_: @This(), comptime Tag: type, value: Tag.Vector) Tag.Mask {
        const bits: Tag.Vector = value & @as(Tag.Vector, @splat(7));
        return bits < @as(Tag.Vector, @splat(3));
    }
};

const Mix = struct {
    pub fn call(_: @This(), comptime Tag: type, value: Tag.Vector) Tag.Vector {
        return value *% @as(Tag.Vector, @splat(1_664_525)) +%
            @as(Tag.Vector, @splat(1_013_904_223));
    }
};

pub fn prepare(_: std.mem.Allocator) void {
    for (&input, 0..) |*value, index| {
        const bits: u32 = @truncate(index *% 2_654_435_761 +% 1_013_904_223);
        value.* = @bitCast(bits);
    }
    expected_count = pipeline();
    expected_checksum = checksum(output[0..expected_count]);
}

pub fn filterTransform(_: std.mem.Allocator) void {
    var selected: usize = 0;
    {
        const phase = bench.phaseAt("simd.algo.filter-transform", @src());
        defer phase.end();
        selected = pipeline();
    }
    if (selected != expected_count) @panic("SIMD algorithm benchmark count failed");
    if (checksum(output[0..selected]) != expected_checksum) {
        @panic("SIMD algorithm benchmark checksum failed");
    }
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed("simd.algo.filter-transform.complete");
}

pub fn prepareEquality(_: std.mem.Allocator) void {
    var prng = std.Random.DefaultPrng.init(0x507c9c25);
    prng.random().bytes(&equality_left);
    @memcpy(&equality_right, &equality_left);
}

pub fn stdEquality(_: std.mem.Allocator) void {
    var same = false;
    {
        const phase = bench.phaseAt("simd.algo.equality.std", @src());
        defer phase.end();
        same = std.mem.eql(u8, &equality_left, &equality_right);
    }
    if (!same) @panic("SIMD equality benchmark found unequal copies");
    bench.coz.progressNamed("simd.algo.equality.std.complete");
}

pub fn vectorEquality(_: std.mem.Allocator) void {
    var same = false;
    {
        const phase = bench.phaseAt("simd.algo.equality.vector", @src());
        defer phase.end();
        same = simd.equal(Bytes, &equality_left, &equality_right);
    }
    if (!same) @panic("SIMD equality benchmark found unequal copies");
    bench.coz.progressNamed("simd.algo.equality.vector.complete");
}

/// Prepares sorted nine-byte keys, the shape of an encoded integer key on a
/// database page. Each sample orders every adjacent pair and one scattered
/// pair per key, 8190 comparisons.
pub fn prepareOrderKeys(_: std.mem.Allocator) void {
    for (&order_keys, 0..) |*key, index| {
        _ = std.fmt.bufPrint(key, "k{d:0>8}", .{index}) catch unreachable;
    }
    expected_order_checksum = orderChecksum(stdByteOrder);
}

pub fn stdOrderKeys(_: std.mem.Allocator) void {
    var sum: u64 = 0;
    {
        const phase = bench.phaseAt("simd.algo.order.keys.std", @src());
        defer phase.end();
        sum = orderChecksum(stdByteOrder);
    }
    if (sum != expected_order_checksum) @panic("SIMD key order benchmark checksum failed");
    bench.coz.progressNamed("simd.algo.order.keys.std.complete");
}

pub fn vectorOrderKeys(_: std.mem.Allocator) void {
    var sum: u64 = 0;
    {
        const phase = bench.phaseAt("simd.algo.order.keys.vector", @src());
        defer phase.end();
        sum = orderChecksum(vectorByteOrder);
    }
    if (sum != expected_order_checksum) @panic("SIMD key order benchmark checksum failed");
    bench.coz.progressNamed("simd.algo.order.keys.vector.complete");
}

/// Prepares two spans that differ only in their last byte, so ordering them
/// reads both spans whole.
pub fn prepareOrderSpans(allocator: std.mem.Allocator) void {
    prepareEquality(allocator);
    equality_right[equality_bytes - 1] +%= 1;
    expected_span_order = std.mem.order(u8, &equality_left, &equality_right);
    std.debug.assert(expected_span_order != .eq);
}

pub fn stdOrderSpans(_: std.mem.Allocator) void {
    var result: std.math.Order = .eq;
    {
        const phase = bench.phaseAt("simd.algo.order.span.std", @src());
        defer phase.end();
        result = std.mem.order(u8, &equality_left, &equality_right);
    }
    if (result != expected_span_order) @panic("SIMD span order benchmark result failed");
    bench.coz.progressNamed("simd.algo.order.span.std.complete");
}

pub fn vectorOrderSpans(_: std.mem.Allocator) void {
    var result: std.math.Order = .eq;
    {
        const phase = bench.phaseAt("simd.algo.order.span.vector", @src());
        defer phase.end();
        result = simd.order(Bytes, &equality_left, &equality_right);
    }
    if (result != expected_span_order) @panic("SIMD span order benchmark result failed");
    bench.coz.progressNamed("simd.algo.order.span.vector.complete");
}

/// Prepares zero pages, the shape of a reserved database page that was
/// never written. Each sample tests every page whole.
pub fn prepareUniformPages(_: std.mem.Allocator) void {
    for (&uniform_pages) |*page| @memset(page, 0);
}

pub fn stdUniformPages(_: std.mem.Allocator) void {
    var zero: usize = 0;
    {
        const phase = bench.phaseAt("simd.algo.all-equal.std", @src());
        defer phase.end();
        for (&uniform_pages) |*page| {
            if (std.mem.allEqual(u8, page, 0)) zero += 1;
        }
    }
    if (zero != uniform_page_count) @panic("SIMD all-equal benchmark found a written page");
    bench.coz.progressNamed("simd.algo.all-equal.std.complete");
}

pub fn vectorUniformPages(_: std.mem.Allocator) void {
    var zero: usize = 0;
    {
        const phase = bench.phaseAt("simd.algo.all-equal.vector", @src());
        defer phase.end();
        for (&uniform_pages) |*page| {
            if (simd.allEqual(Bytes, page, 0)) zero += 1;
        }
    }
    if (zero != uniform_page_count) @panic("SIMD all-equal benchmark found a written page");
    bench.coz.progressNamed("simd.algo.all-equal.vector.complete");
}

fn orderChecksum(comptime orderBytes: fn ([]const u8, []const u8) std.math.Order) u64 {
    var sum: u64 = 0;
    for (1..order_key_count) |index| {
        const partner = (index * 7919) % order_key_count;
        const adjacent = orderBytes(&order_keys[index - 1], &order_keys[index]);
        const scattered = orderBytes(&order_keys[index], &order_keys[partner]);
        sum = sum *% 9 +% 3 * @as(u64, @backingInt(adjacent)) +% @backingInt(scattered);
    }
    return sum;
}

fn stdByteOrder(left: []const u8, right: []const u8) std.math.Order {
    return std.mem.order(u8, left, right);
}

fn vectorByteOrder(left: []const u8, right: []const u8) std.math.Order {
    return simd.order(Bytes, left, right);
}

pub fn writeEqualityGates(results: []const bench.Result) !void {
    const floor_ns = try (bench.floor.Bytes{
        .count = 2 * equality_bytes,
        .throughput = .{ .measured = .{ .rung = .l3, .pattern = .streaming } },
    }).nanoseconds(null);
    std.debug.assert(floor_ns > 0);
    for (results) |result| {
        var gate = bench.floor.Gate{
            .scope = "simd.algo.equality.vector",
            .floor_ns = floor_ns,
            .measured_ns = result.median_ns,
        };
        if (std.mem.eql(u8, result.name, equality_std_name)) {
            gate.scope = "simd.algo.equality.std";
            if (gate.ratio() > 10) gate.gap = std_equality_gap;
        } else if (!std.mem.eql(u8, result.name, equality_vector_name)) continue;
        bench.pretty.diagnostic.writeStdoutText("{f}", .{gate});
    }
}

fn pipeline() usize {
    const selected = simd.copyIf(D, &input, &output, Keep{});
    simd.transform(D, output[0..selected], Mix{});
    return selected;
}

fn checksum(values: []const i32) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| {
        hash = (hash ^ @as(u32, @bitCast(value))) *% 0x0000_0100_0000_01b3;
    }
    return hash;
}
