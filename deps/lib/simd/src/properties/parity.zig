const simd = @import("simd");

test "property: pinned Highway declarations are public" {
    comptime {
        for (simd.parity.core_callables) |callable| {
            if (!@hasDecl(simd, callable.zig)) {
                @compileError("private pinned Highway callable: " ++ callable.upstream);
            }
        }
        for (simd.parity.supplemental_callables) |callable| {
            if (!@hasDecl(simd, callable.zig)) {
                @compileError("private pinned Highway declaration: " ++ callable.upstream);
            }
        }
    }
}
