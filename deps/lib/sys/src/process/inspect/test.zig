const std = @import("std");
const builtin = @import("builtin");
const sys = @import("../../root.zig");

const inspect = sys.process.inspect;

test "group census counts a running leader" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var storage: [16 * 1024]inspect.ProcessId = undefined;
    const own = try inspect.group(std.os.linux.getpid());
    try std.testing.expect(try inspect.groupRunning(own, &storage));
}

test "group census treats an unreaped exited group as drained" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const leader = switch (try sys.process.fork()) {
        .child => {
            sys.process.createOwnProcessGroup() catch sys.process.exit(2);
            sys.process.exit(0);
        },
        .parent => |pid| pid,
    };
    var reaped = false;
    defer if (!reaped) {
        _ = sys.process.waitDirect(leader) catch {};
    };
    for (0..5_000) |_| {
        if (try sys.process.peekNoHang(leader) != null) break;
        sys.time.sleepMilliseconds(1);
    } else return error.TestLeaderDidNotExit;
    try std.testing.expectEqual(leader, try inspect.group(leader));
    try std.testing.expect(try sys.process.processGroupAlive(leader));
    var storage: [16 * 1024]inspect.ProcessId = undefined;
    try std.testing.expect(!try inspect.groupRunning(leader, &storage));
    const termination = try sys.process.waitDirect(leader);
    reaped = true;
    try std.testing.expectEqual(@as(i64, 0), sys.process.exitCode(termination));
    try std.testing.expect(!try inspect.groupRunning(leader, &storage));
    try std.testing.expectError(error.BufferTooSmall, inspect.groupRunning(
        try inspect.group(std.os.linux.getpid()),
        storage[0..1],
    ));
}
