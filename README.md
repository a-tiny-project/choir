<p align="center">
  <img src="logo.svg" alt="Choir" width="360" />
</p>

# Choir v26.6.2

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
gh release download v26.6.2 --repo a-tiny-project/choir --pattern 'choir-v26.6.2.tar.gz'
tar -xzf choir-v26.6.2.tar.gz
```

Choir builds with a development release of Zig, `0.17.0-dev.1465+8b2d0ce21`,
plus two patches listed in
[nix/zig-consumer-patches.list](nix/zig-consumer-patches.list). One forwards the
target's object format and dynamic linker to the build scripts of dependencies.
The other keeps the LLVM backend from giving under-aligned structs and unions a
larger alignment than Zig declares for them. The extracted directory is a Nix
flake, and its default development shell supplies this compiler on Linux and
macOS. A project that depends on Choir enters that shell and fetches the
archive:

```sh
nix develop /path/to/choir-v26.6.2
zig fetch --save=choir /path/to/choir-v26.6.2.tar.gz
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

Before each release, a fresh project builds and runs this program against the
archive on Linux and macOS, with `Limits.testing` in place of `Limits.standard`.
Inside the development shell, `zig build test` at the archive root runs Choir's
unit tests.

## Code

- [Public namespace](src/root.zig)
- [IR model](src/core/root.zig)
- [Pass manager](src/passes/root.zig)
- [Backends](src/backends/root.zig)
- [Build and test steps](build.zig)

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).
