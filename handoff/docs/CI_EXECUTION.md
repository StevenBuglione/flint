# Executable CI and first-baseline activation

The handoff contains a runnable workflow and producer orchestration, not precomputed release evidence. `scaffold/.github/workflows/ci.yml` calls `scaffold/tools/ci.py`; after `tools/bootstrap.py` creates the implementation checkout, these become `.github/workflows/ci.yml` and `tools/ci.py`. Public contract files remain outside the implementation import path. An unimplemented package, missing benchmark producer, absent platform receipt, or failed measurement makes the full CI status fail.

## Six gates and the commands that produce evidence

| Gate | Executed work |
|---|---|
| 1 Quality/safety | Real pinned dfmt byte comparison and D-Scanner reports, Python/source-guard tests, `@safe`/`@trusted` policy, DMD/LDC positive/negative lifetime and `@nogc` fixtures, all 37 DMD package suites, C ASan/UBSan and D ASan. |
| 2 Architecture | Exact direct-dependency allowlists, no cycles/higher-tier imports, private-boundary restrictions, compiler-generated import audits, and all five approved BetterC packages compiling, linking and executing both natively and in WASM. |
| 3 Compile | Nine real cold/incremental DMD/LDC samples for every package, compiler peak RSS, actual template-instance evidence, and fixed benchmark app builds. |
| 4 Size | Actual linked/stripped O3/Oz artifacts, private-dependency closure checks, and each package's positive incremental linked-size contribution. HTTP executable hashes must match the measured O3 artifacts. |
| 5 Runtime/GC | Nine HTTP samples for both implementations, five 21-sample microbenchmarks, and actual per-worker/process GC counters around steady state. |
| 6 Targets | Seven compatibility targets, real native tests, ELF architecture/closure checks, static musl CLI/REST execution without shared-library files, and the real module's WASM/JavaScript ABI conformance. |

The collector retains ten detailed receipt categories to support these six decisions: quality, safety, DAG, BetterC, sanitizers, cross-platform, hot GC, runtime, compile, and size. A receipt contains the command, exact commit, result, output artifact, and SHA256. Hashes detect accidental alteration; they do not attest that hostile source or a hostile runner reported honestly.

Useful local entry points from an implemented checkout are:

```sh
python3 tools/ci.py --plan static
python3 tools/ci.py static
python3 tools/ci.py platform --target linux-x86_64-glibc
python3 tools/ci.py container --target linux-x86_64-musl
python3 tools/ci.py sanitizers
python3 tools/gates.py --package web --gate structural
```

`--plan` prints commands and does not generate verification receipts. `static` records quality and DAG checks, builds the pinned native CI closure, then records safety and native BetterC execution. Platform execution records its own full native test/negative-fixture/BetterC result. The WASM target additionally compiles and links every `packages/<name>/tests/betterc.d` fixture for arena, serde, validate, wasm-bridge and ui-signals, exports `flint_test`, and executes each through `tests/wasm/betterc.mjs`. That helper rejects any runtime/host imports and calls the actual assertion entry point. The lane then links the framework sample and runs `node tests/wasm/run.mjs build/bench-wasm.wasm`; it does not substitute the handoff's standalone ABI probe for these implementations.

Normal DUB tests use the `unittest` build. Sanitizer tests use `--build=plain` with explicit `-unittest`, because an observed DUB 1.43 behavior otherwise omits unittest code while still constructing a successful test runner. The sanitizer environment also carries `-fsanitize=address`, bounds checks, a Clang link driver, and C ASan/UBSan link flags. D's lane is ASan; the C lane supplies both ASan and UBSan. No D UBSan result is claimed. Separate DUB homes prevent instrumented and ordinary build caches from being mixed.

All 37 native package suites include `wasi` with its default Wasmtime provider. Ordinary preparation therefore invokes `native_build.py --profile ci --library wasmtime`; a missing Rust compiler or engine build is a failure, never an unsupported-test skip. The sanitizer lane first builds `--profile wasm-host` without instrumentation in `.native-sanitized/engine-build`, installing into `.native-sanitized/install/linux-x86_64-glibc`. It then builds the C CI profile with ASan/UBSan in `.native-sanitized`, using that same cumulative installation prefix and emitting all DUB provider links. This preserves actual WASI host tests while instrumenting the D code and C shims/providers. **The Rust engine itself is uninstrumented in this lane**; these results do not certify Rust sanitizer coverage. Installation receipts identify each library's requested instrumentation and record the engine's actual Rust compiler and Cargo versions.

## Platform matrix

| Receipt target | Execution environment |
|---|---|
| `linux-x86_64-glibc` | GitHub-hosted `ubuntu-24.04`, native LDC x86-64 archive. |
| `linux-aarch64-glibc` | GitHub-hosted `ubuntu-24.04-arm`, native LDC AArch64 archive. |
| `linux-x86_64-musl` | Native x86-64 host runs the digest-locked Alpine image and the official LDC Alpine x86-64 archive. |
| `linux-aarch64-musl` | Native ARM64 host runs the same multi-architecture Alpine image and official LDC Alpine AArch64 archive. |
| `macos-arm64` | GitHub-hosted `macos-15`; the runner script verifies that the actual machine is ARM64. |
| `windows-x86_64` | GitHub-hosted `windows-2025`; the script enters the installed x64 MSVC developer environment before native builds. |
| `wasm32` | Linux builds the BetterC WebAssembly artifact; Node runs the real module's initialization, updates, bounds/ABI, and memory-growth conformance tests. |

GitHub's current hosted-runner table documents the ARM64 Ubuntu and macOS labels. Hosted images may change; these are compatibility jobs, not the source of compile/runtime performance comparisons. The latter run on the dedicated host below. [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

The Alpine index was retrieved from the upstream Docker registry and pinned to `sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f`; both amd64 and arm64 manifests were present. Node-based GitHub actions execute on the glibc host. Actual musl compiler/test processes execute inside Alpine, without a glibc compatibility shim. The Docker image pin does not freeze Alpine's package repositories; it fixes the base image, while installed build utilities remain part of the compatibility-job environment.

### Mandatory static musl proof

Alpine execution alone is not evidence of static linkage. Both musl architecture lanes must run `tools/static_smoke.py` after the native package tests. For each of **O3 and Oz**, it builds the canonical CLI and REST with the pinned LDC, `-static`, `-link-defaultlib-shared=false`, DIP1000 and enabled bounds checks. This compatibility profile does not claim a musl ThinLTO measurement. It strips retained copies, applies the existing CLI/REST absolute byte ceilings, and retains `readelf --wide --file-header --program-headers --dynamic` output.

An independent bounded ELF64 parser checks the actual machine field (x86-64 or AArch64), executable type, header/segment bounds, and dynamic-table termination. It rejects **every PT_INTERP segment and every active DT_NEEDED entry**. A self-relocating static PIE dynamic table is allowed only without required shared libraries. These fields' meanings come from the [ELF program-header specification](https://gabi.xinuos.com/elf/07-pheader.html) and [dynamic-linking specification](https://gabi.xinuos.com/elf/08-dynamic.html); the diagnostic command is defined by [GNU readelf](https://sourceware.org/binutils/docs/binutils/readelf.html).

Each stripped executable then runs as a real process in a separate temporary `chroot`. The CLI root contains only its executable, the checked-in `application.json`, and an empty `tmp` directory. It must print the expected `Hello, Flint!` line and successfully execute its config/log workload. The REST root contains only its executable and empty `tmp`; the parent verifies exact `/health` and `/json` response bytes, content types and successful statuses, with readiness/cleanup deadlines. No shared libraries, loader, host library paths, or certificates are copied in. The Docker lane supplies native execution and the chroot privilege inside its disposable VM/container boundary. Running this script on glibc or an emulator is rejected.

The static-proof JSON, build flags, binary hashes, ELF diagnostics, stripped binaries and empty-root command receipts are uploaded with that target's platform evidence. Current handoff verification tests the ELF detector against malformed cases and an **actually compiled dynamic C executable**, which must be rejected. The complete static Flint/musl lane has not run before the framework exists. In the glibc size lane, `measure_builds.py` separately forces static D runtimes and rejects unexpected private DT_NEEDED providers; ordinary enumerated OS runtime libraries remain allowed there.

The Windows prerequisite helper downloads the verified upstream WinFlexBison 2.5.25 ZIP, checks its SHA256, rejects unsafe archive paths, and exposes its programs to Meson. These are host build utilities. The shipped runtime dependency license policy remains separately defined in `native-lock.json`. Hosted jobs install ordinary build tools from their platform package managers; native source versions and archives are independently locked by `native_build.py`.

### Pinned Rust provisioning for the default engine

Before any native preparation, `ci.py` runs `tools/install_rust.py --target <receipt-target>`. The installer uses Rust **1.97.0** and Rustup **1.29.3**, with all six native host triples mapped explicitly. It verifies the distribution-manifest SHA256 and the target-specific immutable Rustup bootstrap SHA256 before executing the bootstrap. Those pins are in `policy/toolchains.json`; their official-source observations are retained in the handoff's `research/rust-host-toolchain.json`. Upstream references are the [Rust 1.97.0 distribution manifest](https://static.rust-lang.org/dist/channel-rust-1.97.0.toml) and [Rustup release manifest](https://static.rust-lang.org/rustup/release-stable.toml).

Installation uses project-private `.tools/rust/rustup` and `.tools/rust/cargo` directories, sets `RUSTUP_TOOLCHAIN=1.97.0`, and prepends only that Cargo bin directory for native subprocesses. It preserves the runner's `HOME`, removes inherited compiler/wrapper/flag overrides, disables Rustup self-updates, and checks the installed Rustup version, rustc release and host triple, and Cargo version. Rustup verifies downloaded component checksums against the official distribution metadata. No preinstalled Rustup, Alpine Rustup package, or floating GitHub setup action is required. Windows uses the same checksum-verified bootstrap after MSVC environment setup. The Wasmtime recipe requests a static library, including on musl.

Native evidence retains the toolchain installation receipt, native install metadata, and build logs; the sanitizer evidence additionally retains the separate engine-build logs. Performance jobs retain these under their measured commit's output directory. Local handoff verification successfully executed the pinned installer on Linux x86-64 glibc and retained its actual Rustup, rustc and Cargo identities. Installation on the other five hosts and full engine execution on every target remain CI obligations; the handoff's script tests and official pin observations do not claim those runtime outcomes.

## Performance and sanitizer runner contract

Provision a single-job ephemeral Linux x86-64 glibc VM with label `flint-perf-x86_64-v1`. Register it using GitHub's ephemeral/JIT mechanism and destroy the VM, working disks, and execution identity after that job. Do not reuse a container sharing writable host paths as the security boundary. GitHub recommends ephemeral autoscaling, but a label by itself provides no isolation. [GitHub self-hosted runner reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners).

The runner image must provide Python 3.12+ with venv, Git, taskset/util-linux, C/C++ build tools, CMake, Ninja, Meson, Perl, autoconf/automake/libtool, Bison/Flex, X11 development headers for the approved SDL profile, and **Clang 22.1.8** with its sanitizer runtimes. The sanitizer command verifies the Clang version. No unverified Clang image digest is invented in this handoff. LDC, DMD, Go, and oha are installed from the checksum-locked official assets; the same installations serve base and candidate. Each checkout provisions the identical locked Rust host toolchain in its own private directories before building Wasmtime.

Set `FLINT_EPHEMERAL_RUNNER=1` and `FLINT_RUNNER_LABEL=flint-perf-x86_64-v1` in the provisioned runner environment. These values are operational assertions checked by the script, not cryptographic proof of VM isolation. The runner must expose CPUs 2–3 for the server and 4–7 for load generation without cross-set SMT siblings. Provision the reviewed CPU topology, fixed frequency/governor policy, enough RAM for the compiler ceilings, and otherwise idle CPUs. The collector fingerprints kernel/libc/CPU identity, CPU affinity and governors. Provision external runner-log retention before discarding the machine.

The workflow uses `pull_request`, `push`, and owner-triggered `workflow_dispatch`, not `pull_request_target`. It requests read-only repository permissions, does not persist checkout credentials, does not request user/application secrets, and uses pinned action commit SHAs. The `flint-ci` environment used for ordinary measurements must have no secrets and no required manual reviewers. Restrict runner-network access and infrastructure credentials through the provisioner, because source under test executes arbitrary code. GitHub's runner security guidance describes this trust boundary. [GitHub secure-use reference](https://docs.github.com/en/actions/reference/security/secure-use).

Base and candidate checkouts execute under the **same OS user** so measurements share the host environment. The implementation does not prevent candidate code from modifying the base directory or previously written artifacts. Trusted workflow/tool changes, code-owner review, the ephemeral VM boundary, and reviewed source are governance requirements. These receipts are not tamper-resistant attestations. An adversarial-evidence workflow would need a separately trusted collector and stronger artifact/process isolation.

## Comparison order and statistics

For pull requests, candidate is GitHub's tested merge commit (`GITHUB_SHA`), and base is the event's exact base commit. This ties the final required status to the integration tree GitHub is evaluating. For pushes, the two exact identities are `before` and `after`. Manual compare mode requires a different real base SHA. Both checkouts are separate directories, have their own generated native paths and project caches, and use the same locked tool installations.

`ci.py pair` runs a **complete base measurement block followed by a complete candidate block**. It does not interleave these commits' individual trials. The statistical helper uses independent-sample bootstrap intervals for the ratio of group medians, with independently resampled groups. It does not invent pairing by zipping unrelated trials. Time drift between blocks is still a limitation; matching environment fingerprints cannot remove thermal, scheduler, or background-work trends. Repeat a questionable result under a stable runner rather than selectively dropping unfavorable samples.

Within each HTTP collection, Flint and Go trial order alternates; this local alternation is described in `HTTP_BENCHMARK_PROTOCOL.md`. The shared gate still uses the consistent independent-sample procedure. HTTP uses separate offered-load latency and unconstrained-capacity phases. Each full commit collection requires at least 39 minutes of HTTP load alone, so the workflow allows six hours for the complete comparison and retains partial failure artifacts.

Changed native/toolchain/workload manifests invalidate a cross-commit comparison. Rebuild an actual baseline under the new reviewed measurement policy; do not copy old numbers or label one commit as two different commits. Package budgets remain policy decisions subject to code-owner review.

## Initial baseline: real execution, no fabricated regression pass

The initial handoff cannot pass release CI: it intentionally has no package runtime implementations, complete package benchmark fixtures, microbenchmark producer, or all-worker hot-GC producer. Follow `benchmarks/REQUIRED_PRODUCERS.md` in the implementation checkout (the handoff's `scaffold/benchmarks/REQUIRED_PRODUCERS.md`) for the latter interfaces. A normal first push with an all-zero `before` SHA fails with an explicit initial-baseline message.

The first real implementation must be validated as its own initial baseline. The workflow has a distinct `workflow_dispatch` **baseline** mode for this purpose. Its concrete sequence is:

1. Finish the runtime implementation and required producers; commit the actual source on the repository's default branch through the owner's initial project-activation process. Provision the runners and place real users/teams in `.github/CODEOWNERS` for `/.github/`, `/tools/`, `/policy/`, and `/benchmarks/`. The supplied `.github/CODEOWNERS.example` is illustrative and does not invent a repository owner.
2. Create the `flint-baseline` GitHub environment with at least one required reviewer, **prevent self-review** enabled, and deployment access restricted to protected branches. Configure ordinary branch/owner review before activation. The `refs` job reads this environment via the GitHub API and fails if these protections are missing. The baseline dispatch must originate from the default branch.
3. Dispatch `Flint CI` with `mode=baseline`; leave `base_sha` empty. Only candidate static/sanitizer/platform jobs execute. After those complete, the protected environment must approve the measurement job. That job runs the complete real build, HTTP, micro, and GC producers, then executes:

   ```sh
   python3 tools/gates.py --gate baseline --evidence ../paired/baseline.json
   ```

4. The baseline command enforces actual receipt integrity, all absolute budgets, Go comparisons, GC zero-allocation requirements, and all platform results. It makes **no regression claim**. Its final GitHub status is `Flint / baseline evidence`, which is deliberately different from `Flint / all six gates`. Keep the JSON, its retained-artifact directory, source commit, raw logs, and environment fingerprints together.
5. Enable the required all-six comparison status for subsequent changes after reviewing that genuine first baseline. Future compare runs remeasure their real base and candidate on the same host; they do not trust copied constants from the seed file. No fake predecessor commit or same-commit comparison is needed.

The owner can prepare an exact repository ruleset locally:

```sh
python3 tools/configure_github.py --repo OWNER/REPO --branch main
```

This writes reviewable JSON and does not call GitHub. After the real initial baseline and CODEOWNERS setup are complete, the owner can explicitly add `--apply`. That path uses `gh api` with a structured JSON input file, checks administration permission, and creates or updates only the named `Flint required CI` ruleset. It requires the final all-six status, current-base testing, one approving review, code-owner review, approval after the last push, resolved discussions, and no force pushes. It does not remove unrelated rulesets or add bypass actors. `--integration-id` can bind the required status to a separately verified GitHub App ID; the handoff does not guess one. The ruleset mechanism and parameters are from GitHub's [repository-rules API](https://docs.github.com/en/rest/repos/rules).

Environment creation/protection and branch activation are repository-owner operations. The handoff does not configure a real repository, register a runner, or send any messages. GitHub's [environment API documentation](https://docs.github.com/en/rest/deployments/environments) describes the reviewer/self-review and protected-branch settings used by the baseline guard.

## Evidence retention and current verification limits

Each matrix job uploads `artifacts/` even after failure. Role-prefixed artifact names keep base and candidate separate; target-specific directories prevent cross-platform file collisions. Downloads occur within the same workflow run and enforce artifact digest validation. The collector independently checks receipt commit IDs and retained artifact hashes. The final job rejects failed, skipped, cancelled, or missing prerequisites; baseline mode uses its separate status name instead of turning a skipped comparison into an all-six success.

Current handoff verification can establish Python/script parsing, tool guard tests, compiler-checked declarations, fixture semantics, native C probes, the standalone WASM ABI probe, Go reference tests, and a short Go-versus-Go HTTP harness smoke. It cannot establish Flint runtime performance, zero-GC request execution, platform parity, full native linkage, or production sanitizer cleanliness before those implementations exist. The workflow keeps those distinctions executable by failing on missing evidence.
