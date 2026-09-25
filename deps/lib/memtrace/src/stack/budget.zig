const std = @import("std");
const pretty_json = @import("pretty").json;
const sys = @import("sys");

const Allocator = std.mem.Allocator;
const schema = "tiny.memtrace.causal-budget/v1";
const max_budget_bytes: usize = 64 * 1024;
const max_report_line_bytes: usize = 256 * 1024;

pub const Format = enum {
    text,
    jsonl,
};

pub const Outcome = struct {
    passed: bool,
    checks: u32,
    failures: u32,
};

const Values = struct {
    roots: u128 = 0,
    root_requested_bytes: u128 = 0,
    backing_requested_bytes: u128 = 0,
    high_water_live_bytes: u128 = 0,
};

const Limits = struct {
    roots: ?u128 = null,
    root_requested_bytes: ?u128 = null,
    backing_requested_bytes: ?u128 = null,
    high_water_live_bytes: ?u128 = null,
};

const SourceRule = struct {
    name: []const u8,
    site_function_contains: ?[]const u8,
    caller_function_contains: ?[]const u8,
    caller_owner_function_contains: ?[]const u8,
    min_source_groups: u32,
    max_source_groups: u32,
    limits: Limits,
};

const Budget = struct {
    name: []const u8,
    totals: Limits,
    sources: []const SourceRule,
};

const SourceResult = struct {
    values: Values = .{},
    matched_groups: u32 = 0,
};

const Evaluation = struct {
    allocator: Allocator,
    budget: Budget,
    totals: ?Values = null,
    source_results: []SourceResult,
    summary_status_complete: bool = false,
    sources_complete: bool = false,

    fn init(allocator: Allocator, budget: Budget) !Evaluation {
        const results = try allocator.alloc(SourceResult, budget.sources.len);
        @memset(results, .{});
        return .{
            .allocator = allocator,
            .budget = budget,
            .source_results = results,
        };
    }

    fn ingest(self: *Evaluation, line: []const u8) !void {
        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            line,
            .{},
        );
        defer parsed.deinit();
        const row = try object(parsed.value);
        const kind = try requiredString(row, "kind");
        if (std.mem.eql(u8, kind, "causal_root_summary")) {
            if (self.totals != null) return error.DuplicateCausalRootSummary;
            const status = try requiredString(row, "status");
            self.summary_status_complete = std.mem.eql(
                u8,
                status,
                "process_memory_operation_complete",
            );
            const source_groups = try requiredUnsigned(row, "source_groups");
            const displayed_sources = try requiredUnsigned(
                row,
                "displayed_sources",
            );
            self.sources_complete = source_groups == displayed_sources;
            self.totals = try values(row);
            return;
        }
        if (!std.mem.eql(u8, kind, "causal_root_source")) return;
        const site = try requiredString(row, "site_function");
        const caller = optionalString(row, "caller_function");
        const caller_owner = optionalString(row, "caller_owner_function");
        const actual = try values(row);
        for (self.budget.sources, self.source_results) |rule, *result| {
            if (rule.site_function_contains) |expected| {
                if (!std.mem.containsAtLeast(
                    u8,
                    site,
                    1,
                    expected,
                )) {
                    continue;
                }
            }
            if (rule.caller_function_contains) |expected| {
                const actual_caller = caller orelse continue;
                if (!std.mem.containsAtLeast(
                    u8,
                    actual_caller,
                    1,
                    expected,
                )) {
                    continue;
                }
            }
            if (rule.caller_owner_function_contains) |expected| {
                const actual_owner = caller_owner orelse continue;
                if (!std.mem.containsAtLeast(
                    u8,
                    actual_owner,
                    1,
                    expected,
                )) {
                    continue;
                }
            }
            result.matched_groups = try std.math.add(
                u32,
                result.matched_groups,
                1,
            );
            try addValues(&result.values, actual);
        }
    }

    fn assess(
        self: *const Evaluation,
        writer: *std.Io.Writer,
        format: Format,
        report_path: []const u8,
    ) !Outcome {
        const totals = self.totals orelse
            return error.MissingCausalRootSummary;
        if (!self.sources_complete) return error.TruncatedCausalRootSources;
        var outcome = Outcome{
            .passed = self.summary_status_complete,
            .checks = 1,
            .failures = @intFromBool(!self.summary_status_complete),
        };
        try writeStatusCheck(
            writer,
            format,
            "capture",
            "complete",
            @intFromBool(self.summary_status_complete),
            1,
            self.summary_status_complete,
        );
        try assessLimits(
            writer,
            format,
            "total",
            totals,
            self.budget.totals,
            &outcome,
        );
        for (
            self.budget.sources,
            self.source_results,
        ) |rule, result| {
            const matched = result.matched_groups >= rule.min_source_groups and
                result.matched_groups <= rule.max_source_groups;
            outcome.checks = try std.math.add(u32, outcome.checks, 1);
            if (!matched) {
                outcome.passed = false;
                outcome.failures = try std.math.add(
                    u32,
                    outcome.failures,
                    1,
                );
            }
            try writeRangeCheck(
                writer,
                format,
                rule.name,
                "matched_source_groups",
                result.matched_groups,
                rule.min_source_groups,
                rule.max_source_groups,
                matched,
            );
            try assessLimits(
                writer,
                format,
                rule.name,
                result.values,
                rule.limits,
                &outcome,
            );
        }
        try writeOutcome(
            writer,
            format,
            self.budget.name,
            report_path,
            outcome,
        );
        return outcome;
    }
};

pub fn checkFromPaths(
    allocator: Allocator,
    report_path: []const u8,
    budget_path: []const u8,
    writer: *std.Io.Writer,
    format: Format,
) !Outcome {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const budget_bytes = try sys.fs.readFileAlloc(
        arena,
        budget_path,
        max_budget_bytes,
    );
    const budget = try parseBudget(arena, budget_bytes);
    var evaluation = try Evaluation.init(arena, budget);
    try ingestPath(&evaluation, report_path);
    return try evaluation.assess(writer, format, report_path);
}

fn ingestPath(evaluation: *Evaluation, path: []const u8) !void {
    var file = try sys.fs.cwd().openFile(sys.fs.debugIo(), path, .{});
    defer file.close(sys.fs.debugIo());
    var buffer: [max_report_line_bytes]u8 = undefined;
    var reader = file.reader(sys.fs.debugIo(), &buffer);
    while (true) {
        const line = reader.interface.takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed => return reader.err.?,
            else => return err,
        };
        const actual = line orelse break;
        const trimmed = std.mem.trim(u8, actual, " \t\r");
        if (trimmed.len != 0) try evaluation.ingest(trimmed);
    }
}

fn parseBudget(allocator: Allocator, bytes: []const u8) !Budget {
    const parsed = try std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        bytes,
        .{},
    );
    const root = try object(parsed);
    const actual_schema = try requiredString(root, "schema");
    if (!std.mem.eql(u8, actual_schema, schema)) {
        return error.UnsupportedCausalBudgetSchema;
    }
    const source_values = try array(root.get("sources") orelse
        return error.InvalidCausalBudget);
    const sources = try allocator.alloc(SourceRule, source_values.items.len);
    for (source_values.items, sources) |value, *source| {
        const row = try object(value);
        source.* = .{
            .name = try requiredString(row, "name"),
            .site_function_contains = try optionalBudgetString(
                row,
                "site_function_contains",
            ),
            .caller_function_contains = try optionalBudgetString(
                row,
                "caller_function_contains",
            ),
            .caller_owner_function_contains = try optionalBudgetString(
                row,
                "caller_owner_function_contains",
            ),
            .min_source_groups = try sourceGroupLimit(
                row,
                "min_source_groups",
                1,
            ),
            .max_source_groups = try sourceGroupLimit(
                row,
                "max_source_groups",
                1,
            ),
            .limits = try parseLimits(row),
        };
        if (source.name.len == 0 or !hasSourceSelector(source.*)) {
            return error.InvalidCausalBudget;
        }
        if (source.min_source_groups > source.max_source_groups) {
            return error.InvalidCausalBudget;
        }
    }
    return .{
        .name = try requiredString(root, "name"),
        .totals = try parseLimits(try object(root.get("totals") orelse
            return error.InvalidCausalBudget)),
        .sources = sources,
    };
}

fn optionalBudgetString(
    row: std.json.ObjectMap,
    key: []const u8,
) !?[]const u8 {
    const value = row.get(key) orelse return null;
    const string = switch (value) {
        .string => |actual| actual,
        else => return error.InvalidCausalBudget,
    };
    if (string.len == 0) return error.InvalidCausalBudget;
    return string;
}

fn hasSourceSelector(source: SourceRule) bool {
    return source.site_function_contains != null or
        source.caller_function_contains != null or
        source.caller_owner_function_contains != null;
}

fn sourceGroupLimit(
    row: std.json.ObjectMap,
    key: []const u8,
    default: u32,
) !u32 {
    const value = try optionalUnsigned(row, key) orelse return default;
    return std.math.cast(u32, value) orelse error.InvalidCausalBudget;
}

fn parseLimits(row: std.json.ObjectMap) !Limits {
    return .{
        .roots = try optionalUnsigned(row, "max_roots"),
        .root_requested_bytes = try optionalUnsigned(
            row,
            "max_root_requested_bytes",
        ),
        .backing_requested_bytes = try optionalUnsigned(
            row,
            "max_backing_requested_bytes",
        ),
        .high_water_live_bytes = try optionalUnsigned(
            row,
            "max_high_water_live_bytes",
        ),
    };
}

fn values(row: std.json.ObjectMap) !Values {
    return .{
        .roots = try requiredUnsigned(row, "roots"),
        .root_requested_bytes = try requiredUnsigned(
            row,
            "root_requested_bytes",
        ),
        .backing_requested_bytes = try requiredUnsigned(
            row,
            "backing_requested_bytes",
        ),
        .high_water_live_bytes = try requiredUnsigned(
            row,
            "high_water_live_bytes",
        ),
    };
}

fn addValues(target: *Values, next: Values) !void {
    target.roots = try std.math.add(u128, target.roots, next.roots);
    target.root_requested_bytes = try std.math.add(
        u128,
        target.root_requested_bytes,
        next.root_requested_bytes,
    );
    target.backing_requested_bytes = try std.math.add(
        u128,
        target.backing_requested_bytes,
        next.backing_requested_bytes,
    );
    target.high_water_live_bytes = try std.math.add(
        u128,
        target.high_water_live_bytes,
        next.high_water_live_bytes,
    );
}

fn assessLimits(
    writer: *std.Io.Writer,
    format: Format,
    scope: []const u8,
    actual: Values,
    limits: Limits,
    outcome: *Outcome,
) !void {
    try assessLimit(
        writer,
        format,
        scope,
        "roots",
        actual.roots,
        limits.roots,
        outcome,
    );
    try assessLimit(
        writer,
        format,
        scope,
        "root_requested_bytes",
        actual.root_requested_bytes,
        limits.root_requested_bytes,
        outcome,
    );
    try assessLimit(
        writer,
        format,
        scope,
        "backing_requested_bytes",
        actual.backing_requested_bytes,
        limits.backing_requested_bytes,
        outcome,
    );
    try assessLimit(
        writer,
        format,
        scope,
        "high_water_live_bytes",
        actual.high_water_live_bytes,
        limits.high_water_live_bytes,
        outcome,
    );
}

fn assessLimit(
    writer: *std.Io.Writer,
    format: Format,
    scope: []const u8,
    metric: []const u8,
    actual: u128,
    maybe_maximum: ?u128,
    outcome: *Outcome,
) !void {
    const maximum = maybe_maximum orelse return;
    const passed = actual <= maximum;
    outcome.checks = try std.math.add(u32, outcome.checks, 1);
    if (!passed) {
        outcome.passed = false;
        outcome.failures = try std.math.add(u32, outcome.failures, 1);
    }
    try writeStatusCheck(
        writer,
        format,
        scope,
        metric,
        actual,
        maximum,
        passed,
    );
}

fn writeRangeCheck(
    writer: *std.Io.Writer,
    format: Format,
    scope: []const u8,
    metric: []const u8,
    actual: u128,
    minimum: u128,
    maximum: u128,
    passed: bool,
) !void {
    switch (format) {
        .text => try writer.print(
            "causal_budget_check scope={s} metric={s} actual={d} min={d} " ++
                "max={d} status={s}\n",
            .{
                scope,
                metric,
                actual,
                minimum,
                maximum,
                if (passed) "pass" else "fail",
            },
        ),
        .jsonl => {
            var stream = pretty_json.Writer.init(writer, .minified);
            const row = try stream.object();
            try row.field("kind", "causal_budget_check");
            try row.field("scope", scope);
            try row.field("metric", metric);
            try row.field("actual", actual);
            try row.field("min", minimum);
            try row.field("max", maximum);
            try row.field("status", if (passed) "pass" else "fail");
            try row.endLine();
        },
    }
}

fn writeStatusCheck(
    writer: *std.Io.Writer,
    format: Format,
    scope: []const u8,
    metric: []const u8,
    actual: u128,
    maximum: u128,
    passed: bool,
) !void {
    switch (format) {
        .text => try writer.print(
            "causal_budget_check scope={s} metric={s} actual={d} max={d} " ++
                "status={s}\n",
            .{
                scope,
                metric,
                actual,
                maximum,
                if (passed) "pass" else "fail",
            },
        ),
        .jsonl => {
            var stream = pretty_json.Writer.init(writer, .minified);
            const row = try stream.object();
            try row.field("kind", "causal_budget_check");
            try row.field("scope", scope);
            try row.field("metric", metric);
            try row.field("actual", actual);
            try row.field("max", maximum);
            try row.field("status", if (passed) "pass" else "fail");
            try row.endLine();
        },
    }
}

fn writeOutcome(
    writer: *std.Io.Writer,
    format: Format,
    name: []const u8,
    report_path: []const u8,
    outcome: Outcome,
) !void {
    switch (format) {
        .text => try writer.print(
            "causal_budget name={s} report={s} checks={d} failures={d} " ++
                "status={s}\n",
            .{
                name,
                report_path,
                outcome.checks,
                outcome.failures,
                if (outcome.passed) "pass" else "fail",
            },
        ),
        .jsonl => {
            var stream = pretty_json.Writer.init(writer, .minified);
            const row = try stream.object();
            try row.field("kind", "causal_budget");
            try row.field("name", name);
            try row.field("report", report_path);
            try row.field("checks", outcome.checks);
            try row.field("failures", outcome.failures);
            try row.field("status", if (outcome.passed) "pass" else "fail");
            try row.endLine();
        },
    }
}

fn object(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |actual| actual,
        else => error.InvalidCausalBudget,
    };
}

fn array(value: std.json.Value) !std.json.Array {
    return switch (value) {
        .array => |actual| actual,
        else => error.InvalidCausalBudget,
    };
}

fn requiredString(
    row: std.json.ObjectMap,
    key: []const u8,
) ![]const u8 {
    return optionalString(row, key) orelse error.InvalidCausalBudget;
}

fn optionalString(
    row: std.json.ObjectMap,
    key: []const u8,
) ?[]const u8 {
    const value = row.get(key) orelse return null;
    return switch (value) {
        .string => |actual| actual,
        else => null,
    };
}

fn requiredUnsigned(
    row: std.json.ObjectMap,
    key: []const u8,
) !u128 {
    return try optionalUnsigned(row, key) orelse
        error.InvalidCausalBudget;
}

fn optionalUnsigned(
    row: std.json.ObjectMap,
    key: []const u8,
) !?u128 {
    const value = row.get(key) orelse return null;
    return switch (value) {
        .integer => |actual| if (actual < 0)
            error.InvalidCausalBudget
        else
            @intCast(actual),
        else => error.InvalidCausalBudget,
    };
}

test "causal budget enforces totals and one exact source group" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const budget = try parseBudget(arena,
        \\{
        \\  "schema":"tiny.memtrace.causal-budget/v1",
        \\  "name":"fixture",
        \\  "totals":{"max_roots":4,"max_high_water_live_bytes":64},
        \\  "sources":[{
        \\    "name":"tree",
        \\    "site_function_contains":"Tree.create",
        \\    "caller_function_contains":"compile",
        \\    "caller_owner_function_contains":"compileDecodedOnce",
        \\    "max_roots":2,
        \\    "max_root_requested_bytes":32,
        \\    "max_backing_requested_bytes":48,
        \\    "max_high_water_live_bytes":16
        \\  }]
        \\}
    );
    var evaluation = try Evaluation.init(arena, budget);
    try evaluation.ingest(
        \\{"kind":"causal_root_summary","status":"process_memory_operation_complete","roots":4,"root_requested_bytes":64,"backing_requested_bytes":48,"high_water_live_bytes":64,"source_groups":1,"displayed_sources":1}
    );
    try evaluation.ingest(
        \\{"kind":"causal_root_source","roots":2,"root_requested_bytes":32,"backing_requested_bytes":48,"high_water_live_bytes":16,"site_function":"Tree.create","caller_function":"Compiler.compile","caller_owner_function":"Compiler.compileDecodedOnce"}
    );
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const outcome = try evaluation.assess(
        &output.writer,
        .jsonl,
        "fixture.jsonl",
    );
    try std.testing.expect(outcome.passed);
    try std.testing.expectEqual(@as(u32, 0), outcome.failures);
    try std.testing.expect(std.mem.indexOf(
        u8,
        output.written(),
        "\"status\":\"pass\"",
    ) != null);
}

test "causal budget rejects a duplicated source match" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const budget = try parseBudget(arena,
        \\{"schema":"tiny.memtrace.causal-budget/v1","name":"fixture","totals":{},"sources":[{"name":"source","site_function_contains":"alloc"}]}
    );
    var evaluation = try Evaluation.init(arena, budget);
    try evaluation.ingest(
        \\{"kind":"causal_root_summary","status":"process_memory_operation_complete","roots":1,"root_requested_bytes":1,"backing_requested_bytes":1,"high_water_live_bytes":1,"source_groups":2,"displayed_sources":2}
    );
    const source =
        \\{"kind":"causal_root_source","roots":1,"root_requested_bytes":1,"backing_requested_bytes":1,"high_water_live_bytes":1,"site_function":"alloc"}
    ;
    try evaluation.ingest(source);
    try evaluation.ingest(source);
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const outcome = try evaluation.assess(
        &output.writer,
        .text,
        "fixture.jsonl",
    );
    try std.testing.expect(!outcome.passed);
    try std.testing.expectEqual(@as(u32, 1), outcome.failures);
}

test "causal budget aggregates a bounded source group family" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const budget = try parseBudget(arena,
        \\{
        \\  "schema":"tiny.memtrace.causal-budget/v1",
        \\  "name":"fixture",
        \\  "totals":{},
        \\  "sources":[{
        \\    "name":"located",
        \\    "site_function_contains":"LocatedCloner",
        \\    "min_source_groups":2,
        \\    "max_source_groups":3,
        \\    "max_roots":5,
        \\    "max_high_water_live_bytes":48
        \\  }]
        \\}
    );
    var evaluation = try Evaluation.init(arena, budget);
    try evaluation.ingest(
        \\{"kind":"causal_root_summary","status":"process_memory_operation_complete","roots":5,"root_requested_bytes":80,"backing_requested_bytes":64,"high_water_live_bytes":48,"source_groups":2,"displayed_sources":2}
    );
    try evaluation.ingest(
        \\{"kind":"causal_root_source","roots":2,"root_requested_bytes":32,"backing_requested_bytes":16,"high_water_live_bytes":16,"site_function":"LocatedCloner.cloneExpr"}
    );
    try evaluation.ingest(
        \\{"kind":"causal_root_source","roots":3,"root_requested_bytes":48,"backing_requested_bytes":48,"high_water_live_bytes":32,"site_function":"LocatedCloner.cloneSite"}
    );
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const outcome = try evaluation.assess(
        &output.writer,
        .jsonl,
        "fixture.jsonl",
    );
    try std.testing.expect(outcome.passed);
    try std.testing.expectEqual(@as(u32, 0), outcome.failures);
    try std.testing.expect(std.mem.indexOf(
        u8,
        output.written(),
        "\"actual\":2,\"min\":2,\"max\":3",
    ) != null);
}

test "causal budget selects a complete caller family without a site filter" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const budget = try parseBudget(arena,
        \\{
        \\  "schema":"tiny.memtrace.causal-budget/v1",
        \\  "name":"fixture",
        \\  "totals":{},
        \\  "sources":[{
        \\    "name":"owned-authorship",
        \\    "caller_function_contains":"value.own.Cloner.cloneExpr",
        \\    "min_source_groups":2,
        \\    "max_source_groups":2,
        \\    "max_roots":5,
        \\    "max_high_water_live_bytes":48
        \\  }]
        \\}
    );
    var evaluation = try Evaluation.init(arena, budget);
    try evaluation.ingest(
        \\{"kind":"causal_root_summary","status":"process_memory_operation_complete","roots":6,"root_requested_bytes":96,"backing_requested_bytes":64,"high_water_live_bytes":64,"source_groups":3,"displayed_sources":3}
    );
    try evaluation.ingest(
        \\{"kind":"causal_root_source","roots":2,"root_requested_bytes":32,"backing_requested_bytes":16,"high_water_live_bytes":16,"site_function":"LocatedCloner.cloneExpr","caller_function":"value.own.Cloner.cloneExpr"}
    );
    try evaluation.ingest(
        \\{"kind":"causal_root_source","roots":3,"root_requested_bytes":48,"backing_requested_bytes":48,"high_water_live_bytes":32,"site_function":"LocatedCloner.cloneSite","caller_function":"value.own.Cloner.cloneExpr"}
    );
    try evaluation.ingest(
        \\{"kind":"causal_root_source","roots":1,"root_requested_bytes":16,"backing_requested_bytes":0,"high_water_live_bytes":16,"site_function":"LocatedCloner.cloneExpr","caller_function":"other.Cloner.cloneExpr"}
    );
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    const outcome = try evaluation.assess(
        &output.writer,
        .jsonl,
        "fixture.jsonl",
    );
    try std.testing.expect(outcome.passed);
    try std.testing.expectEqual(@as(u32, 0), outcome.failures);
    try std.testing.expect(std.mem.indexOf(
        u8,
        output.written(),
        "\"actual\":2,\"min\":2,\"max\":2",
    ) != null);
}

test "causal budget rejects an inverted source group range" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectError(
        error.InvalidCausalBudget,
        parseBudget(arena,
            \\{
            \\  "schema":"tiny.memtrace.causal-budget/v1",
            \\  "name":"fixture",
            \\  "totals":{},
            \\  "sources":[{
            \\    "name":"located",
            \\    "site_function_contains":"LocatedCloner",
            \\    "min_source_groups":3,
            \\    "max_source_groups":2
            \\  }]
            \\}
        ),
    );
}

test "causal budget rejects a source rule without a selector" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectError(
        error.InvalidCausalBudget,
        parseBudget(arena,
            \\{
            \\  "schema":"tiny.memtrace.causal-budget/v1",
            \\  "name":"fixture",
            \\  "totals":{},
            \\  "sources":[{"name":"everything"}]
            \\}
        ),
    );
    try std.testing.expectError(
        error.InvalidCausalBudget,
        parseBudget(arena,
            \\{
            \\  "schema":"tiny.memtrace.causal-budget/v1",
            \\  "name":"fixture",
            \\  "totals":{},
            \\  "sources":[{
            \\    "name":"everything",
            \\    "caller_function_contains":""
            \\  }]
            \\}
        ),
    );
}
