const std = @import("std");
const coz = @import("coz");

const profile = coz.profile;
const analysis = coz.analysis;

pub fn locationEqual(left: profile.Location, right: profile.Location) !void {
    try std.testing.expectEqualStrings(left.file, right.file);
    try std.testing.expectEqual(left.line, right.line);
}

pub fn eventEqual(left: profile.Event, right: profile.Event) !void {
    try std.testing.expectEqual(std.meta.activeTag(left), std.meta.activeTag(right));
    switch (left) {
        .startup => |left_event| {
            const right_event = right.startup;
            try std.testing.expectEqual(left_event.timestamp_ns, right_event.timestamp_ns);
        },
        .experiment => |left_event| {
            const right_event = right.experiment;
            try locationEqual(left_event.selected, right_event.selected);
            try std.testing.expectEqual(left_event.virtual_speedup, right_event.virtual_speedup);
            try std.testing.expectEqual(left_event.duration_ns, right_event.duration_ns);
            try std.testing.expectEqual(left_event.selected_samples, right_event.selected_samples);
        },
        .throughput => |left_event| {
            const right_event = right.throughput;
            try std.testing.expectEqualStrings(left_event.name, right_event.name);
            try std.testing.expectEqual(left_event.delta, right_event.delta);
        },
        .latency => |left_event| {
            const right_event = right.latency;
            try std.testing.expectEqualStrings(left_event.name, right_event.name);
            try std.testing.expectEqual(left_event.arrivals, right_event.arrivals);
            try std.testing.expectEqual(left_event.departures, right_event.departures);
            try std.testing.expectEqual(left_event.outstanding, right_event.outstanding);
        },
        .runtime => |left_event| {
            const right_event = right.runtime;
            try std.testing.expectEqual(left_event.duration_ns, right_event.duration_ns);
        },
        .sample => |left_event| {
            const right_event = right.sample;
            try locationEqual(left_event.location, right_event.location);
            try std.testing.expectEqual(left_event.count, right_event.count);
        },
        .sampling => |left_event| try samplingEqual(left_event, right.sampling),
    }
}

pub fn summaryEqual(left: analysis.Summary, right: analysis.Summary) !void {
    try integrityEqual(left.capture_integrity, right.capture_integrity);
    try std.testing.expectEqual(left.results.len, right.results.len);
    for (left.results, right.results) |left_result, right_result| {
        try resultEqual(left_result, right_result);
    }
}

fn samplingEqual(left: profile.Sampling, right: profile.Sampling) !void {
    try std.testing.expectEqual(left.record_count, right.record_count);
    try std.testing.expectEqual(left.sample_record_count, right.sample_record_count);
    try std.testing.expectEqual(left.lost_record_count, right.lost_record_count);
    try std.testing.expectEqual(left.lost_event_count, right.lost_event_count);
    try std.testing.expectEqual(left.lost_samples_record_count, right.lost_samples_record_count);
    try std.testing.expectEqual(left.lost_samples_count, right.lost_samples_count);
    try std.testing.expectEqual(left.throttle_record_count, right.throttle_record_count);
    try std.testing.expectEqual(left.unthrottle_record_count, right.unthrottle_record_count);
    try std.testing.expectEqual(
        std.meta.activeTag(left.loss_counter),
        std.meta.activeTag(right.loss_counter),
    );
    switch (left.loss_counter) {
        .available => |value| try std.testing.expectEqual(value, right.loss_counter.available),
        .unsupported, .read_failed => {},
    }
    try std.testing.expectEqual(left.terminal_status, right.terminal_status);
}

fn integrityEqual(left: analysis.CaptureIntegrity, right: analysis.CaptureIntegrity) !void {
    try std.testing.expectEqualStrings(left.status, right.status);
    try std.testing.expectEqualStrings(left.method, right.method);
    try std.testing.expectEqualStrings(left.action, right.action);
    if (left.message) |message| {
        try std.testing.expectEqualStrings(message, right.message.?);
    } else {
        try std.testing.expect(right.message == null);
    }
    try std.testing.expectEqual(left.record_count, right.record_count);
    try std.testing.expectEqual(left.sample_record_count, right.sample_record_count);
    try std.testing.expectEqual(left.lost_record_count, right.lost_record_count);
    try std.testing.expectEqual(left.lost_event_count, right.lost_event_count);
    try std.testing.expectEqual(left.lost_samples_record_count, right.lost_samples_record_count);
    try std.testing.expectEqual(left.lost_samples_count, right.lost_samples_count);
    try std.testing.expectEqual(left.throttle_record_count, right.throttle_record_count);
    try std.testing.expectEqual(left.unthrottle_record_count, right.unthrottle_record_count);
    try std.testing.expectEqual(left.loss_counter_value, right.loss_counter_value);
    try std.testing.expectEqualStrings(left.terminal_status, right.terminal_status);
}

pub fn summaryInvariants(summary: analysis.Summary) !void {
    for (summary.results) |result| {
        try std.testing.expect(result.measurements.len > 0);
        try std.testing.expect(std.math.isFinite(result.baseline_value_ns));
        try std.testing.expect(result.baseline_value_ns > 0);

        var selected_samples: u64 = 0;
        var min_program_speedup: f64 = std.math.inf(f64);
        var max_program_speedup: f64 = -std.math.inf(f64);
        var baseline_seen = false;

        for (result.measurements) |measurement| {
            try std.testing.expect(measurement.program_speedup >= -1);
            try std.testing.expect(measurement.program_speedup <= 2);
            selected_samples += measurement.selected_samples;
            min_program_speedup = @min(min_program_speedup, measurement.program_speedup);
            max_program_speedup = @max(max_program_speedup, measurement.program_speedup);
            if (measurement.virtual_speedup == result.baseline_virtual_speedup) {
                try std.testing.expectApproxEqAbs(result.baseline_value_ns, measurement.value_ns, 0.000000001);
                baseline_seen = true;
            }
            switch (result.kind) {
                .throughput => {
                    try std.testing.expect(measurement.throughput_delta != null);
                    try std.testing.expect(measurement.latency_arrivals == null);
                    try std.testing.expect(measurement.latency_departures == null);
                    try std.testing.expect(measurement.latency_outstanding == null);
                },
                .latency => {
                    try std.testing.expect(measurement.throughput_delta == null);
                    try std.testing.expect(measurement.latency_arrivals != null);
                    try std.testing.expect(measurement.latency_departures != null);
                    try std.testing.expect(measurement.latency_outstanding != null);
                },
            }
        }

        try std.testing.expect(baseline_seen);
        try std.testing.expectEqual(result.total_selected_samples, selected_samples);
        try std.testing.expectApproxEqAbs(result.min_program_speedup, min_program_speedup, 0.000000001);
        try std.testing.expectApproxEqAbs(result.max_program_speedup, max_program_speedup, 0.000000001);
        if (result.slope) |value| try std.testing.expect(std.math.isFinite(value));
    }
}

fn optionalFloatEqual(left: ?f64, right: ?f64) !void {
    if (left == null or right == null) {
        try std.testing.expect(left == null and right == null);
        return;
    }
    try std.testing.expectApproxEqAbs(left.?, right.?, 0.000000001);
}

fn optionalU64Equal(left: ?u64, right: ?u64) !void {
    if (left == null or right == null) {
        try std.testing.expect(left == null and right == null);
        return;
    }
    try std.testing.expectEqual(left.?, right.?);
}

fn measurementEqual(left: analysis.Measurement, right: analysis.Measurement) !void {
    try std.testing.expectApproxEqAbs(left.virtual_speedup, right.virtual_speedup, 0.000000001);
    try std.testing.expectApproxEqAbs(left.program_speedup, right.program_speedup, 0.000000001);
    try std.testing.expectEqual(left.experiment_count, right.experiment_count);
    try std.testing.expectEqual(left.selected_samples, right.selected_samples);
    try std.testing.expectEqual(left.observations, right.observations);
    try std.testing.expectEqual(left.duration_ns, right.duration_ns);
    try std.testing.expectApproxEqAbs(left.value_ns, right.value_ns, 0.000000001);
    try optionalU64Equal(left.throughput_delta, right.throughput_delta);
    try optionalU64Equal(left.latency_arrivals, right.latency_arrivals);
    try optionalU64Equal(left.latency_departures, right.latency_departures);
    try optionalFloatEqual(left.latency_outstanding, right.latency_outstanding);
}

fn resultEqual(left: analysis.Result, right: analysis.Result) !void {
    try std.testing.expectEqual(left.kind, right.kind);
    try locationEqual(left.selected, right.selected);
    try std.testing.expectEqualStrings(left.progress_point, right.progress_point);
    try std.testing.expectApproxEqAbs(left.baseline_virtual_speedup, right.baseline_virtual_speedup, 0.000000001);
    try std.testing.expectApproxEqAbs(left.baseline_value_ns, right.baseline_value_ns, 0.000000001);
    try std.testing.expectApproxEqAbs(left.min_program_speedup, right.min_program_speedup, 0.000000001);
    try std.testing.expectApproxEqAbs(left.max_program_speedup, right.max_program_speedup, 0.000000001);
    try std.testing.expectEqual(left.total_selected_samples, right.total_selected_samples);
    try optionalFloatEqual(left.slope, right.slope);
    try std.testing.expectEqualDeep(left.support, right.support);
    try std.testing.expectEqual(left.measurements.len, right.measurements.len);
    for (left.measurements, right.measurements) |left_measurement, right_measurement| {
        try measurementEqual(left_measurement, right_measurement);
    }
}
