pub const Verdict = enum {
    improved,
    regressed,
    neutral,

    pub fn name(self: Verdict) []const u8 {
        return @tagName(self);
    }
};

pub const Result = struct {
    base_median: u64,
    candidate_median: u64,
    ratio: f64,
    ci_low: f64,
    ci_high: f64,
    verdict: Verdict,
};
