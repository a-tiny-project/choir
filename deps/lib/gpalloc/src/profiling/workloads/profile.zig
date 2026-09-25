const parameters = @import("parameters.zig");

pub const Profile = enum {
    native,
    preload,
};

pub fn phase(comptime profile: Profile, comptime name: []const u8) []const u8 {
    const workload = switch (profile) {
        .native => "rocksdb_fillrandom_trace",
        .preload => "rocksdb_fillrandom_preload_trace",
    };
    return "gpalloc.phase." ++ workload ++ "." ++ name;
}

pub fn size(comptime profile: Profile, len: usize) usize {
    return switch (profile) {
        .native => len,
        .preload => preloadFastTotalLen(len),
    };
}

pub fn optionsSize(index: usize) usize {
    const sizes = [_]usize{ 64, 96, 160, 256, 512, 768, 1024, 2048 };
    return sizes[index % sizes.len];
}

fn preloadFastTotalLen(len: usize) usize {
    const with_header = len + parameters.rocksdb_trace_preload_header_bytes;
    return @max(with_header, parameters.rocksdb_trace_preload_min_bytes);
}
