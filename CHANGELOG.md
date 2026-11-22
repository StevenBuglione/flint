# Changelog

## Unreleased

- Milestone 9 (ADR-027) adds knowledge and tooling for people and agents:
  - `flint docs`, `flint examples` and `flint explain` answer from an offline index of the pinned API.
  - `flint generate` produces canonical components, and new projects get an `AGENTS.md`.
  - `flint mcp` serves the API, the diagnostics catalogue and the build loop over `flint:mcp`, which gains blocking tools.
  - `flint watch` rebuilds and restarts or retests on every change.
  - `flint run --debug` and the generated launch configurations come with gdb pretty-printers.
  - `flint lsp` gives editors diagnostics, hover, go-to-definition and completion.
  - With the DMD fork's new `-verror-hide`, a framework misuse is one error at the user's line naming the field, handler or service. Object files stay byte-identical.
- Bring Flint up natively on Windows x86-64 (ADR-026): the pinned DMD and LDC install and verify there, `flint` bootstraps itself, and 12 pure-D packages pass on both compilers, with Win32 process supervision (job objects, named pipes), console sessions over the shared terminal ABI, and Ctrl+C handling.
- Implement the 37-package Flint library catalog, from scoped arenas and Linux reactors to typed HTTP, SQL, terminal, WASM, and application adapters.
- Add Linux io_uring and epoll execution, linked HTTP/1.1 and HTTP/2, PostgreSQL and SQLite integration, gRPC, WebSocket support, middleware, and bounded cancellation.
- Add built-in terminal rendering with a BetterC browser bridge, signal graph, and pinned Wasmtime host for core, Preview1, and component programs.
- Add Kafka and JetStream, signed S3-compatible storage, SMTP and HTTP mail, five AI wire dialects, MCP stdio and Streamable HTTP, escaped HTML templates, compression and archives, and SDL3 desktop integration.
- Add reproducible compiler, size, microbenchmark, and per-worker GC measurements. The RPC and Wasmtime probes link their verified reference archives through dedicated recipes.

- Build faster than Go on Linux with a forked DMD 2.114.0, which keeps a resident druntime/Phobos compile server (ADR-016), and a forked DUB 1.43.0 with a parallel compile pipeline and direct `mold` linking. The language and public APIs are unchanged.
- Fix defects found in the Milestone 1–5 review across HTTP/1 and HTTP/2, the reactor, logging, templates, MCP, cache, SQL, JetStream, JWKS, gRPC and TUI.
- Implement the ADR-017 behaviour decisions:
  - io_uring delivers data from cancelled reads;
  - DI `@PreDestroy` runs only after a successful `@PostConstruct`;
  - configuration types may share files;
  - floats are written as shortest round-trip;
  - responses carry a `Date` header and return 405 with `Allow`;
  - JetStream reconnects automatically.
- Rebuild `flint:desktop` after Tauri v2's architecture in D over GTK and WebKitGTK (ADR-020).
- Keep heavy Phobos templates and archive cascades out of library compiles, so all 37 packages meet their compile-time, memory, template (ADR-019) and size caps.
- Pass the strict sanitizer lane with full ASan and UBSan, using a sanitizer-aware D runtime.
- Join background worker threads (cache, actuator, MCP, storage, security) on close and return from starting one only once it runs, so no worker overlaps runtime termination; this fixes an intermittent segfault at process exit.
- Run all 37 package suites, the native checks and the protocol peers on Linux AArch64 (glibc and static musl) in a full-system emulated guest, with wall-clock test bounds reported rather than asserted under emulation.
- Certify the initial Linux baseline at `d076103`. The first recorded build without a compile server takes 0.142 s for the CLI and 0.376 s for REST. Flint against Go:

  | Metric | Flint / Go |
  | --- | ---: |
  | CLI build time | 0.92 |
  | REST build time | 0.68 |
  | CLI binary size | 0.44 |
  | REST binary size | 0.98 |
  | REST throughput | 2.61 |
  | REST p99 latency | 0.10 |
  | REST RSS | 0.90 |
  | REST CPU per request | 0.62 |

- Record the Flint platform direction (ADR-021) and license Flint under Apache-2.0.

- Add the `flint` command ([docs/flint-cli.md](docs/flint-cli.md)), written in D on Flint's own libraries. It provides `new`, `build`, `run`, `test`, `check`, `fmt`, `lock`, `toolchain install|verify|info`, `doctor`, `daemon start|stop|status`, `version`, `explain` and `receipt`, with versioned `--json` output, stable exit codes and no prompts.
- Add the Flint project model: `flint.toml` with a closed schema, the deterministic and byte-verified `flint.lock`, the `config/application*.toml` and `src/<project>/` conventions, module paths checked against file paths, and `.flint/` for generated recipes, builds, receipts and caches.
- Move the canonical build profiles into `policy/profiles.toml`, shared by `flint`, `tools/ci.py` and `tools/measure_builds.py` with unchanged flags, and add `policy/platform.toml`.
- Write a build receipt next to every artifact. Added flags, a non-profile compiler or an unverified toolchain mark it non-canonical. `flint toolchain install` records the receipt that ties the installed DMD and DUB fork to `toolchain/*.patch`.
- Port the structural gate, the dfmt and D-Scanner checks and the safety policy into `flint check`, with the fast subset in every build. Every `flint` error has a stable `FLINT-Ennnn` code with a location, cause and fix, and `flint explain` describes each one.
- Start the fixture peers that workspace test suites declare in `policy/test-peers.toml`: the AI, S3, HTTP, JWKS and SMTP peers, MinIO, Valkey and a disposable PostgreSQL cluster. A missing peer fails its package with FLINT-E0815 instead of being skipped. `flint test --scenarios` runs `mq`'s live scenarios against real Kafka 4.1.2 and NATS JetStream 2.15.3.
- Pin every peer in `policy/peer-lock.json`, with published checksums or recorded tag commits. `tools/install_peers.py` verifies each archive, builds Valkey, nats-server and MinIO, using the pinned Go for the Go programs, extracts Kafka and a Temurin JRE, and writes a receipt per peer.
- Add `flint.config` named policy files without environment layers, `flint.serde.owned.serialize` and `flint.term.describe` (ADR-022).
- Fix two link and build failures: `flint:os` failed to link in DMD library builds, and the `flint:term` C shim failed to compile under fortified GCC.
- Add Go-style dependencies: repository paths with semantic-version tags, minimal version selection, a content-addressed git cache with `FLINT_PROXY` and offline builds, verified tree hashes in `flint.lock`, and `flint deps tree|why|update|vendor` (ADR-023).
- Add native packages through `[native]`. Flint's resolver drives a pinned, isolated Conan 2.34.0 that is never visible. Its only source is the checked-in recipe index `native/conan-index`, generated from `policy/native-lock.json` for the 19 providers. `flint.lock` records each package's recipe revision, package ID, source hash and binary hash. Conflicts name both requesters. `system = true` marks the build non-portable, and `bundled` ships a shared library with a run path. The workspace passes 74/74 against the Conan-built providers.
- Add embedded C (`native/`, `[native.c]`): the pinned clang with `-Werror` and full hardening, content-hash caching, a fixed clang-tidy profile in `flint check`, ASan and UBSan under `flint test --sanitize`, and the rule that only `ffi` modules reach C.
- Add `flint package [--target T] [--container] [--sbom]`: static executables (static-PIE musl cross-linked against a pinned Alpine sysroot), reproducible archives, a `FROM scratch` OCI image written without a container engine, SPDX 2.3 and CycloneDX 1.6 SBOMs, and `flint deps audit` for hashes, licences and LGPL/AGPL obligations.
- Add the DUB compatibility index (`"dub:<name>" = "<version>"`, `policy/dub-index.toml`). A DUB package that fails Flint's safety checks builds only under an `[unchecked]` waiver, which every build, receipt, SBOM and audit shows.
- Fix `flint daemon stop` returning before a server's lock holder exited, which made a Milestone 7 test flaky.

See [Linux certification](docs/milestones/06.md) for the Milestone 6 evidence, run history and the deliberately failing macOS and Windows platform condition, [Milestone 07](docs/milestones/07.md) for the `flint` CLI, and [Milestone 08](docs/milestones/08.md) for dependencies and packaging.
