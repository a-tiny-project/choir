const std = @import("std");
const model = @import("model.zig");

const fanout = @import("fanout.zig");
const aligned = @import("aligned.zig");
const allocation = @import("allocation.zig");
const barnes = @import("barnes.zig");
const cache = @import("cache.zig");
const cfrac = @import("cfrac.zig");
const churn = @import("churn.zig");
const compiler = @import("compiler.zig");
const document = @import("document.zig");
const espresso = @import("espresso.zig");
const foreign = @import("foreign.zig");
const handoff = @import("handoff.zig");
const large = @import("large.zig");
const larson_workload = @import("larson.zig");
const mstress = @import("mstress.zig");
const pareto = @import("pareto.zig");
const parallel = @import("parallel.zig");
const survivors = @import("survivors.zig");
const producer = @import("producer.zig");
const redis = @import("redis.zig");
const ring = @import("ring.zig");
const reverse = @import("reverse.zig");
const rocksdb = @import("rocksdb.zig");
const server = @import("server.zig");
const solver = @import("solver.zig");
const latency = @import("latency.zig");

const Workload = model.Workload;

pub const all = [_]Workload{
    .{ .id = "small_churn", .name = "small alloc/free x256", .run = smallChurn },
    .{ .id = "retained_bursts", .name = "retained burst reuse", .run = repeatedBursts },
    .{ .id = "mixed_realloc", .name = "mixed realloc churn", .run = mixedSizeChurn },
    .{ .id = "realloc_in_place", .name = "in-place realloc x256", .run = reallocInPlace },
    .{ .id = "large_direct", .name = "large direct x128", .run = largeDirect },
    .{ .id = "large_cache_pressure", .name = "large cache pressure x64", .run = largeCachePressure },
    .{ .id = "huge_cache_pressure", .name = "huge cache pressure x40", .run = hugeCachePressure },
    .{ .id = "parallel_same_class", .name = "parallel same-class x256", .run = parallelSameClass },
    .{ .id = "parallel_mixed_classes", .name = "parallel mixed-classes x256", .run = parallelMixedClasses },
    .{ .id = "thread_churn", .name = "short-lived thread churn x128", .run = threadChurn },
    .{ .id = "larson", .name = "Larson server simulator x16384", .run = larson },
    .{ .id = "larson_preload_trace", .name = "Larson preload header trace x40000", .run = larsonPreloadTrace },
    .{ .id = "active_fanout", .name = "active thread-cache fanout x256", .run = activeFanout },
    .{ .id = "producer_consumer", .name = "producer-consumer x128", .run = producerConsumer },
    .{ .id = "producer_reuse_trace", .name = "producer remote-free reuse trace x8192", .run = producerReuseTrace },
    .{ .id = "remote_ring", .name = "remote ring x256", .run = remoteRing },
    .{ .id = "working_set_churn", .name = "working-set churn x1024", .run = workingSetChurn },
    .{ .id = "working_set_steady", .name = "steady working-set churn x2048", .run = workingSetSteady },
    .{ .id = "false_sharing", .name = "passive false-sharing churn x4096", .run = falseSharing },
    .{ .id = "asymmetric_handoff", .name = "asymmetric producer handoff x1024", .run = asymmetricHandoff },
    .{ .id = "pareto_size_mix", .name = "Pareto size/lifetime mix x4096", .run = paretoSizeMix },
    .{ .id = "phase_survivors", .name = "phase survivor fragmentation x1536", .run = phaseSurvivors },
    .{ .id = "aligned_mix", .name = "over-aligned allocation mix x256", .run = alignedMix },
    .{ .id = "tail_latency", .name = "refill tail-latency pressure x2048", .run = tailLatency },
    .{ .id = "cfrac_trace", .name = "cfrac precision arithmetic trace x4096", .run = cfracTrace },
    .{ .id = "espresso_trace", .name = "espresso sparse cover trace x6144", .run = espressoTrace },
    .{ .id = "compiler_trace", .name = "compiler allocation trace x3584", .run = compilerTrace },
    .{ .id = "server_trace", .name = "server list allocation trace x1024", .run = serverTrace },
    .{ .id = "redis_trace", .name = "Redis list benchmark trace x1024", .run = redisTrace },
    .{ .id = "solver_trace", .name = "solver backtracking trace x1536", .run = solverTrace },
    .{ .id = "document_trace", .name = "document rendering trace x1248", .run = documentTrace },
    .{ .id = "barnes_trace", .name = "Barnes tree table trace x1024 bodies", .run = barnesTrace },
    .{ .id = "rocksdb_fillrandom_trace", .name = "RocksDB fillrandom trace x4 memtables", .run = rocksdbFillrandomTrace },
    .{ .id = "rocksdb_fillrandom_preload_trace", .name = "RocksDB fillrandom preload trace x4 memtables", .run = rocksdbFillrandomPreloadTrace },
    .{ .id = "reverse_free_trace", .name = "MicroQuill sh6 reverse-free trace x1024 slots", .run = reverseFreeTrace },
    .{ .id = "reverse_free_preload_trace", .name = "MicroQuill sh6 preload reverse-free trace x1024 slots", .run = reverseFreePreloadTrace },
    .{ .id = "foreign_free_trace", .name = "MicroQuill sh8 foreign-free trace x2x1024 slots", .run = foreignFreeTrace },
    .{ .id = "foreign_free_preload_trace", .name = "MicroQuill sh8 preload foreign-free trace x2x1024 slots", .run = foreignFreePreloadTrace },
    .{ .id = "sh8_preload_trace", .name = "MicroQuill sh8 preload local trace x29284", .run = sh8PreloadTrace },
    .{ .id = "mstress_trace", .name = "server phase migration trace x9216", .run = mstressTrace },
};

pub const detail = [_]Workload{
    .{ .id = "realloc_mixed_sparse", .name = "mixed sparse realloc x1024", .run = reallocMixedSparse },
    .{ .id = "realloc_cross_class", .name = "cross-class realloc x512", .run = reallocCrossClass },
    .{ .id = "active_fanout_full", .name = "active thread-cache fanout x32768", .run = activeFanoutFull },
    .{ .id = "remote_ring_full", .name = "remote ring x8192", .run = remoteRingFull },
    .{ .id = "working_set_steady_full", .name = "steady working-set churn x262144", .run = workingSetSteadyFull },
    .{ .id = "working_set_steady_16_full", .name = "steady 16-byte working-set churn x262144", .run = workingSetSteady16Full },
    .{ .id = "local_cache_16", .name = "local 16-byte cache churn x16384", .run = localCache16 },
    .{ .id = "local_cache_48", .name = "local 48-byte cache churn x16384", .run = localCache48 },
    .{ .id = "oversubscribed_cache", .name = "oversubscribed thread-cache churn x2048", .run = oversubscribedCache },
    .{ .id = "alloc_test_trace", .name = "alloc-test Pareto full-touch trace x131072", .run = allocTestTrace },
    .{ .id = "alloc_test_preload_trace", .name = "alloc-test preload Pareto full-touch trace x131072", .run = allocTestPreloadTrace },
    .{ .id = "alloc_test_preload_threaded_trace", .name = "alloc-test preload threaded trace x2x131072", .run = allocTestPreloadThreadedTrace },
    .{ .id = "phase_survivors_full", .name = "phase survivor fragmentation x6144", .run = phaseSurvivorsFull },
    .{ .id = "reverse_free_threaded_trace", .name = "MicroQuill sh6 threaded trace x2x5000 slots", .run = reverseFreeThreadedTrace },
    .{ .id = "foreign_free_detail_trace", .name = "MicroQuill sh8 foreign-free trace x2x4096 slots", .run = foreignFreeDetailTrace },
    .{ .id = "sh8_preload_detail_trace", .name = "MicroQuill sh8 preload detail trace x2x32768 slots", .run = sh8PreloadDetailTrace },
    .{ .id = "xmalloc_preload_trace", .name = "xmalloc preload producer-consumer trace x2x4096", .run = xmallocPreloadTrace },
};

pub const activeFanout = fanout.run;
pub const activeFanoutFull = fanout.full;
pub const alignedMix = aligned.run;
pub const asymmetricHandoff = handoff.asymmetricHandoff;
pub const allocTestPreloadThreadedTrace = allocation.allocTestPreloadThreadedTrace;
pub const allocTestPreloadTrace = allocation.allocTestPreloadTrace;
pub const allocTestTrace = allocation.allocTestTrace;
pub const barnesTrace = barnes.run;
pub const cfracTrace = cfrac.run;
pub const mixedSizeChurn = churn.mixedSizeChurn;
pub const reallocCrossClass = churn.reallocCrossClass;
pub const reallocInPlace = churn.reallocInPlace;
pub const reallocMixedSparse = churn.reallocMixedSparse;
pub const repeatedBursts = churn.repeatedBursts;
pub const smallChurn = churn.smallChurn;
pub const compilerTrace = compiler.run;
pub const documentTrace = document.run;
pub const espressoTrace = espresso.run;
pub const falseSharing = handoff.falseSharing;
pub const foreignFreeDetailTrace = foreign.foreignFreeDetailTrace;
pub const foreignFreePreloadTrace = foreign.foreignFreePreloadTrace;
pub const foreignFreeTrace = foreign.foreignFreeTrace;
pub const hugeCachePressure = large.hugeCachePressure;
pub const larson = larson_workload.run;
pub const larsonPreloadTrace = larson_workload.preloadTrace;
pub const largeCachePressure = large.cachePressure;
pub const largeDirect = large.direct;
pub const localCache16 = cache.localCache16;
pub const localCache48 = cache.localCache48;
pub const mstressTrace = mstress.run;
pub const oversubscribedCache = cache.oversubscribedCache;
pub const parallelMixedClasses = parallel.mixedClasses;
pub const parallelSameClass = parallel.sameClass;
pub const paretoSizeMix = pareto.sizeMix;
pub const phaseSurvivors = survivors.run;
pub const phaseSurvivorsFull = survivors.full;
pub const producerConsumer = producer.consumer;
pub const producerReuseTrace = producer.reuseTrace;
pub const threadChurn = parallel.threadChurn;
pub const redisTrace = redis.run;
pub const remoteRing = ring.run;
pub const remoteRingFull = ring.full;
pub const reverseFreePreloadTrace = reverse.reverseFreePreloadTrace;
pub const reverseFreeThreadedTrace = reverse.reverseFreeThreadedTrace;
pub const reverseFreeTrace = reverse.reverseFreeTrace;
pub const rocksdbFillrandomPreloadTrace = rocksdb.rocksdbFillrandomPreloadTrace;
pub const rocksdbFillrandomTrace = rocksdb.rocksdbFillrandomTrace;
pub const serverTrace = server.run;
pub const sh8PreloadDetailTrace = foreign.sh8PreloadDetailTrace;
pub const sh8PreloadTrace = foreign.sh8PreloadTrace;
pub const solverTrace = solver.run;
pub const tailLatency = latency.run;
pub const workingSetChurn = cache.workingSetChurn;
pub const workingSetSteady = cache.workingSetSteady;
pub const workingSetSteadyFull = cache.workingSetSteadyFull;
pub const workingSetSteady16Full = cache.workingSetSteady16Full;
pub const xmallocPreloadTrace = producer.xmallocPreloadTrace;

pub fn byId(id: []const u8) ?Workload {
    for (all) |workload| {
        if (std.mem.eql(u8, workload.id, id)) return workload;
    }
    for (detail) |workload| {
        if (std.mem.eql(u8, workload.id, id)) return workload;
    }
    return null;
}
