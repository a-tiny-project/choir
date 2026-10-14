# Choir changelog

## v26.10.2

- The README teaches Choir through one program. It declares a `calc.powi`
  operation, rewrites `x^13` into five multiplications, compiles the result with
  the native JIT, and calls it. `examples/consumer` holds that program.
- A vertex or fragment stage reads one element of a uniform array by a run-time
  index with `gpu.uniform_element`. SPIR-V, MSL and the CPU twin lower it, and a
  draw's uniform window grows from 1024 to 2048 bytes.
- Native execution on Apple arm64 runs operations it refused before:
  - `arith.sqrt`, `fma`, `exp`, `log`, `sin`, `cos`, `tan`, `tanh`, `pow` and
    `floor` at `f32` and `f64`
  - the signed 64-bit overflow operations `arith.addo`, `subo` and `mulo`
  - `f32` comparisons, bitcasts between scalars of one width, and casts between
    `f32` and `f64` and between `f32` and the integer kinds
  - vectors: `splat`, `extract`, `insert`, the elementwise operations,
    `vec_cmp`, `vec_shuffle` and `vec_constant`
  - `memref.alloc` and `memref.dealloc`, through `malloc` and `free`
  - `memref.atomic_load`, `atomic_store`, `atomic_cas` and `fence`
- The x86-64 runtime runs the code it emits on macOS, where it ran only on
  Linux.
- Each native target declares the bounds it holds a program to, such as the
  values a loop carries and the bytes a frame holds, in `backends.x86_64.bounds`
  and `backends.aarch64.bounds`. A refusal past a bound carries the bound, its
  limit, what the program held, and what the refused step asked for.
- An x86-64 call passes at most 64 arguments. A call to an external symbol with
  more arguments compiled before and is now refused.
- `Runtime.functionPlacement` reports whether the target placed a function's
  values in registers or kept them in frame slots, and names the operation that
  kept them there. `Runtime.reported` keeps the stage, error and operation of
  the last failed compile. `Runtime.placeValues` turns placement off for the
  functions compiled after it.
- The x86-64 backend corrects code that computed wrong answers:
  - a parallel move that swaps two frame slots, or that moves reals in a cycle
    through frame slots
  - a call whose setup overwrote an argument before reading it
  - a value reloaded before a loop and read inside it
  - a 32-bit memory index, which carried the upper half of its register into the
    address
  - signed and unsigned comparisons of 8-bit and 16-bit integers
  - negation of float vector lanes, which now flips each lane's sign bit
- The x86-64 backend refuses programs it compiled wrongly before: a frame too
  large to address (`error.FrameTooLarge`), a memref whose byte size overflows
  (`error.MemrefTooLarge`), a `func.return` inside an `scf.while`, and an
  `scf.for` over a counter narrower than 32 bits.
- Code emitted for x86-64 stops at `ud2` where it went on with a wrong value
  before: at an allocation whose byte count overflows or whose `malloc` returns
  null, at a shift whose count is outside its operand's width, and at an 8-bit
  or 16-bit signed division of the minimum by -1.
- The x86-64 allocator gives register homes to unsigned words and reals that are
  compared, selected, passed to calls and returned. An integer operation takes a
  literal that fits 32 bits as an immediate, a call within one code image is
  relative, and a signed division by a power of two compiles to a shift.
- The verifier refuses a `func.return` whose operands differ from its function's
  results in count or type, and a `memref.atomic_cas` whose element is not a
  32-bit or 64-bit integer.
- The evaluator answers each arith result in a carrier of the result's own kind.
  An unsigned result reads zero-extended: a `u8` add of 127 and 1 answers 128,
  where it answered -128. `sqrt` of a negative operand answers a NaN, and a NaN
  that arithmetic produced is an attribute of its own, apart from a NaN whose
  bits are known.
- The evaluator names the failures arith declares: `DivisionByZero`,
  `SignedDivisionOverflow`, `InvalidShiftAmount` and `InvalidFloatToInteger`.
  The first three returned `InvalidOperand` before, and the last returned
  `UnsupportedOperation`.
- An effect enumerator receives an `EffectSubject` in place of its operation:
  `fn (EffectSubject, *Collector) void`. The subject offers the operation's own
  name, attributes, counts, types and arithmetic policy, and no path to other
  operations. `passes.effects.revisionAlloc` is public.
- A cached effect summary of a division by a constant no longer permits
  discarding the division after that constant is set to zero in place.
- A parallel pass runs on a pool the caller lends through
  `ThreadingOptions.pool`. Without one, a parallel call starts and joins its own
  threads.
- The bytecode decoder refuses a location that names itself or a later location
  with `error.InvalidTable`.
- A backend whose verifier runs out of memory answers `OutOfMemory`, where it
  answered `VerificationFailed`.
- A build no longer stops with `CompilerInputSymlinkDepthExceeded` when an
  include directory links to itself, as the one ncurses installs does.
- Dialect operation collection gives each declaration its own compile-time
  reflection allowance, so larger dialects compile without a local branch-quota
  override.
- The aarch64 backend reserves code before it emits a function, so a fresh
  runtime no longer counts its first function as outgrowing the reservation.
- An aarch64 runtime can turn placement off: `Runtime.placeValues(false)` keeps
  every value of every later function in its frame slot, as on x86_64, where it
  answered `FrameOnlyUnsupported`.
- A host that compiles one module at a time can lend all its runtimes one
  working store: `Runtime.initWithScratch` takes the target's `Scratch`, which
  on aarch64 is the placement plan. `initWithExecutablePolicy` still gives each
  runtime its own.
- An aarch64 function may hold 4,096 operations and 4,096 values, up from 1,024
  operations and 256 values, and a frame of 510 slots, 4,080 bytes, up from 64.
  A frame record past the 504 bytes `stp` reaches is saved and restored through
  x16. A function past an operation, value or frame bound is refused before any
  code is emitted, and the refusal names the bound, its figure and what the
  function asked for, which for operations is the function's whole count.
- Source-link build helpers take the source URL from explicit configuration or
  GitHub repository variables. Revision-only helpers resolve commits without a
  source URL.
- Build provenance preserves revision and version outputs when no source URL is
  configured. Consumers that read a source link receive the configuration
  diagnostic during compilation.
- A parallel call with `max_threads = 0` and no pool runs no more lanes than the
  process's cgroup v2 `cpu.max` quota allows, rounded up to whole CPUs. It used
  to start one lane per CPU the host reports.

Earlier releases are described at https://github.com/a-tiny-project/choir/releases.
