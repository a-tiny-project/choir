const std = @import("std");

pub const Metric = enum {
    wall,
    relative_time,
    rtime,
    memory_ops,

    pub fn label(self: Metric) []const u8 {
        return @tagName(self);
    }

    pub fn parsesStdout(self: Metric) bool {
        return self != .wall;
    }
};

pub const ParseError = error{MetricMissing};

pub fn deriveNs(metric: Metric, stdout_text: []const u8, wall_ns: u64) ParseError!u64 {
    return switch (metric) {
        .wall => wall_ns,
        .relative_time => secondsToNs(try floatAfter(stdout_text, " time: ")),
        .rtime => secondsToNs(try floatAfter(stdout_text, "rtime: ")),
        .memory_ops => opsToNs(try integerBefore(stdout_text, " memory ops")),
    };
}

const reference_ops: u64 = 2_000_000;

fn opsToNs(ops: u64) ParseError!u64 {
    if (ops == 0) return error.MetricMissing;
    return (reference_ops * std.time.ns_per_s) / ops;
}

fn secondsToNs(seconds: f64) u64 {
    return @intFromFloat(seconds * std.time.ns_per_s);
}

fn floatAfter(text: []const u8, needle: []const u8) ParseError!f64 {
    const start = std.mem.lastIndexOf(u8, text, needle) orelse
        return error.MetricMissing;
    var index = start + needle.len;
    const digits_start = index;
    var seen_dot = false;
    while (index < text.len) : (index += 1) {
        const byte = text[index];
        if (byte == '.' and !seen_dot) {
            seen_dot = true;
            continue;
        }
        if (!std.ascii.isDigit(byte)) break;
    }
    if (index == digits_start) return error.MetricMissing;
    return std.fmt.parseFloat(f64, text[digits_start..index]) catch
        error.MetricMissing;
}

fn integerBefore(text: []const u8, needle: []const u8) ParseError!u64 {
    const needle_start = std.mem.lastIndexOf(u8, text, needle) orelse
        return error.MetricMissing;
    var start = needle_start;
    while (start > 0 and std.ascii.isDigit(text[start - 1])) start -= 1;
    if (start == needle_start) return error.MetricMissing;
    return std.fmt.parseUnsigned(u64, text[start..needle_start], 10) catch
        error.MetricMissing;
}

test "relative time parses the larson summary line" {
    const line = "Throughput =   785845 operations per second, relative time: 5.024s.\n";
    try std.testing.expectEqual(
        @as(u64, 5_024_000_000),
        try deriveNs(.relative_time, line, 99),
    );
}

test "rtime parses the xmalloc summary line" {
    const line = "rtime: 0.081, free/sec: 1234.567 M\n";
    try std.testing.expectEqual(@as(u64, 81_000_000), try deriveNs(.rtime, line, 99));
}

test "memory ops parses the rptest summary line and inverts to time" {
    const line = "random     16 threads random size [16,8000] 2 loops... 12345678 memory ops/CPU second (peak 123MiB)\n";
    const expected = (reference_ops * std.time.ns_per_s) / 12_345_678;
    try std.testing.expectEqual(expected, try deriveNs(.memory_ops, line, 99));
}

test "wall passes the measured wall time through" {
    try std.testing.expectEqual(@as(u64, 4242), try deriveNs(.wall, "anything", 4242));
}

test "missing markers and zero ops report missing metrics" {
    try std.testing.expectError(error.MetricMissing, deriveNs(.relative_time, "no marker", 0));
    try std.testing.expectError(error.MetricMissing, deriveNs(.rtime, "rtime: junk", 0));
    try std.testing.expectError(error.MetricMissing, deriveNs(.memory_ops, " memory ops", 0));
    try std.testing.expectError(error.MetricMissing, deriveNs(.memory_ops, "0 memory ops", 0));
}

test "last occurrence wins when threads echo intermediate lines" {
    const lines =
        "Thread  2 frees 100 blocks in 0.50 seconds. 12.00 free/sec.\n" ++
        "rtime: 1.500, free/sec: 66.667 M\n";
    try std.testing.expectEqual(@as(u64, 1_500_000_000), try deriveNs(.rtime, lines, 0));
}
