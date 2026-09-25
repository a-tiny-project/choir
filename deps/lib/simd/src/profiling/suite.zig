const std = @import("std");
const bench = @import("bench");
const sys = @import("sys");
const arithmetic = @import("arithmetic.zig");
const bits = @import("bits.zig");
const layout = @import("layout.zig");
const convert = @import("convert.zig");
const compact = @import("compact.zig");
const crypto = @import("crypto.zig");
const math = @import("math.zig");
const algo = @import("algo.zig");
const bitpack = @import("bitpack.zig");
const dot = @import("dot.zig");
const matmul = @import("matmul.zig");
const hash = @import("hash.zig");
const phast = @import("phast.zig");
const cuckoo = @import("cuckoo.zig");
const cuckoo2x2 = @import("cuckoo2x2.zig");
const shardmul = @import("shardmul.zig");
const matvec = @import("matvec.zig");
const random = @import("random.zig");
const image = @import("image.zig");
const unroller = @import("unroller.zig");
const bitset = @import("bitset.zig");
const robust = @import("robust.zig");
const stats = @import("stats.zig");
const autotune = @import("autotune.zig");
const cache = @import("cache.zig");
const aligned = @import("aligned.zig");
const print = @import("print.zig");
const target = @import("target.zig");
const topology = @import("topology.zig");
const sort = @import("sort.zig");
const thread = @import("thread.zig");

fn benchMinTimeNs(allocator: std.mem.Allocator, default: u64) !u64 {
    const value = try sys.env.getOwned(allocator, "BENCH_MIN_TIME_NS");
    defer if (value) |text| allocator.free(text);
    return if (value) |text| try std.fmt.parseUnsigned(u64, text, 10) else default;
}

test "bench: fixed-width arithmetic and awkward scalar tails" {
    const allocator = sys.allocator.benchmarkAllocator();
    const filter = try sys.env.getOwned(allocator, "BENCH_FILTER");
    defer if (filter) |value| allocator.free(value);

    var suite = bench.Suite.init(allocator, .{
        .min_time_ns = try benchMinTimeNs(allocator, 10_000_000),
        .min_iterations = 5,
        .max_iterations = 200,
        .warmup_iterations = 1,
        .allocation_attribution = .sample_call,
    });
    defer suite.deinit();
    suite.setFilter(filter);

    const prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = arithmetic.prepare,
    };
    try suite.add("simd add scalar u32 x262157", arithmetic.scalarAdd, prepared);
    try suite.add("simd add vector u32x8 x262157", arithmetic.vectorAdd, prepared);
    const bits_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = bits.prepare,
    };
    try suite.add("simd bits scalar u64 x131077", bits.scalarMix, bits_prepared);
    try suite.add("simd bits vector u64x4 x131077", bits.vectorMix, bits_prepared);
    const layout_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = layout.prepare,
    };
    try suite.add("simd layout scalar u32 x131075", layout.scalarInterleave, layout_prepared);
    try suite.add("simd layout vector u32x8 x131075", layout.vectorInterleave, layout_prepared);
    const convert_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = convert.prepare,
    };
    try suite.add("simd convert scalar f32 i32 x262157", convert.scalarConvert, convert_prepared);
    try suite.add("simd convert vector f32x8 i32x8 x262157", convert.vectorConvert, convert_prepared);
    const compact_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = compact.prepare,
    };
    try suite.add("simd compact scalar u32 x262157", compact.scalarCompact, compact_prepared);
    try suite.add("simd compact vector u32x8 x262157", compact.vectorCompact, compact_prepared);
    const crypto_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = crypto.prepare,
    };
    try suite.add("simd AES four rounds u8x16 x65539", crypto.vectorAesRounds, crypto_prepared);
    const math_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = math.prepare,
    };
    try suite.add("simd transcendental chain f64x4 x65536", math.transcendentalChain, math_prepared);
    try suite.add("simd floor division i32x8 x65536", math.floorIntegerDivision, math_prepared);
    try suite.add("simd scalar division u64 x262157", math.scalarUnsignedDivision, math_prepared);
    const algo_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = algo.prepare,
    };
    try suite.add("simd algorithm filter transform i32x8 x262157", algo.filterTransform, algo_prepared);
    const equality_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = algo.prepareEquality,
    };
    try suite.add(algo.equality_std_name, algo.stdEquality, equality_prepared);
    try suite.add(algo.equality_vector_name, algo.vectorEquality, equality_prepared);
    const order_keys_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = algo.prepareOrderKeys,
    };
    try suite.add(algo.order_keys_std_name, algo.stdOrderKeys, order_keys_prepared);
    try suite.add(algo.order_keys_vector_name, algo.vectorOrderKeys, order_keys_prepared);
    const order_spans_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = algo.prepareOrderSpans,
    };
    try suite.add(algo.order_span_std_name, algo.stdOrderSpans, order_spans_prepared);
    try suite.add(algo.order_span_vector_name, algo.vectorOrderSpans, order_spans_prepared);
    const uniform_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = algo.prepareUniformPages,
    };
    try suite.add(algo.uniform_std_name, algo.stdUniformPages, uniform_prepared);
    try suite.add(algo.uniform_vector_name, algo.vectorUniformPages, uniform_prepared);
    const bitpack_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = bitpack.prepare,
    };
    try suite.add("simd Pack16 u16x16 bits13 x2048", bitpack.pack16RoundTrip, bitpack_prepared);
    try suite.add("simd Pack32 u32x8 bits11 x2048", bitpack.pack32RoundTrip, bitpack_prepared);
    try suite.add("simd Pack64 FoR u64x4 bits33 x2048", bitpack.pack64FrameRoundTrip, bitpack_prepared);
    const dot_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = dot.prepare,
    };
    try suite.add("simd dot f32x8 x262157", dot.floating, dot_prepared);
    try suite.add("simd dot bf16x16 x262157", dot.bfloat, dot_prepared);
    const matmul_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = matmul.prepare,
    };
    try suite.add(
        "simd matmul int8-i32 2x2x8 x16384",
        matmul.integer,
        matmul_prepared,
    );
    try suite.add(
        "simd matmul bfloat-f32 2x2x4 x16384",
        matmul.bfloat,
        matmul_prepared,
    );
    const matvec_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = matvec.prepare,
    };
    try suite.add("simd matvec f32x8 257x1027", matvec.floating, matvec_prepared);
    try suite.add("simd matvec bf16-f32 257x1027", matvec.mixed, matvec_prepared);
    try suite.add("simd matvec bf16x16 257x1027", matvec.bfloat, matvec_prepared);
    const random_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = random.prepare,
    };
    try suite.add("simd xoshiro scalar u64 x262157", random.scalar, random_prepared);
    try suite.add("simd xoshiro vector u64x4 x262157", random.vector, random_prepared);
    try suite.add("simd AES counter u64 x65539", random.aesCounter, random_prepared);
    const image_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = image.prepare,
    };
    try suite.add("simd image scalar u32 1027x257", image.scalar, image_prepared);
    try suite.add("simd image vector u32x8 1027x257", image.vector, image_prepared);
    try suite.add("simd image mirror x262157", image.mirrored, image_prepared);
    const unroller_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = unroller.prepare,
    };
    try suite.add("simd unroller scalar i32 x262157", unroller.scalar, unroller_prepared);
    try suite.add("simd unroller native i32 x262157", unroller.vector, unroller_prepared);
    try suite.add("simd unroller reduce native i32 x262157", unroller.reduction, unroller_prepared);
    const bitset_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = bitset.prepare,
    };
    try suite.add("simd bitset flat sparse 64/4096", bitset.flatSparse, bitset_prepared);
    try suite.add("simd bitset atomic sparse 64/4096", bitset.atomicSparse, bitset_prepared);
    try suite.add(
        "simd bitset hierarchical sparse 64/4096",
        bitset.hierarchicalSparse,
        bitset_prepared,
    );
    const robust_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = robust.prepare,
    };
    try suite.add(
        "simd robust mode counting few-unique u64 x1024",
        robust.countingMode,
        robust_prepared,
    );
    try suite.add(
        "simd robust mode comparison sort u64 x1024",
        robust.comparisonMode,
        robust_prepared,
    );
    try suite.add(
        "simd robust median absolute deviation u64 x1024",
        robust.medianAbsoluteDeviation,
        robust_prepared,
    );
    const stats_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = stats.prepare,
    };
    try suite.add(
        "simd stats online moments f32 x4096",
        stats.onlineMoments,
        stats_prepared,
    );
    try suite.add(
        "simd stats assimilate 64 shards x64",
        stats.assimilatedMoments,
        stats_prepared,
    );
    try suite.add(
        "simd stats histogram 64 bins x4096",
        stats.histogram,
        stats_prepared,
    );
    const autotune_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = autotune.prepare,
    };
    try suite.add(
        "simd auto-tune cost distribution x4096",
        autotune.costDistribution,
        autotune_prepared,
    );
    try suite.add(
        "simd auto-tune packed skip list x4096",
        autotune.skipList,
        autotune_prepared,
    );
    try suite.add(
        "simd auto-tune exhaustive 256 candidates",
        autotune.exhaustiveTuning,
        autotune_prepared,
    );
    const cache_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = cache.prepare,
    };
    try suite.add(
        "simd cache stream 4096 lines x128 bytes",
        cache.streamLines,
        cache_prepared,
    );
    try suite.add(
        "simd cache control cycle x4096",
        cache.controlCycle,
        cache_prepared,
    );
    const aligned_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = aligned.prepare,
    };
    try suite.add(
        "simd aligned allocation 65536 u64",
        aligned.allocationLifecycle,
        aligned_prepared,
    );
    try suite.add(
        "simd aligned row traversal 16^4 u32",
        aligned.rowTraversal,
        aligned_prepared,
    );
    try suite.add(
        "simd aligned vector growth 4096 u64",
        aligned.vectorGrowth,
        aligned_prepared,
    );
    const print_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = print.prepare,
    };
    try suite.add(
        "simd diagnostic scalar formatting x4096",
        print.scalarValues,
        print_prepared,
    );
    try suite.add(
        "simd diagnostic vector windows u32x8 x1024",
        print.vectorWindows,
        print_prepared,
    );
    const target_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = target.prepare,
    };
    try suite.add(
        "simd runtime target detection x4096",
        target.detection,
        target_prepared,
    );
    try suite.add(
        "simd runtime target dispatch x65536",
        target.selection,
        target_prepared,
    );
    try suite.add(
        "simd cached target dispatch x262144",
        target.cachedSelection,
        target_prepared,
    );
    const topology_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = topology.prepare,
    };
    try suite.add(
        "simd topology assembly 256 LP",
        topology.assembly,
        topology_prepared,
    );
    try suite.add(
        "simd topology affinity read x4096",
        topology.affinity,
        topology_prepared,
    );
    try suite.add(
        "simd topology cached cache geometry x262144",
        topology.cachedCaches,
        topology_prepared,
    );
    const sort_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = sort.prepare,
    };
    try suite.add(
        "simd VQSort base network u32 x256",
        sort.baseU32,
        sort_prepared,
    );
    try suite.add(
        "simd VQSort base network K64V64 x64",
        sort.baseK64V64,
        sort_prepared,
    );
    try suite.add(
        "simd VQSort public sort u32 x65536",
        sort.publicSortU32,
        sort_prepared,
    );
    try suite.add(
        "simd VQSort public partial u32 x65536 k16384",
        sort.publicPartialU32,
        sort_prepared,
    );
    try suite.add(
        "simd VQSort public select u32 x65536 k32768",
        sort.publicSelectU32,
        sort_prepared,
    );
    const thread_block_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = thread.prepareBlock,
        .teardown = thread.teardown,
    };
    try suite.add(
        "simd thread pool block static 8",
        thread.blockStatic,
        thread_block_prepared,
    );
    try suite.add(
        "simd thread pool block dynamic 8x257",
        thread.blockDynamic,
        thread_block_prepared,
    );
    const thread_spin_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = thread.prepareSpin,
        .teardown = thread.teardown,
    };
    try suite.add(
        "simd thread pool spin static 8",
        thread.spinStatic,
        thread_spin_prepared,
    );
    try suite.add(
        "simd thread pool spin dynamic 8x257",
        thread.spinDynamic,
        thread_spin_prepared,
    );
    const hash_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = hash.prepare,
    };
    try suite.add("simd Triple32 scalar u32 x262157", hash.scalar32, hash_prepared);
    try suite.add("simd Lemire reduction u32 x262157", hash.lemire32, hash_prepared);
    try suite.add("simd Triple32 vector u32x8 x262157", hash.vector32, hash_prepared);
    try suite.add("simd Moremur scalar u64 x262157", hash.scalar64, hash_prepared);
    try suite.add("simd Moremur vector u64x4 x262157", hash.vector64, hash_prepared);
    const phast_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = phast.prepare,
    };
    try suite.add("simd PHAST scalar u32 x262157", phast.scalar, phast_prepared);
    try suite.add("simd PHAST vector u32x8 x262157", phast.vector, phast_prepared);
    try suite.add("simd PHAST build 500", phast.build, phast_prepared);
    const cuckoo_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = cuckoo.prepare,
    };
    try suite.add("simd Cuckoo build 60000", cuckoo.buildDefault, cuckoo_prepared);
    try suite.add("simd Cuckoo maximum matching 60000", cuckoo.buildMaximum, cuckoo_prepared);
    try suite.add("simd Cuckoo minimum cost 63000", cuckoo.buildMinimumCost, cuckoo_prepared);
    try suite.add("simd Cuckoo local search 60000", cuckoo.buildLocalSearch, cuckoo_prepared);
    try suite.add("simd Cuckoo scalar u32 x262157", cuckoo.scalar, cuckoo_prepared);
    try suite.add("simd Cuckoo batch u32x8 x262157", cuckoo.batch, cuckoo_prepared);
    try suite.add(
        "simd Cuckoo batch precomputed u32x8 x262157",
        cuckoo.batchPrecomputed,
        cuckoo_prepared,
    );
    try suite.add("simd Cuckoo u16 scalar u32 x262157", cuckoo.scalarU16, cuckoo_prepared);
    try suite.add("simd Cuckoo u16 batch u32x8 x262157", cuckoo.batchU16, cuckoo_prepared);
    try suite.add("simd Cuckoo u16 convert 4194304", cuckoo.convertU16, cuckoo_prepared);
    const cuckoo2x2_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = cuckoo2x2.prepare,
    };
    try suite.add("simd Cuckoo2x2 scalar u32 x262157", cuckoo2x2.scalar, cuckoo2x2_prepared);
    try suite.add("simd Cuckoo2x2 vector u32x8 x262157", cuckoo2x2.vector, cuckoo2x2_prepared);
    try suite.add("simd Cuckoo2x2 build 60000", cuckoo2x2.build, cuckoo2x2_prepared);
    const shardmul_prepared = .{
        .evaluation = @as(bench.Evaluation, .{ .fixed = 1 }),
        .prepare = shardmul.prepare,
    };
    try suite.add("simd ShardMul scalar u64 x262157", shardmul.scalar, shardmul_prepared);
    try suite.add("simd ShardMul vector u64x8 x262157", shardmul.vector, shardmul_prepared);
    try suite.add("simd ShardMul build 8192+1024", shardmul.build, shardmul_prepared);
    try suite.run();
    try algo.writeEqualityGates(suite.results.items);
}
