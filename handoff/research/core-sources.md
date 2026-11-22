# Core language and ownership evidence

Access date: **2026-11-21**. These are primary sources. Claims below are deliberately narrow; the detailed ownership protocols and performance limits in specs are Flint decisions. Live documentation can have inconsistent version labels, so the actual pinned compiler tests take precedence for syntax/flags.

| Source | Verified capability / limitation | Flint consequence |
| --- | --- | --- |
| [D function specification](https://dlang.org/spec/function.html#nogc-functions) | @nogc restricts D GC allocation/calls; another thread may still trigger GC. `scope` and `return scope` constrain indirection escape. | Distinct checks for allocation and process collections; borrowed arena APIs have explicit lifetime annotations. |
| [BetterC specification](https://dlang.org/spec/betterc.html) | BetterC excludes druntime-dependent classes, TypeInfo, exceptions, AA, threading and module constructors. Supplied slices work; ordinary D runtime arrays do not. Imports alone do not prove library compatibility. | Shared structs/slices core; optional native adapters; link/run probes in addition to compile checks. |
| [Memory safety specification](https://dlang.org/spec/memory-safe-d.html) | Safe interfaces and trusted boundaries are distinct; lifetime checks must be enabled for the chosen toolchain. | DIP1000 stays enabled, explicit misuse fixtures, no resettable raw-slice API. |
| [GC API](https://dlang.org/library/core/memory/gc.html) | Foreign references need explicit roots/ranges; add/remove range only changes scan registration. | No GC pointers in arenas; paired root-registration adapters for retained C callbacks. |
| [GC statistics](https://dlang.org/library/core/memory/gc.allocated_in_current_thread.html) | allocatedInCurrentThread reports cumulative bytes for the calling thread. | Sample each participating reactor worker itself at barriers; process main-thread counters alone are insufficient. |
| [GC ProfileStats](https://dlang.org/library/core/memory/gc.profile_stats.html) | Profile statistics contain numCollections and collection/pause timing. | Detect unrelated-thread collections during measured phases instead of declaring @nogc globally pause-free. |
| [Fiber API](https://dlang.org/library/core/thread/fiber/fiber.html) | A suspended fiber may be passed to another thread; execution uses the calling thread's context. | Flint pinning is a deliberate policy. TLS is not fiber-local request storage. |
| [UDA specification](https://dlang.org/spec/attribute.html#uda) | Attributes attach compile-time metadata; struct values are valid annotations. | Bare markers and constructor-valued markers in the contracts are valid D syntax; effects require explicit generated binders. |
| [Traits specification](https://dlang.org/spec/traits.html) | getAttributes/getUnitTests expose metadata at compile time. | Inspect explicit registries; no unbounded module scan. |
| [JSON RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) | Defines interoperable JSON syntax and UTF-8 expectations. | Strict JSON parser with additional Flint duplicate-key/resource limits. |
| [TOML 1.0.0](https://toml.io/en/v1.0.0) | Defines the deliberately selected config format grammar and value types. | Pin TOML 1.0 behavior; do not claim latest TOML grammar support. |
| [Unicode 17.0.0 PropList](https://www.unicode.org/Public/17.0.0/ucd/PropList.txt) | Lists the 25 White_Space code points used by the validator. | Exact NotBlank table, deterministic UTF-8 semantics. |

## Observed compiler verification

The actual DMD 2.114.0 and LDC 1.43.0 installations were run against core contracts. Both accepted instantiated config/DI/log/mock/serde/validate usage, accepted native BetterC core probes, and rejected callback-slice escape, returning an arena that borrows a local stack array, and direct fabrication through Buffer's private constructor. DMD emitted a native BetterC object; LDC emitted a wasm32 object for the core probe. See the machine-readable [receipt](../verification/core-contracts.json) and [probe files](../verification/probes/).

The probe does **not** link or run Flint runtime implementations. Function declarations are API fixtures, not no-op substitutes. It validates syntax, instantiation and lifetime restrictions, while package acceptance requires implementing the behavior, passing dub test, linking the correct C libraries and running benchmarks on the designated runner.

## Findings that changed the brief

1. @nogc alone cannot guarantee no collection pauses or zero C allocations. The gate requires both per-thread allocation deltas and process collection counters, plus explicit C allocation measurement where applicable.
2. A safe region API needs lifetime and reset discipline. Handle generations and callback borrows avoid exposing a slice that safe user code could retain after reset.
3. Fibers are pinned by Flint policy, not because the D Fiber API universally bans migration. Logging context must still be restored at fiber switches.
4. BetterC support is a property of the imported and linked code path. Optional owned/YAML adapters cannot be swept into every WASM build and still support the small-core claim.
5. Exact lifetime attributes matter. Compiler probes caught missing scope on ref RequestArena parameters and implicit this; all public contracts were corrected.
6. D struct field privacy alone did not prevent an aggregate construction probe. An explicit private Buffer constructor suppresses that API, with runtime validation retained.

## Recommended source audit details

Use the pinned druntime source for Fiber call/yield attributes, thread registration and sanitizer behavior before implementing trusted wrappers. Do not erase @nogc/@safe attributes with function-pointer casts. Check C callback signatures, calling convention, alignment and final-completion ownership against pinned headers. The original API boundary declaration is only the beginning of that review; ASan/fuzz and OS-specific completion tests are mandatory.

## Native owner counter evidence

The [official core.atomic API](https://dlang.org/library/core/atomic.html) and the pinned compiler distributions supply atomic load/store and compare/exchange. On 2026-11-21 both DMD 2.114.0 and LDC 1.43.0 compiled, linked and executed a native BetterC saturating 64-bit counter without a custom C object. The probe checks initial IDs, the last nonzero ID and permanent exhaustion. [Receipt and exact probe source](../verification/native-betterc-atomics.json). This is a standalone intrinsic/link capability check; it does not establish concurrent Flint arena behavior or a browser atomic implementation.
