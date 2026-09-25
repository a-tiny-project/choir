const std = @import("std");

pub const filter_flag = "--test-filter";
pub const exclude_flag = "--test-exclude";
pub const priority_flag = "--test-priority";
pub const selection_receipt_flag = "--test-selection-receipt";
pub const supervised_receipts_flag = "--test-supervised-receipts";
pub const seed_flag = "--seed";

const max_arguments = 256;
const value_flags = [_][]const u8{
    filter_flag,
    exclude_flag,
    priority_flag,
    selection_receipt_flag,
    supervised_receipts_flag,
};

pub const Failure = union(enum) {
    missing_executable,
    missing_value: []const u8,
    unsupported: []const u8,
    too_many_arguments,
};

pub const Action = union(enum) {
    run,
    help,
    failure: Failure,
};

pub fn parse(iterator: anytype) Action {
    if (iterator.next() == null) return .{ .failure = .missing_executable };
    for (0..max_arguments) |_| {
        const argument = iterator.next() orelse return .run;
        if (isHelp(argument)) return .help;
        for (value_flags) |flag| {
            if (std.mem.eql(u8, argument, flag)) {
                if (iterator.next() == null) {
                    return .{ .failure = .{ .missing_value = flag } };
                }
                break;
            }
            if (joinedValue(argument, flag)) break;
        } else {
            if (joinedValue(argument, seed_flag)) continue;
            return .{ .failure = .{ .unsupported = argument } };
        }
    }
    if (iterator.next() == null) return .run;
    return .{ .failure = .too_many_arguments };
}

fn isHelp(argument: []const u8) bool {
    return std.mem.eql(u8, argument, "-h") or
        std.mem.eql(u8, argument, "--help");
}

fn joinedValue(argument: []const u8, flag: []const u8) bool {
    return argument.len > flag.len and
        argument[flag.len] == '=' and
        std.mem.eql(u8, argument[0..flag.len], flag);
}

const SliceIterator = struct {
    values: []const []const u8,
    index: usize = 0,

    fn next(self: *SliceIterator) ?[]const u8 {
        if (self.index >= self.values.len) return null;
        defer self.index += 1;
        return self.values[self.index];
    }
};

fn parseSlice(values: []const []const u8) Action {
    var iterator = SliceIterator{ .values = values };
    return parse(&iterator);
}

test "help is terminal before test execution" {
    try std.testing.expectEqual(.help, parseSlice(&.{ "test", "--help" }));
    try std.testing.expectEqual(.help, parseSlice(&.{ "test", "-h" }));
}

test "runner and Zig value arguments remain supported" {
    const action = parseSlice(&.{
        "test",
        "--test-filter",
        "unit",
        "--test-filter=integration",
        "--test-exclude",
        "slow",
        "--test-exclude=network",
        "--test-priority",
        "startup",
        "--test-priority=shutdown",
        "--test-selection-receipt",
        "receipt.txt",
        "--test-selection-receipt=other.txt",
        "--test-supervised-receipts",
        "receipts",
        "--test-supervised-receipts=other-receipts",
        "--seed=0x5eed5eed",
    });
    try std.testing.expectEqual(.run, action);
}

test "unsupported arguments fail closed" {
    const unsupported = "--listen=-";
    const action = parseSlice(&.{ "test", "--test-filter=unit", unsupported });
    try std.testing.expect(action == .failure);
    try std.testing.expectEqualStrings(unsupported, action.failure.unsupported);
}

test "value arguments fail closed when their value is missing" {
    for (value_flags) |flag| {
        const action = parseSlice(&.{ "test", flag });
        try std.testing.expect(action == .failure);
        try std.testing.expectEqualStrings(flag, action.failure.missing_value);
    }
}

test "argument count bound fails closed" {
    var values: [max_arguments + 2][]const u8 = @splat("--seed=0");
    values[0] = "test";
    const action = parseSlice(&values);
    try std.testing.expect(action == .failure);
    try std.testing.expect(action.failure == .too_many_arguments);
}
