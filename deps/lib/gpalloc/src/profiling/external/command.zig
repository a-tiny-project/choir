const std = @import("std");
const sys = @import("sys");

const options = @import("options.zig");
const output = @import("output.zig");
const runner = @import("runner.zig");

pub fn main(init: sys.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const parsed = options.parse(args[1..]) catch |err| {
        try output.writeParseError(arena, err);
        sys.process.exit(2);
    };

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = sys.stdio.stdout().writer(sys.stdio.debugIo(), &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (parsed.show_help) {
        try output.writeUsage(arena);
        return;
    }
    if (parsed.list_benchmarks) {
        try runner.writeBenchmarks(stdout);
        try stdout.flush();
        return;
    }

    try output.writeRunStart(stdout, parsed);
    if (!suiteInstalled(parsed.suite_dir)) {
        try output.writeSuiteMissing(stdout, parsed.suite_dir);
        try output.writeRunEnd(stdout, 0, 0);
        try stdout.flush();
        sys.process.exit(1);
    }
    var resolved = parsed;
    resolved.suite_dir = try sys.fs.realPathAlloc(arena, parsed.suite_dir);
    const totals = try runner.runSelectedBenchmarks(arena, init.io, init.environ_map, stdout, resolved);
    try output.writeRunEnd(stdout, totals.benches, totals.errors);
    try stdout.flush();
    if (totals.errors != 0) sys.process.exit(1);
}

fn suiteInstalled(suite_dir: []const u8) bool {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const bench_dir = std.fmt.bufPrint(&buffer, "{s}/out/bench", .{suite_dir}) catch return false;
    sys.fs.cwd().access(sys.fs.debugIo(), bench_dir, .{}) catch return false;
    return true;
}
