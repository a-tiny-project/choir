pub const Header = extern struct {
    magic: u64,
    value: usize,
};

pub const magic: u64 = 0x5441_4641_5354_0001;
pub const alignment_bytes = 16;
pub const header_bytes = @sizeOf(Header);
pub const min_total_len = header_bytes + alignment_bytes;
