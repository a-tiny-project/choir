const std = @import("std");
const hypothesis = @import("hypothesis");
const simd = @import("simd");
const run = @import("run.zig");

const Allocator = std.mem.Allocator;
const DF = simd.FixedTag(f32, 8);
const DB = simd.BFloat16Tag(16);
const max_rows: usize = 17;
const max_columns: usize = 65;
const max_area: usize = max_rows * max_columns;

fn drawFloat(data: *hypothesis.ConjectureData) !f32 {
    const drawn: i32 = @intCast(try data.drawInteger(0, 256, 128));
    return @as(f32, @floatFromInt(drawn - 128)) * (1.0 / 32.0);
}

fn close(expected: f32, actual: f32) bool {
    const tolerance = 96 * std.math.floatEps(f32) * @max(@abs(expected), 1);
    return @abs(expected - actual) <= tolerance;
}

fn expectClose(expected: f32, actual: f32) !void {
    try std.testing.expect(close(expected, actual));
}

pub const MatrixProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const rows: usize = @intCast(try data.drawInteger(0, max_rows, 0));
        const columns: usize = @intCast(try data.drawInteger(0, max_columns, 0));
        const area = rows * columns;
        var matrix: [max_area]f32 = undefined;
        var vector: [max_columns]f32 = undefined;
        var add: [max_rows]f32 = undefined;
        for (matrix[0..area]) |*value| value.* = try drawFloat(data);
        for (vector[0..columns]) |*value| value.* = try drawFloat(data);
        for (add[0..rows]) |*value| value.* = try drawFloat(data);
        var output: [max_rows]f32 = undefined;
        simd.matVec(DF, matrix[0..area], vector[0..columns], output[0..rows]);
        const without_add = output;
        for (output[0..rows], 0..) |actual, row| {
            var expected: f32 = 0;
            for (matrix[row * columns ..][0..columns], vector[0..columns]) |a, b| {
                expected = @mulAdd(f32, a, b, expected);
            }
            try expectClose(expected, actual);
        }
        simd.matVecAdd(
            DF,
            matrix[0..area],
            vector[0..columns],
            add[0..rows],
            output[0..rows],
        );
        for (output[0..rows], add[0..rows], 0..) |actual, addend, row| {
            try expectClose(without_add[row] + addend, actual);
        }
        if (rows != 0 and columns != 0) {
            const changed: usize = @intCast(try data.drawInteger(0, rows - 1, 0));
            matrix[changed * columns] += 0.5;
            simd.matVec(DF, matrix[0..area], vector[0..columns], output[0..rows]);
            for (output[0..rows], 0..) |actual, row| {
                if (row != changed) try std.testing.expectEqual(without_add[row], actual);
            }
        }
    }
};

pub const BFloatMatrixProperty = struct {
    pub fn property(data: *hypothesis.ConjectureData, _: Allocator) !void {
        const rows: usize = @intCast(try data.drawInteger(0, max_rows, 0));
        const columns: usize = @intCast(try data.drawInteger(0, max_columns, 0));
        const area = rows * columns;
        var matrix: [max_area]simd.BFloat16 = undefined;
        var vector_f32: [max_columns]f32 = undefined;
        var vector_bf: [max_columns]simd.BFloat16 = undefined;
        var add_f32: [max_rows]f32 = undefined;
        var add_bf: [max_rows]simd.BFloat16 = undefined;
        for (matrix[0..area]) |*value| value.* = simd.BFloat16.fromF32(try drawFloat(data));
        for (vector_f32[0..columns], vector_bf[0..columns]) |*fv, *bv| {
            fv.* = try drawFloat(data);
            bv.* = simd.BFloat16.fromF32(fv.*);
        }
        for (add_f32[0..rows], add_bf[0..rows]) |*fv, *bv| {
            fv.* = try drawFloat(data);
            bv.* = simd.BFloat16.fromF32(fv.*);
        }
        var output: [max_rows]f32 = undefined;
        simd.matVecBFloatF32Add(
            DF,
            matrix[0..area],
            vector_f32[0..columns],
            add_f32[0..rows],
            output[0..rows],
        );
        for (output[0..rows], 0..) |actual, row| {
            var expected: f32 = 0;
            for (matrix[row * columns ..][0..columns], vector_f32[0..columns]) |a, b| {
                expected = @mulAdd(f32, a.toF32(), b, expected);
            }
            expected += add_f32[row];
            try expectClose(expected, actual);
        }
        simd.matVecBFloat16Add(
            DB,
            matrix[0..area],
            vector_bf[0..columns],
            add_bf[0..rows],
            output[0..rows],
        );
        for (output[0..rows], 0..) |actual, row| {
            var expected: f32 = 0;
            for (matrix[row * columns ..][0..columns], vector_bf[0..columns]) |a, b| {
                expected = @mulAdd(f32, a.toF32(), b.toF32(), expected);
            }
            expected += add_bf[row].toF32();
            try expectClose(expected, actual);
        }
    }
};

test "property: matvec rows equal independent scalar products and additive forms" {
    try hypothesis.checkNamed(MatrixProperty, "simd-matvec-row-model", run.settings());
}

test "property: bfloat matvec forms equal widened scalar products" {
    try hypothesis.checkNamed(BFloatMatrixProperty, "simd-matvec-bfloat-model", run.settings());
}
