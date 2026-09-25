//! Measured memory claims for build lanes, derived from Loom receipts.
//!
//! `loom ledger requirements` writes `measured.requirements` from the tree
//! peaks that receipts record. The build lowers a defaulted ordinary lane to
//! its measured claim only when the registry explicitly permits replay. A
//! lane the table omits or leaves unmarked keeps the policy default.

const std = @import("std");
const requirements = @import("requirements.zig");

pub const evidence_ref = "build/api/src/measured.requirements";
pub const entry_capacity: usize = requirements.lane_capacity;
pub const samples_min: u32 = 5;
pub const claim_floor_mib: u64 = 1024;
pub const claim_quantum_mib: u64 = 512;
/// The durable receipt step label has this fixed maximum byte length.
pub const receipt_step_bytes_max: usize = 512;

const table_text = @embedFile("measured.requirements");
const table_bytes_max: usize = 128 * 1024;
const field_count: usize = 5;

pub const Entry = struct {
    directory: []const u8,
    step: []const u8,
    memory_mib: u32,
};

pub const ParseError = error{
    DuplicateOrUnsorted,
    InvalidClaim,
    InvalidField,
    InvalidPeak,
    InvalidSamples,
    TooManyEntries,
    WrongFieldCount,
};

const table: []const Entry = parsed: {
    if (table_text.len > table_bytes_max) {
        @compileError("measured requirements exceed their byte bound");
    }
    break :parsed parse(table_text) catch |err|
        @compileError("invalid measured requirements: " ++ @errorName(err));
};

/// Returns the lowered requirement for one lane, or null when the table has
/// no entry for it, replay is not permitted, the requirement was declared by
/// its package, or the measured claim would not lower it.
pub fn lower(
    requirement: requirements.Requirement,
    directory: []const u8,
    step: []const u8,
) ?requirements.Requirement {
    return lowerIn(table, requirement, directory, step);
}

pub fn entries() []const Entry {
    return table;
}

/// Returns the memory claim that covers a measured peak: the peak plus half,
/// rounded up to whole claim quanta and at least the claim floor.
pub fn marginClaimMib(peak_kib: u64) u64 {
    std.debug.assert(peak_kib > 0);
    const margin_kib = peak_kib +| peak_kib / 2;
    const margin_mib = std.math.divCeil(u64, margin_kib, 1024) catch unreachable;
    const quanta = std.math.divCeil(u64, margin_mib, claim_quantum_mib) catch unreachable;
    return @max(claim_floor_mib, quanta *| claim_quantum_mib);
}

pub fn claimForPeak(peak_kib: u64) ?u32 {
    if (peak_kib == 0) return null;
    const claim = marginClaimMib(peak_kib);
    const default_mib = requirements.defaultRequirement(.ordinary).memory_mib;
    return if (claim < default_mib) @intCast(claim) else null;
}

fn lowerIn(
    measured: []const Entry,
    requirement: requirements.Requirement,
    directory: []const u8,
    step: []const u8,
) ?requirements.Requirement {
    std.debug.assert(requirement.valid());
    if (requirement.class != .ordinary) return null;
    if (!requirement.replay_safe) return null;
    if (requirement.evidence_kind != .defaulted) return null;
    if (requirement.memory_bytes != null) return null;
    const claim = lookup(measured, directory, step) orelse return null;
    if (claim >= requirement.memory_mib) return null;
    var lowered = requirement;
    lowered.memory_mib = claim;
    lowered.evidence_kind = .measured;
    lowered.evidence_ref = evidence_ref;
    std.debug.assert(lowered.valid());
    return lowered;
}

fn lookup(measured: []const Entry, directory: []const u8, step: []const u8) ?u32 {
    const Key = struct { directory: []const u8, step: []const u8 };
    const index = std.sort.binarySearch(
        Entry,
        measured,
        Key{ .directory = directory, .step = step },
        struct {
            fn compare(key: Key, entry: Entry) std.math.Order {
                return order(key.directory, key.step, entry);
            }
        }.compare,
    ) orelse return null;
    return measured[index].memory_mib;
}

fn order(directory: []const u8, step: []const u8, entry: Entry) std.math.Order {
    const by_directory = std.mem.order(u8, directory, entry.directory);
    if (by_directory != .eq) return by_directory;
    return std.mem.order(u8, step, entry.step);
}

/// Parses the table at compile time. Each line holds a directory, a step, a
/// claim in MiB, a receipt count, and the peak tree RSS in KiB, separated by
/// tabs and sorted by directory then step. `#` starts a comment line.
fn parse(comptime text: []const u8) ParseError![]const Entry {
    @setEvalBranchQuota(4_000_000);
    const default_mib = requirements.defaultRequirement(.ordinary).memory_mib;
    var values: [entry_capacity]Entry = undefined;
    var count: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var fields: [field_count][]const u8 = undefined;
        var parts = std.mem.splitScalar(u8, line, '\t');
        var index: usize = 0;
        while (parts.next()) |part| : (index += 1) {
            if (index == field_count) return error.WrongFieldCount;
            fields[index] = part;
        }
        if (index != field_count) return error.WrongFieldCount;
        if (!eligibleIdentity(fields[0], fields[1])) return error.InvalidField;
        const claim = std.fmt.parseUnsigned(u32, fields[2], 10) catch
            return error.InvalidClaim;
        if (claim == 0 or claim >= default_mib) return error.InvalidClaim;
        const samples = std.fmt.parseUnsigned(u32, fields[3], 10) catch
            return error.InvalidSamples;
        if (samples < samples_min) return error.InvalidSamples;
        const peak_kib = std.fmt.parseUnsigned(u64, fields[4], 10) catch
            return error.InvalidPeak;
        if (peak_kib == 0) return error.InvalidPeak;
        if (claimForPeak(peak_kib) != claim) return error.InvalidClaim;
        if (count == entry_capacity) return error.TooManyEntries;
        const entry = Entry{
            .directory = fields[0],
            .step = fields[1],
            .memory_mib = claim,
        };
        if (count > 0 and order(entry.directory, entry.step, values[count - 1]) != .gt) {
            return error.DuplicateOrUnsorted;
        }
        values[count] = entry;
        count += 1;
    }
    const result = values[0..count].*;
    return &result;
}

fn validIdentity(value: []const u8, bytes_max: usize) bool {
    return value.len > 0 and value.len <= bytes_max and
        std.mem.indexOfAny(u8, value, " \t\r\n") == null;
}

/// A registered lane must render one exact, bounded receipt label. Directory
/// components use the canonical catalog spelling, with `.` reserved for root.
pub fn eligibleIdentity(directory: []const u8, step: []const u8) bool {
    if (!validIdentity(directory, requirements.directory_bytes_max) or
        !validIdentity(step, requirements.step_bytes_max) or
        std.mem.indexOfAny(u8, directory, "+#\\") != null or
        std.mem.indexOfAny(u8, step, "+#") != null) return false;
    const root = std.mem.eql(u8, directory, ".");
    if (!root) {
        if (directory[0] == '/' or directory[directory.len - 1] == '/') return false;
        var components = std.mem.splitScalar(u8, directory, '/');
        while (components.next()) |component| {
            if (component.len == 0 or std.mem.eql(u8, component, ".") or
                std.mem.eql(u8, component, "..")) return false;
        }
    }
    const label_len = step.len + if (root) @as(usize, 0) else directory.len + 1;
    return label_len <= receipt_step_bytes_max;
}

test "qualified label eligibility holds component and receipt byte bounds" {
    const directory: [requirements.directory_bytes_max]u8 = @splat('d');
    const step: [requirements.step_bytes_max]u8 = @splat('s');
    try std.testing.expect(eligibleIdentity(&directory, &step));
    try std.testing.expectEqual(@as(usize, 385), directory.len + 1 + step.len);
    try std.testing.expect(directory.len + 1 + step.len <= receipt_step_bytes_max);
    const oversized_directory: [requirements.directory_bytes_max + 1]u8 = @splat('d');
    try std.testing.expect(!eligibleIdentity(&oversized_directory, &step));
    const oversized_step: [requirements.step_bytes_max + 1]u8 = @splat('s');
    try std.testing.expect(!eligibleIdentity(&directory, &oversized_step));
    try std.testing.expect(!eligibleIdentity("lib/./chic", "journal-test"));
    try std.testing.expect(!eligibleIdentity("/lib/chic", "journal-test"));
    try std.testing.expect(!eligibleIdentity("lib/chic/", "journal-test"));
}

test "measured table parses sorted lanes and rejects malformed lines" {
    const parsed = comptime try parse(
        "# directory\tstep\tmemory_mib\tsamples\tpeak_tree_kib\n" ++
            ".\tchic-host-tests\t1536\t209\t935112\n" ++
            ".\tcli\t3584\t104\t2154496\n" ++
            "lib/chic\tjournal-test\t1024\t18\t418820\n",
    );
    try std.testing.expectEqual(@as(usize, 3), parsed.len);
    try std.testing.expectEqual(@as(?u32, 3584), lookup(parsed, ".", "cli"));
    try std.testing.expectEqual(@as(?u32, 1024), lookup(parsed, "lib/chic", "journal-test"));
    try std.testing.expectError(error.DuplicateOrUnsorted, comptime parse(
        ".\tcli\t1024\t5\t1\n.\tchic-host-tests\t1024\t5\t1\n",
    ));
    try std.testing.expectError(error.DuplicateOrUnsorted, comptime parse(
        ".\tpbt\t1024\t5\t1\n.\tpbt\t1024\t5\t1\n",
    ));
    try std.testing.expectError(error.InvalidClaim, comptime parse(
        ".\tpbt\t5120\t1\t1\n",
    ));
    try std.testing.expectError(error.InvalidSamples, comptime parse(
        ".\tpbt\t1024\t0\t1\n",
    ));
    try std.testing.expectError(error.InvalidSamples, comptime parse(
        ".\tpbt\t1024\t1\t1\n",
    ));
    try std.testing.expectError(error.InvalidPeak, comptime parse(
        ".\tpbt\t1024\t5\t0\n",
    ));
    try std.testing.expectError(error.InvalidClaim, comptime parse(
        ".\tpbt\t1024\t5\t2000000\n",
    ));
    try std.testing.expectError(error.InvalidField, comptime parse(
        ".\ta+b\t1024\t5\t1\n",
    ));
    try std.testing.expectError(error.InvalidField, comptime parse(
        "lib/../chic\tjournal-test\t1024\t5\t1\n",
    ));
    try std.testing.expectError(error.InvalidField, comptime parse(
        "lib//chic\tjournal-test\t1024\t5\t1\n",
    ));
    try std.testing.expectError(error.InvalidField, comptime parse(
        "lib/chic\tjournal#test\t1024\t5\t1\n",
    ));
    try std.testing.expectError(error.WrongFieldCount, comptime parse(
        ".\tpbt\t1024\t1\n",
    ));
}

test "measured claims lower only defaulted ordinary lanes" {
    const measured = comptime try parse(
        ".\tpbt\t1024\t9\t400000\n" ++
            "lib/chic\tjournal-test\t1024\t18\t418820\n",
    );
    var defaulted = requirements.defaultRequirement(.ordinary);
    try std.testing.expectEqual(@as(?requirements.Requirement, null), lowerIn(measured, defaulted, ".", "pbt"));
    defaulted.replay_safe = true;
    const lowered = lowerIn(measured, defaulted, ".", "pbt").?;
    try std.testing.expectEqual(@as(u32, 1024), lowered.memory_mib);
    try std.testing.expectEqual(requirements.EvidenceKind.measured, lowered.evidence_kind);
    try std.testing.expectEqualStrings(evidence_ref, lowered.evidence_ref);
    try std.testing.expectEqual(defaulted.cpu_jobs, lowered.cpu_jobs);
    try std.testing.expectEqual(@as(?requirements.Requirement, null), lowerIn(measured, defaulted, ".", "other"));
    try std.testing.expectEqual(@as(u32, 1024), lowerIn(measured, defaulted, "lib/chic", "journal-test").?.memory_mib);
    try std.testing.expectEqual(@as(?requirements.Requirement, null), lowerIn(measured, defaulted, "lib/chic", "other"));
    try std.testing.expectEqual(@as(?requirements.Requirement, null), lowerIn(measured, defaulted, "lib/../chic", "journal-test"));
    var declared = defaulted;
    declared.evidence_kind = .exploratory;
    try std.testing.expectEqual(@as(?requirements.Requirement, null), lowerIn(measured, declared, ".", "pbt"));
    var exact = defaulted;
    exact.memory_bytes = 512 * 1024 * 1024;
    exact.memory_mib = 512;
    try std.testing.expectEqual(@as(?requirements.Requirement, null), lowerIn(measured, exact, ".", "pbt"));
    const heavy = requirements.defaultRequirement(.heavy);
    try std.testing.expectEqual(@as(?requirements.Requirement, null), lowerIn(measured, heavy, ".", "pbt"));
    var small = defaulted;
    small.memory_mib = 768;
    try std.testing.expectEqual(@as(?requirements.Requirement, null), lowerIn(measured, small, ".", "pbt"));
}

test "margin claims cover half again the peak in whole quanta" {
    try std.testing.expectEqual(claim_floor_mib, marginClaimMib(1));
    try std.testing.expectEqual(@as(u64, 1536), marginClaimMib(804_692));
    try std.testing.expectEqual(@as(u64, 5120), marginClaimMib(4 * 804_692));
    try std.testing.expectEqual(@as(?u32, 1536), claimForPeak(804_692));
    try std.testing.expectEqual(@as(?u32, null), claimForPeak(4 * 804_692));
}

test "checked-in measured table parses within its bounds" {
    for (entries()) |entry| {
        try std.testing.expect(entry.memory_mib > 0);
        try std.testing.expect(entry.memory_mib < requirements.defaultRequirement(.ordinary).memory_mib);
    }
}
