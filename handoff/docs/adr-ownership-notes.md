# Core architecture decision notes

These records provide the detailed rationale for the numbered ADRs. Decisions are normative; they are not claims of measured framework performance.

## DIP1000 is mandatory

**Decision.** Enable `-preview=dip1000` in every DMD/LDC configuration and preserve @safe bounds checks in releases. Borrowed parameters carry scope, returned lifetime relationships carry return scope, and borrowed struct methods carry scope on implicit this.

**Evidence.** Actual pinned compiler probes accept the core positive usage and reject both arena-backing and callback-slice escapes. Omitting scope on the arena parameter or method caused legitimate safe use to fail, and was corrected in the contracts. The probes and captured diagnostics are in `verification/core-contracts.json`.

**Trade-off.** An agent must learn a small set of lifetime annotations and fix a boundary signature rather than disabling checking. D does not provide complete Rust-style ownership/exclusivity, so dynamic handle checks still protect resettable lifetimes. DIP1000 is necessary here, not sufficient alone.

## Arena handles and callbacks instead of escaping slices

**Decision.** The safe request API returns opaque scalar handles and only borrows bytes in scope callbacks. Reset rejects active callbacks and invalidates handles with owner/epoch. Explicit private constructors avoid accidental D aggregate construction, and default handles fail validation.

**Rejected option.** An @trusted allocate returning ubyte[] plus an @safe reset would let ordinary application code keep a slice after invalidation. Calling that wrapper trusted would be an unsound promise.

**Consequences.** There is a small handle-validation/branch cost at access, measured in the arena benchmark. Bulk operations amortize it over the whole slice. Zeroing on allocation is O(bytes) and protects request isolation; reset alone remains O(1). WASM uses the same semantics without druntime. Owner IDs and epochs fail closed on wrap.

## GC coexistence and references retained by C

**Decision.** Hot request regions contain no GC references. Ordinary D service/config objects are constructed before traffic and retained by druntime-visible roots. Foreign memory which must retain GC pointers uses a native registration adapter; register before exposing the callback/state, unregister only after the last completion, then free. No unregistered GC pointer lives on a foreign worker stack.

**Evidence.** core.memory describes addRoot/addRange and the hazards of threads unknown to the GC. addRange only adds the region to scanning; it does not own that region. Per-thread allocation counters and process collection counts measure different properties.

**Consequences.** D GC collection is process-wide with respect to registered threads. A request's @nogc call tree may still pause for another thread. The high-throughput profile must bound/relocate all traffic-time GC activity; performance claims remain gated against the equivalent Go process. Disabling GC while allocations grow is explicitly rejected. A worker process is the isolation boundary when an unbounded allocating integration cannot meet the latency contract.

## Pinned fibers and real task-local context

**Decision.** No Flint fiber migration, even though D permits transferring suspended fibers. A fiber's task record owns request/log context and the scheduler installs/restores it at every transition.

**Consequence.** A plain TLS MDC is insufficient. Every yield path and completion resumption must be tested with alternating requests. Per-core pinning simplifies ownership but cannot preempt CPU-heavy handlers; offload is explicit and bounded.

## BetterC core and native adapters

**Decision.** Structs, handles, fixed arrays and supplied slices form the shared core; owned GC strings, classes, threads, runtime TLS and exception paths stay in optional native modules. The same implementation is compiled for native and wasm32; do not maintain two nearly identical copies.

**Consequence.** A declared function or successful semantic-only compile does not prove a working browser binary. Native/wasm link and execution fixtures are separate gates. YAML is an optional libyaml-backed profile with C allocation and its own link artifacts; it is excluded from the tiny WASM core budget.

## Generated wiring is explicit and bounded

**Decision.** AppContext receives all bean/binding/registrar types explicitly and produces a bounded graph with direct constructor calls. Codegen never creates import statements or scans whole transitive module graphs.

**Consequence.** Compile-time discovery disappears from startup, but class allocation and interface dispatch remain normal runtime operations. Configuration-provided instances are borrowed, constructed beans are owned and rolled back/destroyed in reverse order. Duplicate bindings and cycles are compile errors with a concrete path.

## Error contracts remain nonallocating

**Decision.** Hot APIs use Status/Error/Result(T); Error carries a static string plus optional input byte offset. No exception object or formatted diagnostic allocation is hidden in parse/validation failures. Human diagnostics are expanded at startup/worker boundaries.

**Consequence.** Error paths have deterministic output/resource budgets and can run under @nogc. Template constraints and checked returns must make unsupported input types fail clearly before an unsafe conversion reaches runtime.
