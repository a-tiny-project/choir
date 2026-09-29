//! Runs one aarch64 function for the backend's own witnesses. Test support only: nothing a
//! consumer reaches imports this, and `execution.native` reports aarch64 as unable to execute.
//!
//! THIS NEVER FLUSHES THE INSTRUCTION CACHE. It copies code into a fresh mapping, makes the
//! mapping executable, and calls it. QEMU user mode translates from memory and tolerates that.
//! Hardware with separate instruction and data caches does not: a real aarch64 target needs
//! `__clear_cache` or IC IVAU, DSB and ISB over the range before the first call, and a hardware
//! witness or a stated gap.

const std = @import("std");
const ir = @import("../../../core/root.zig");
const dialects = @import("../../../dialects/root.zig");
const sys = @import("sys");
const backend = @import("../backend.zig");

const Backend = backend.Backend;
const max_arguments = backend.max_arguments;

/// Lowers `module`, emits `entry`, and calls it with `args` in x0..x7. Returns its one integer
/// result, or null when it returns nothing. Refuses a wrong argument count with
/// `error.ArgumentCountMismatch` and a diagnostic at the function, before emitting anything.
pub fn run(host: *Backend, module: *ir.Operation, entry: []const u8, args: []const i64) !?i64 {
    const lowered = try host.lower(module);
    const func = ir.inspection.functionDefinitionByName(lowered, entry) orelse
        return error.FunctionNotFound;
    const function = dialects.FuncDialect.FuncOp{ .op = func };
    if (args.len != function.getNumArguments()) {
        var diagnostic = func.emitError("aarch64 call argument count does not match the function signature");
        defer diagnostic.deinit();
        _ = diagnostic.emit() catch {};
        return error.ArgumentCountMismatch;
    }
    const code = try host.compileFunctionToMachineCode(lowered, entry);
    defer host.allocator.free(code);
    return enter(code, args, function.getNumResults() != 0);
}

fn enter(code: []const u8, args: []const i64, has_result: bool) error{MapFailed}!?i64 {
    std.debug.assert(args.len <= max_arguments);
    std.debug.assert(code.len > 0);

    var memory = sys.memory.mapAnonymous(code.len, .{ .read = true, .write = true }) catch
        return error.MapFailed;
    defer sys.memory.unmap(memory);

    @memcpy(memory[0..code.len], code);
    sys.memory.protect(memory, .{ .read = true, .execute = true }) catch return error.MapFailed;

    if (has_result) return call(i64, memory.ptr, args);
    call(void, memory.ptr, args);
    return null;
}

fn call(comptime Result: type, address: [*]u8, args: []const i64) Result {
    std.debug.assert(args.len <= max_arguments);
    return switch (args.len) {
        0 => blk: {
            const func: *const fn () callconv(.c) Result = @ptrCast(@alignCast(address));
            break :blk func();
        },
        1 => blk: {
            const func: *const fn (i64) callconv(.c) Result = @ptrCast(@alignCast(address));
            break :blk func(args[0]);
        },
        2 => blk: {
            const func: *const fn (i64, i64) callconv(.c) Result = @ptrCast(@alignCast(address));
            break :blk func(args[0], args[1]);
        },
        3 => blk: {
            const func: *const fn (i64, i64, i64) callconv(.c) Result = @ptrCast(@alignCast(address));
            break :blk func(args[0], args[1], args[2]);
        },
        4 => blk: {
            const func: *const fn (i64, i64, i64, i64) callconv(.c) Result = @ptrCast(@alignCast(address));
            break :blk func(args[0], args[1], args[2], args[3]);
        },
        5 => blk: {
            const func: *const fn (i64, i64, i64, i64, i64) callconv(.c) Result = @ptrCast(@alignCast(address));
            break :blk func(args[0], args[1], args[2], args[3], args[4]);
        },
        6 => blk: {
            const func: *const fn (i64, i64, i64, i64, i64, i64) callconv(.c) Result = @ptrCast(@alignCast(address));
            break :blk func(args[0], args[1], args[2], args[3], args[4], args[5]);
        },
        7 => blk: {
            const func: *const fn (i64, i64, i64, i64, i64, i64, i64) callconv(.c) Result = @ptrCast(@alignCast(address));
            break :blk func(args[0], args[1], args[2], args[3], args[4], args[5], args[6]);
        },
        8 => blk: {
            const func: *const fn (i64, i64, i64, i64, i64, i64, i64, i64) callconv(.c) Result = @ptrCast(@alignCast(address));
            break :blk func(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
        },
        else => unreachable,
    };
}
