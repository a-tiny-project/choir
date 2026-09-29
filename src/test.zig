const std = @import("std");
const choir = @import("root.zig");
const backends = @import("backends/test.zig");
const bytecode = @import("bytecode/test.zig");
const compiler = @import("compiler/test.zig");
const composition = @import("composition/test.zig");
const core = @import("core/test.zig");
const dialects = @import("dialects/test.zig");
const diagnostics = @import("diagnostics/test.zig");
const egraph = @import("egraph/test.zig");
const eval = @import("eval/test.zig");
const passes = @import("passes/test.zig");
const product = @import("product/test.zig");
const serialization = @import("serialization/test.zig");

/// Shared by the owned tests and the explicit expected-observation generator.
pub const rewrite_observations = @import("passes/observations/fixture/root.zig");
/// Shared by the stage emitter tests and the SPIR-V validation gate.
pub const gpu_fixture = @import("backends/gpu/fixture/root.zig");
/// The CPU stage lowering, for the tool that writes stage objects.
pub const gpu_cpu = @import("backends/gpu/cpu/root.zig");

test {
    _ = backends;
    _ = bytecode;
    _ = compiler;
    _ = composition;
    _ = core;
    _ = dialects;
    _ = diagnostics;
    _ = egraph;
    _ = eval;
    _ = passes;
    _ = product;
    _ = serialization;
}

test "choir package namespace" {
    std.testing.refAllDecls(choir);
}
