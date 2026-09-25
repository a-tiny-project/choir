const alloc_phase = @import("alloc_phase");

pub const Limits = struct {
    file_bytes: usize,
};

pub const DeriveError = alloc_phase.input.DeriveError;

pub const Capacity = struct {
    file_bytes: usize,
    storage_bytes: usize,

    pub fn derive(limits: Limits) DeriveError!Capacity {
        return alloc_phase.input.deriveCapacity(
            Limits,
            Capacity,
            "file_bytes",
            limits,
        );
    }
};
