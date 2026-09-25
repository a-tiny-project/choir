const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const D = simd.FixedTag(u64, 4);
const Generator = simd.VectorXoshiro(D);
const value_count: usize = 262_157;
const aes_count: usize = 65_539;
const seed: u64 = 0x5349_4d44_524e_4721;

var output: [value_count]u64 = undefined;
var aes_output: [aes_count]u64 = undefined;
var expected_scalar: u64 = 0;
var expected_vector: u64 = 0;
var expected_aes: u64 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    scalarPipeline();
    expected_scalar = checksum(&output);
    vectorPipeline();
    expected_vector = checksum(&output);
    aesPipeline();
    expected_aes = checksum(&aes_output);
}

pub fn scalar(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.random.xoshiro.scalar", @src());
        defer phase.end();
        scalarPipeline();
    }
    if (checksum(&output) != expected_scalar) @panic("scalar xoshiro benchmark witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed("simd.random.xoshiro.scalar.complete");
}

pub fn vector(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.random.xoshiro.u64x4", @src());
        defer phase.end();
        vectorPipeline();
    }
    if (checksum(&output) != expected_vector) @panic("vector xoshiro benchmark witness failed");
    std.mem.doNotOptimizeAway(&output);
    bench.coz.progressNamed("simd.random.xoshiro.u64x4.complete");
}

pub fn aesCounter(_: std.mem.Allocator) void {
    {
        const phase = bench.phaseAt("simd.random.aes-ctr", @src());
        defer phase.end();
        aesPipeline();
    }
    if (checksum(&aes_output) != expected_aes) @panic("AES counter benchmark witness failed");
    std.mem.doNotOptimizeAway(&aes_output);
    bench.coz.progressNamed("simd.random.aes-ctr.complete");
}

fn scalarPipeline() void {
    var generator = simd.Xoshiro.init(seed);
    for (&output) |*value| value.* = generator.next();
}

fn vectorPipeline() void {
    var generator = Generator.init(seed);
    generator.fill(&output);
}

fn aesPipeline() void {
    const engine = simd.AesCtrEngine.initDeterministic();
    var stream = simd.RngStream.init(&engine, seed);
    for (&aes_output) |*value| value.* = stream.next();
}

fn checksum(values: []const u64) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| hash = (hash ^ value) *% 0x0000_0100_0000_01b3;
    return hash;
}
