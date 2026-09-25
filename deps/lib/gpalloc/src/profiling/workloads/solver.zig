const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");

pub fn run(allocator: std.mem.Allocator) void {
    var learned: [parameters.solver_trace_learned_count]?[]u8 = @as([parameters.solver_trace_learned_count]?[]u8, @splat(null));
    var learned_index: usize = 0;

    var depth: usize = 0;
    while (depth < parameters.solver_trace_depth_count) : (depth += 1) {
        var clauses: [parameters.solver_trace_clause_count]?[]u8 = @as([parameters.solver_trace_clause_count]?[]u8, @splat(null));

        {
            const decide_phase = bench.phaseAt("gpalloc.phase.solver_trace.decide", @src());
            defer decide_phase.end();

            const assignment = allocator.alloc(u8, 24 + depth * 8) catch @panic("allocation failed");
            assignment[0] = @truncate(depth);
            std.mem.doNotOptimizeAway(assignment.ptr);
            allocator.free(assignment);
        }

        {
            const propagate_phase = bench.phaseAt("gpalloc.phase.solver_trace.propagate", @src());
            defer propagate_phase.end();

            for (&clauses, 0..) |*clause, index| {
                const bytes = allocator.alloc(u8, clauseSize(index, depth)) catch @panic("allocation failed");
                bytes[0] = @truncate(index + depth);
                clause.* = bytes;
            }
        }

        {
            const learn_phase = bench.phaseAt("gpalloc.phase.solver_trace.learn", @src());
            defer learn_phase.end();

            var index: usize = 0;
            while (index < 6 and learned_index < learned.len) : (index += 1) {
                const bytes = allocator.alloc(u8, 96 + (depth + index) * 24) catch @panic("allocation failed");
                bytes[0] = @truncate(index + depth);
                learned[learned_index] = bytes;
                learned_index += 1;
            }
        }

        {
            const backtrack_phase = bench.phaseAt("gpalloc.phase.solver_trace.backtrack", @src());
            defer backtrack_phase.end();

            for (&clauses, 0..) |*clause, index| {
                const bytes = clause.* orelse continue;
                if ((index + depth) % 3 == 0 and learned_index < learned.len) {
                    learned[learned_index] = bytes;
                    learned_index += 1;
                    clause.* = null;
                    continue;
                }
                std.mem.doNotOptimizeAway(bytes.ptr);
                allocator.free(bytes);
                clause.* = null;
            }
        }

        if (depth % 4 == 3) {
            const restart_phase = bench.phaseAt("gpalloc.phase.solver_trace.restart", @src());
            defer restart_phase.end();

            var index: usize = 0;
            while (index < learned_index) : (index += 2) {
                if (learned[index]) |bytes| {
                    std.mem.doNotOptimizeAway(bytes.ptr);
                    allocator.free(bytes);
                    learned[index] = null;
                }
            }
            coz.progressNamed("gpalloc.phase.solver_trace.restart");
        }
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.solver_trace.drain", @src());
        defer drain_phase.end();

        for (&learned) |*clause| {
            const bytes = clause.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            clause.* = null;
        }
    }
}

fn clauseSize(index: usize, depth: usize) usize {
    const sizes = [_]usize{ 48, 72, 96, 128, 192, 256, 384, 768 };
    return sizes[(index * 13 + depth * 5) % sizes.len];
}
