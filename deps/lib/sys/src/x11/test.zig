const std = @import("std");
const subject = @import("root.zig");

const auth = subject.auth;
const connection = subject.connection;
const display = subject.display;
const protocol = subject.protocol;
const xlib = subject.xlib;
const Connection = subject.Connection;
const Limits = subject.Limits;
const Capacity = subject.Capacity;
const CapacityError = subject.CapacityError;
const minimum_reply_byte_count = subject.minimum_reply_byte_count;
const default_reply_byte_count = subject.default_reply_byte_count;
const Message = subject.Message;
const RetainError = subject.RetainError;
const Status = subject.Status;
const ConnectError = subject.ConnectError;
const IoError = subject.IoError;
const ReplyView = subject.ReplyView;
const ReplyError = subject.ReplyError;
const Request = subject.Request;
const RequestError = subject.RequestError;

test {
    std.testing.refAllDecls(subject);
}

test "display target resolves to the connection socket path" {
    var buffer: [64]u8 = undefined;
    const target = try display.parse(":0");
    const path = try target.socketPath(&buffer);
    try std.testing.expect(std.mem.startsWith(u8, path, "/tmp/.X11-unix/X"));
}
