# Changelog

## Unreleased

- Flint becomes a port of Spring (ADR-030): Spring's public names with "Spring" replaced by "Flint", a repository family mirroring spring-projects, a Java → D API mapping rulebook (`docs/spring/api-mapping.md`) and an upstream licence matrix (`policy/upstream-licences.json`). The roadmap gains Milestones 13–15 for the port, and Milestone 10's remaining starter work is superseded.
  - `flint api` proves the port complete. `fetch` downloads the pinned upstream sources by checksum. `extract` writes a manifest of every public and protected Java element, with a declaration parser written in D. `coverage` fails on any element `api/mapping.json` leaves unclassified. `diff` lists what changed between two upstream tags. The manifests of Spring Framework v7.1.0 and Spring Boot v4.2.0 are under `api/upstream/`.
  - Phase 1 API coverage. Manifests of the Phase 1 third-party APIs: Jakarta Annotation, Validation, Persistence and Servlet; Jackson core, databind and annotations; SLF4J; Micrometer; Hibernate Validator. Per-repo mappings at rulebook v2. `flint api checklist` writes the 28 Phase 1 checklists to `docs/spring/phase1/checklists/`. `flint api headers` checks ported files against the licence matrix, and `tools/gates.py --gate api` runs headers and coverage per repo.
  - Flint AOT (`docs/spring/aot-contract.md`), the build step that replaces Spring's runtime reflection. `flint build` runs it for projects with a `@FlintBootApplication`. The compiler extracts each module's types and attributes, and the generator writes plain D: bean definitions in Spring's order, conditions decided at startup (class presence at build time), `@Configuration` subclasses, AOP proxies with Spring's self-invocation semantics, request-mapping tables, descriptors and derived-query SQL. A method-body edit regenerates nothing.
  - The Spring side-by-side harness (`benchmarks/spring/`, ADR-030 section 8). gs-rest-service, gs-relational-data-access and spring-petclinic-rest (JDBC on PostgreSQL) are pinned by commit and checksum, built with the pinned JDK, Maven and Spring Boot 4.2.0, and scored by black-box suites recorded from them. The suites compare status, headers, JSON, ProblemDetail, actuator output and Boot log events. The Java references pass 18, 1 and 109 cases. The Go comparators are registered before measurement. `measure_builds.py --spring` publishes both build headlines (platform cache against a std-primed `GOCACHE`, and from scratch against `go build -a`), `load_bench.py` gains the Spring-style workload `policy/spring-http-benchmark.json`, `spring_bench.py gc-matrix` runs the ports under druntime GC settings, and `gates.py --gate spring` checks the Phase 1 exit.
- Phase 0 binary-size levers (ADR-030 section 5, `docs/milestones/13-binary-size.md`):
  - Linux glibc PIE outputs link with RELR packed relocations. This takes 765,880 bytes off bench-rest and 147,384 off bench-cli, with PIE, relro and now kept.
  - The release and size profiles pass LDC's `-fno-moduleinfo-localclasses`, so `--gc-sections` drops unused classes: 2,000 classes with 50 used shrink from 2.46 MB to 0.49 MB. The DMD fork gains the same switch.
  - OpenSSL is built for TLS 1.2 and 1.3 only (ADR-031). This takes 899,216 bytes off bench-rest, and every handshake of Flint's TLS profile negotiates as before (`tools/tls_profile_matrix.py`).
  - `policy/budgets.json` gives framework modules linked-bytes budgets, checked by the gates. `measure_builds.py --app-sizes` measures the apps' release sizes alone.
- Milestone 10, in progress (ADR-028):
  - flint:engine-di gains compile-time conditional registration: `@ConditionalOnConfig`, `@ConditionalOnMissingBean` and `AutoConfiguration` lists, driven by `config/application.toml`.
  - Starters live under `starters/` and are added with `flint add`:
    - flint:starter-web runs a configured REST service in one call and serves a single-page front end.
    - flint:starter-observability serves health, readiness and Prometheus metrics.
  - Ordinary handlers need no `nothrow`/`@nogc`/`scope`: flint:engine-web runs them on a worker thread, with replies of any size.
  - `flint openapi` writes the controllers' OpenAPI 3.1 document and a typed TypeScript client.
  - `flint check` flags nullable class fields (FLINT-E0530) and handler attributes the framework makes unneeded (FLINT-E0531), and reports attributes per handler.
  - The vibe-coding benchmark has Go and Spring Boot references for all four tasks, and each passes its acceptance test.
    - They build with the pinned Go 1.27.4, and with a Temurin JDK 21.0.13.1+2, Maven 3.9.16 and Spring Boot 4.2.0 newly pinned with checksums in `policy/peer-lock.json`.
  - Graceful shutdown: flint:os dispatches SIGTERM as well as SIGINT, and flint:engine-web drains on it. The listener closes, in-flight requests finish within a grace period, and the process exits 0, 124 when the grace period expires, or 130 after a second signal.
- Milestone 9 (ADR-027) adds knowledge and tooling for people and agents:
  - `flint docs`, `flint examples` and `flint explain` answer from an offline index of the pinned API.
  - `flint generate` produces canonical components, and new projects get an `AGENTS.md`.
  - `flint mcp` serves the API, the diagnostics catalogue and the build loop over `flint:engine-mcp`, which gains blocking tools.
  - `flint watch` rebuilds and restarts or retests on every change.
  - `flint run --debug` and the generated launch configurations come with gdb pretty-printers.
  - `flint lsp` gives editors diagnostics, hover, go-to-definition and completion.
  - With the DMD fork's new `-verror-hide`, a framework misuse is one error at the user's line naming the field, handler or service. Object files stay byte-identical.
  - The vibe-coding benchmark has four tasks with black-box acceptance tests and a harness for coding agents.
  - Writing its first reference adds three library features: flint:config binds keys relaxed (`data_file` sets `dataFile`), flint:cli prints help for subcommands, and flint:term's `writeStream` writes to standard error from `@safe` code.
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
- Rebuild `flint:engine-desktop` after Tauri v2's architecture in D over GTK and WebKitGTK (ADR-020).
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
