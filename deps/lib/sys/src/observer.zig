const std = @import("std");

pub const enabled = true;

pub const Operation = enum(u8) {
    map,
    unmap,
    protect,
    discard,
    decommit,
    advise,
};

pub const Source = enum(u8) {
    anonymous,
    reserve,
    anonymous_fixed,
    private_file,
    shared_file,
    private_file_fixed,
    unmap,
    protect,
    discard,
    decommit,
    huge_pages,
    small_pages,
};

pub const Event = struct {
    operation: Operation,
    source: Source,
    address: usize,
    len: usize,
    return_address: usize,
    succeeded: bool,
};

pub const Sink = struct {
    context: *anyopaque,
    record: *const fn (context: *anyopaque, event: Event) void,
};

pub const Session = struct {
    sink: if (enabled) ?*const Sink else void =
        if (enabled) null else {},
    active: if (enabled) bool else void =
        if (enabled) false else {},

    pub fn deinit(self: *Session) void {
        if (comptime !enabled) return;
        std.debug.assert(callback_depth == 0);
        std.debug.assert(self.active);
        const address = @intFromPtr(self.sink.?);
        const previous = active_sink.cmpxchgStrong(
            address,
            0,
            .acq_rel,
            .acquire,
        );
        std.debug.assert(previous == null);
        while (active_operations.load(.acquire) != 0) {
            std.atomic.spinLoopHint();
        }
        self.active = false;
        self.sink = null;
    }
};

pub const Suppression = struct {
    active: bool = true,

    pub fn deinit(self: *Suppression) void {
        if (!self.active) return;
        std.debug.assert(callback_depth > 0);
        callback_depth -= 1;
        self.active = false;
    }
};

var active_sink = std.atomic.Value(usize).init(0);
var active_operations = std.atomic.Value(usize).init(0);
threadlocal var callback_depth: u8 = 0;

pub fn install(sink: *const Sink) error{AlreadyInstalled}!Session {
    if (comptime !enabled) return .{};
    std.debug.assert(callback_depth == 0);
    const address = @intFromPtr(sink);
    std.debug.assert(address != 0);
    if (active_sink.cmpxchgStrong(
        0,
        address,
        .acq_rel,
        .acquire,
    ) != null) {
        return error.AlreadyInstalled;
    }
    return .{
        .sink = sink,
        .active = true,
    };
}

pub inline fn suppress() Suppression {
    std.debug.assert(callback_depth < std.math.maxInt(u8));
    callback_depth += 1;
    return .{};
}

pub inline fn record(event: Event) void {
    if (comptime !enabled) return;
    if (callback_depth != 0) return;
    _ = active_operations.fetchAdd(1, .acquire);
    const sink_address = active_sink.load(.acquire);
    if (sink_address == 0) {
        _ = active_operations.fetchSub(1, .release);
        return;
    }
    const sink: *const Sink = @ptrFromInt(sink_address);
    callback_depth += 1;
    sink.record(sink.context, event);
    callback_depth -= 1;
    _ = active_operations.fetchSub(1, .release);
}

test "physical memory observer records owner operations" {
    if (!enabled) return error.SkipZigTest;
    const Recorder = struct {
        event: ?Event = null,

        fn sink(self: *@This()) Sink {
            return .{
                .context = self,
                .record = accept,
            };
        }

        fn accept(context: *anyopaque, event: Event) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.event = event;
            record(event);
        }
    };
    var recorder = Recorder{};
    var sink = recorder.sink();
    var session = try install(&sink);
    defer session.deinit();
    const expected = Event{
        .operation = .map,
        .source = .anonymous,
        .address = 0x1000,
        .len = 4096,
        .return_address = 0x2000,
        .succeeded = true,
    };
    record(expected);
    try std.testing.expectEqual(expected, recorder.event.?);
}

test "disabled physical memory observer is inert" {
    if (enabled) return error.SkipZigTest;
    var sink = Sink{
        .context = undefined,
        .record = undefined,
    };
    var session = try install(&sink);
    defer session.deinit();
    record(.{
        .operation = .unmap,
        .source = .unmap,
        .address = 0,
        .len = 0,
        .return_address = 0,
        .succeeded = true,
    });
}
