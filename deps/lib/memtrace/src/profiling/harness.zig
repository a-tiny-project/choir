const std = @import("std");
const bench = @import("bench");
const sys = @import("sys");

pub const Harness = struct {
    allocator: std.mem.Allocator,
    filter: ?[]u8,
    suite: bench.Suite,

    pub fn init() !Harness {
        const allocator = sys.allocator.benchmarkAllocator();
        const filter = try sys.env.getOwned(allocator, "BENCH_FILTER");
        errdefer if (filter) |value| allocator.free(value);

        var suite = bench.Suite.init(allocator, .{
            .min_time_ns = try benchMinTimeNs(allocator, 10_000_000),
            .min_iterations = 5,
            .max_iterations = 1000,
            .warmup_iterations = 1,
            .allocation_attribution = .sample_call,
        });
        suite.setFilter(filter);
        return .{
            .allocator = allocator,
            .filter = filter,
            .suite = suite,
        };
    }

    pub fn deinit(self: *Harness) void {
        self.suite.deinit();
        if (self.filter) |value| self.allocator.free(value);
        self.* = undefined;
    }
};

fn benchMinTimeNs(allocator: std.mem.Allocator, default: u64) !u64 {
    const value = try sys.env.getOwned(allocator, "BENCH_MIN_TIME_NS");
    defer if (value) |text| allocator.free(text);
    return if (value) |text| try std.fmt.parseUnsigned(u64, text, 10) else default;
}
