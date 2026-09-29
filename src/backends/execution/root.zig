//! One execution contract for every target that runs compiled Choir code.
//!
//! A consumer builds `native.Runtime` with its limits, compiles or loads modules into it, and
//! calls them through a checked pointer or a checked call. It never names an instruction set.
//! The same source compiles on every host. Where the host has no target, `init` fails with
//! `error.ExecutionUnavailable` and `native.reason` says why.

const host = @import("host.zig");
const image = @import("image.zig");
const runtime = @import("runtime.zig");
const target = @import("target.zig");
const value = @import("value.zig");

pub const Limits = @import("limits.zig").Limits;
pub const Handle = image.Handle;
pub const Emitted = image.Emitted;
pub const Value = value.Value;
pub const Vector = value.Vector;
pub const check = value.check;
pub const agrees = value.agrees;

pub const Runtime = runtime.Runtime;
pub const Refusal = runtime.Refusal;
pub const UnavailableError = runtime.UnavailableError;
pub const CapacityError = runtime.CapacityError;
pub const HandleError = runtime.HandleError;
pub const LookupError = runtime.LookupError;
pub const CallError = runtime.CallError;
pub const SymbolError = runtime.SymbolError;
pub const InitError = runtime.InitError;
pub const LoadError = runtime.LoadError;
pub const CompileError = runtime.CompileError;

pub const assertTarget = target.assertTarget;
pub const Unavailable = target.Unavailable;
pub const Builtin = target.Builtin;
pub const Failure = target.Failure;
pub const LowerError = target.LowerError;

pub const native = host.native;
pub const Select = host.Select;
pub const reason = host.reason;
