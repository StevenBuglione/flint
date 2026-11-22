# Arena

[`flint.arena`](source/flint/arena/package.d) implements the [arena contract](../../handoff/specs/tier-0/arena.md). `RequestArena` borrows caller-owned backing. Nonempty allocations align to the backing address and clear their bytes before returning. Empty allocations return valid zero-length handles and leave the cursor unchanged.

Handles carry a process-unique owner, an epoch, and a checked byte range. Scoped visitors prevent slice escape under DIP1000. Reentrant visitors may use valid handles while reset returns `conflict`. Reset preserves the recorded peak, advances the epoch, and retires the arena if the epoch would wrap. Arena and pool moves preserve the prior owner only in the destination. Moving, overwriting, or explicitly destroying a borrowed owner halts at the lifetime boundary.

The native worker-local slab pool uses fixed backing and metadata supplied at startup. A lease carries its pool identity and generation. Release during a visitor returns `conflict`, and checkout clears reused blocks. The caller retains ownership of the backing and metadata for the lifetime of the pool.

## Verification

- DMD 2.114.0 and LDC 1.43.0 passed the DUB unit suites. Both compilers rejected escaped callback/backing storage, forged buffers, and a GC-allocating callback.
- The pinned LDC passed the seeded reuse suite with ASan, leak detection, and stack-use-after-return detection enabled.
- The package fixture linked and executed as native BetterC on both compilers and as wasm32 BetterC under Node. The WASM test host rejected an intentionally built shared-memory fixture.
- The structural gate and pinned formatting and static analysis checks passed.
- The isolated native lifetime fixture passed in debug and release on both compilers. Quiescent moves and destruction preserved ownership checks, and all active moves, overwrites, and destruction attempts terminated before their visitors could return.

Exact commands, exits, log hashes and diagnostic benchmark samples are in `artifacts/tasks/m1-arena/results.json` on the development host. The receipt SHA-256 is `e043c07d0f880ed4901b5b2a48ef3b348071c5f71fa2601fc110cf231f6de176`. The toolchain lock SHA-256 is `6a049639e452c0e7b9b98175faf1abff69613bdc2d04e0602e0d71923e6111d6`.

## Benchmarks

From the repository root, run `dub run --root=packages/arena/bench --compiler=ldc2` and `dub run --root=packages/arena/bench/baseline --compiler=ldc2`. The probes measure 64-byte and 4096-byte allocations, 1,000 64-byte allocations before a reset, and a checked read. Each case runs for at least 150 ms and reports operations, elapsed time, bytes zeroed per operation, and a consumed checksum. The baseline uses the same timing harness and a caller-owned array.

Local O3 and Oz ThinLTO probes executed successfully. The stripped feature-minus-baseline size deltas were 4,256 bytes at O3 and 4,256 bytes at Oz. The full cross-platform acceptance and designated-runner release performance measurements are pending.
