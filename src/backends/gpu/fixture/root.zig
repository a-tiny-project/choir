//! Shared support for the gpu emitter tests: textual kernels and the stage
//! modules that every stage emitter and the SPIR-V validation gate read.

const text = @import("text.zig");

pub const stages = @import("stages.zig");

pub const parse = text.parse;
pub const lower = text.lower;
pub const emitText = text.emitText;
pub const expectContains = text.expectContains;
pub const expectAbsent = text.expectAbsent;
