# Flint concurrency

`flint.conc` provides monotonic deadlines, ref-counted cancellation contexts,
bounded MPSC and MPMC channels, and blocking-work offload. The public API is
defined in the [concurrency specification](../../handoff/specs/tier-0/conc.md).

- The cancellation slab holds up to 16,384 live sources and retained contexts.
  Each node retains its parent. Closing a source releases the owner reference,
  and context copies preserve the identity until their last copy is destroyed.
  Cancellation and deadline comparison are ordered under one slab lock.
- Channels allocate a bounded ring at creation. The producer gate serializes
  publication and close. MPSC relies on a single consumer, and MPMC serializes
  consumption with a separate gate. The cell sequence synchronizes payload
  publication and reuse across the producer and consumer gates. Destroy a
  channel after all callers have finished using it.
- Each worker slot owns up to 4 KiB of input and 4 KiB of output. A live ticket
  occupies its slot through execution and collection. Polling `join` reports
  `unavailable` while work is active. A small output buffer can retry. Shutdown
  waits for running calls, discards queued work, and retires every ticket.

## Verification

`dub test :conc --compiler=dmd` and `dub test :conc --compiler=ldc2` run
cancellation and queue lifetime tests, compiler rejection checks for forbidden
transfer types, concurrent FIFO history replay, reduced-counter wraparound,
arena-copy offload, completion races, and shutdown. The package also passes the
structural gate and pinned formatter and D-Scanner checks. Linux x86-64
glibc behavior runs under LDC AddressSanitizer with leak detection. Linux
x86-64 musl passes with a statically linked executable in an empty root. The
other native targets have source-level type checks and require runtime receipts.

The feature and control executables in `bench/` produce a digest from their
release-mode workload. Pass `--measure` to collect diagnostic queue throughput,
rejections and p99 enqueue latency, and to time the 4 KiB round trips. The
feature also times cancellation checks. Release performance budgets require
the designated runner and complete recorded evidence.
