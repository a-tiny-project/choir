const std = @import("std");
const bench = @import("bench");
const sys = @import("sys");

const memtrace = bench.memtrace;
const allocations_env = "TINY_PROFILE_ALLOCATIONS_PATH";

pub const Session = struct {
    output_path: ?[]u8 = null,
    tracer: ?memtrace.Tracer = null,
    traced: ?memtrace.TracingAllocator = null,

    pub fn start(
        self: *Session,
        control_allocator: std.mem.Allocator,
        measured_allocator: std.mem.Allocator,
    ) !void {
        self.output_path = try sys.env.getOwned(control_allocator, allocations_env);
        errdefer if (self.output_path) |path| control_allocator.free(path);
        if (self.output_path == null) return;
        self.tracer = try memtrace.Tracer.init(control_allocator, .{
            .record_events = true,
            .allocation_attribution = .stack,
        });
        if (self.tracer) |*tracer| {
            self.traced = try tracer.tracedAllocatorWithOptions(measured_allocator, .{
                .name = "gpalloc.measured",
                .retention = .retains_freed_memory,
            });
        }
    }

    pub fn allocator(self: *Session, fallback: std.mem.Allocator) std.mem.Allocator {
        if (self.traced) |*traced| return traced.allocator();
        return fallback;
    }

    pub fn tracerPtr(self: *Session) ?*memtrace.Tracer {
        if (self.tracer) |*tracer| return tracer;
        return null;
    }

    pub fn finish(self: *Session) !void {
        const path = self.output_path orelse return;
        const tracer = self.tracerPtr() orelse return;
        try tracer.writeEventsBundlePath(path);
    }

    pub fn deinit(self: *Session, control_allocator: std.mem.Allocator) void {
        if (self.tracer) |*tracer| tracer.deinit();
        if (self.output_path) |path| control_allocator.free(path);
        self.* = .{};
    }
};

test "gpalloc driver traces only the measured allocator" {
    if (comptime !@hasDecl(std.process.Environ.Block, "view")) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    const root = try temporary.parent_dir.realPathFileAlloc(
        std.Options.debug_io,
        temporary.sub_path[0..],
        allocator,
    );
    defer allocator.free(root);
    const path = try std.fs.path.join(allocator, &.{ root, "allocations.jsonl" });
    defer allocator.free(path);

    var environment = sys.env.Map.init(allocator);
    defer environment.deinit();
    try environment.put(allocations_env, path);
    const block = try environment.createPosixBlock(allocator, .{});
    defer block.deinit(allocator);

    const previous = sys.env.current();
    sys.env.installProcessEnvironment(.{ .block = block });
    defer sys.env.installProcessEnvironment(previous);

    var session: Session = .{};
    try session.start(allocator, allocator);
    defer session.deinit(allocator);

    const measured = session.allocator(allocator);
    var span = try memtrace.Context.init(session.tracerPtr(), null).enter("small_churn");
    const memory = try measured.alloc(u8, 64);
    measured.free(memory);
    span.exit();
    try session.finish();

    const events = try sys.fs.readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"alloc\"") != null);
    try std.testing.expect(
        std.mem.indexOf(u8, events, "\"scope\":\"root/small_churn\"") != null,
    );
}
