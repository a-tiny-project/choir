const harness_mod = @import("harness.zig");
const churn = @import("churn.zig");

pub fn run() !void {
    var harness = try harness_mod.Harness.init();
    defer harness.deinit();

    try harness.suite.add("memtrace record mixed-order churn x2304", churn.churn, .{
        .min_time_ns = 250_000_000,
        .max_iterations = 512,
    });
    try harness.suite.add("memtrace record mixed-order events x2304", churn.churnRecorded, .{
        .min_time_ns = 250_000_000,
        .max_iterations = 512,
    });
    try harness.suite.add("memtrace record exact stacks x2304", churn.churnExact, .{
        .min_time_ns = 250_000_000,
        .max_iterations = 32,
    });
    try harness.suite.run();
}
