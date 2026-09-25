const std = @import("std");

const command = @import("command.zig");
const options = @import("options.zig");

pub const receipt_directory_option = options.directory_option;
pub const receipt_token_option = options.token_option;
pub const receipt_directory_environment = options.directory_environment;
pub const receipt_token_environment = options.token_environment;
pub const shard_count_environment = options.shard_count_environment;

pub fn addFocusedRun(
    b: *std.Build,
    run: *std.Build.Step.Run,
    output_name: []const u8,
) std.Build.LazyPath {
    run.setEnvironmentVariable(options.supervised_environment, "1");
    run.setEnvironmentVariable(
        options.supervisor_deadline_environment,
        b.fmt("{d}", .{options.supervised_deadline_ms}),
    );
    run.setEnvironmentVariable(
        options.supervisor_heartbeat_environment,
        b.fmt("{d}", .{options.supervised_heartbeat_ms}),
    );
    run.setEnvironmentVariable("TINY_TIMING_RUNNER_REPORT", "0");
    run.stdio = .inherit;
    run.addArg(command.supervised_receipts_flag);
    return run.addOutputDirectoryArg(output_name);
}
