# flint:log acceptance traceability

Source: Section 6 of the [log specification](../../handoff/specs/tier-1/log.md).
Tests run with `dub test :log` on DMD and LDC. The fiber schedule is a fixed round-robin and the
concurrent-producer case checks properties that hold under any OS interleaving, so no test draws
random input and none needs a seed.

| # | Section 6 item | Covering test(s) | Status |
| --- | --- | --- | --- |
| 1a | JSON escaping for control bytes, quotes and Unicode | `tests/records.d:a structured record escapes control and Unicode bytes and copies borrowed message storage`; `source/flint/log/encoding.d:block fast paths escape and validate a special byte at every block offset`; `tests/records.d:console output remains one line and explicit context bypasses the convenience provider` (console escaping) | covered |
| 1b | Empty messages and fields | `tests/records.d:empty fields are valid, key bytes are validated, and revealing a sensitive key is explicit` (empty message, empty key and value); `tests/records.d:the complete encoded record accepts 4095 and 4096 bytes and rejects 4097` (`info("")`) | covered |
| 1c | 4095/4096/4097-byte records | `tests/records.d:the complete encoded record accepts 4095 and 4096 bytes and rejects 4097` (4097 is `resourceExhausted` and counted as dropped) | covered |
| 2a | Full ring | `tests/lifecycle.d:normal and error reserves saturate independently and close drains accepted records` | covered |
| 2b | Reserved error ring full | `tests/lifecycle.d:normal and error reserves saturate independently and close drains accepted records` (16 accepted, 17th `resourceExhausted`, dropped counter) | covered |
| 2c | Consumer failure | `tests/lifecycle.d:a native sink error is reported and subsequent producers see the fault` (`/dev/full`); `tests/lifecycle.d:the native sink reports a closed pipe without delivering SIGPIPE to the caller` | covered |
| 2d | Timeout flush | `tests/lifecycle.d:normal and error reserves saturate independently and close drains accepted records` (`flush(10)` is `timedOut`); `tests/lifecycle.d:native pipe output resumes a partial record without rewriting its accepted prefix` | covered |
| 2e | Close with pending records | `tests/lifecycle.d:normal and error reserves saturate independently and close drains accepted records` (close drains all 17); `tests/lifecycle.d:a drain deadline abandons a blocked sink and leaves flush able to report loss` | covered |
| 2f | Double close | `tests/lifecycle.d:normal and error reserves saturate independently and close drains accepted records` (two handle copies closed in turn; a later write is `unavailable`) | covered |
| 3 | Two interleaved fibers and an offloaded worker retain distinct request and trace IDs | `tests/concurrency.d:two interleaved fibers and an offloaded worker retain distinct request and trace identifiers` (round-robin scheduler installs and restores each task's context on every resume; worker passes a copied context explicitly; an unscoped worker call and a standalone call carry zero context) | added |
| 4 | No borrowed input survives return | `tests/records.d:a structured record escapes control and Unicode bytes and copies borrowed message storage` (message); `tests/records.d:mutating message, key and value storage after write leaves the emitted record unchanged` (key bytes, value bytes and the fields array) | covered + added |
| 5a | Hot producer per-thread GC allocation delta is zero | `tests/records.d:a structured record escapes control and Unicode bytes and copies borrowed message storage`; `tests/concurrency.d:32 concurrent producers publish valid complete JSON without allocating on producer threads` (per-thread delta on each of 32 threads) | covered |
| 5b | Valid JSON under 32 concurrent producers | `tests/concurrency.d:32 concurrent producers publish valid complete JSON without allocating on producer threads` (every line parses, per-request counts exact, `seq` strictly increasing) | covered |
| S-1 | FFI/kernel lifetime tests under the platform sanitizer jobs | `source/flint/log/sys/sinks.d` unittests and the native sink cases above | blocked (sanitizer job is a CI gate, not run in this pass; the native sink cases pass uninstrumented on DMD and LDC) |
