const std = @import("std");
const corpus = @import("corpus.zig");
const harness_mod = @import("harness.zig");
const ingest = @import("ingest.zig");

pub fn run() !void {
    var harness = try harness_mod.Harness.init();
    defer harness.deinit();

    var arena_state = std.heap.ArenaAllocator.init(harness.allocator);
    defer arena_state.deinit();
    try corpus.build(arena_state.allocator());
    defer corpus.reset();

    try harness.suite.add("memtrace replay canonical x1024", ingest.small, .{ .max_iterations = 128 });
    try harness.suite.add("memtrace replay canonical x8192", ingest.large, .{ .max_iterations = 32 });
    try harness.suite.add("memtrace replay summary x8192", ingest.summary, .{ .max_iterations = 32 });
    try harness.suite.run();
}
