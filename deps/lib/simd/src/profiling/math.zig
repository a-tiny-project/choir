const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const F = simd.FixedTag(f64, 4);
const I = simd.FixedTag(i32, 8);
const block_count: usize = 65_536;
const float_count: usize = block_count * F.lane_count;
const integer_count: usize = block_count * I.lane_count;
const scalar_count: usize = 262_157;

var float_input: [float_count]f64 = undefined;
var float_output: [float_count]f64 = undefined;
var integer_input: [integer_count]i32 = undefined;
var integer_output: [integer_count]i32 = undefined;
var scalar_input: [scalar_count]u64 = undefined;
var scalar_output: [scalar_count]u64 = undefined;
var expected_float_checksum: u64 = 0;
var expected_integer_checksum: u64 = 0;
var expected_scalar_checksum: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    for (0..float_count) |index| {
        float_input[index] = 0.125 + @as(f64, @floatFromInt(index % 32_641)) / 4096.0;
        float_output[index] = 0;
    }
    for (0..integer_count) |index| {
        const bits: u32 = @truncate(index *% 2_654_435_761 +% 1_013_904_223);
        integer_input[index] = @bitCast(bits);
        integer_output[index] = 0;
    }
    for (0..scalar_count) |index| {
        scalar_input[index] = index *% 0x9e37_79b9_7f4a_7c15 +% 0xd1b5_4a32_d192_ed03;
        scalar_output[index] = 0;
    }

    expected_float_checksum = checksumSeed();
    var float_index: usize = 0;
    while (float_index < float_count) : (float_index += F.lane_count) {
        const result = mathBlock(simd.load(F, float_input[float_index..]));
        const lanes: [F.lane_count]f64 = result;
        for (lanes) |lane_value| expected_float_checksum = checksumFloat(expected_float_checksum, lane_value);
    }

    expected_integer_checksum = checksumSeed();
    const params = simd.computeDivisorParams(i32, -37);
    var integer_index: usize = 0;
    while (integer_index < integer_count) : (integer_index += I.lane_count) {
        const result = simd.intDivFloor(I, simd.load(I, integer_input[integer_index..]), params);
        const lanes: [I.lane_count]i32 = result;
        for (lanes) |lane_value| expected_integer_checksum = checksumInteger(expected_integer_checksum, lane_value);
    }

    expected_scalar_checksum = checksumSeed();
    const scalar_divisor = simd.Divisor64.init(1_000_000_007);
    for (scalar_input) |value| {
        expected_scalar_checksum = checksumStep(
            expected_scalar_checksum,
            scalar_divisor.divide(value) ^ scalar_divisor.remainder(value),
        );
    }
}

pub fn transcendentalChain(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.math.transcendental", @src());
        defer phase.end();
        var index: usize = 0;
        while (index < float_count) : (index += F.lane_count) {
            const result = mathBlock(simd.load(F, float_input[index..]));
            simd.store(F, result, float_output[index..]);
        }
    }
    witnessFloat("simd.math.transcendental.complete");
}

pub fn floorIntegerDivision(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.intdiv.floor", @src());
        defer phase.end();
        const params = simd.computeDivisorParams(i32, -37);
        var index: usize = 0;
        while (index < integer_count) : (index += I.lane_count) {
            const result = simd.intDivFloor(I, simd.load(I, integer_input[index..]), params);
            simd.store(I, result, integer_output[index..]);
        }
    }
    witnessInteger("simd.intdiv.floor.complete");
}

pub fn scalarUnsignedDivision(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.intdiv.scalar", @src());
        defer phase.end();
        const divisor = simd.Divisor64.init(1_000_000_007);
        for (scalar_input, &scalar_output) |value, *output| {
            output.* = divisor.divide(value) ^ divisor.remainder(value);
        }
    }
    witnessScalar("simd.intdiv.scalar.complete");
}

fn mathBlock(input: F.Vector) F.Vector {
    const angle = input - @as(F.Vector, @splat(4));
    const logarithm = simd.fastLog(F, input);
    const exponential = simd.fastExp(F, -input * @as(F.Vector, @splat(0.125)));
    return simd.sin(F, angle) + simd.cos(F, angle) + logarithm + exponential + simd.erf(F, angle);
}

fn witnessFloat(comptime progress_name: []const u8) void {
    var checksum = checksumSeed();
    for (float_output) |value| checksum = checksumFloat(checksum, value);
    if (checksum != expected_float_checksum) @panic("SIMD math benchmark witness failed");
    std.mem.doNotOptimizeAway(&float_output);
    bench.coz.progressNamed(progress_name);
}

fn witnessInteger(comptime progress_name: []const u8) void {
    var checksum = checksumSeed();
    for (integer_output) |value| checksum = checksumInteger(checksum, value);
    if (checksum != expected_integer_checksum) @panic("SIMD integer division benchmark witness failed");
    std.mem.doNotOptimizeAway(&integer_output);
    bench.coz.progressNamed(progress_name);
}

fn witnessScalar(comptime progress_name: []const u8) void {
    var checksum = checksumSeed();
    for (scalar_output) |value| checksum = checksumStep(checksum, value);
    if (checksum != expected_scalar_checksum) @panic("SIMD scalar division benchmark witness failed");
    std.mem.doNotOptimizeAway(&scalar_output);
    bench.coz.progressNamed(progress_name);
}

fn checksumSeed() u64 {
    return 0xcbf2_9ce4_8422_2325;
}

fn checksumFloat(checksum: u64, value: f64) u64 {
    return checksumStep(checksum, @bitCast(value));
}

fn checksumInteger(checksum: u64, value: i32) u64 {
    return checksumStep(checksum, @as(u32, @bitCast(value)));
}

fn checksumStep(checksum: u64, value: u64) u64 {
    return (checksum ^ value) *% 0x0000_0100_0000_01b3;
}
