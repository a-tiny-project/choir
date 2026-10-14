//! A compiler author's language adds one operation, `calc.powi`, which raises an integer to a
//! fixed power. The author writes its declaration and one rewrite into Choir's shared `arith`
//! operations. Choir supplies verification, constant folding, dead-code elimination, and code
//! generation, so the program compiles to machine code and runs inside this process.

const std = @import("std");
const choir = @import("choir");
const ir = choir.ir;

const arith = choir.dialects.ArithDialect;
const func = choir.dialects.FuncDialect;
const Runtime = choir.backends.execution.native.Runtime;

/// The author's dialect. `calc.powi` takes one integer and a positive exponent.
pub const CalcDialect = struct {
    pub const name = "calc";
    const templates = ir.dialects.operationTemplate.dialect(@This());
    pub const spec = ir.dialects.dialectSpec(@This(), .{});

    pub const PowOp = struct {
        op: *ir.Operation,

        pub const leaf = templates.explicitLeaf(@This(), .{
            .mnemonic = "powi",
            .operands = .{"base"},
            .results = .{"result"},
            .required_attrs = .{ir.dialects.attribute.integer("exponent")},
            .interfaces = &.{ir.dialects.opSpec.verifier(verifyPow)},
        });
        pub const operation_name = leaf.operation_name;

        pub fn create(context: *ir.Context, base: *ir.Value, exponent: i64) !PowOp {
            const pow = try leaf.createLeaf(context, .unknown, &.{base}, &.{base.type});
            try leaf.setI64Attr(pow, "exponent", exponent);
            return pow;
        }

        pub fn getBase(self: PowOp) *ir.Value {
            return leaf.getOperand(self, "base");
        }

        pub fn getExponent(self: PowOp) i64 {
            return leaf.getI64Attr(self, "exponent").?;
        }

        pub fn getResult(self: PowOp) *ir.Value {
            return self.op.getResult(0).?;
        }
    };
};

/// The verifier rejects an exponent below one, which the rewrite does not handle.
fn verifyPow(op_ptr: *const anyopaque) anyerror!void {
    const op: *ir.Operation = @ptrCast(@alignCast(@constCast(op_ptr)));
    const pow = CalcDialect.PowOp{ .op = op };
    if ((CalcDialect.PowOp.leaf.getI64Attr(pow, "exponent") orelse 0) < 1)
        return error.ExponentBelowOne;
}

/// Rewrites `calc.powi` by square-and-multiply: the binary digits of the exponent select which
/// repeated squares of the base to multiply together, so x^13 = x^8 * x^4 * x.
fn lowerPow(op: *ir.Operation, rewriter: *ir.rewrite.PatternRewriter) ir.rewrite.PatternResult {
    lowerPowOrFail(op, rewriter) catch return .failure;
    return .success;
}

fn lowerPowOrFail(op: *ir.Operation, rewriter: *ir.rewrite.PatternRewriter) !void {
    const pow = CalcDialect.PowOp{ .op = op };
    const context = op.getContext();
    rewriter.setInsertionPointBefore(op);

    var exponent = pow.getExponent();
    var square = pow.getBase();
    var product: ?*ir.Value = null;
    while (true) {
        if (exponent & 1 == 1) {
            product = if (product) |partial|
                try multiply(context, rewriter, partial, square)
            else
                square;
        }
        exponent >>= 1;
        if (exponent == 0) break;
        square = try multiply(context, rewriter, square, square);
    }
    try rewriter.replaceOp(op, &.{product.?});
}

fn multiply(
    context: *ir.Context,
    rewriter: *ir.rewrite.PatternRewriter,
    lhs: *ir.Value,
    rhs: *ir.Value,
) !*ir.Value {
    const mul = try arith.MulOp.create(context, .unknown, lhs, rhs);
    _ = try rewriter.insert(mul.op);
    return mul.getResult();
}

/// Applies the author's rewrite everywhere in `module`, then Choir's shared constant folding
/// and dead-code elimination, verifying the module after each pass.
fn lower(allocator: std.mem.Allocator, context: *ir.Context, module: *ir.Operation) !void {
    var patterns = ir.rewrite.RewritePatternSet.init(allocator);
    defer patterns.deinit();
    try patterns.add(ir.rewrite.RewritePattern.init(.{
        .name = "calc-powi-to-arith",
        .root_op_name = CalcDialect.PowOp.operation_name,
    }, lowerPow));
    const rewritten = choir.passes.applyPatternsGreedily(allocator, context, module, &patterns, .{});
    if (rewritten.termination != .converged) return error.RewriteDidNotConverge;

    var passes = choir.PassManager.init(allocator);
    defer passes.deinit();
    passes.enableVerifier();
    try passes.addPass(choir.passes.createConstantFoldingPass());
    try passes.addPass(choir.passes.createDeadCodeEliminationPass());
    if (passes.run(module, context) != .success) return error.PassFailed;
}

/// A compiler session: a context with Choir's dialects and the author's, and one module.
const Session = struct {
    context: choir.Context,
    integer: ir.Type,
    module: *ir.Operation,

    /// Initializes in place, because registered dialects and operations keep `&self.context`.
    fn init(self: *Session, allocator: std.mem.Allocator) !void {
        self.context = try choir.Context.init(allocator, choir.Context.Limits.testing);
        errdefer self.context.deinit(allocator);
        try choir.dialects.registerAllDialects(&self.context);
        try ir.dialects.loadDialectSpec(&self.context, CalcDialect.spec);
        self.integer = try arith.getScalarType(&self.context, .i64);
        self.module = (try choir.dialects.BuiltinDialect.ModuleOp.create(&self.context, .unknown)).op;
    }

    fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        self.module.erase();
        self.context.deinit(allocator);
    }

    /// Adds `fn name(x: i64) i64 { return calc.powi(x, exponent); }`.
    fn addPower(self: *Session, name: []const u8, exponent: i64) !void {
        const context = &self.context;
        const function = try func.FuncOp.create(context, .unknown, name, &.{self.integer}, &.{self.integer});
        try self.addBody(function, function.getArgument(0), exponent);
    }

    /// Adds `fn name() i64 { return calc.powi(base, exponent); }` with a constant base.
    fn addConstantPower(self: *Session, name: []const u8, base: i64, exponent: i64) !void {
        const context = &self.context;
        const function = try func.FuncOp.create(context, .unknown, name, &.{}, &.{self.integer});
        const constant = try arith.ConstantOp.createInt(context, .unknown, self.integer, base);
        try function.getEntryBlock().addOperation(constant.op);
        try self.addBody(function, constant.getResult(), exponent);
    }

    fn addBody(self: *Session, function: func.FuncOp, base: *ir.Value, exponent: i64) !void {
        const pow = try CalcDialect.PowOp.create(&self.context, base, exponent);
        const ret = try func.ReturnOp.create(&self.context, .unknown, &.{pow.getResult()});
        try function.getEntryBlock().addOperation(pow.op);
        try function.getEntryBlock().addOperation(ret.op);
        try (choir.dialects.BuiltinDialect.ModuleOp{ .op = self.module }).getBodyBlock().addOperation(function.op);
    }

    fn print(self: *Session, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
        try ir.dump.writeOperation(allocator, writer, self.module);
    }
};

const Power = *const fn (i64) callconv(.c) i64;
const Constant = *const fn () callconv(.c) i64;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &stdout.interface;

    var session: Session = undefined;
    try session.init(allocator);
    defer session.deinit(allocator);
    try session.addPower("power13", 13);
    try session.addConstantPower("two13", 2, 13);
    try ir.verifyOperation(session.module, .{});
    try out.writeAll("Before lowering:\n");
    try session.print(allocator, out);

    try lower(allocator, &session.context, session.module);
    try out.writeAll("\nAfter lowering, constant folding, and dead-code elimination:\n");
    try session.print(allocator, out);

    if (!Runtime.available) {
        try out.print("\nNative execution is unavailable here: {s}\n", .{choir.backends.execution.native.reason.?});
        return out.flush();
    }
    var runtime = try Runtime.init(allocator, .testing);
    defer runtime.deinit();
    const handle = try runtime.compile(session.module);
    const power13 = try runtime.getFunction(handle, "power13", Power);
    const two13 = try runtime.getFunction(handle, "two13", Constant);
    try out.print("\npower13(3) = {d}\ntwo13() = {d}\n", .{ power13(3), two13() });
    try out.flush();
}

fn countOperations(module: *ir.Operation, operation_name: []const u8) usize {
    return ir.inspection.countOperationsNamed(module, operation_name);
}

fn repeatedProduct(base: i64, exponent: i64) i64 {
    var product: i64 = 1;
    var remaining = exponent;
    while (remaining > 0) : (remaining -= 1) product *= base;
    return product;
}

test "x^13 lowers to five multiplications and runs natively" {
    const allocator = std.testing.allocator;
    var session: Session = undefined;
    try session.init(allocator);
    defer session.deinit(allocator);
    try session.addPower("power13", 13);
    try lower(allocator, &session.context, session.module);
    try std.testing.expectEqual(0, countOperations(session.module, CalcDialect.PowOp.operation_name));
    try std.testing.expectEqual(5, countOperations(session.module, "arith.mul"));

    if (!Runtime.available) return error.SkipZigTest;
    var runtime = try Runtime.init(allocator, .testing);
    defer runtime.deinit();
    const handle = try runtime.compile(session.module);
    const power13 = try runtime.getFunction(handle, "power13", Power);
    try std.testing.expectEqual(1594323, power13(3));
    try std.testing.expectEqual(8192, power13(2));
}

test "the compiled rewrite agrees with repeated multiplication" {
    const allocator = std.testing.allocator;
    var session: Session = undefined;
    try session.init(allocator);
    defer session.deinit(allocator);
    var names: [16][8]u8 = undefined;
    for (1..17) |exponent| {
        const name = try std.fmt.bufPrint(&names[exponent - 1], "power{d}", .{exponent});
        try session.addPower(name, @intCast(exponent));
    }
    try lower(allocator, &session.context, session.module);

    if (!Runtime.available) return error.SkipZigTest;
    var runtime = try Runtime.init(allocator, .testing);
    defer runtime.deinit();
    const handle = try runtime.compile(session.module);
    for (1..17) |exponent| {
        const name = try std.fmt.bufPrint(&names[exponent - 1], "power{d}", .{exponent});
        const power = try runtime.getFunction(handle, name, Power);
        var base: i64 = -9;
        while (base <= 9) : (base += 1) {
            try std.testing.expectEqual(repeatedProduct(base, @intCast(exponent)), power(base));
        }
    }
}

test "a constant base folds to one constant" {
    const allocator = std.testing.allocator;
    var session: Session = undefined;
    try session.init(allocator);
    defer session.deinit(allocator);
    try session.addConstantPower("two13", 2, 13);
    try lower(allocator, &session.context, session.module);
    try std.testing.expectEqual(0, countOperations(session.module, "arith.mul"));
    try std.testing.expectEqual(1, countOperations(session.module, "arith.constant"));

    if (!Runtime.available) return error.SkipZigTest;
    var runtime = try Runtime.init(allocator, .testing);
    defer runtime.deinit();
    const handle = try runtime.compile(session.module);
    const two13 = try runtime.getFunction(handle, "two13", Constant);
    try std.testing.expectEqual(8192, two13());
}

test "the verifier rejects an exponent below one" {
    const allocator = std.testing.allocator;
    var session: Session = undefined;
    try session.init(allocator);
    defer session.deinit(allocator);
    try session.addPower("power0", 0);
    try std.testing.expectError(error.ExponentBelowOne, ir.verifyOperation(session.module, .{}));
}

test "code generation refuses calc.powi before lowering" {
    if (!Runtime.available) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var session: Session = undefined;
    try session.init(allocator);
    defer session.deinit(allocator);
    try session.addPower("power13", 13);
    var runtime = try Runtime.init(allocator, .testing);
    defer runtime.deinit();
    try std.testing.expectError(error.JitCompileFailed, runtime.compile(session.module));
}
