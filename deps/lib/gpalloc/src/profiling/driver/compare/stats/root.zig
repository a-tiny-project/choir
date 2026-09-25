const bench = @import("bench");
const compute = @import("compute.zig");
const model = @import("model.zig");

pub const Verdict = model.Verdict;
pub const Result = model.Result;
pub const ComparisonLimits = bench.ComparisonLimits;
pub const ComparisonCapacity = bench.ComparisonCapacity;
pub const ComparisonCapacityError = bench.ComparisonCapacityError;
pub const ComparisonStorage = bench.ComparisonStorage;
pub const ComparisonStorageStatus = bench.ComparisonStorageStatus;
pub const ComparisonStorageExhaustion = bench.ComparisonStorageExhaustion;
pub const ComparisonError = bench.ComparisonError;
pub const compareSeries = compute.compareSeries;
