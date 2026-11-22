# CI performance budgets and evidence rules

## Scope and initial measurement

The caps in `../scaffold/policy/budgets.json` and `packages.json` are engineering targets. No baseline measurement is invented in this handoff. All six gate categories are represented in the workflows; the complete release gate is deliberately blocked until implementations, runner provisioning and measured evidence exist. During initial construction, an atomic slice passes its concrete package tests and structural gate. That result must never be described as full six-gate certification.

Establish the first baseline on the first working implementation commit, save its raw observations and content hashes, then protect that baseline. There is no meaningful percentage regression against a nonexistent implementation. The initial baseline review evaluates absolute caps, correctness, safety, target support and Go parity. Every subsequent implementation PR compares both base and candidate on the same freshly provisioned runner. The absence of an initial baseline is a visible setup prerequisite, not an automatic green result. This resolves the otherwise contradictory demand for regression measurements before any runtime exists.

## Runner contract

Required label: `flint-perf-x86_64-v1`. Provision an ephemeral Linux x86-64 bare-metal runner with a fixed CPU model, BIOS/microcode, kernel, governor, physical core count, RAM, compiler archives and native lock. Reserve two physical server cores and four load-generator cores (the supplied workload uses server CPUs 2–3 and client CPUs 4–7, with two workers in both applications); disable SMT siblings for those cores. Keep the agent, package downloads and builds outside the runtime measurement window. Record the actual CPU model rather than pretending all cloud vCPUs are equivalent. Use a separate client host for maximum-throughput runs if loopback/client CPU becomes limiting. A runner with different identity cannot compare to this baseline.

Absolute build-time gates do not run as blocking measurements on randomly loaded shared GitHub runners. Those runners perform correctness/platform checks and produce diagnostic timings. The dedicated runner performs the numeric gate. It is ephemeral, contains no deployment secrets, and is destroyed after each untrusted pull request. Cancellation and timeouts prevent runaway tests from retaining resources.

## Gates

| Gate | Required evidence and failure condition |
|---|---|
| 1 Quality/safety | dfmt byte comparison; D-Scanner findings checked; module `@safe:` policy; allowlisted small trusted functions with SAFETY comments; negative lifetime tests; D ASan and C-shim ASan/UBSan; bounded fuzz cases |
| 2 Architecture | Recipe graph and actual imports agree; no cycle/reverse-tier/CLI→web-data edge; forbidden imports rejected; five core packages compile and link in native BetterC and browser wasm32 probe closures |
| 3 Compile | Nine cold and nine changed-source incremental DMD/LDC observations per package and applicable canonical app; medians below hard caps; ratio of sample medians and its independent-sample 99% bootstrap upper bound ≤1.10; compiler RSS and template counts within both absolute and 10% growth caps |
| 4 Size | O3 and Oz stripped executable sizes; full privately shipped dependency closure counted for dynamic profiles; raw and deterministic-gzip WASM sizes; all hard caps and 1.05 growth ratios enforced |
| 5 Runtime/GC | Correctness-matched HTTP workload; nine independent load runs; p50/p99/p99.9, achieved throughput, CPU/request and peak RSS; 21-run microbenchmarks; zero monotonic GC allocation deltas on all relevant workers and zero collection delta during the measured interval |
| 6 Targets | Native execution on Linux x86-64/aarch64 glibc and musl, macOS arm64 and Windows x86-64; WASM execution with its JS ABI decoder; dynamic closure audit, C/D ABI probes and platform cancellation tests |

## Canonical application caps

| Application | DMD cold / incremental | LDC cold / incremental | Stripped size |
|---|---:|---:|---:|
| bench-cli | <1.5 s / <1.0 s | <12 s / <6 s | <3,000,000 bytes |
| bench-rest | <3.0 s / <1.0 s | <25 s / <10 s | <8,000,000 bytes |
| bench-wasm | not applicable to DMD wasm | <3.0 s / <1.0 s | <300,000 raw and <100,000 gzip bytes |

Per-package limits appear in the manifest and every spec. Their binary limit measures framework overhead over a monomorphic provider-equivalent counterpart: retain the same direct Flint dependencies and call the same selected native-provider operations directly through the pinned upstream C ABI, excluding the measured Flint package itself. Native preparation emits identical verified provider flags into both recipes. Flags alone do not defeat dead stripping; the reference must execute equivalent provider work with the same features, inputs and resource limits. Record each full binary's bytes and SHA256 beside `max(0, O3_feature−O3_baseline, Oz_feature−Oz_baseline)`. The small wrapper delta is never reported as the complete deployment footprint. For WASI, the 49,152-byte proposal applies to wrapper overhead over the same Wasmtime compile/instantiate/invoke workload; the complete engine-containing binary remains separately visible. No padding, unrelated live features, whole-archive retention or shared Flint implementation logic may inflate the reference. Empty-import dead-code elimination is not an acceptable probe. Native C dependencies are built before compile timing, but their delivered bytes are counted in size. Record clean source/prepared dependency cache status explicitly; do not include network time in one language's compiler measurement and omit it in the other.

## Workload equivalence and statistical rules

The minimal REST benchmark has `GET /health` and `GET /json`, identical status/headers/body, HTTP/1.1 keepalive, fixed response bytes and no TLS/database/logging in either implementation. It tests the transport/router/serializer baseline, not the golden database service. Add separately named TLS/HTTP2/database scenarios with identical functionality on both sides. A win on the minimal profile is not generalized to every production application.

Use one below-saturation open-loop offered rate to compare latency without hiding queueing; calibrate it from the lower baseline capacity and freeze it for both sides. Record offered/achieved rates, all errors and dropped work; overload failures are counted as failures rather than omitted fast requests. Use a separate saturation sweep for throughput, also with an error budget of zero. Never compare p99 measured at different offered rates. Warm up for 10 seconds and measure for 60 seconds per run. The HTTP harness alternates Flint/Go order within each checkout and retains individual run histograms. The current CI coordinator measures the base checkout first and the candidate second on the same host; it records this block order and does not claim temporal pairing between commits. Report p99.9 only when at least 100,000 successful requests are observed per run.

Use ratios of run-level medians and deterministic 10,000-resample independent-sample bootstrap intervals: resample each group separately, without pairing observations by array index. Same-host block ordering still leaves a possible thermal, frequency or system-load drift effect; fingerprints and confidence intervals cannot remove that bias. A suspected drift failure requires a documented infrastructure investigation and fresh measurements, not a claim that the samples were temporally paired. A regression exceeding 5% in latency/RSS/CPU or a throughput decrease over 5% fails; if the upper interval crosses the permitted bound, the result is inconclusive and therefore blocking until rerun on a stable runner. Do not repeatedly rerun until a favorable sample appears. A designated diagnostic rerun is allowed once after an identified infrastructure cause is logged; otherwise the PR remains blocked.

The Go superiority profile requires at least 1% favorable differences with the interval on the favorable side for throughput, p99, RSS and CPU/request, plus smaller release binaries and faster cold DMD builds. This is deliberately stronger than calling an indistinguishable result a win. The Go reference uses the exact pinned Go compiler, `-trimpath -ldflags=-s -w`, matched worker settings and no handicap.

## Allocation and compiler metrics

`GC.allocatedInCurrentThread()` is read on each participating thread before and after the request barrier. Thread count and all per-thread deltas are included. The process `GC.profileStats().numCollections` delta must also be zero. C malloc, retained pools and process RSS are distinct metrics; @nogc does not mean no native allocation. GC-disabled execution still checks allocated-byte deltas and cannot excuse a growing native heap.

Measure compiler peak RSS with the complete build process tree on the dedicated Linux runner. Retain `-vtemplates=list-instances` and explicit time-trace files; the pinned trace parser version is part of the environment fingerprint. Count instantiated template contexts consistently. A changed parser/compiler makes the baseline incompatible and requires reviewed remeasurement, never a silent new denominator.

## Baseline and policy changes

Candidate code is prohibited by review policy from changing the base checkout or its observations. The supplied same-user, same-host workflow does not provide an operating-system isolation boundary between checkouts. Protected governance files, required human review of policy changes and a disposable runner are therefore part of the trust model; artifact hashes are integrity checks, not proof against a malicious producer. Baseline artifacts are keyed by commit, workload hash, toolchain hash, target, feature configuration and native lock. Budget/workload/required-check changes are protected by repository review rules and the repository's explicitly configured baseline review policy. The handoff cannot create those account-specific settings without a destination repository. `tools/configure_github.py --repo OWNER/REPO` provides a concrete API operation for the owner to apply after selecting the repo.

Increasing a budget requires an ADR with raw before/after samples, explanation, user-visible feature benefit and mitigation options. Accepted increases are explicit history; they are never hidden as “noise”. No baseline update can change correctness payloads, skip cross-platform checks or weaken safety tests as an incidental side effect.
