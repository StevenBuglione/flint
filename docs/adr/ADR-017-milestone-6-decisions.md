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
