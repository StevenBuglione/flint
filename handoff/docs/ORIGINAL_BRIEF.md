# Role & Mission

Act as a **Principal Systems Architect, Compiler/Toolchain Engineer, and Staff Java/Go/D Developer**.

Your mission is to perform **exhaustive, up-to-date technical research** on the D programming language ecosystem (targeting DMD 2.114+, LDC 1.43+, DUB subpackages, ImportC, `-betterC`, `dfmt`, `dscanner`, and `wasm32`) and produce a **complete, implementation-ready handoff `.zip` archive** (`flint-agent-handoff.zip`) so autonomous AI coding agents can build the **`flint`** monorepo from scratch with minimal human intervention.

Do not produce vague summaries or placeholders (`TBD`, "implement as needed"). Every specification, file layout, C-FFI pinning decision, public API signature, CI gate, and acceptance criterion inside the handoff `.zip` must be concrete, verified, and directly executable by coding agents.

---

# Core Vision & Engineering Philosophy

We are making **D** our default, general-purpose language for AI-agent-driven software development across backend microservices, CLIs, TUIs, cloud automation, AI/MCP tooling, and WebAssembly frontends.

Our target engineering triangle is non-negotiable:
1. **Spring Boot / Java Semantics & Ergonomics:** A Java/Spring Boot developer must feel immediately comfortable in `flint`. Replicate Spring Boot 4's declarative developer experience (`@RestController`, `@Service`, `@Get`, `@Post`, `@Table`, `@Valid`, `@HttpExchange`, `@Scheduled`, `@Tool`, `@Command`)—**but never port Spring's runtime reflection, classpath scanning, or dynamic proxies**. Replace those internals with D's **compile-time UDAs, `__traits`, `static foreach`, and `mixin`s** so wiring happens at compile time with zero runtime overhead.
2. **Better-Than-Go Compile Time, Speed, Binary Size, & Latency:**
   - **Dev loop (`dmd`):** Faster than `go build` (sub-second incremental builds; under 1.5s cold builds for CLIs and under 3s for REST services).
   - **Release builds (`ldc2` / LLVM):** Beat Go on raw CPU throughput, RSS memory footprint, and stripped binary size (under 3 MB for CLIs, under 8 MB for REST microservices, under 100 KB gzipped for WASM core modules).
   - **Concurrency & Tail Latency:** Beat Go's p99 latency on servers by designing around D's strengths—**thread-per-core event loops (`io_uring` / `kqueue` / `IOCP`) + pinned local fibers + `@nogc` per-request arena allocators**—instead of fighting D's thread-local storage (TLS) or stop-the-world GC.
3. **Pragmatic Memory Safety (`@safe` Where It Makes Sense):**
   - Default to `@safe` across all application code, public framework APIs, serialization, validation, DI wiring, CLI, and TUI layers.
   - Where raw performance or C interop demands it (arena bump allocators, lock-free queues, OS event loops, C library bindings, WASM linear memory), use tightly encapsulated `@trusted` / `@system` boundary modules—never sprawling across business logic.
   - Every `@trusted` function must be tiny, auditable, covered by unit/fuzz/ASan tests, and carry a mandatory `// SAFETY:` justification comment. Never sacrifice meaningful runtime performance for ideological purity, and never leave unsafe pointer manipulation exposed to application developers.
4. **Wrap C at the Bottom, Write Clean D at the Top:**
   - Never ask coding agents to re-implement TLS, cryptography, HTTP/2 frame parsers, SQLite engines, Postgres wire protocols, or Kafka protocols in pure D.
   - Wrap battle-tested C libraries (`OpenSSL`/`libsodium`, `llhttp`/`nghttp2`, `libcurl`, `libsqlite3`, `libpq`, `librdkafka`, `zstd`/`zlib`/`brotli`, `wasmtime`/`WAMR`) via pinned `extern(C)` or ImportC shims.
5. **Agent-First Dialect ("Agent D"):**
   - LLMs have less training data in D than in Java/Go/Rust. The handoff must define a strict, canonical **"Agent D" dialect** and golden code templates:
     - Default to `struct` for data/DTOs; use `class`/`interface` only when runtime polymorphism or DI contracts require it.
     - Confine all heavy template metaprogramming, `__traits`, and `mixin` generation strictly inside framework library internals (`flint:di`, `flint:serde`, `flint:web`, `flint:data`, `flint:cli`) so application code stays clean, readable, and fast for `dmd` to compile.
     - Ban deprecated D1/early-D2 idioms and ambiguous Phobos imports.

---

# Master Library List (All 37 Libraries in the `flint` Monorepo)

All 37 libraries live as independent DUB subpackages (`packages/<name>/dub.sdl`) inside the `flint` monorepo so users only pay compile time and binary size for the subpackages they import.

## Tier 0: Runtime, Concurrency & Memory Core
| Subpackage | Reference Implementation (Java / Go) | Required Feel & D Implementation Strategy |
| :--- | :--- | :--- |
| `flint:reactor` | **Java:** Netty (`io.netty`)<br>**Go:** `runtime/netpoll` | Thread-per-core event loop (`io_uring` Linux, `kqueue` macOS, `IOCP` Windows) with core-pinned fibers respecting D's TLS model. No cross-thread fiber migration. |
| `flint:arena` | **Java:** Netty `ByteBufAllocator`<br>**Go:** `sync.Pool` | `@nogc`, `-betterC`-compatible bump/arena allocators and buffer pools. O(1) `RequestArena` reset keeps GC off the server hot path. |
| `flint:conc` | **Go:** `errgroup`, `chan`, `context`<br>**Java:** `StructuredTaskScope` | Lock-free MPSC/MPMC channels, bounded worker thread pools (offloading blocking C/disk calls off reactor cores), and Go-style `Context` cancellation/deadlines. |

## Tier 1: Core Spring Foundation
| Subpackage | Reference Implementation (Java / Go) | Required Feel & D Implementation Strategy |
| :--- | :--- | :--- |
| `flint:di` | **Java:** Spring Core (`spring-context`, Spring Boot 4 `BeanRegistrar`) | Compile-time IoC container: `@Service`, `@Repository`, `@Component`, `@Singleton`, constructor injection, and explicit `BeanRegistrar` wiring generating a static `AppContext` via `__traits`/`mixin`. Zero runtime classpath scanning. |
| `flint:config` | **Java:** Spring Boot `@ConfigurationProperties`<br>**Go:** `spf13/viper` | Binds `application.toml`/`.json`/`.env`, CLI overrides, and active profiles (`dev`, `prod`) into strongly typed D `struct`s at startup; fail-fast on missing keys. |
| `flint:serde` | **Java:** Jackson 3 (`tools.jackson`)<br>**Go:** `encoding/json` | Compile-time JSON/TOML/YAML serialization via UDAs (`@JsonName`, `@JsonIgnore`, `@JsonDefault`). Must support `@nogc` + `flint:arena` + `-betterC` for WASM reuse. |
| `flint:validate` | **Java:** Jakarta Bean Validation 3.1 / Hibernate Validator<br>**Go:** `go-playground/validator` | Declarative struct validation via UDAs (`@NotBlank`, `@Min`, `@Max`, `@Email`, `@Pattern`) unrolled at compile time via `static foreach`. `@nogc` + `-betterC`-compatible. |
| `flint:log` | **Java:** SLF4J + Logback<br>**Go:** `log/slog`, `rs/zerolog` | High-throughput, `@nogc`-capable structured logger with JSON (prod) and pretty colorized console (dev) sinks, plus thread-local MDC request-ID propagation. |
| `flint:test` | **Java:** JUnit 5 + AssertJ + Spring Boot Test<br>**Go:** `stretchr/testify` | Fluent assertions (`expect(x).toEqual(y)`), compile-time interface mock generator (`Mock!UserRepo`), and rich test runner hooking into D's built-in `unittest` blocks. |

## Tier 2: Web, APIs & Cloud ("Spring Boot Web")
| Subpackage | Reference Implementation (Java / Go) | Required Feel & D Implementation Strategy |
| :--- | :--- | :--- |
| `flint:web` | **Java:** Spring WebMVC (`spring-boot-starter-web`)<br>**Go:** `net/http` + `go-chi/chi` | HTTP/1.1 & HTTP/2 server on `flint:reactor` (wrapping `llhttp`/`nghttp2`). `@RestController`, `@RequestMapping`, `@Get`, `@Post`, `@PathVariable`, `@QueryParam`, `@RequestBody`, API versioning, `@ControllerAdvice` compiled into a static radix-tree router. |
| `flint:http` | **Java:** Spring 7 `@HttpExchange` / `RestClient`<br>**Go:** `go-resty/resty` | Fluent HTTP client (wrapping `libcurl` or native `flint:reactor`) plus compile-time declarative interface clients (`@HttpExchange`, `@GetExchange`). |
| `flint:security` | **Java:** Spring Security (filter chain DSL, `@PreAuthorize`)<br>**Go:** `golang-jwt/jwt` + `crypto/*` | Composable auth middleware, JWT, OAuth2/OIDC bearer validation, RBAC (`@RolesAllowed`), CORS, and password hashing wrapping `OpenSSL` or `libsodium`. |
| `flint:actuator` | **Java:** Spring Boot Actuator 4 + Micrometer 2<br>**Go:** OpenTelemetry + Prometheus `client_golang` | `/actuator/health` (K8s liveness/readiness), `/actuator/metrics` (Prometheus scrape), and OTLP trace/metric export. |
| `flint:schedule` | **Java:** Spring `@Scheduled` + Resilience4j<br>**Go:** `robfig/cron` | Cron/fixed-rate task UDAs (`@Scheduled`), plus composable resilience primitives (`@Retryable`, circuit breakers, rate limiters, timeouts). |
| `flint:rpc` | **Java:** Spring gRPC (Boot 4.1)<br>**Go:** `google.golang.org/grpc` + `coder/websocket` | WebSockets (`@WebSocket`), SSE, and Protobuf codegen / gRPC transport layer. |

## Tier 3: Data & Persistence ("Spring Data")
| Subpackage | Reference Implementation (Java / Go) | Required Feel & D Implementation Strategy |
| :--- | :--- | :--- |
| `flint:sql` | **Java:** JDBC + HikariCP<br>**Go:** `database/sql` + `jackc/pgx` | Async-friendly connection pool + `extern(C)`/ImportC drivers for PostgreSQL (`libpq`) and SQLite (`libsqlite3`) with prepared statements and `@Transactional` scoping. |
| `flint:data` | **Java:** Spring Data JDBC + jOOQ<br>**Go:** `sqlc` | `@Table`, `@Id`, `@Column` UDAs generating compile-time row-to-struct mappers, type-safe `CrudRepository!(T, ID)`, and `@Query` binding. Zero runtime ORM proxy bloat. |
| `flint:migrate` | **Java:** Flyway<br>**Go:** `pressly/goose` | Embeds versioned `.sql` migrations via D's compile-time `import(...)` (`-J`), tracking checksums and applying migrations automatically at startup. |
| `flint:cache` | **Java:** Spring Cache (`@Cacheable`, `@CacheEvict`) + Caffeine<br>**Go:** `redis/go-redis` | Unified caching API backed by lock-striped in-memory LRU/TTL cache and RESP3 Redis/Valkey client (`hiredis` or native `flint:reactor`). |

## Tier 4: CLI & TUI Stack ("Go + Charmbracelet")
| Subpackage | Reference Implementation (Java / Go) | Required Feel & D Implementation Strategy |
| :--- | :--- | :--- |
| `flint:cli` | **Go:** `spf13/cobra` + `pflag`<br>**Java:** `picocli` | UDA-driven CLI parser (`@Command`, `@Option`, `@Arg`) auto-generating typed parsing, validation, colorized `--help`, and bash/zsh/PowerShell completions at compile time. |
| `flint:term` | **Go:** `golang.org/x/term` + `muesli/termenv` | Cross-platform raw terminal mode (`termios` / Windows Console API), terminal size, ANSI color profile detection, alt-screen, mouse/key decoding. |
| `flint:tui` | **Go:** Charmbracelet `bubbletea/v2` | Elm Architecture (Model–Update–View) TUI runtime with differential rendering, async commands, and input event loop. |
| `flint:style` | **Go:** Charmbracelet `lipgloss/v2` | Declarative terminal styling/layout: colors, padding, margins, borders, horizontal/vertical joins, box alignment. |
| `flint:widgets` | **Go:** Charmbracelet `bubbles/v2` | Reusable `flint:tui` widgets: text input, textarea, viewport, filterable list, data table, progress bar, spinner, paginator. |
| `flint:prompt` | **Go:** Charmbracelet `huh` | High-level interactive forms/wizards (confirm, select, multi-select, password, grouped surveys) usable standalone or inside `flint:tui`. |
| `flint:os` | **Go:** `os/exec` + `os/signal` + `path/filepath` | Ergonomic wrapper over `std.process`/`std.file`: context-cancellable subprocesses with live stdout/stderr streaming, graceful `SIGINT`/`SIGTERM` hooks, recursive globbing. |

## Tier 5: WebAssembly, Browser PWAs & Edge (`WASM` / `-betterC`)
| Subpackage | Reference Implementation (Java / Go / Web) | Required Feel & D Implementation Strategy |
| :--- | :--- | :--- |
| `flint:wasm-bridge` | **Go:** `syscall/js` + TinyGo<br>**Rust:** `wasm-bindgen` | `-betterC` LDC `wasm32` target. Linear-memory binary command buffer paired with a tiny JS micro-driver flushing batched DOM/Canvas/WebGPU ops once per animation frame. |
| `flint:ui-signals` | **Web:** SolidJS / Preact Signals<br>**Rust:** Leptos | Fine-grained reactive state graph in `-betterC` D (`struct`s + flat arrays, zero GC) emitting minimal patches to `flint:wasm-bridge`. |
| `flint:wasi` | **Go:** `GOOS=wasip1` + `wazero`<br>**Wasm:** WASI 0.2 / 0.3 | Dual scope: (1) WASI 0.2/0.3 compilation target for edge runtimes; (2) `extern(C)` wrapper around `wasmtime`/`WAMR` to run sandboxed WASM plugins inside native `flint` servers. |

## Tier 6: Event-Driven Cloud, Queues & Storage ("Spring Cloud")
| Subpackage | Reference Implementation (Java / Go) | Required Feel & D Implementation Strategy |
| :--- | :--- | :--- |
| `flint:mq` | **Java:** Spring Kafka / AMQP<br>**Go:** `nats.go` / `franz-go` | Wrap `librdkafka` for Kafka + lightweight native `flint:reactor` NATS JetStream client. Expose `@KafkaListener` / `@StreamListener` UDAs wired at compile time. |
| `flint:storage` | **Java:** Spring Cloud AWS S3<br>**Go:** `aws-sdk-go-v2` / `minio-go` | S3-compatible object storage client (S3, R2, MinIO) over `flint:http` with SigV4 signing and streaming multipart upload/download. |
| `flint:mail` | **Java:** Spring Mail (`JavaMailSender`)<br>**Go:** `go-mail` | Unified email abstraction supporting SMTP (over `flint:reactor` + OpenSSL) and HTTP transactional APIs (SES, Resend, Postmark). |

## Tier 7: AI & Agent Tooling ("Spring AI")
| Subpackage | Reference Implementation (Java / Go) | Required Feel & D Implementation Strategy |
| :--- | :--- | :--- |
| `flint:ai` | **Java:** Spring AI (`ChatClient`, `@Tool`)<br>**Go:** `openai-go` / `anthropic-sdk-go` | Unified LLM client (OpenAI, Anthropic, Gemini, OpenRouter) over `flint:http` with SSE streaming, compile-time JSON Schema generation from D `struct`s, and `@Tool` function dispatchers. |
| `flint:mcp` | **Java:** Spring AI MCP<br>**Go:** `mark3labs/mcp-go` | Model Context Protocol (MCP) server & client (stdio + Streamable HTTP) driven by `@McpTool` and `@McpResource` UDAs. |

## Tier 8: Server-Side HTML, Compression & Native UI
| Subpackage | Reference Implementation (Java / Go) | Required Feel & D Implementation Strategy |
| :--- | :--- | :--- |
| `flint:template` | **Java:** JTE / Thymeleaf<br>**Go:** `a-h/templ` | Compile-time HTML/email templating via `import(...)` + CTFE/`mixin` for SSR and HTMX with compile-time variable checking. |
| `flint:codec` | **Java:** `java.util.zip` / Commons Compress<br>**Go:** `klauspost/compress` | Thin `extern(C)` wrappers for `zstd`, `zlib`, and `brotli` (HTTP compression + archives), plus optional `stb_image`. |
| `flint:desktop` | **Go:** Wails<br>**Rust:** Tauri / GPUI | Optional native desktop shell wrapping WebView2 / WKWebView / WebKitGTK via C (or SDL3 + wgpu for pure GPU-rendered native apps). |

---

# Deep Research Tasks You Must Perform Before Writing Specs

Research and resolve every technical risk below with concrete, evidence-backed architectural decisions (ADRs):

1. **D Toolchain & Monorepo Mechanics (2026 Reality):**
   - Research DUB subpackage quirks (e.g., `targetType "none"` root recipes, incremental build caching, `dub describe`, `subConfiguration`, build graph orchestration across 37 subpackages) and design a clean workspace orchestration tool/script (`tools/flint-build.d` or `Makefile`/`justfile`) so agents can build, test, and benchmark affected subpackages cleanly.
   - Research exact compiler flags for `dmd` (fast dev/test, `-unittest`, `-preview=dip1000` evaluation—decide explicitly whether to enable `dip1000` or avoid it for agent ergonomics!) and `ldc2` (release optimization, `-O3`, `-Oz`, `--flto=thin`, PGO, static `musl` linking via `zig cc` or Alpine containers, and `-mtriple=wasm32-unknown-unknown-wasm`).
2. **Existing D Ecosystem Audit (Build vs. Wrap vs. Fork):**
   - Audit existing D projects (`vibe-core`, `photon`, `serverino`, `mir-ion`, `arsd`, `silly`, `hunt`, `opend`) and make a crisp decision per tier on whether to build cleanly from scratch over C libraries or vendor/adapt specific ideas—keeping our strict zero-bloat, fast-compile, Spring-feel guarantees intact.
3. **Compile-Time Performance Traps in D:**
   - Document the exact patterns that destroy `dmd` compile speed (excessive `std.regex`, recursive templates, giant `static foreach` over huge symbol tables, importing heavy Phobos umbrella modules) and specify concrete architectural workarounds (`-ftime-trace` / template instantiation caps, minimal imports, helper codegen boundaries).
4. **Thread-Per-Core + Arena + GC Coexistence:**
   - Design the exact memory ownership contract between `flint:reactor`, `flint:arena`, `flint:web`, and D's GC (including how GC-managed user objects and `@nogc` request arenas safely interact, when to call `GC.addRange`/`GC.removeRange` vs. banning escaping references, and how to prove zero GC triggers on hot paths in CI).
5. **`-betterC` Dual-Target Compatibility Strategy:**
   - Specify the exact subset of D allowed inside `flint:arena`, `flint:serde`, `flint:validate`, `flint:wasm-bridge`, and `flint:ui-signals` so they compile cleanly both in full D (`dmd`/`ldc2` native) and in `-betterC` (`ldc2` `wasm32`) without code duplication.
6. **C-Library Pinning & Cross-Compilation Matrix:**
   - Pin exact C library versions, licenses (permissive/MIT/BSD/Apache/Zlib only—flag any GPL/LGPL risks), header strategy (`extern(C)` bindings vs. ImportC), and static vs. dynamic linking rules across Linux (`x86_64`/`aarch64` musl & glibc), macOS (`arm64`), and Windows (`x86_64`).

---

# Mandatory CI/CD Quality, Architecture, Speed & Performance Gates

Design a complete, runnable CI/CD governance system so that **coding agents can never silently degrade compile times, binary sizes, architecture, safety, or runtime performance**. Every PR must enforce all 6 gates:

1. **Gate 1 — Code Quality & Pragmatic Safety:**
   - `dfmt --check` formatting verification.
   - `dscanner` static analysis (style, unused variables, cyclomatic complexity, deprecated constructs).
   - **Safety Audit Script:** Enforces `@safe` coverage targets per tier; verifies `@trusted` / `@system` only appear in allowlisted low-level modules (`ffi/`, `sys/`, `arena/`, `reactor/`) and that every `@trusted` block has an adjacent `// SAFETY:` rationale comment.
   - AddressSanitizer / UndefinedBehaviorSanitizer (`ldc2 -fsanitize=address,undefined`) run on all `@trusted` / C-FFI unit tests.
2. **Gate 2 — Architectural Boundary & DAG Enforcement:**
   - Automated dependency graph checker parsing all `dub.sdl` files and D `import` statements:
     - Enforces strictly acyclic imports and strict Tier ordering (e.g., Tier 4 CLI/TUI packages may NEVER import Tier 2/3 Web/Data packages; Tier 0/1 may NEVER import higher tiers).
     - Enforces zero forbidden Phobos imports (e.g., banning `std.regex` in core packages to protect compile times).
     - Verifies `-betterC` + `wasm32` compilation succeeds for all dual-target packages (`flint:arena`, `flint:serde`, `flint:validate`, `flint:wasm-bridge`, `flint:ui-signals`).
3. **Gate 3 — Compile-Time Regression Budgets (Anti-Slowdown Gate):**
   - Measures and tracks cold + incremental `dmd` and `ldc2` compile times for every subpackage and 3 canonical benchmark apps (`bench-cli`, `bench-rest`, `bench-wasm`).
   - Enforces hard ceilings (e.g., `bench-cli` cold `dmd` build under 1.5s; `bench-rest` cold `dmd` build under 3.0s) AND fails CI if any PR increases compile time by more than 10% over baseline.
   - Tracks template instantiation counts / compiler memory usage to catch metaprogramming creep early.
4. **Gate 4 — Binary Size Regression Budgets:**
   - Measures stripped `ldc2` release binaries (`-O3` and `-Oz`) for `bench-cli`, `bench-rest`, and `bench-wasm` (`.wasm` raw + gzipped).
   - Enforces hard caps (e.g., `bench-cli` under 3 MB, `bench-rest` under 8 MB, `bench-wasm` under 100 KB gzipped) and fails CI on greater than 5% unexplained growth.
5. **Gate 5 — Runtime Performance, Allocation & Tail-Latency Benchmarks (vs. Baseline & Reference Go Binary):**
   - Microbenchmark suite (`flint:arena`, `flint:serde`, `flint:validate`, router dispatch, `flint:reactor` echo) with statistical regression detection.
   - End-to-end HTTP load benchmark (`wrk`/`oha`) comparing `bench-rest` against a committed baseline **and** an equivalent reference Go (`net/http`) service on throughput (req/s), p50/p99/p99.9 latency, and peak RSS RAM.
   - **Hot-Path GC Allocation Gate:** Runs hot-path endpoints under D's GC profiler (`--DRT-gcopt=profile:1`) and fails CI if unexpected GC collections or heap allocations occur inside `@nogc` request paths.
6. **Gate 6 — Cross-Platform & Static Binary Matrix:**
   - Linux (`x86_64`, `aarch64` static `musl` via LDC + `zig cc` or Alpine), macOS (`arm64`), Windows (`x86_64`), and `wasm32` target verification.

---

# Required Deliverable: Exact Handoff `.zip` Package Structure

Package all research, architecture, specs, CI pipelines, scripts, and golden templates into a downloadable **`flint-agent-handoff.zip`** with the following structure:

```text
flint-agent-handoff/
├── README.md                          # Executive overview & quickstart for human + agents
├── AGENTS.md                          # Master autonomous coding-agent operating manual & rules
├── MILESTONES_EXECUTION_PLAN.md       # Phased build order (Milestones 1–6) with dependency DAG & parallelizable workstreams
├── docs/
│   ├── RESEARCH_REPORT.md             # Deep research findings (DMD/LDC 2026, DUB quirks, existing D libs audit, WASM/-betterC)
│   ├── AGENT_D_DIALECT.md             # Strict "Agent D" coding standard, pragmatic @safe/@trusted rules, forbidden patterns
│   ├── ARCHITECTURE_DAG.md            # Full 37-package dependency graph, tier isolation rules, memory/concurrency contract
│   ├── C_FFI_PINNING_MATRIX.md        # Exact C libraries, versions, licenses, linking strategy, cross-compile recipes
│   ├── CI_PERFORMANCE_BUDGETS.md      # Exact numeric thresholds for Gates 1–6 & how baselines are updated
│   └── adrs/                          # Numbered Architecture Decision Records (ADR-001 through ADR-012+)
├── specs/
│   ├── tier-0/                        # Detailed engineering specs for reactor, arena, conc
│   ├── tier-1/                        # di, config, serde, validate, log, test
│   ├── tier-2/                        # web, http, security, actuator, schedule, rpc
│   ├── tier-3/                        # sql, data, migrate, cache
│   ├── tier-4/                        # cli, term, tui, style, widgets, prompt, os
│   ├── tier-5/                        # wasm-bridge, ui-signals, wasi
│   ├── tier-6/                        # mq, storage, mail
│   ├── tier-7/                        # ai, mcp
│   └── tier-8/                        # template, codec, desktop
│   # EVERY library spec MUST contain:
│   #   1. Purpose & Java/Go reference parity checklist
│   #   2. Exact DUB subpackage recipe (`dub.sdl`) & allowed dependencies
│   #   3. Concrete public D API signatures & UDA definitions (exact syntax)
│   #   4. Internal architecture, C-FFI bindings, safety tier (`@safe`/`@trusted`/`@nogc`/`-betterC`)
│   #   5. Compile-time & binary-size budgets for that package
│   #   6. Acceptance criteria, edge cases, and required `unittest` + benchmark test cases
├── scaffold/
│   ├── dub.sdl                        # Root monorepo DUB manifest
│   ├── dfmt.ini / .editorconfig       # Formatter configuration
│   ├── dscanner.ini                   # Static analyzer configuration
│   ├── tools/                         # Workspace build orchestrator + CI guardrail scripts (DAG, safety, compile-time, size, GC profile)
│   └── .github/workflows/             # Complete GitHub Actions workflows implementing Gates 1–6
├── templates/
│   ├── golden-cli/                    # Canonical CLI app using flint:cli + flint:log + flint:config
│   ├── golden-tui/                    # Canonical TUI app using flint:tui + flint:style + flint:widgets
│   ├── golden-rest-service/           # Canonical Spring-style REST API using flint:di + flint:web + flint:data + flint:serde
│   ├── golden-wasm-app/               # Canonical -betterC WASM module + tiny JS micro-driver using flint:wasm-bridge + flint:ui-signals
│   └── reference-go-rest/             # Minimal equivalent Go `net/http` service used as the CI head-to-head performance baseline
└── task-prompts/
    └── milestone-01..06.md            # Ready-to-dispatch atomic agent task prompts (with exact input files, commands, and definition-of-done)
```

---

# Execution & Verification Rules for You (GPT Pro)

1. **Be brutally concrete:** Write real, syntactically valid D code in all golden templates and library specs—never pseudocode. Verify that every UDA syntax, `__traits` pattern, `dub.sdl` subpackage reference, and compiler flag is valid in modern D (DMD 2.114+ / LDC 1.43+).
2. **Prevent agent deadlocks:** In `MILESTONES_EXECUTION_PLAN.md` and `task-prompts/`, break work into small, independently testable vertical slices where every task ends with a passing `dub test` + CI gate command.
3. **Flag real trade-offs honestly:** Where D has genuine friction (e.g., `dip1000` ergonomics, `-betterC` string/exception limitations, Windows `IOCP` vs. Linux `io_uring`, DUB subpackage caching), document the exact engineering workaround in an ADR so coding agents never waste cycles rediscovering known pitfalls.
4. **Generate the actual `.zip` file:** Create every file in the tree above, verify internal cross-references and JSON/SDL/YAML syntax, package everything cleanly into `flint-agent-handoff.zip`, and provide a concise executive summary of the completed package and any high-risk decisions I should review before unleashing the coding agents.