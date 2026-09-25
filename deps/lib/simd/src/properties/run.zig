const hypothesis = @import("hypothesis");

pub fn settings() hypothesis.Settings {
    return hypothesis.Settings.quick()
        .withSeed(0x5349_4d44_4857_5921)
        .withSeedFromEnv()
        .withDatabase("zig-out/hypothesis-failures/simd");
}
