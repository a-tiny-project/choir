const profiling = @import("profiling");

pub fn main() !void {
    try profiling.record.run();
}
