const std = @import("std");
const subject = @import("root.zig");

const required_capabilities = subject.required_capabilities;
const coregraphics = subject.coregraphics;
const cocoa = subject.cocoa;
const dispatch = subject.dispatch;
const foundation = subject.foundation;
const gamecontroller = subject.gamecontroller;
const metal = subject.metal;
const objc = subject.objc;

test {
    std.testing.refAllDecls(subject);
}
