const std = @import("std");
const sys = @import("sys");
const gpalloc = @import("gpalloc");

const options = @import("options.zig");

pub const Selected = struct {
    storage: gpalloc.GpAllocator = undefined,
    owns_storage: bool = false,
    allocator: std.mem.Allocator = undefined,
};

pub fn init(selected: *Selected, mode: options.AllocatorMode, collect_stats: bool) void {
    selected.* = .{};
    selected.allocator = switch (mode) {
        .gpalloc => initGpalloc(selected, .{}, collect_stats),
        .gpalloc_limited_thread_caches => initGpalloc(selected, .{
            .thread_cache_active_limit = 2,
        }, collect_stats),
        .gpalloc_unlimited_thread_caches => initGpalloc(selected, .{
            .thread_cache_active_limit = std.math.maxInt(usize),
        }, collect_stats),
        .gpalloc_no_thread_exit_flush => initGpalloc(selected, .{
            .flush_thread_cache_on_thread_exit = false,
        }, collect_stats),
        .gpalloc_no_large_cache => initGpalloc(selected, .{
            .large_cache = false,
        }, collect_stats),
        .gpalloc_os_pages => initGpalloc(selected, .{
            .page_provider = .os,
        }, collect_stats),
        .gpalloc_os_discard => initGpalloc(selected, .{
            .page_provider = .os,
            .retained_empty_page_policy = .discard_unused,
        }, collect_stats),
        .gpalloc_release_empty => initGpalloc(selected, .{
            .empty_page_retention_limit = 0,
        }, collect_stats),
        .smp => std.heap.smp_allocator,
        .system => systemAllocator(),
    };
}

pub fn deinit(selected: *Selected) void {
    if (selected.owns_storage) selected.storage.deinit();
    selected.owns_storage = false;
}

pub fn stats(selected: *Selected) ?gpalloc.Stats {
    if (!selected.owns_storage) return null;
    return selected.storage.stats();
}

fn initGpalloc(selected: *Selected, config: gpalloc.Config, collect_stats: bool) std.mem.Allocator {
    var effective = config;
    effective.collect_stats = collect_stats;
    selected.storage = gpalloc.GpAllocator.init(systemAllocator(), effective);
    selected.owns_storage = true;
    return selected.storage.allocator();
}

fn systemAllocator() std.mem.Allocator {
    return sys.allocator.requiredHostInteropAllocator("gpalloc benchmark driver");
}
