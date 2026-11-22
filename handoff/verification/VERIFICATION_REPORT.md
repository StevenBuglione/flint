# Preparation verification and remaining acceptance

Prepared on **21 November 2026**. This archive is an implementation handoff for 37 DUB subpackages. The checks below establish the integrity of that handoff and the explicitly named executable tools/probes. They do not establish that the 37 runtime libraries have already been implemented or that Flint has met its performance targets.

## Executed checks

The aggregate machine-readable result is [handoff-validation.json](handoff-validation.json). Its final aggregate run passed **48 preparation checks, with zero failures and zero omitted aggregate checks**. This count includes grouped suites; it is not a claim of 48 full-framework runtime tests. It records each command, exit status and failure scope, including expected rejections. The final archive includes the source of the probes so a subsequent agent can reproduce the checks.

| Area | What was actually checked | Evidence |
|---|---|---|
| Archive structure | All 37 specifications/recipes, 15 numbered ADRs, all golden applications, task prompts, JSON/SDL/YAML syntax, Python syntax and internal Markdown links | [Aggregate result](handoff-validation.json) |
| Public D contracts | DMD 2.114.0 and LDC 1.43.0 semantic checks of all declaration modules, complete D modules in the specifications and golden API usage | [Aggregate result](handoff-validation.json), [core details](core-contracts.json), [service details](service-contracts.json) |
| Lifetime and safety misuse | Valid borrowers compile; escaped arena storage/callback slices, forged handles, forbidden allocations and generated unsafe/import constructs are rejected for the intended reason | [Compile fixtures](ci-compile-fixtures.json), [TUI/WASM contract checks](tui-wasm-contracts.json), [guard tests](../scaffold/tools/test_guards.py) and [native BetterC atomic probe](native-betterc-atomics.json) |
| Golden source quality | The real pinned dfmt byte-comparison check and D-Scanner reports run on golden, benchmark and BetterC fixture source | [Aggregate result](handoff-validation.json) |
| DUB | Real resolution of every requested child package; isolated test recipes prove external unittest files run, a failing assertion fails, and BetterC entry points stay out of ordinary library builds | [DUB test-selection probe](dub-unittest-selection.json), [native recipe emission](native-dub-emission.json) |
| Native compiler capabilities | Actual O3 and Oz ThinLTO links/runs, DMD development flags, explicit LDC time traces, accepted D ASan instrumentation flag, rejected unsupported UBSan flag, and an instrument/execute/merge/use PGO cycle | [Toolchain capability checks](toolchain-capabilities.json) |
| Browser ABI and host driver | A real 658-byte WASM probe links and executes eight ABI tests; 22 additional Node checks cover epochs, sequence wrap/replay, Canvas bounds, node generations, subtree confinement/depth and validation before DOM mutation | [WASM probe runner](../tools/verify_wasm.py), [driver tests](probes/driver_contract_test.mjs), [aggregate result](handoff-validation.json) |
| Native C and D ABI | Actual llhttp, zlib and liburing source builds; C/D ABI queries, HTTP request parsing and compression round trips linked through both D compilers | [Native smoke receipt](native-smoke.json) |
| Native sanitizers | Two instrumented CTests pass for the ABI/parser/compression probes, using GCC 14.2.0 AddressSanitizer and UndefinedBehaviorSanitizer | [Sanitizer receipt](native-sanitizers.json) and [CTest log](ffi/native-sanitizer-ctest.log) |
| Go and load producer | Real Go reference service unit tests, and a short real-process Go-versus-Go run that exercises the HTTP measurement harness | [Go service checks](go-reference-tests.json), [Go CLI execution](go-cli-smoke.json), [load-harness smoke](http-load-harness-smoke.json) |
| Governance tools | Negative tests for malformed/missing/forged evidence, source/import policy and statistical gates; actual Actions syntax linting, helper commands and installer checks | [Aggregate result](handoff-validation.json), [CI helper receipt](ci-tooling.json), [evidence producer tests](evidence-tools.json) |
| Native target plans | Concrete plans for the six declared native targets and supported provider sets; generated native DUB blocks parse and remain idempotent; default Wasmtime and all 37 tests remain in each native CI lane | [Native plans](native-build-plans.json), [DUB emission](native-dub-emission.json), [native CI compatibility](native-ci-compatibility.json) |
| Rust host setup | Pinned rustup 1.29.3 and Rust 1.97.0 installation executed successfully on Linux x86-64 glibc, with host and version checks | [Installation receipt](rust-install-linux-x86_64-glibc.json), [installation log](rust-install-linux-x86_64-glibc.log) |

### What a compiler pass means here

Files in `contracts/source/` define signatures and type/lifetime contracts. Most runtime methods deliberately have declarations without bodies. The four D golden applications are checked against these declarations. This proves that their syntax, UDA usage, parameter types, borrowing rules and template instantiations are compatible with the pinned compilers. Linking and executing the full applications requires the implementations specified in the milestones.

The five BetterC behavioral fixtures contain real assertions, with native `main` and wasm32 `flint_test` entry points. Preparation checks their semantics against the contracts. CI must later link them against the actual packages and execute every fixture natively and in WASM. The standalone 658-byte ABI probe is deliberately separate from those package tests.

### Sanitizer limits

The local native smoke used **GCC 14.2.0**, not the future CI Clang toolchain. AddressSanitizer and UndefinedBehaviorSanitizer were enabled on its C code. Local LeakSanitizer execution was unavailable under the tracing environment, so that run explicitly used `ASAN_OPTIONS=detect_leaks=0`; no leak-check pass is claimed. The proposed CI sanitizer lane requires Clang 22.1.8, enables leak checks and runs actual implemented D tests under LDC ASan. Those full-framework D sanitizer and leak-check outcomes remain unexecuted. The [DUB sanitizer-profile diagnostic](dub-sanitizer-unittest.json) confirms that `-unittest` reached compilation, while explicitly recording that linking could not run because Clang is absent locally.

LDC 1.43.0 rejects `-fsanitize=address,undefined`. The governance system therefore distinguishes D ASan from C ASan/UBSan. A C UBSan pass is never presented as UBSan coverage of D semantics.

### Performance and platform limits

No Flint request throughput, p99/p99.9, compiler time, deployed binary size or zero-GC performance baseline exists yet. The numeric caps are enforced engineering goals. The load-harness smoke runs **the Go reference on both labeled sides**, with shortened durations; it verifies the producer and is explicitly rejected as production performance evidence.

The six-target native build plans are plan-generation checks. They do not certify macOS, Windows, ARM64 or musl runtime behavior. The supplied workflow requires execution on those targets, static-musl artifact inspection and empty-root tests, plus all five actual BetterC WASM fixtures. Likewise, source pinning for 24 native libraries is not a claim that all 24 libraries were built and exercised locally on every target.

Every complete native CI lane requires the default Wasmtime provider and a successful plugin invocation. The pinned Rust bootstrap metadata and native build plans make that dependency explicit. The Rust installer ran successfully on Linux x86-64 glibc; the other five host installations and full Wasmtime builds remain part of implementation CI. The local C sanitizer smoke does not cover Rust internals.

Package-size budgets measure wrapper overhead against a provider-equivalent baseline that performs the same native operations through the upstream C ABI. Both complete binaries, their hashes and the normalized provider profile remain in the evidence. Identical linker flags alone are insufficient: the workload must keep equivalent provider code live. The absolute CLI and REST binary caps and browser-WASM module cap remain unchanged and count the complete measured artifact.

The initial-baseline gate validates complete actual evidence against absolute limits, Go comparisons, safety and platforms. It does not claim percentage regression certification without a prior implementation. Subsequent comparisons use independent-sample bootstrap inference and record base-then-candidate block order; a common machine does not remove possible time drift.

## Reproduce preparation checks

Install the pinned dependencies in `tools/requirements.txt` and `scaffold/tools/requirements.txt`, then run from the archive root with the installed tool paths:

```sh
python3 tools/verify_handoff.py --dmd /path/to/dmd --ldc /path/to/ldc2 --dub /path/to/dub --go /path/to/go --node /path/to/node --dfmt /path/to/dfmt --dscanner /path/to/dscanner
python3 tools/verify_toolchains.py --dmd /path/to/dmd --ldc /path/to/ldc2
python3 verification/verify-tui-wasm-contracts.py --dmd /path/to/dmd --ldc /path/to/ldc2
```

The compiler-capability probe is a Linux-native toolchain check. Its tiny PGO training program tests the compiler workflow only; production PGO needs a representative application workload. Native C smoke reproduction takes an actual built prefix through `verification/run-native-smoke.py --prefix PATH --dmd PATH --ldc PATH`; the prefix must contain the recorded llhttp/zlib/ABI artifacts.

`verification/diagnostics/` preserves earlier exploratory compiler diagnostics where available. They explain rejected approaches, not failures of the final selected path. The aggregate final receipt and the explicitly scoped receipts above determine the preparation status.
