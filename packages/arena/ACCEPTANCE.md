# flint:arena acceptance traceability

Source: Section 6 of the [arena specification](../../handoff/specs/tier-0/arena.md).
Unit tests run with `dub test :arena` on DMD and LDC. Compile-negative and lifetime fixtures run with
`python3 packages/arena/negative/check.py <dmd|ldc2>`; the shared `tests/compile` fixtures are also run by
`tools/ci.py check --gate safety`. The BetterC fixture `tests/betterc.d` runs under `tools/ci.py check --gate betterc`
(native DMD and LDC) and the wasm32 lane of `tools/ci.py platform-run`. Generated schedules use fixed xorshift seeds
(`0xb94752ab`, `0x0ddba11`).

| # | Section 6 item | Covering test(s) | Status |
| --- | --- | --- | --- |
| 1a | Allocate alignments 1, 2, 8, 16, 4096 | `tests/arena_behavior.d:alignment is based on the actual backing address` (odd backing address; every slice pointer checked); `tests/arena_behavior.d:seeded allocation and reuse preserve bounds, identity and initialized bytes` (alignments 1..4096, seed `0xb94752ab`) | covered |
| 1b | Reject alignments 0, 3 and 8192 without changing the cursor | `tests/arena_behavior.d:alignment is based on the actual backing address` (`invalidArgument`, `used` unchanged) | covered |
| 2a | Allocate exactly capacity and capacity+1 | `tests/arena_behavior.d:capacity and padding checks leave arena usage intact on failure`; `tests/arena_behavior.d:every outOfMemory path, including overflowing padding, preserves cursor, peak and live bytes` (exact remainder succeeds after every failure) | covered + added |
| 2b | `size_t.max` and overflowing padding | `tests/arena_behavior.d:capacity and padding checks leave arena usage intact on failure`; `tests/arena_behavior.d:every outOfMemory path, including overflowing padding, preserves cursor, peak and live bytes` (`size_t.max` and `size_t.max - remaining + 1` at every alignment; padding to 4096 larger than the remainder; oversized `copyIn` and `append`) | covered + added |
| 2c | `outOfMemory` never corrupts state | `tests/arena_behavior.d:every outOfMemory path, including overflowing padding, preserves cursor, peak and live bytes` (used, peak, capacity, resets, live handle bytes and append handle length unchanged after each failure) | added |
| 3a | Stale owner | `tests/arena_behavior.d:a new arena at the same backing address receives a unique owner`; `source/flint/arena/package.d:an arena constructed after owner identities are exhausted fails permanently`; `source/flint/arena/sys/owner.d:native owner IDs saturate without recycling` | covered + added |
| 3b | Stale epoch | `tests/arena_behavior.d:invalid, foreign and expired handles never enter the visitor`; `tests/arena_behavior.d:seeded allocation and reuse preserve bounds, identity and initialized bytes`; `tests/arena_behavior.d:reentrant writes, reset during write and empty slices keep the borrow consistent` (stale handles rejected by `write`) | covered + added |
| 3c | `.init` handle | `tests/arena_behavior.d:invalid, foreign and expired handles never enter the visitor` | covered |
| 3d | Reset during read (and write) | `tests/arena_behavior.d:nested read and write retain the active borrow until the outer visitor returns`; `tests/arena_behavior.d:reentrant writes, reset during write and empty slices keep the borrow consistent`; `source/flint/arena/package.d:borrow count cannot roll over` | covered + added |
| 3e | Reentrant write | `tests/arena_behavior.d:nested read and write retain the active borrow until the outer visitor returns` (write inside read); `tests/arena_behavior.d:reentrant writes, reset during write and empty slices keep the borrow consistent` (write inside write, three levels) | covered + added |
| 3f | Empty slice | `tests/arena_behavior.d:zero capacity accepts a valid empty handle`; `tests/arena_behavior.d:reentrant writes, reset during write and empty slices keep the borrow consistent` (zero-length write, zero-length handle stays valid after later allocations and expires with its epoch) | covered + added |
| 3g | Double reset | `tests/arena_behavior.d:invalid, foreign and expired handles never enter the visitor`; `tests/arena_behavior.d:reentrant writes, reset during write and empty slices keep the borrow consistent` | covered |
| 3h | Epoch exhaustion | `source/flint/arena/package.d:epoch exhaustion retires the arena and invalidates its outstanding handles` | covered |
| 4a | Poison/reset/reuse backing exposes no previous request content | `tests/arena_behavior.d:allocation clears storage and copy-in preserves overlapping input`; `tests/arena_behavior.d:seeded allocation and reuse preserve bounds, identity and initialized bytes`; `tests/arena_behavior.d:poisoned and reused backing never exposes a previous request, and handles stay bound to their arena` (0xA5-poisoned backing, 64 seeded requests with distinct fill patterns, and a fresh arena over the same poisoned bytes; seed `0x0ddba11`) | covered + added |
| 4b | Handles for arena A fail against B | `tests/arena_behavior.d:invalid, foreign and expired handles never enter the visitor` (read); `tests/arena_behavior.d:append joins parser fragments and preserves prefix handles and bounds on failure` (append); `tests/arena_behavior.d:poisoned and reused backing never exposes a previous request, and handles stay bound to their arena` (identical epoch/offset/length in both directions for read, write and append) | covered + added |
| 5a | Compile-fail: returning an arena backed by a local array | `tests/compile/escape_storage.d` (shared, via `tools/ci.py check --gate safety` and `negative/check.py`); `negative/escape_parameter.d` (backed by a `scope` parameter) | covered + added |
| 5b | Compile-fail: assigning a callback slice to a global | `tests/compile/escape_borrow.d` (read visitor); `negative/escape_write.d` (write visitor) | covered + added |
| 5c | Compile-fail: calling a non-@nogc function inside the callback | `negative/callback_gc.d` (previously had no runner; now run by `negative/check.py` and matched to the specific `@nogc` diagnostic) | added |

Related evidence beyond Section 6, also run by `negative/check.py`: `tests/compile/forge_buffer.d` (handles cannot be
fabricated) and `negative/active_borrow.d`, built with debug and release flags. In that fixture quiescent arena and pool
moves and destruction keep their ownership checks. Moving, overwriting or destroying an arena or pool that is lent to a
visitor dies with SIGABRT before the visitor returns.

Not run locally: the sanitizer job for this package. The FFI/kernel lifetime rule ("run under the platform sanitizer
jobs") needs `tools/ci.py check --gate sanitizers`, which requires Clang 22.1.8; that Clang is not installed here. The
arena has no FFI; its only `sys` code is the atomic owner counter and the abort helper, both covered above.

No always-success or stub behaviour was found. Every error return is reached by a test above.
