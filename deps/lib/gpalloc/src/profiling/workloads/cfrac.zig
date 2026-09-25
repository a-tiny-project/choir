const std = @import("std");
const bench = @import("bench");
const coz = bench.coz;
const parameters = @import("parameters.zig");
const touch = @import("touch.zig");

const nextWorkingSetState = touch.nextWorkingSetState;

pub fn run(allocator: std.mem.Allocator) void {
    var factor_base: [parameters.cfrac_trace_factor_count]?[]u8 = @as([parameters.cfrac_trace_factor_count]?[]u8, @splat(null));
    var accumulators: [parameters.cfrac_trace_accumulator_count]?[]u8 = @as([parameters.cfrac_trace_accumulator_count]?[]u8, @splat(null));
    var relations: [parameters.cfrac_trace_relation_count]?[]u8 = @as([parameters.cfrac_trace_relation_count]?[]u8, @splat(null));
    var state: u32 = 0x7a34_51d9;

    {
        const factor_phase = bench.phaseAt("gpalloc.phase.cfrac_trace.factor_base", @src());
        defer factor_phase.end();

        for (&factor_base, 0..) |*factor, index| {
            const prime_vector = allocator.alloc(u8, factorVectorSize(index)) catch @panic("allocation failed");
            prime_vector[0] = @truncate(index);
            factor.* = prime_vector;

            const trial = allocator.alloc(u8, precisionSize(index, nextWorkingSetState(&state))) catch @panic("allocation failed");
            trial[0] = @truncate(index);
            std.mem.doNotOptimizeAway(trial.ptr);
            allocator.free(trial);
        }
        coz.progressNamed("gpalloc.phase.cfrac_trace.factor_base");
    }

    {
        const arithmetic_phase = bench.phaseAt("gpalloc.phase.cfrac_trace.arithmetic", @src());
        defer arithmetic_phase.end();

        var round: usize = 0;
        while (round < parameters.cfrac_trace_round_count) : (round += 1) {
            var temps: [parameters.cfrac_trace_temp_count]?[]u8 = @as([parameters.cfrac_trace_temp_count]?[]u8, @splat(null));
            for (&temps, 0..) |*temp, index| {
                const precision = allocator.alloc(u8, precisionSize(index + round, nextWorkingSetState(&state))) catch @panic("allocation failed");
                precision[0] = @truncate(index + round);
                temp.* = precision;
            }

            for (&temps, 0..) |*temp, index| {
                const precision = temp.* orelse continue;
                if (index % 7 == 0) {
                    const slot = (index + round) % accumulators.len;
                    if (accumulators[slot]) |old| {
                        std.mem.doNotOptimizeAway(old.ptr);
                        allocator.free(old);
                    }
                    accumulators[slot] = precision;
                    temp.* = null;
                    continue;
                }
                std.mem.doNotOptimizeAway(precision.ptr);
                allocator.free(precision);
                temp.* = null;
            }

            coz.progressNamed("gpalloc.phase.cfrac_trace.arithmetic");
        }
    }

    {
        const sieve_phase = bench.phaseAt("gpalloc.phase.cfrac_trace.sieve", @src());
        defer sieve_phase.end();

        for (&relations, 0..) |*relation, index| {
            const residue = allocator.alloc(u8, precisionSize(index * 3, nextWorkingSetState(&state))) catch @panic("allocation failed");
            residue[0] = @truncate(index);
            const bit_vector = allocator.alloc(u8, relationSize(index, nextWorkingSetState(&state))) catch @panic("allocation failed");
            bit_vector[0] = @truncate(index);
            relation.* = bit_vector;
            std.mem.doNotOptimizeAway(residue.ptr);
            allocator.free(residue);
        }
        coz.progressNamed("gpalloc.phase.cfrac_trace.sieve");
    }

    {
        const solve_phase = bench.phaseAt("gpalloc.phase.cfrac_trace.solve", @src());
        defer solve_phase.end();

        var solution_index: usize = 0;
        while (solution_index < parameters.cfrac_trace_solution_count) : (solution_index += 1) {
            const row = allocator.alloc(u8, relationSize(solution_index * 5, nextWorkingSetState(&state))) catch @panic("allocation failed");
            row[0] = @truncate(solution_index);
            const candidate = allocator.alloc(u8, precisionSize(solution_index * 11, nextWorkingSetState(&state))) catch @panic("allocation failed");
            candidate[0] = @truncate(solution_index);
            std.mem.doNotOptimizeAway(candidate.ptr);
            allocator.free(candidate);
            std.mem.doNotOptimizeAway(row.ptr);
            allocator.free(row);

            if (solution_index % 3 == 0) {
                const slot = solution_index % relations.len;
                if (relations[slot]) |relation| {
                    std.mem.doNotOptimizeAway(relation.ptr);
                    allocator.free(relation);
                    relations[slot] = null;
                }
            }
        }
        coz.progressNamed("gpalloc.phase.cfrac_trace.solve");
    }

    {
        const drain_phase = bench.phaseAt("gpalloc.phase.cfrac_trace.drain", @src());
        defer drain_phase.end();

        for (&accumulators) |*record| {
            const bytes = record.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            record.* = null;
        }
        for (&relations) |*record| {
            const bytes = record.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            record.* = null;
        }
        for (&factor_base) |*record| {
            const bytes = record.* orelse continue;
            std.mem.doNotOptimizeAway(bytes.ptr);
            allocator.free(bytes);
            record.* = null;
        }
    }
}

fn precisionSize(index: usize, state: usize) usize {
    const digits = 1 + ((index * 7 + state * 13) % 64);
    return 8 + digits * @sizeOf(u16);
}

fn factorVectorSize(index: usize) usize {
    return 16 + ((index * 17) % 96) * @sizeOf(u32);
}

fn relationSize(index: usize, state: usize) usize {
    return 24 + ((index * 11 + state * 5) % 128);
}
