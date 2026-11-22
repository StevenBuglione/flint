# Milestones and execution order

The dependency graph in `scaffold/policy/packages.json` is authoritative. Tasks are behavioral vertical slices; contracts may be reviewed early but a contract typecheck is not implementation completion. Each package owner implements the complete spec, including the acceptance cases beyond the short task description below.

## Parallel workstreams

| Milestone | Packages introduced | Independent work after prerequisites |
|---|---|---|
| 1: Memory, cancellation and platform operations | arena, conc, reactor | arena first; OS backend adapters after operation contract |
| 2: Typed foundations and a complete console slice | test, serde, validate, config, log, di, style, term, os, cli | serde/validate/test/style; log/di/term/os after arena+conc |
| 3: HTTP and persistence vertical slices | http, web, security, sql, data, migrate, cache, schedule, actuator, rpc | http/web/sql; security after http; data/migrate after sql |
| 4: Terminal interaction and browser/edge WASM | tui, widgets, prompt, wasm-bridge, ui-signals, wasi | TUI/widgets/forms; bridge/signals; native WASM embedding |
| 5: Cloud, AI and optional composition adapters | mq, storage, mail, ai, mcp, template, codec, desktop | mq; storage/mail; AI/MCP; template/codec; desktop |
| 6: Freeze, empirical gates and release readiness | release audit of all 37 | correctness matrix; benchmark runner; dependency/legal/provenance audit |

## Milestone 1: Memory, cancellation and platform operations

Dispatch details: `task-prompts/milestone-01.md`.

- **M1.1 — arena:** Implement checked buffer identities, alignment, overflow-safe allocation, scoped read/write callbacks and reset with outstanding-borrow rejection. Acceptance: Zero capacity; overflow; double reset; foreign/stale handle; stack/callback escape fails compilation; randomized reuse under ASan.

- **M1.2 — conc:** Implement cancellation tree, monotonic deadlines and bounded single-consumer queue first; then separate MPMC sequence-slot queue and bounded offload pool. Acceptance: Cancel-before-start; cancel/complete race; nested deadline; capacity saturation; wraparound; shutdown while producers wait; exact-once completion.

- **M1.3 — reactor:** Implement operation table and epoll fallback, then io_uring feature selection, then kqueue and IOCP behind the same completion contract. Acceptance: Partial read/write; EOF; cancellation before/during/after submit; handle reuse; no free before final completion; blocked io_uring falls back; per-worker GC counters.

Exit: the complete listed package specs pass, all affected dependents still compile, and the milestone application/scenario runs. A missing implementation remains visibly incomplete.

## Milestone 2: Typed foundations and a complete console slice

Dispatch details: `task-prompts/milestone-02.md`.

- **M2.1 — test:** Wire named unittest enumeration, fluent equality assertions and compile-time interface mocks; keep runner code out of production builds. Acceptance: Failing assertion yields nonzero exit; uncaught error distinguished; deterministic naming/filter; generated overloads and const/nogc interface methods compile.

- **M2.2 — serde:** Implement bounded JSON reader/writer with field metadata, checked numeric parsing, duplicate-key policy and arena Text. Then native owned adapter, TOML and optional native YAML. Acceptance: UTF-8/surrogates; number overflow; NaN/infinity rejection; depth64 limit; embedded NUL; unknown keys; stale handles; corpus fuzz; native/BetterC/WASM identical golden JSON.

- **M2.3 — validate:** Implement constraints and a bounded non-backtracking pattern engine; emit field-path diagnostics without GC. Acceptance: Unicode blank strings; numeric bounds; malformed email; regex rejection; multiple failures; Text ownership; native and WASM parity.

- **M2.4 — config:** Implement explicit precedence and profiles with typed required fields and secret-redacted diagnostics. Acceptance: Defaults→base→profile→dotenv→process environment→CLI order; missing/unknown keys; duplicate keys; invalid values; no secret value in any error.

- **M2.5 — log:** Implement bounded structured log ring, task context propagation and drain policy, then console formatting. Acceptance: Full ring; maximum record size; escaping; concurrent fibers with different request IDs; shutdown drain deadline; zero hot-path GC allocations.

- **M2.6 — di:** Generate explicit dependency graph with constructor injection, configured instances and deterministic lifecycle order. Acceptance: Missing/ambiguous bindings and cycles fail compilation; startup failure unwinds constructed services; external resources remain externally owned.

- **M2.7 — term:** Implement raw-mode guard and event decoder; add style layout, OS subprocess lifecycle, then CLI schema/parser as independent leaf tasks. Acceptance: Terminal restore after panic/exception/signal path; split escape sequences; Ctrl-C; subprocess pipe backpressure; cancellation; flag aliases/--/negative numbers; golden CLI help.

Exit: the complete listed package specs pass, all affected dependents still compile, and the milestone application/scenario runs. A missing implementation remains visibly incomplete.

## Milestone 3: HTTP and persistence vertical slices

Dispatch details: `task-prompts/milestone-03.md`.

- **M3.1 — http:** Wrap libcurl multi with bounded response sinks, explicit request lifetime, timeouts and verified TLS defaults. Acceptance: Redirect credentials stripped across origins; cancellation complete-before-free; slow body backpressure; content limits; certificate/hostname errors; retry only replayable requests.

- **M3.2 — web:** Build H1 llhttp parser, static router and arena response ownership. Complete bench-rest correctness before adding H2 nghttp2 flow control. Acceptance: Smuggling CL/TE cases; headers/body limits; duplicate routes fail compile; keepalive; partial sends; cancellation; H2 stream/window exhaustion; golden JSON byte identity.

- **M3.3 — sql:** Implement SQLite offload first and PostgreSQL nonblocking connection states next; pool leases are exclusive and cancellation drains before reuse. Acceptance: Statement binding; transaction rollback on every exit; timeout; server disconnect; exhausted pool; cancelled query drained; connection never shared by two requests.

- **M3.4 — data:** Generate row codecs and repository methods, then wire the golden REST application through DI and migration startup. Acceptance: Null/type mismatches; notFound mapping; parameterized queries; duplicate key status; repeated SQL migration checksum mismatch; concurrent migration lock.

- **M3.5 — security:** Implement auth decision model and crypto shims; add JWT/JWKS and issuer/audience/algorithm policies, then app middleware adaptation. Acceptance: Reject none and algorithm confusion; wrong issuer/audience; unknown key; expired/not-yet-valid; bounded JWKS refresh; CORS origin allowlist; password-hash resource limits.

- **M3.6 — cache:** Implement bounded memory TTL/LRU, hiredis integration and generated cache call boundaries; concurrently add schedule/actuator after their direct dependencies pass. Acceptance: Monotonic TTL; key collision policy; stampede handling; cron DST overlap/gap; health does not recurse; cardinality limits; exporter backpressure.

- **M3.7 — rpc:** Implement WebSocket/SSE lifecycle, protobuf-c generated messages and gRPC framing/status/trailers on H2. Acceptance: Fragmented frames; UTF-8; ping/close timeout; SSE cancellation; gRPC compressed flags/limits; deadline trailers; interop with pinned external client.

Exit: the complete listed package specs pass, all affected dependents still compile, and the milestone application/scenario runs. A missing implementation remains visibly incomplete.

## Milestone 4: Terminal interaction and browser/edge WASM

Dispatch details: `task-prompts/milestone-04.md`.

- **M4.1 — tui:** Implement model-update-view scheduling, diff rendering and cancellable effects; then widgets and prompts on this runtime. Acceptance: Resize while rendering; grapheme width; wide/combining cells; paste; focus; async completion after screen teardown; password never logged; golden TUI exit restores terminal.

- **M4.2 — wasm-bridge:** Implement fixed FLNT ABI encoder and browser decoder conformance fixtures; use one flush per animation frame. Acceptance: Pointer+length overflow; malformed/truncated records; stale generation; unknown op; memory growth; forbidden attributes; canvas/GPU subcommand limits.

- **M4.3 — ui-signals:** Implement bounded signal/observer graph, computed dependencies, deduplicated queue and deterministic flush into bridge. Acceptance: Repeated set; diamond graph; cycles rejected; capacity saturation; disposed source; stale handles; callback reentrancy; native/WASM same patch order.

- **M4.4 — wasi:** Implement native Wasmtime embedding with fuel/memory/capability limits and separate WIT component adapters; keep WAMR capability profile explicit. Acceptance: Guest trap; fuel/deadline interruption; denied filesystem/network host calls; multiple tenants; WASI0.2 and0.3 conformance; unsupported adapter fails clearly.

Exit: the complete listed package specs pass, all affected dependents still compile, and the milestone application/scenario runs. A missing implementation remains visibly incomplete.

## Milestone 5: Cloud, AI and optional composition adapters

Dispatch details: `task-prompts/milestone-05.md`.

- **M5.1 — mq:** Wrap librdkafka delivery/consumer lifecycle and implement bounded NATS JetStream flow; generate listener dispatch. Acceptance: Redelivery and idempotency; rebalance during handler; queue full; drain deadline; commit offsets only after successful handling; no exactly-once claim across external side effects.

- **M5.2 — storage:** Implement SigV4 over verified crypto primitives, bounded streaming uploads and multipart cleanup; mail can proceed independently over http/reactor. Acceptance: Canonicalization vectors; UTF-8/query escaping; clock skew; part retry; failed multipart abort; SMTP STARTTLS required policy; envelope/header injection rejected.

- **M5.3 — ai:** Implement provider-neutral bounded stream events and explicit model/provider configuration, then compile-time schema/tool dispatch. Acceptance: Split SSE/UTF-8; rate-limit retry budget; cancellation; invalid tool arguments; repeated tool IDs; provider usage absent; no cross-provider silent parameter loss.

- **M5.4 — mcp:** Implement stdio and 2026-07-28 HTTP as separate transport state machines; isolate the older compatibility mode. Acceptance: Version/header mismatch; Origin rejection; bounded JSON-RPC framing; stdout cleanliness; cancellation; MRTR retries; schema validation; explicit capability negotiation.

- **M5.5 — template:** Implement context-aware escaped HTML rendering with compile-time variable checking; codec proceeds independently over pinned C shims. Acceptance: HTML/text/attribute/URL context; explicit trusted-HTML wrapper; no dynamic template code; output caps; decompression bomb/ratio/window limits; truncated streams.

- **M5.6 — desktop:** Compose SDL3 permissive native profile and explicit OS webview adapters over WASM bridge; package notices and backend capabilities. Acceptance: Window teardown races; thread-affinity; denied external navigation; bounded JS bridge; platform integration; WebKitGTK excluded from permissive default.

Exit: the complete listed package specs pass, all affected dependents still compile, and the milestone application/scenario runs. A missing implementation remains visibly incomplete.

## Milestone 6: Freeze, empirical gates and release readiness

Dispatch details: `task-prompts/milestone-06.md`.

- **M6.1 — arena:** Complete and run all per-package probe apps, absolute-size profiles and negative safety corpora under both compilers. Acceptance: All37 public contracts implemented and linked; no signature-only or always-success implementation; every specified edge case has observable behavior.

- **M6.2 — web:** Run same-host base/candidate/Go benchmarks on the fingerprinted ephemeral runner with equivalent profiles. Acceptance: All raw samples and histograms retained; zero errors; p99.9 sample size; all worker GC deltas; cold and edited builds; O3/Oz size closure.

- **M6.3 — wasi:** Complete cross-platform execution, ABI layout/callback tests, static ELF inspection and browser/WASI conformance. Acceptance: Allseven platform receipts present; musl binaries execute without host libs; no unsupported sanitizers marked passed; exact lock+notices included.

- **M6.4 — mcp:** Run aggregate gates, verify compatibility documentation and record the first observed baseline or compare to the protected base baseline. Acceptance: All six gates pass without cap changes; failed goals reported explicitly; changelog, source hashes and signed provenance agree with binaries.

Exit: the complete listed package specs pass, all affected dependents still compile, and the milestone application/scenario runs. A missing implementation remains visibly incomplete.
