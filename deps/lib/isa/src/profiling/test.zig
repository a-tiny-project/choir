const std = @import("std");
const bench = @import("bench");
const isa = @import("isa");

const compiler_stream = [_]u8{
    0xb4, 0x7f,
    0x40, 0xb4,
    0x7f, 0x48,
    0x8b, 0x44,
    0x8d, 0xf8,
    0x48, 0x8b,
    0x05, 0x34,
    0x12, 0x00,
    0x00, 0x48,
    0x83, 0xc0,
    0xff, 0x48,
    0x0f, 0xb7,
    0xc1, 0x48,
    0x0f, 0xb6,
    0x01, 0x66,
    0x0f, 0xb7,
    0xc1, 0x88,
    0xe0, 0x8a,
    0xe0, 0x66,
    0x90, 0x40,
    0x0f, 0x90,
    0xc0, 0xf3,
    0xab, 0x66,
    0x66, 0x66,
    0x2e, 0x0f,
    0x1f, 0x84,
    0x00, 0x00,
    0x00, 0x00,
    0x00,
};

const k0_shaped_stream = [_]u8{
    0x0f, 0xc8,
    0x0f, 0x10,
    0xc1, 0x66,
    0x0f, 0x70,
    0xc1, 0x01,
    0x48, 0xf7,
    0xe1, 0x48,
    0xf7, 0xf1,
    0xff, 0x24,
    0xd5, 0x08,
    0xe1, 0x00,
    0x02, 0xee,
    0xc1, 0xc0,
    0x01, 0x48,
    0x89, 0xc4,
    0xf3, 0xa4,
    0x90,
};

const encoded_stream = compiler_stream ++ k0_shaped_stream;
const stream_instruction_count: u32 = 25;
const stream_repeats: u16 = 256;
const checksum_offset: u64 = 0xcbf2_9ce4_8422_2325;
const checksum_prime: u64 = 0x0000_0100_0000_01b3;
const expected_checksum: u64 = 0xe40b_c3c6_5de5_aa3e;

const DecodeResult = struct {
    bytes: u32,
    instructions: u32,
    checksum: u64,
};

const DecodeError = isa.x86.DecodeError || error{InvalidInstructionLength};

var runtime_stream: [encoded_stream.len]u8 = undefined;

fn decodeStream(stream: []const u8) DecodeError!DecodeResult {
    std.debug.assert(stream.len > 0);
    std.debug.assert(stream.len <= std.math.maxInt(u32));
    var offset: usize = 0;
    var instructions: u32 = 0;
    var checksum = checksum_offset;
    while (offset < stream.len) {
        std.debug.assert(instructions < stream.len);
        const instruction = try isa.x86.decode(stream[offset..]);
        const bytes: usize = instruction.bytes;
        if (bytes == 0 or bytes > stream.len - offset) {
            return error.InvalidInstructionLength;
        }
        std.mem.doNotOptimizeAway(instruction);
        checksum = (checksum ^ instruction.form.key()) *% checksum_prime;
        checksum = (checksum ^ @as(u64, @backingInt(instruction.operation))) *%
            checksum_prime;
        checksum = (checksum ^ instruction.bytes) *% checksum_prime;
        offset += bytes;
        instructions += 1;
    }
    std.debug.assert(offset == stream.len);
    return .{
        .bytes = @intCast(offset),
        .instructions = instructions,
        .checksum = checksum,
    };
}

fn decodeCompilerK0Shaped(_: std.mem.Allocator) void {
    const phase = bench.phaseAt("isa.x86.decode.compiler-k0-shaped", @src());
    var aggregate: u64 = 0;
    var repeat: u16 = 0;
    while (repeat < stream_repeats) : (repeat += 1) {
        const result = decodeStream(&runtime_stream) catch
            @panic("ISA decode benchmark corpus failed");
        if (result.bytes != encoded_stream.len or
            result.instructions != stream_instruction_count or
            result.checksum != expected_checksum)
        {
            @panic("ISA decode benchmark result changed");
        }
        aggregate +%= result.checksum;
    }
    phase.end();
    if (aggregate != expected_checksum *% stream_repeats) {
        @panic("ISA decode benchmark aggregate changed");
    }
    std.mem.doNotOptimizeAway(aggregate);
    bench.coz.progressNamed("isa.x86.decode.compiler-k0-shaped.complete");
}

test "bench: ISA compiler and K0-shaped decode stream" {
    @memcpy(&runtime_stream, &encoded_stream);
    const decoded = try decodeStream(&runtime_stream);
    try std.testing.expectEqual(@as(u32, encoded_stream.len), decoded.bytes);
    try std.testing.expectEqual(stream_instruction_count, decoded.instructions);
    try std.testing.expectEqual(expected_checksum, decoded.checksum);

    var suite = bench.Suite.init(std.testing.allocator, .{
        .min_time_ns = 20_000_000,
        .warmup_iterations = 2,
    });
    defer suite.deinit();
    try suite.add(
        "isa.x86.decode.compiler-k0-shaped 256x25",
        decodeCompilerK0Shaped,
        .{},
    );
    try suite.run();
}
