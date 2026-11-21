# Required measurement producers

This is an implementation contract. The handoff contains compiler-checked application sources, real measurement tools and deliberately source-free package probe recipes. It does not contain an implementation of Flint or a performance baseline. Missing framework code, probes, measurements, command receipts or target runs must stop the release workflow.

## Build and size producer

Run from the bootstrapped repository, after native preparation and after committing the implementation and benchmark sources:

```sh
python3 tools/native_build.py --profile ci --target linux-x86_64-glibc --phase build --emit-dub
python3 tools/measure_builds.py --manifest policy/build-benchmarks.json --output artifacts/builds.json --dmd dmd --ldc ldc2 --dub dub --go go --strip strip
```

Every package must provide `packages/<name>/bench/source/app.d` and `packages/<name>/bench/baseline/source/app.d`. Both recipes are already present. Follow the adjacent `PROBE_CONTRACT.md`: the feature program must execute a representative public operation with observable output; its provider-equivalent counterpart must exercise the common direct Flint dependency work and, when selected, the same upstream native-provider operations through the C ABI without importing the measured Flint package. Empty imports, unreachable calls and an identical baseline with the feature omitted by constant folding are invalid. The runtime implementation goes under the package's `source` directory; declaration-only files in the handoff's `contracts` directory must never satisfy this producer.

The manifest names the canonical public module to edit. The tool accepts either a flat `flint/name.d` module or its package form `flint/name/package.d`. It appends a private declaration to the actual existing source and retains the edited source path in each incremental observation. A no-op DUB invocation is not an incremental sample.

Cold means a fresh source copy and a fresh `DUB_HOME`, with no project D objects or DUB build cache. The verified, prepared native install prefix and the toolchain's precompiled runtimes are shared immutable inputs; downloads, C compilation and operating-system page-cache eviction are outside the timed interval. `--cache=local` alone does not isolate DUB 1.43's build cache. The producer checks committed source identity, allowing only native recipe blocks that exactly match `native_build.Builder.dub_blocks()` after rehashing the installed archives. Arbitrary changes between the native marker comments are rejected. All other source and recipe changes must be committed.

Native profiles use `dub build --build=plain` with explicit `DFLAGS`. A real DUB 1.43 probe showed that `--build=debug` still supplies `-debug -g` when release flags are supplied through `DFLAGS`; the producer does not rely on the help text's broad “override” wording. The development profile is DMD, DIP1000, debug symbols and bounds checks. Both LDC profiles enable DIP1000, O3 or Oz, release assertions policy, bounds checks in safe code and ThinLTO. On the verified Linux runner, the system `cc`/`ld` with the official archive's `LLVMgold-ldc.so` plugin successfully links ThinLTO. An external LLD 22 is an optional explicitly selected alternative. Native `-link-internally` is excluded because the tested invocation failed CRT lookup.

There are nine cold and nine edited-source observations for each of 37 package probes and the two native canonical apps under both DMD and LDC. WASM uses the actual exports module, all its source files, bulk-memory support, `-checkaction=halt` and internal LLD. Its edited-source measurement is a full direct recompilation; the tool does not claim an incremental object cache that it does not use. Go gets a separately primed standard-library-only cache copied afresh for each cold app build; the app itself has no cached objects. The reference paths are `examples/reference-go-cli` and `examples/reference-go-rest` after bootstrap. Go app builds and the standard-library primer use `-buildvcs=false`; the source commit is recorded separately, so ambient Git discovery cannot change a copied-source experiment.

The memory measurement sums RSS for the build process and all observed descendants at one-millisecond intervals. It is a sampled process-tree peak, and can miss shorter peaks. Each compiler, linker, configuration file, optional LLVMgold plugin and measurement protocol has a hash in the evidence. A separate instrumented DMD build clears its trace directory on every retry, handles DUB response files, skips the DUB platform-detection probe, and counts actual `vtemplate: N (M distinct) instantiation(s)` output and emits one explicit trace per compiler invocation. Instrumentation overhead does not enter the edit-loop timing samples. A successful build can legitimately instantiate zero templates.

The size producer links and strips both O3 and Oz native programs. It preserves complete feature and provider-equivalent baseline sizes, hashes and their signed difference. Native preparation emits the identical verified provider block into both recipes, and source identity validation checks both. The baseline must actually execute the same provider workload: a link flag for an otherwise unused static archive is insufficient. Both probe source hashes and the selected native profile are frozen comparison inputs. Absolute installation prefixes are normalized only in that separately validated native-profile fingerprint, so equivalent base/candidate worktrees remain comparable. Link layout and optimization can make that signed difference zero or negative; the budget metric is `max(0, O3_difference, Oz_difference)`, with the raw signed results retained. No artificial positive minimum is invented. This is framework overhead, not the complete provider-containing deployment size. For WASI, the baseline must compile, instantiate and invoke the same guest with the same Wasmtime options and limits. Its full engine/dependency/harness footprint is reported, not falsely attributed as an isolated C-only byte count. Full application ceilings still include all retained native code. LDC explicitly selects static default D runtimes. Native dependency libraries are prepared static archives and their retained machine code contributes to the linked executable. `readelf --wide --dynamic` audits every native size probe and canonical app; only the explicit Linux system-runtime allowlist may appear in DT_NEEDED. An unexpected private shared library fails this profile. Privately shipped dynamic dependencies, if introduced by a later profile, require an explicit closure measurement before that profile is accepted. WASM records raw bytes and deterministic gzip with level 9 and mtime 0. Build artifacts published for later load tests are `build/bench-cli`, `build/bench-rest`, `build/reference-go-cli`, `build/reference-go-rest` and `build/bench.wasm`. Native Oz counterparts (`build/bench-cli-Oz`, `build/bench-rest-Oz`) and `build/bench-wasm-Oz.wasm` are also retained. The collector reads the actual published bytes and recomputes raw/gzip sizes, then includes those binaries in the portable evidence bundle.

## Microbenchmark producer

Implement `benchmarks/micro/dub.sdl` and `benchmarks/micro/source/app.d`. Use path dependencies on the required Flint packages. The executable writes exactly one JSON object to stdout after all measurements; compiler diagnostics, progress and human summaries belong on stderr. A failed assertion, unsupported backend or incomplete trial exits nonzero. Do not print hard-coded timing arrays.

The required output is this shape, with **21 measured positive finite values in every array**:

```json
{
  "unit": "nanoseconds_per_operation",
  "micro": {
    "arena": [],
    "serde": [],
    "validate": [],
    "router": [],
    "reactor_echo": []
  }
}
```

The empty arrays above describe the schema and are rejected as measurements. Include extra metadata such as iteration counts, fixture hashes, checksums, timer frequency and backend. Use a monotonic high-resolution clock, discard warmup work, run enough inner operations to exceed timer resolution, divide by the actual completed operation count, and retain one aggregate per independent trial. Checksums or consumed results must prevent the optimizer from deleting measured work. Startup, fixture preparation and reporting remain outside the timed interval; a fake clock or compiler-only probe is not evidence.

| Series | Required operation and correctness check |
|---|---|
| arena | Allocate, write, read and reset through generation-checked handles in a fixed 64 KiB backing region; check sizes, copied bytes and stale-handle rejection outside the timed loop. |
| serde | Encode and decode the same typed 26-byte JSON response used by the REST fixture; check every decoded field and output bytes. Include TOML in a separately named diagnostic benchmark, not by silently changing this frozen series. |
| validate | Validate the frozen DTO containing ASCII and Unicode whitespace, range and text length constraints; include both valid and invalid cases in a fixed deterministic ratio and check error counts. |
| router | Dispatch a frozen table containing literal, parameter and wildcard routes, including misses; check selected handler and captured parameters. Record the table and request corpus digest. |
| reactor_echo | Complete real loopback socket echo operations through Flint's configured native reactor, with fixed payload and connection counts; verify every received byte, cancellation completion and no outstanding operations at trial end. An in-memory queue or no-op callback is not an I/O benchmark. |

Freeze fixtures and iteration policy in committed files before establishing the first baseline. A changed workload is a new baseline experiment, not a candidate speedup.

## Hot-path GC producer

Implement `benchmarks/hot-gc/dub.sdl` and `benchmarks/hot-gc/source/app.d`. It must run the same real transport, router and serializer path as the minimal REST benchmark, with a separate client process or preallocated client machinery. A direct call to an empty handler does not establish allocation behavior of a server request.

Startup may allocate: construct services, worker threads, request arenas, logging/context buffers and sample storage before warmup. Warm the actual request path for at least 10,000 successful requests. Keep normal automatic collection enabled during the measured interval. There must be at least 100,000 completed verified requests in that interval, no errors, no workers created or destroyed, and no cold lazy initialization hidden after the first sample.

Use two complete barriers over every server thread that can execute request-related work, including reactors and any logger/worker thread. Preallocate each worker's numeric sampling slot. At the first barrier, each participating thread records its own `GC.allocatedInCurrentThread()` counter and numeric identity; the coordinator records `GC.profileStats().numCollections` only after all workers are ready and before releasing measured work. At the second barrier, stop admitting requests, drain all request callbacks and completions, then sample the same thread set again before reporting. The sampling and coordination path must not allocate inside this interval. Merely sampling the main thread does not test worker allocations. A sum of current live bytes can fall after collection and is not a replacement for the monotonic allocated-byte counters.

The pinned druntime declaration of `GC.allocatedInCurrentThread()` does not itself expose every desired `@safe @nogc` annotation. Keep instrumentation at the audited benchmark boundary; do not cast function attributes to make it look like a checked hot API. `GC.stats().allocatedInCurrentThread` is the same counter with a different access cost if its verified declaration fits the sampler. Request functions still obey their genuine compile-time `@safe nothrow @nogc` contracts.

The exact required payload is:

```json
{
  "gc": {
    "phase": "steady_state",
    "requests_completed": 100000,
    "worker_count": 2,
    "worker_ids": [101, 102],
    "before_barrier_workers": 2,
    "after_barrier_workers": 2,
    "allocated_before_per_worker": [4000, 8000],
    "allocated_after_per_worker": [4000, 8000],
    "allocated_bytes_per_worker": [0, 0],
    "collections_before": 1,
    "collections_after": 1,
    "collection_delta": 0
  }
}
```

Those numbers are schema examples, not observations and not a baseline. Emit actual counters. The collector recomputes all differences, rejects counter decreases, duplicate or missing worker identities, incomplete barriers and insufficient request counts. The gate requires every allocation difference and the collection difference to equal zero. A nonzero result is retained and fails the gate; do not suppress it or disable the collector to obtain a pass. The optional `--DRT-gcopt=profile:1` summary is supplemental diagnostic output on stderr. It does not prove absence of request allocations by itself. C allocation, pool retention and process RSS are separate measurements; `@nogc` alone cannot establish any of those properties.

Primary declarations: [D GC API](https://dlang.org/library/core/memory/gc.html), [allocatedInCurrentThread](https://dlang.org/library/core/memory/gc.allocated_in_current_thread.html), [profileStats](https://dlang.org/library/core/memory/gc.profile_stats.html). Facts and compiler behavior were checked at the handoff's 2026-11-21 research cut; toolchain updates require repeating the probes.

## Runtime fixtures and negative checks

Each of the five BetterC packages provides `packages/<name>/tests/betterc.d` with `extern(C) int main()` and real assertions. CI compiles, links and executes those fixtures against actual source and dependency closure. `serde.owned` and the optional native YAML adapter are outside the freestanding core. The standalone handoff WASM ABI probe tests a concrete binary protocol and cannot substitute for the actual framework fixture in `tests/wasm/run.mjs`.

The ordinary `dub test :<name>` selects the package's `unittest` configuration, includes `source` and `tests`, and excludes `tests/betterc.d`. A temporary synthetic recipe probe verified that a failing assertion in `tests/contract_tests.d` is really executed. For sanitizer builds using `--build=plain`, explicitly include `-unittest` in `DFLAGS`: a real probe found that omitting it makes DUB's generated runner pass without compiling the unittest bodies. CI also requires the positive and expected-failure sources under `tests/compile`; compiler crashes and unrelated missing imports do not count as expected safety rejections.

## Capturing and collecting evidence

```sh
python3 tools/collect_evidence.py capture-json --kind micro --output artifacts/micro.json -- dub run --quiet --root=benchmarks/micro --compiler=ldc2 --build=release
python3 tools/collect_evidence.py capture-json --kind gc --output artifacts/gc.json -- dub run --quiet --root=benchmarks/hot-gc --compiler=ldc2 --build=release
python3 tools/load_bench.py --manifest policy/http-benchmark.json --output artifacts/http-load.json --oha /absolute/path/to/oha
python3 tools/collect_evidence.py collect --builds artifacts/builds.json --http artifacts/http-load.json --micro artifacts/micro.json --gc artifacts/gc.json --receipts-dir artifacts/receipts --platform-receipts-dir artifacts/platforms --dependency-lock policy/native-lock.json --output artifacts/current.json
```

The collector requires successful command receipts named `quality`, `safety`, `dag`, `betterc` and `sanitizers`, plus execution receipts for all seven declared targets. `ci.py` produces these by running concrete tools and fixtures; it does not accept a command whose sole behavior is printing “passed.” Each receipt identifies the actual Git commit, argv, exit status and retained output digest. The collector accepts separately downloaded target/quality directories, but every receipt must identify the current checkout's commit. Smoke load data is always rejected.

HTTP validation checks the production durations, exactly nine AB/BA trials per server, binary identity against the measured O3 build, successful raw oha results and their digests, matching aggregates, fixed-rate versus capacity commands, process counters, correctness probes and at least 100,000 requests for each reported p99.9. The raw files are resolved from the repository working directory used by the producer, then copied into the portable output bundle.

Preserve `artifacts/current.json` **and** its sibling `artifacts/current-artifacts/` directory. Copying only the JSON deliberately makes the gate fail because actual source artifacts would be missing. Receipt hashes detect missing or modified artifacts; they are integrity records, not cryptographic attestations. Protect the CI workflow, runner image and baseline write permissions from an unreviewed candidate. The gate also compares the public metric summary with its retained source payloads, so editing only a displayed number cannot silently change a result.

Validate the first actual baseline with:

```sh
python3 tools/gates.py --gate baseline --evidence artifacts/current.json
```

This checks absolute caps, correctness/safety/target receipts, GC and Go comparisons and explicitly reports `regression_comparison: not_run_no_prior_baseline`. It does not fabricate another commit. After a protected first-baseline review, subsequent comparisons use `--gate all --evidence artifacts/candidate.json --baseline artifacts/base.json` with two real different commits.

The current CI producer measures the base block and then the candidate block on the same designated host. Those arrays are not temporally paired. `perf_stats.py` therefore independently resamples each group's observations and computes the ratio of group medians using 10,000 replicates and a 99% interval. The same independent-sample method is used consistently for Go comparisons, although their load trials are interleaved. This interval covers sampling variation; it cannot remove systematic thermal, frequency or background-load drift between blocks. Record the block order, keep the host controlled and block a comparison when such drift is observed. Do not claim ordinal sample alignment creates a paired experiment.
