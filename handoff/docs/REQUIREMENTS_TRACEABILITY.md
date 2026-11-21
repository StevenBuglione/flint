# Requirements and verification boundaries

The original request is preserved in `ORIGINAL_BRIEF.md`. This table records every material interpretation/correction so agents do not silently narrow the deliverable or mistake a proposed target for an observed result.

| Requested requirement | Delivered definition and evidence | Remaining implementation work |
|---|---|---|
| All 37 independent libraries | 37 detailed specs, canonical recipes/dependency graph and compiler-checked public contracts | Implement runtime bodies and the specified behavioral suites |
| Spring-style ergonomic UDAs | Exact D syntax and golden DI/REST/CLI examples | Generated dispatch executes at documented call boundaries; ordinary direct D calls are not transparently intercepted |
| Faster/smaller/lower-latency than Go | Numeric absolute/relative gates, matched current-Go references and real collection scripts | Establish first measured baseline and satisfy caps; no Flint performance win is claimed by this handoff |
| DMD 2.114+/LDC 1.43+ | Exact 2.114.0/1.43.0 pins, archive hashes and actual compilation | Stay in their common frontend subset; deliberate upgrades require revalidation |
| Every public application API @safe | Dialect, negative lifetime fixtures, module/default safety audit and trusted-boundary allowlists | Every implementation and generated expansion must pass those checks |
| @nogc arenas with safe lifetime | Generation-checked handles, scoped callbacks, no hidden GC roots, actual escaped-reference compile failures | Runtime generation/bounds/concurrency and ASan/fuzz tests |
| Zero GC on request paths | Compile-time function annotation plus per-thread monotonic counters/process collection barriers | Real server workers must expose instrumented measurement barriers; GC profile summary alone is insufficient |
| Five BetterC/WASM packages | Separate core import closures and compiler probes, real standalone WASM link/execute test | Complete package implementations must link/run natively and in WASM, not merely typecheck declarations |
| JSON/TOML/YAML serialization | JSON/TOML core, full-D owned adapters and optional pinned libyaml backend | YAML is a native optional profile in this plan, not claimed to fit browser BetterC/100KB cap. Extending browser YAML requires a separate explicit parser/allocator/size proof |
| wasm32/WASI 0.2/0.3 | Browser core ABI separated from WIT/components/native engines; current runtime feature seams documented | Complete WASI p3 engine bridge may require same-version Rust C ABI glue where pinned Wasmtime C helpers stop at p2 |
| dfmt --check | Pinned dfmt lacks that flag; executable byte-comparison checker supplies the intended verification | Production source must be formatted; no silent omission of formatting gate |
| LDC ASan+UBSan | Actual LDC rejects undefined sanitizer; D ASan plus C-shim Clang ASan/UBSan and negative compiler tests | No claim of UBSan instrumentation of D semantics |
| Strict tier ordering | All 37 catalog positions retained; explicit direct allowlist; app-supplied high-tier adapters | No lower-tier import of codec/template/desktop just for convenience |
| Static musl and six native targets plus WASM | Pinned official LDC target archives, C source locks, target build recipes and actual platform workflow paths | Runtime acceptance requires executing each OS/architecture; host syntax checks do not certify it |
| Permissive C dependencies | Exact source/archive/license identities and notices, opt-in capability profiles | Verify actual linked transitive closure; WebKitGTK excluded from permissive default, OS frameworks retain OS terms |
| Complete CI governance | Quality/import/safety/measurement/load/size/target scripts and workflows; negative tests of failure cases | Provision repo checks/ephemeral runner and first empirical baseline; YAML cannot create account settings on its own |
| Independently testable task slices | Six milestone dispatch files, explicit package commands, prerequisite graph and concrete acceptance matrices | Full certification remains blocked while implementations/evidence are absent; local slice tests do not impersonate all-six results |
| No placeholders or pseudocode | Public signatures are actual D; executable tools and examples supplied; source-free runtime recipes explicitly fail | Declaration-only APIs are specifications, not function bodies or always-success stubs |
| Downloadable complete ZIP | All documentation, scripts, manifests, contracts, templates and verification evidence packaged together | No separate runtime distribution is represented as already built |

The two explicit product-scope decisions most likely to need review are native-only YAML in v1 and component-runtime integration beyond the pinned C API. They preserve a small, auditable browser core while keeping the required package surfaces defined. The performance caps are retained and may reveal infeasible feature/target combinations during implementation; such failures remain visible rather than being silently relaxed.
