<p align="center">
  <img src="logo.svg" alt="Choir" width="200" />
</p>

# Choir v26.10.1

Choir is a library for building compilers in Zig, in the style of
[MLIR](https://mlir.llvm.org/). A program is held as typed operations in SSA
form (each value is defined exactly once), and related operations are grouped
into _dialects_. Compiler _passes_ rewrite a program from one dialect toward
another until a backend emits machine code, for example for x64 or aarch64.
Choir can also evaluate, serialize, and hash programs in this form.

## Install

The source archive is private to members of the organization, who can download
it with `gh`:

```sh
gh release download v26.10.1 --repo a-tiny-project/choir --pattern 'choir-v26.10.1.tar.gz'
tar -xzf choir-v26.10.1.tar.gz
```

Choir builds with the official Zig 0.17.0 release. The extracted directory is a
Nix flake, and its default development shell supplies that compiler on x86_64
Linux and Apple silicon macOS. A project that depends on Choir builds with any
Zig 0.17.0, such as the one in that shell, and fetches the archive:

```sh
nix develop /path/to/choir-v26.10.1
zig fetch --save=choir /path/to/choir-v26.10.1.tar.gz
```

## Use

The project's `build.zig` then imports the `choir` module:

```zig
const choir = b.dependency("choir", .{ .target = target, .optimize = optimize });
const root = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{.{ .name = "choir", .module = choir.module("choir") }},
});
```

A Choir context owns the operations of a program. It reserves its memory when it
is created, and `Limits` fixes the size of each table in it (`Limits.standard`
suits most programs):

```zig
const std = @import("std");
const choir = @import("choir");

pub fn main() !void {
    var heap: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(heap.deinit() == .ok);
    const allocator = heap.allocator();

    var context = try choir.Context.init(allocator, choir.Context.Limits.standard);
    defer context.deinit(allocator);
    try context.allowUnregistered();
}
```

The archive ships this program as the project in `examples/consumer`, with
`Limits.testing` in place of `Limits.standard`. Before each release,
`zig build run test` there builds and runs it against the archive on x86_64
Linux and Apple silicon macOS. The archive holds the sources Choir's build
compiles, and none of its tests.

## Code

- [Public namespace](src/root.zig)
- [IR model](src/core/root.zig)
- [Pass manager](src/passes/root.zig)
- [Backends](src/backends/root.zig)
- [Build steps](build.zig)
- [Consumer example](examples/consumer/src/main.zig)

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).
