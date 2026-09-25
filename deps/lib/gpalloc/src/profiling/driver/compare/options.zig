const std = @import("std");

pub const default_iterations: u32 = 4000;
pub const default_seed: u64 = 20260612;

pub const Options = struct {
    base_path: []const u8 = "",
    candidate_path: []const u8 = "",
    iterations: u32 = default_iterations,
    seed: u64 = default_seed,
    fail_on_regression: bool = false,
    json: bool = false,
    show_help: bool = false,
};

pub const Error = error{
    InvalidArgument,
    MissingInput,
};

pub fn parse(args: []const [:0]const u8) Error!Options {
    var parsed: Options = .{};
    var positional_count: usize = 0;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--iterations")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.iterations = parsePositiveU32(args[index]) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--seed")) {
            index += 1;
            if (index >= args.len) return error.InvalidArgument;
            parsed.seed = std.fmt.parseInt(u64, args[index], 10) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--fail-on-regression")) {
            parsed.fail_on_regression = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            parsed.json = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            parsed.show_help = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.InvalidArgument;
        } else {
            switch (positional_count) {
                0 => parsed.base_path = arg,
                1 => parsed.candidate_path = arg,
                else => return error.InvalidArgument,
            }
            positional_count += 1;
        }
    }
    if (parsed.show_help) return parsed;
    if (positional_count != 2) return error.MissingInput;
    return parsed;
}

fn parsePositiveU32(text: []const u8) !u32 {
    const value = try std.fmt.parseInt(u32, text, 10);
    if (value == 0) return error.InvalidValue;
    return value;
}

test "parse compare options" {
    const parsed = try parse(&.{
        "base.ndjson",
        "candidate.ndjson",
        "--iterations",
        "100",
        "--seed",
        "7",
        "--fail-on-regression",
        "--json",
    });
    try std.testing.expectEqualStrings("base.ndjson", parsed.base_path);
    try std.testing.expectEqualStrings("candidate.ndjson", parsed.candidate_path);
    try std.testing.expectEqual(@as(u32, 100), parsed.iterations);
    try std.testing.expectEqual(@as(u64, 7), parsed.seed);
    try std.testing.expect(parsed.fail_on_regression);
    try std.testing.expect(parsed.json);
}

test "parse compare requires two inputs" {
    try std.testing.expectError(error.MissingInput, parse(&.{"only.ndjson"}));
    try std.testing.expectError(error.InvalidArgument, parse(&.{ "a", "b", "c" }));
    try std.testing.expectError(error.InvalidArgument, parse(&.{ "a", "b", "--iterations", "0" }));
    try std.testing.expectError(error.InvalidArgument, parse(&.{ "a", "b", "--unknown" }));
}

test "parse compare help skips input requirement" {
    const parsed = try parse(&.{"--help"});
    try std.testing.expect(parsed.show_help);
}
