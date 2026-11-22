# Changelog

## Unreleased

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

See [Linux certification](docs/milestones/06.md) for the evidence, run history and the deliberately failing macOS and Windows platform condition.
