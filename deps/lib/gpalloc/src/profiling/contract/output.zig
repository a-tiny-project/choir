const std = @import("std");
const pretty = @import("pretty");
const pretty_usage = @import("pretty_usage");

const usage_text =
    \\usage: gpalloc-semantic-contracts --allocator MODE --case CASE
    \\
    \\Options:
    \\  --allocator MODE  Allocator mode: gpalloc, system.
    \\  --case CASE       Contract case to run.
    \\  -h, --help        Print this message.
    \\
    \\Cases:
    \\  native-alloc-roundtrip
    \\  native-aligned-alloc
    \\  native-realloc-grow-preserve
    \\  native-realloc-shrink-preserve
    \\  native-resize-shrink-preserve
    \\  native-cross-thread-free
;

pub fn writeUsage(allocator: std.mem.Allocator) !void {
    try pretty_usage.writeStdoutUsageText(allocator, usage_text);
}

pub fn writeParseError(allocator: std.mem.Allocator, err: anyerror) !void {
    const stderr = pretty_usage.Terminal.stderr(allocator, .{});
    try stderr.writeErrorTextFmt("gpalloc-semantic-contracts", "{s}", .{@errorName(err)});
    try stderr.writeDoc(pretty.hardline);
    try stderr.writeUsageText(usage_text);
}

pub fn writeMissingCase(allocator: std.mem.Allocator) !void {
    const stderr = pretty_usage.Terminal.stderr(allocator, .{});
    try stderr.writeErrorText("gpalloc-semantic-contracts", "missing --case");
    try stderr.writeDoc(pretty.hardline);
    try stderr.writeUsageText(usage_text);
}

pub fn writeCaseError(
    allocator: std.mem.Allocator,
    case_id: []const u8,
    err: anyerror,
) !void {
    try pretty_usage.Terminal.stderr(allocator, .{}).writeErrorTextFmt(
        "gpalloc-semantic-contracts",
        "{s}: {s}",
        .{ case_id, @errorName(err) },
    );
}
