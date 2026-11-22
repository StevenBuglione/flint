# ADR-017: Milestone 6 scope and behaviour decisions

Status: accepted by the project owner on 2026-11-21.

## Context

Milestone 6 freezes the API, runs the empirical gates and prepares a release. Several of its requirements need the project owner's choices, and the Milestone 1–5 review left behaviour questions open.

## Decisions

1. **Designated performance runner.** The project workstation (AMD Ryzen 9 5900X, NixOS) acts as `flint-perf-x86_64-v1`. Its identity is fingerprinted in every evidence bundle; server benchmarks use CPUs 2–3 and the load generator CPUs 4–7, with their SMT siblings kept idle. It is not ephemeral; evidence records that fact rather than claiming otherwise.
2. **Platform scope.** Milestone 6 completes Linux x86-64 and aarch64, glibc and static musl, plus wasm32. macOS arm64 and Windows x86-64 stay visibly incomplete; Gate 6 reports them as failing rather than removing them.
3. **Provenance.** Release artifacts are signed with Sigstore keyless signing; a project-owner GPG key is the fallback.
4. **CI.** GitHub Actions stays disabled; all evidence is produced and retained locally.
5. **ADR-016** is accepted: a resident compile server holding only druntime and Phobos counts as a retained toolchain runtime.
6. **Desktop.** The desktop package is redesigned after Tauri's architecture, implemented in D over the platform C libraries (GTK and WebKitGTK on Linux), never by wrapping Rust crates. Its spec change and LGPL deployment profile are reviewed through their own ADR.
7. **io_uring cancellation.** A read that completed with data before its cancellation took effect is delivered as a successful completion with that data, as on epoll.
8. **DI lifecycle.** `@PreDestroy` runs only for beans whose `@PostConstruct` succeeded, as the specification states.
9. **Shared configuration files.** Several `@ConfigurationProperties` types may bind from one file; unknown-key rejection applies to keys that no bound prefix claims.
10. **Floating-point output.** Serde writes the shortest decimal that round-trips, as Go does.
11. **HTTP.** Responses carry a `Date` header; a known path with an unsupported method returns 405 with `Allow`.
12. **JetStream.** The client reconnects automatically after a transport error or timeout.
13. **Integration.** `codex/flint-milestones` merges to `main` through a pull request only after Milestone 6 passes.
14. **Size margin.** REST's Oz size at 0.981 of Go is a guardrail; changes must not cross 0.99.

## Consequences

The full `tools/gates.py --gate all` cannot pass while two required platforms are out of scope; the milestone report states this explicitly instead of weakening the gate.

## Public API additions

The handoff archive under `handoff/` stays byte-identical to its `MANIFEST.sha256`; additions that the decisions require are recorded here instead of being edited into the frozen specifications and contracts.

- **Decision 9:** `flint.config` adds one overload beside `load!T`:

  ```d
  Error load(T...)(scope const ref ConfigOptions options, ref T values) if (T.length != 0);
  ```

  It reads the files, `.env`, environment and arguments once and binds every value from that one snapshot; types may share a prefix. With `rejectUnknownKeys`, a key is unknown only when no bound type's schema claims it, so a misspelt key inside a bound prefix is still rejected with the same diagnostic as `load!T`. On failure every value is reset to its initializer and the earliest diagnostic by key is returned. `load!T` keeps single-type semantics.

- **Fiber wake-up.** Owner fibers waiting for stream or HTTP-client progress had no completion wake-up. They resumed on every loop pass for 200 µs and then polled every 1 ms, so a peer slower than 200 µs paid up to 1 ms per wait plus 200 µs of spinning. `flint.reactor` adds a targeted wake and a wait that also observes a caller's context:

  ```d
  struct TaskWaker { uint ownerCore = uint.max; uint slot; ulong generation; bool valid() const pure nothrow @nogc; }
  Result!TaskWaker currentWaker() const nothrow @nogc;              // member of Reactor
  Error wake(TaskWaker waker) nothrow @nogc;                         // member of Reactor
  Error yieldUntil(Deadline deadline, ref scope const Context watched) nothrow @nogc; // member of Reactor
  ```

  `wake` is callable only on the owner loop. It marks a suspended fiber due, so the loop's next `resumeReadyTasks` pass resumes it before blocking. Waking a running or already due fiber does nothing, so waiters re-check their condition before yielding. Each task start gives its fiber slot a new generation, and a handle that outlives its task is rejected with `notFound`. The `yieldUntil` overload also ends the yield when the owner loop sees `watched` cancelled or expired, on the same per-pass check it already applies to the task's own context, so a wait on a handler-created context needs no polling. HTTP/1 read and write completions and close wake a streaming handler. HTTP/2 stream events, output drained by the provider and connection abort wake a stream's handler. The HTTP client keeps a list of waiting fibers per owner and wakes them on native readiness, on a libcurl timer fired by any fiber, and when a fiber's own call moves libcurl's timer ahead of another waiter's wake. Each waiter also sleeps no later than libcurl's next timer, read through the new internal C export `flint_http_timer`. The spin windows are gone. A 1 s fallback deadline remains only as a safety net against a missed wake (see `streamFallbackNanos` and the client's `fallbackMillis`). It never fires on a correct path. At one resumption per second, ten thousand idle stream waiters cost about 10,000 resumptions per second in total.

## Measurement method changes

The first two changes were made before any baseline was recorded, and the milestone report shows counts under the old and new method. The next two were made after official performance runs at `96e475e` and `5f96e22`, whose results the report keeps. The last came from the AArch64 replay at `00ea4fc`.

- **Template counts per target.** `tools/measure_builds.py` counts template instantiations in a separate instrumented build. That build now uses one compiler invocation per target (`FLINT_DUB_PIPELINE=0`), as upstream DUB does. The Flint DUB pipeline splits targets into chunks sized by the host's hardware threads, and every chunk re-instantiates the shared druntime templates. A chunked count therefore depended on the machine, not the code (arena's probe counted 9,946 chunked vs 6,646 per target). Timed builds still use the pipeline.
- **Probe scaffolding without Phobos.** Package probes printed their reports with `std.stdio`/`std.format`/`std.conv`. That scaffolding alone was most of each probe's template count and much of its compile time: arena's probe counted 6,646 instantiations, of which the arena package contributed 21. The probes now print through `core.stdc` with byte-identical output apart from timing fields. Workloads, checksums and baselines are unchanged, and Phobos remains wherever it is part of a baseline's equivalent operation or of result validation. Feature and baseline share the harness, so size deltas are unaffected.
- **Compile server primed before DMD trials.** ADR-016 lets cold trials start with the compile server running for the measured flags and requires the report to state the first build without a server. `tools/measure_builds.py` did neither: trial 0 of each fixture started the server, and because the server key includes each fixture's `-version` flags, every fixture started its own. Its prelude analysis and worker pre-forking ran beside the next trials. In the run at `96e475e`, bench-cli trials 1 and 2 took 0.275 s and 0.162 s against 0.095–0.145 s for the rest, so the median ratio to Go (0.985) passed while its 99% upper bound (1.449) did not. Each DMD fixture now records one build with `FLINT_DMD_SERVER=0` as `dmd_first_build_seconds`, then runs two unscored builds that start the server before trial 0. Both appear in the trial receipts as states `first` and `prime`. LDC, which has no server, and Go, which already primed its standard library, are unchanged.
- **Process-tree RSS sampled without a host-wide scan.** Every timed build is polled each millisecond for the summed RSS of its process tree. The poller used psutil's `children(recursive=True)`, which reads the status of every process on the host (about 800 here) on each call, so the poller itself took CPU from the build it was timing. Alternating timed and untimed builds showed it lengthening the parallel DMD CLI build by 9 ms (94 → 103 ms) and the Go CLI build by 5 ms (110 → 115 ms). At `5f96e22` the CLI ratio's 99% upper bound was 1.0005. `timed_process` now reads `/proc/<pid>/stat` only for PIDs allocated since the build started, falling back to a full scan if PIDs wrap. The sampled quantity and its 1 ms interval are unchanged and agree with psutil on a live build. With it, two replications of the nine-trial CLI comparison gave ratios 0.885 (upper 0.923) and 0.874 (upper 0.905).
- **Wall-clock test bounds under emulation.** Five package tests assert wall-clock bounds that show the absence of a polling stall:
  - os child reaping under 3 ms;
  - SQL lease handoffs and full-queue rejection;
  - Web streamed and echoed responses;
  - HTTP client exchanges on a reused connection.

  The AArch64 lanes run these tests in a full-system QEMU guest, where a plain C `fork`/`exec`/`wait` alone takes 4.5–5 ms and a loopback round trip 0.5–0.7 ms, so those bounds measure the emulator. A lane running under emulation sets `FLINT_EMULATED=1`. The tests then print each measurement with its bound instead of asserting it, and every functional check still runs. Native lanes do not set the variable, and the bounds are enforced there as before. The replay at `00ea4fc` also exposed two test defects, which were fixed rather than relaxed:
  - a cancellation-order check had a 1 µs deadline margin;
  - the SQL saturation test could hang `close` after a failed check, raced its own probe against waiters re-queuing, and gave probes that must be rejected a 1 ms deadline that a starved thread could pass before `acquire` reached the queue; it also assumed no queued wait would reach the specified min(deadline, 5 s) bound, which a heavily loaded host can exceed during the saturation phase. Such waiters now re-queue, and the probes accept the other outcome only after one has.
