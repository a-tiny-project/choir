const std = @import("std");
const hypothesis = @import("hypothesis");

pub fn drawUsize(
    conjecture: *hypothesis.ConjectureData,
    min: usize,
    max: usize,
    shrink_towards: usize,
) !usize {
    return @intCast(try conjecture.drawInteger(
        @intCast(min),
        @intCast(max),
        @intCast(shrink_towards),
    ));
}

pub fn drawAlignment(conjecture: *hypothesis.ConjectureData) !std.mem.Alignment {
    const shift = try drawUsize(conjecture, 0, 15, 0);
    return .fromByteUnits(@as(usize, 1) << @as(u6, @intCast(shift)));
}
