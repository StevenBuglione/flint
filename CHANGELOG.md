# Changelog

## Unreleased

- Implement the 37-package Flint library catalog, from scoped arenas and Linux reactors to typed HTTP, SQL, terminal, WASM, and application adapters.
- Add Linux io_uring and epoll execution, linked HTTP/1.1 and HTTP/2, PostgreSQL and SQLite integration, gRPC, WebSocket support, middleware, and bounded cancellation.
- Add built-in terminal rendering with a BetterC browser bridge, signal graph, and pinned Wasmtime host for core, Preview1, and component programs.
- Add Kafka and JetStream, signed S3-compatible storage, SMTP and HTTP mail, five AI wire dialects, MCP stdio and Streamable HTTP, escaped HTML templates, compression and archives, and SDL3 desktop integration.
- Add reproducible compiler, size, microbenchmark, and per-worker GC measurements. The RPC and Wasmtime probes link their verified reference archives through dedicated recipes.

- Add the `flint` command ([docs/flint-cli.md](docs/flint-cli.md)), written in D on Flint's own libraries. It provides `new`, `build`, `run`, `test`, `check`, `fmt`, `lock`, `toolchain install|verify|info`, `doctor`, `daemon start|stop|status`, `version`, `explain` and `receipt`, with versioned `--json` output, stable exit codes and no prompts.
- Add the Flint project model: `flint.toml` with a closed schema, the deterministic and byte-verified `flint.lock`, the `config/application*.toml` and `src/<project>/` conventions, module paths checked against file paths, and `.flint/` for generated recipes, builds, receipts and caches.
- Move the canonical build profiles into `policy/profiles.toml`, shared by `flint`, `tools/ci.py` and `tools/measure_builds.py` with unchanged flags, and add `policy/platform.toml`.
- Write a build receipt next to every artifact. Added flags, a non-profile compiler or an unverified toolchain mark it non-canonical. `flint toolchain install` records the receipt that ties the installed DMD and DUB fork to `toolchain/*.patch`.
- Port the structural gate, the dfmt and D-Scanner checks and the safety policy into `flint check`, with the fast subset in every build. Every `flint` error has a stable `FLINT-Ennnn` code with a location, cause and fix, and `flint explain` describes each one.
- Add `flint.config` named policy files without environment layers, `flint.serde.owned.serialize` and `flint.term.describe` (ADR-022).
- Fix two link and build failures: `flint:os` failed to link in DMD library builds, and the `flint:term` C shim failed to compile under fortified GCC.

See [Linux release verification](docs/milestones/06.md) for observed limits and remaining certification checks, and [Milestone 07](docs/milestones/07.md) for the `flint` CLI.
