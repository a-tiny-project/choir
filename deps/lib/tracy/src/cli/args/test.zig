const namespace = @import("root.zig");
const std = @import("std");

const types = namespace.types;
const scalar = namespace.scalar;
const summary = namespace.summary;
const context = namespace.context;
const csv = namespace.csv;
const tree = namespace.tree;
const stats = namespace.stats;
const frame = namespace.frame;
const memory = namespace.memory;
const lock = namespace.lock;
const message = namespace.message;
const sample = namespace.sample;
const fiber = namespace.fiber;
const gpu = namespace.gpu;
const system = namespace.system;
const plot = namespace.plot;
const find = namespace.find;
const source = namespace.source;
const flame = namespace.flame;
const timeline = namespace.timeline;
const compare = namespace.compare;
test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(namespace);
}
