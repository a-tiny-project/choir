pub const Entry = struct {
    size: usize,
    count: usize,
};

pub const values = [_]Entry{
    .{ .size = 8, .count = 1000 },
    .{ .size = 16, .count = 5000 },
    .{ .size = 48, .count = 1000 },
    .{ .size = 72, .count = 100 },
    .{ .size = 148, .count = 100 },
    .{ .size = 200, .count = 100 },
    .{ .size = 520, .count = 10 },
    .{ .size = 1056, .count = 5 },
    .{ .size = 4096, .count = 3 },
    .{ .size = 9162, .count = 1 },
    .{ .size = 34562, .count = 1 },
    .{ .size = 168524, .count = 1 },
};
