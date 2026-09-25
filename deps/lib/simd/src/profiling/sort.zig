const std = @import("std");
const bench = @import("bench");
const simd = @import("simd");

const u32_count: usize = 256;
const kv_count: usize = 64;
const public_count: usize = 65_536;
const partial_count: usize = public_count / 4;
const select_index: usize = public_count / 2;

var u32_source: [u32_count]u32 = undefined;
var u32_work: [u32_count]u32 = undefined;
var kv_source: [kv_count]simd.K64V64 = undefined;
var kv_work: [kv_count]simd.K64V64 = undefined;
var public_source: [public_count]u32 = undefined;
var public_work: [public_count]u32 = undefined;
var scratch = simd.sort.testing.Scratch{};
var expected_u32: u64 = 0;
var expected_kv: u64 = 0;
var expected_public: u64 = 0;
var expected_partial: u64 = 0;
var expected_selected: u32 = 0;

pub fn prepare(_: std.mem.Allocator) void {
    var state = simd.sort.testing.RandomState.init(0x5352_5433_3255, 0x4b56_3634_5636_34);
    for (&u32_source) |*value| value.* = @truncate(state.next());
    for (&kv_source) |*value| value.* = .{
        .value = state.next(),
        .key = state.next(),
    };
    for (&public_source) |*value| value.* = @truncate(state.next());
    @memcpy(&u32_work, &u32_source);
    simd.sort.testing.networkSort(u32, .ascending, &u32_work, &scratch) catch
        @panic("VQSort u32 benchmark preparation failed");
    expected_u32 = integerDigest(&u32_work);
    @memcpy(&kv_work, &kv_source);
    simd.sort.testing.networkSort(simd.K64V64, .descending, &kv_work, &scratch) catch
        @panic("VQSort KV benchmark preparation failed");
    expected_kv = keyValueDigest(&kv_work);
    @memcpy(&public_work, &public_source);
    std.mem.sort(u32, &public_work, {}, ascendingU32);
    expected_public = integerDigest(&public_work);
    expected_partial = integerDigest(public_work[0..partial_count]);
    expected_selected = public_work[select_index];
}

pub fn baseU32(_: std.mem.Allocator) void {
    @memcpy(&u32_work, &u32_source);
    const phase = bench.phaseAt("simd.vqsort.base.u32", @src());
    simd.sort.testing.networkSort(u32, .ascending, &u32_work, &scratch) catch
        @panic("VQSort u32 benchmark failed");
    phase.end();
    if (integerDigest(&u32_work) != expected_u32) @panic("VQSort u32 witness failed");
    std.mem.doNotOptimizeAway(&u32_work);
    bench.coz.progressNamed("simd.vqsort.base.u32.complete");
}

pub fn baseK64V64(_: std.mem.Allocator) void {
    @memcpy(&kv_work, &kv_source);
    const phase = bench.phaseAt("simd.vqsort.base.k64v64", @src());
    simd.sort.testing.networkSort(simd.K64V64, .descending, &kv_work, &scratch) catch
        @panic("VQSort KV benchmark failed");
    phase.end();
    if (keyValueDigest(&kv_work) != expected_kv) @panic("VQSort KV witness failed");
    std.mem.doNotOptimizeAway(&kv_work);
    bench.coz.progressNamed("simd.vqsort.base.k64v64.complete");
}

pub fn publicSortU32(_: std.mem.Allocator) void {
    @memcpy(&public_work, &public_source);
    const phase = bench.phaseAt("simd.vqsort.public.sort.u32", @src());
    simd.vqSort(u32, .ascending, &public_work);
    phase.end();
    if (integerDigest(&public_work) != expected_public) @panic("VQSort public sort witness failed");
    std.mem.doNotOptimizeAway(&public_work);
    bench.coz.progressNamed("simd.vqsort.public.sort.u32.complete");
}

pub fn publicPartialU32(_: std.mem.Allocator) void {
    @memcpy(&public_work, &public_source);
    const phase = bench.phaseAt("simd.vqsort.public.partial.u32", @src());
    simd.vqPartialSort(u32, .ascending, &public_work, partial_count) catch
        @panic("VQSort public partial witness failed");
    phase.end();
    if (integerDigest(public_work[0..partial_count]) != expected_partial) {
        @panic("VQSort public partial digest failed");
    }
    std.mem.doNotOptimizeAway(&public_work);
    bench.coz.progressNamed("simd.vqsort.public.partial.u32.complete");
}

pub fn publicSelectU32(_: std.mem.Allocator) void {
    @memcpy(&public_work, &public_source);
    const phase = bench.phaseAt("simd.vqsort.public.select.u32", @src());
    simd.vqSelect(u32, .ascending, &public_work, select_index) catch
        @panic("VQSort public select witness failed");
    phase.end();
    if (public_work[select_index] != expected_selected) @panic("VQSort public select value failed");
    std.mem.doNotOptimizeAway(&public_work);
    bench.coz.progressNamed("simd.vqsort.public.select.u32.complete");
}

fn ascendingU32(_: void, a: u32, b: u32) bool {
    return a < b;
}

fn integerDigest(values: []const u32) u64 {
    var digest: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| digest = (digest ^ value) *% 0x0000_0100_0000_01b3;
    return digest;
}

fn keyValueDigest(values: []const simd.K64V64) u64 {
    var digest: u64 = 0xcbf2_9ce4_8422_2325;
    for (values) |value| {
        digest = (digest ^ value.key) *% 0x0000_0100_0000_01b3;
        digest = (digest ^ value.value) *% 0x0000_0100_0000_01b3;
    }
    return digest;
}
