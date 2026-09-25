const sys = @import("sys");

pub const posix_einval = 22;
pub const posix_enomem = 12;
pub const posix_enosys = 38;

pub fn fail(value: c_int) ?*anyopaque {
    set(value);
    return null;
}

pub fn set(value: c_int) void {
    sys.errno.setHostInterop(value);
}

pub fn current() c_int {
    return sys.errno.currentHostInterop();
}
