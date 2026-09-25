const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const memtrace = bench.memtrace;
const workloads = @import("workloads");

const allocator_module = @import("allocator.zig");
const options = @import("options.zig");
const output = @import("output.zig");

pub fn writeWorkloads(writer: *std.Io.Writer) !void {
    var line_buffer: [512]u8 = undefined;
    for (workloads.all) |workload| try writeWorkload(writer, &line_buffer, workload);
    for (workloads.detail) |workload| try writeWorkload(writer, &line_buffer, workload);
}

pub fn runSelectedWorkloads(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    parsed: options.Options,
    measured_allocator: *allocator_module.Selected,
    allocation_tracer: ?*memtrace.Tracer,
) !u32 {
    if (parsed.workload_id) |id| {
        if (std.mem.eql(u8, id, "all")) {
            return runAllWorkloads(
                allocator,
                writer,
                parsed,
                measured_allocator,
                allocation_tracer,
            );
        }
        const workload = workloads.byId(id) orelse return error.UnknownWorkload;
        try runOneWorkload(
            allocator,
            writer,
            parsed,
            measured_allocator,
            allocation_tracer,
            workload,
        );
        return 1;
    }
    return runAllWorkloads(
        allocator,
        writer,
        parsed,
        measured_allocator,
        allocation_tracer,
    );
}

fn runAllWorkloads(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    parsed: options.Options,
    measured_allocator: *allocator_module.Selected,
    allocation_tracer: ?*memtrace.Tracer,
) !u32 {
    for (workloads.all) |workload| {
        try runOneWorkload(
            allocator,
            writer,
            parsed,
            measured_allocator,
            allocation_tracer,
            workload,
        );
    }
    return workloads.all.len;
}

pub fn stabilizerConfig(seed: u64) bench.stabilizer.Config {
    return .{
        .seed = seed,
        .heap = .{ .enabled = false },
    };
}

fn runOneWorkload(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    parsed: options.Options,
    measured_allocator: *allocator_module.Selected,
    allocation_tracer: ?*memtrace.Tracer,
    workload: workloads.Workload,
) !void {
    const workload_latency = bench.phaseAt("gpalloc.workload", @src());
    workload_latency.setName(workload.id);
    defer workload_latency.end();
    var allocation_span = try memtrace.Context.init(allocation_tracer, null).enter(workload.id);
    defer allocation_span.exit();

    var layout_runtime: ?bench.stabilizer.Runtime = if (parsed.stabilizer)
        try bench.stabilizer.Runtime.init(allocator, stabilizerConfig(parsed.stabilizer_seed))
    else
        null;
    defer if (layout_runtime) |*runtime| runtime.deinit();

    var warmup_index: u32 = 0;
    while (warmup_index < parsed.warmup) : (warmup_index += 1) {
        callEvals(&layout_runtime, measured_allocator.allocator, workload, parsed.evals);
        coz.progressNamed("gpalloc.warmup");
    }

    const samples = try allocator.alloc(u64, parsed.samples);
    defer allocator.free(samples);

    const stats_before = if (parsed.allocator_stats) allocator_module.stats(measured_allocator) else null;
    var sample_index: u32 = 0;
    while (sample_index < parsed.samples) : (sample_index += 1) {
        {
            const sample_latency = bench.phaseAt("gpalloc.sample", @src());
            sample_latency.setName(workload.id);
            defer sample_latency.end();

            bench.rerandomizeLayout(&layout_runtime, "gpalloc.stabilizer.rerandomize");
            const start = bench.nowNs();
            callEvals(&layout_runtime, measured_allocator.allocator, workload, parsed.evals);
            const total_ns = bench.elapsedNs(start);
            const ns = total_ns / parsed.evals;
            samples[sample_index] = ns;
            try output.writeSample(
                writer,
                parsed,
                resultWorkload(workload),
                sample_index,
                total_ns,
                ns,
            );
            coz.progressNamed("gpalloc.sample");
        }
    }

    var statistics = try bench.StatisticsStorage.init(allocator, .{ .samples = samples.len });
    defer statistics.deinit(allocator);
    statistics.activate();
    const stats = try bench.computeSampleStats(&statistics, samples);
    try output.writeSummary(writer, parsed, resultWorkload(workload), stats);
    if (stats_before) |before| {
        if (allocator_module.stats(measured_allocator)) |after| {
            try output.writeAllocatorStats(writer, parsed, resultWorkload(workload), .{
                .before = before,
                .after = after,
            });
        }
    }
    coz.progressNamed("gpalloc.workload.complete");
}

fn writeWorkload(
    writer: *std.Io.Writer,
    line_buffer: *[512]u8,
    workload: workloads.Workload,
) !void {
    try bench.pretty.write(
        writer,
        .{ .text = try std.fmt.bufPrint(line_buffer, "{s}\t{s}\n", .{
            workload.id,
            workload.name,
        }) },
        .{},
    );
}

test "stabilizer config disables heap shuffling for measured allocators" {
    const layout_config = stabilizerConfig(7);
    try std.testing.expectEqual(@as(u64, 7), layout_config.seed);
    try std.testing.expect(!layout_config.heap.enabled);
    try std.testing.expect(layout_config.stack.enabled);
    try std.testing.expect(layout_config.code.enabled);
}

fn resultWorkload(workload: workloads.Workload) output.Workload {
    return .{ .id = workload.id, .name = workload.name };
}

fn callEvals(
    layout_runtime: *?bench.stabilizer.Runtime,
    measured_allocator: std.mem.Allocator,
    workload: workloads.Workload,
    evals: u32,
) void {
    if (layout_runtime.*) |*active| {
        const pad = active.nextStackPad();
        bench.callWithStackPad(pad.unit, runEvals, .{ measured_allocator, workload, evals });
        return;
    }
    runEvals(measured_allocator, workload, evals);
}

fn runEvals(allocator: std.mem.Allocator, workload: workloads.Workload, evals: u32) void {
    var eval_index: u32 = 0;
    while (eval_index < evals) : (eval_index += 1) {
        workload.run(allocator);
        coz.progressNamed("gpalloc.eval");
    }
}
