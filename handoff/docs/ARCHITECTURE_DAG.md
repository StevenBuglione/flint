# Package DAG and ownership architecture

`../scaffold/policy/packages.json` is the machine-readable source of truth. Catalog tiers are the user's tiers. An edge in the table means a permitted direct compile dependency; every actual direct import also needs its corresponding DUB dependency. The graph must be acyclic even within one tier. D module hierarchy may contain submodules of the listed module.

| DUB package | Tier | Direct dependencies | Public D module |
|---|---:|---|---|
| `flint:reactor` | 0 | `arena`, `conc` | `flint.reactor` |
| `flint:arena` | 0 | `none` | `flint.arena` |
| `flint:conc` | 0 | `arena` | `flint.conc` |
| `flint:di` | 1 | `arena` | `flint.di` |
| `flint:config` | 1 | `arena`, `serde`, `validate` | `flint.config` |
| `flint:serde` | 1 | `arena` | `flint.serde` |
| `flint:validate` | 1 | `arena` | `flint.validate` |
| `flint:log` | 1 | `arena`, `conc` | `flint.log` |
| `flint:test` | 1 | `none` | `flint.test` |
| `flint:web` | 2 | `arena`, `reactor`, `conc`, `di`, `serde`, `validate`, `log` | `flint.web` |
| `flint:http` | 2 | `arena`, `reactor`, `conc`, `serde` | `flint.http` |
| `flint:security` | 2 | `arena`, `http`, `serde`, `conc` | `flint.security` |
| `flint:actuator` | 2 | `arena`, `reactor`, `web`, `http`, `log`, `serde`, `conc` | `flint.actuator` |
| `flint:schedule` | 2 | `arena`, `reactor`, `conc`, `log` | `flint.schedule` |
| `flint:rpc` | 2 | `arena`, `reactor`, `conc`, `web`, `http`, `serde` | `flint.rpc` |
| `flint:sql` | 3 | `arena`, `reactor`, `conc`, `log` | `flint.sql` |
| `flint:data` | 3 | `arena`, `sql`, `serde`, `validate`, `di`, `conc` | `flint.data` |
| `flint:migrate` | 3 | `arena`, `sql`, `log`, `conc` | `flint.migrate` |
| `flint:cache` | 3 | `arena`, `reactor`, `conc`, `serde` | `flint.cache` |
| `flint:cli` | 4 | `arena`, `validate` | `flint.cli` |
| `flint:term` | 4 | `arena` | `flint.term` |
| `flint:tui` | 4 | `arena`, `conc`, `term`, `style` | `flint.tui` |
| `flint:style` | 4 | `none` | `flint.style` |
| `flint:widgets` | 4 | `arena`, `tui`, `style` | `flint.widgets` |
| `flint:prompt` | 4 | `arena`, `term`, `tui`, `widgets`, `validate` | `flint.prompt` |
| `flint:os` | 4 | `arena`, `conc` | `flint.os` |
| `flint:wasm-bridge` | 5 | `arena` | `flint.wasm_bridge` |
| `flint:ui-signals` | 5 | `arena`, `wasm-bridge` | `flint.ui_signals` |
| `flint:wasi` | 5 | `arena`, `conc` | `flint.wasi` |
| `flint:mq` | 6 | `arena`, `reactor`, `conc`, `serde`, `log` | `flint.mq` |
| `flint:storage` | 6 | `arena`, `http`, `security`, `conc` | `flint.storage` |
| `flint:mail` | 6 | `arena`, `http`, `reactor`, `conc` | `flint.mail` |
| `flint:ai` | 7 | `arena`, `http`, `serde`, `conc`, `validate` | `flint.ai` |
| `flint:mcp` | 7 | `arena`, `http`, `web`, `serde`, `validate`, `conc` | `flint.mcp` |
| `flint:template` | 8 | `arena`, `serde` | `flint.templates` |
| `flint:codec` | 8 | `arena` | `flint.codec` |
| `flint:desktop` | 8 | `arena`, `conc`, `os`, `wasm-bridge` | `flint.desktop` |

## Composition boundaries

Tier 0 has no application service dependencies. Tier 1 can depend on Tier 0 or earlier peers but cannot depend on web/data. Tier 4 CLI/TUI has an additional prohibition on web/data even though their catalog numbers are lower. The console app itself can choose both a CLI and an HTTP adapter; `flint:cli` cannot import that adapter.

Codec/template packages retain their Tier 8 catalog position. A web application imports `flint:web` and `flint:codec` and registers a compression callback. Web only knows its callback interface. The same principle attaches server-side templates, UI shells, cache adapters, tracing sinks and provider integrations without reverse dependencies. `flint:security` produces independent authorization decisions; an application supplies them to web middleware. It does not import the web layer.

`flint:serde` uses a package module so its BetterC core can be imported independently of full-D `owned` and YAML adapter modules. The dependency gate checks the specific closure of every dual-target entry point. A compatible root module does not prove every optional submodule is BetterC.

## Lifecycle contract

1. Process startup loads configuration, checks secrets/required settings, creates explicit native resources and provides externally owned handles to the DI context.
2. DI allocates its service graph, topologically calls lifecycle callbacks and constructs controllers. Route metadata is generated at compile time; sockets bind only after all startup validation succeeds.
3. Each loop thread owns connection state, an operation table, timers, a bounded incoming queue and a local fiber pool. A connection belongs to one loop. Native completions carry stable operation IDs with generations.
4. A request borrows a checked arena, immutable service references and a cancellation context. Input parsing enforces configured limits before allocation. Arena handles are valid only for that request epoch.
5. Returning from a handler does not free pending send buffers. The HTTP layer retains ownership until every send/cancel completion is observed; then it resets the arena and returns it to the local pool.
6. Offloaded work receives an explicitly owned immutable copy, never a borrowed arena view. Its completion is posted back to the owner loop. Deadline cancellation is idempotent and cannot race into a double free.
7. Shutdown stops admission, propagates cancellation, drains/aborts streams within a fixed deadline, observes final completions, joins worker threads, shuts down DI in reverse dependency order and finally closes externally owned resources.

## Request context and GC

A task-local context carries trace/request IDs, deadlines and authorization identity. A thread-local current-task pointer is saved/restored on every fiber switch. A worker queue message includes a copied context snapshot. The logger never reads another fiber's stale MDC.

GC data and native data have distinct ownership: startup DI objects are GC-rooted; arena payloads never hold GC pointers. Opaque `void*` fields are private implementation details, never permission for a public `@safe` API to accept arbitrary pointers. Foreign storage with GC references requires an exceptional audited registration owner. The default request path does not call `GC.addRange` or globally disable the collector.

## Cancellation and bounded work

Every enqueue operation declares capacity and full behavior. Reactor completion queues and channel rings use power-of-two bounded capacities. An overload returns `resourceExhausted` or waits with a cancellation/deadline token. No dropping a completion that releases memory. Timers use monotonic deadlines; civil-time cron is separate and defines daylight-saving behavior. Any C callback may only enqueue/copy approved data and must not throw across the ABI.

## Feature and trust boundaries

System/C bindings are `@system` and private; tiny wrappers establish sizes, ownership, thread affinity and callback lifetimes before exposing `@safe` methods. Hardware atomics use explicit memory orders and prove reclamation independently of ring-index atomicity. MPSC and MPMC are separate tested implementations. No boolean label such as “lock-free” exempts a queue from fairness, ABA, overflow, cancellation and wraparound tests.

Browser exports validate ranges in linear memory with overflow-safe arithmetic. JS validates record length, opcode, generation and UTF-8 before touching DOM state. Server plugin instances are isolated by engine memory/fuel/epoch limits and host-call allowlists; request arenas are not exposed as raw host pointers to a guest.
