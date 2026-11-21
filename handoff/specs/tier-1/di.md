# flint:di — implementation specification

Status: normative design for agents; contract declarations have been syntax checked. Runtime behavior below is an acceptance requirement, not a claim that a framework implementation already exists. The compiler receipt is [core-contracts.json](../../verification/core-contracts.json).

## 1. Purpose and reference parity

Generate constructor wiring for an explicit list of application beans, with Spring-style UDAs and deterministic startup/shutdown.

- [ ] Spring component/service/repository annotations are descriptive metadata on explicitly registered types.
- [ ] Constructor injection, interface-to-implementation bindings, singleton identity, startup hooks, shutdown hooks and test replacements are supported.
- [ ] No classpath scan, dynamic proxy, late class loading, reflection-based invocation or field injection is part of the contract.

## 2. Package boundary and exact DUB recipe

Catalog tier: **1**. Direct allowed Flint dependencies: **flint:arena**. No transitive import is an excuse to add a direct import without updating the dependency policy. Production code may not depend on flint:test. Recipe path: `packages/di/dub.sdl`, invoked from the monorepo root.

```sdl
name "di"
description "Flint di subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"

configuration "library" {
    targetType "library"
}
configuration "unittest" {
    targetType "library"
    sourcePaths "source" "tests"
    importPaths "source" "tests"
    excludedSourceFiles "tests/betterc.d"
}
```

The root manifest registers the subpackage path. Fully qualified flint:<name> sibling dependencies resolve in the parent package; do not turn these dependencies into independently fetched registry packages. The recipe and [packages policy](../../scaffold/policy/packages.json) are authoritative.

## 3. Public D API and UDA definitions

These are concrete signatures in the contract fixture, not executable implementations. Internal representation may change while preserving signatures and semantics. Source: `contracts/source/flint/di.d`.

```d
/// Public API contract; declarations are not runtime implementations.
module flint.di;
import flint.arena : Error;

@safe:
struct Service
{
}

struct Repository
{
}

struct Component
{
}

struct Singleton
{
}

struct Inject
{
}

struct Named
{
    string value;
}

struct PostConstruct
{
}

struct PreDestroy
{
}

struct Bind(Contract, Implementation)
{
    alias ContractType = Contract;
    alias ImplementationType = Implementation;
}
/// Bindings are explicit types; no module/classpath scan occurs.
struct BeanRegistrar(Bindings...)
{
}
/// Members expose concrete type-directed access to startup-created beans.
struct AppContext(Beans...)
{
    private void* state;
    @disable this(this);
    Error provide(T)(T value);
    Error initialize();
    T get(T)();
    void shutdown() nothrow;
}
```

## 4. Internal architecture, ownership and safety

The AppContext type argument list is the complete registration boundary. Each entry is a bean type, `Bind!(Contract,Implementation)`, or `BeanRegistrar!(Bindings...)`; flatten registrars left to right and reject duplicate final bindings. A bean has exactly one eligible public constructor. More than one constructor requires exactly one `@Inject` constructor; missing, ambiguous or cyclic dependencies are compile-time errors. Discover constructor parameter types with `__traits` and a bounded local type list, never by scanning imported modules. UDAs use `__traits(getAttributes, symbol)` only on listed types and members.

Build a graph of at most 128 beans and 512 constructor edges. Run iterative topological sorting at compile time; on a cycle, produce the actual type path. Generate one initialization function with fixed calls and one reverse-order cleanup function. Fail at compile time if `@PostConstruct`/`@PreDestroy` is duplicated, takes parameters, is inaccessible or has an unsupported signature. PostConstruct returns `Error` or void; PreDestroy is `void nothrow`. Constructor exceptions are caught at the startup boundary and converted into a startup Error after cleanup. Never catch Error-derived invariant failures to continue with a corrupt context.

`provide!T(value)` supplies a preconfigured instance before initialization, and only for T explicitly registered in the type list. Providing after startup or twice returns `conflict`; a missing type is a compile-time error. Supplied instances are borrowed by the context: the provider retains resource-close responsibility and keeps the handle valid until after `shutdown`. This supports Pool/Config values without teaching DI database APIs. Automatically constructed beans are owned by the context. On initialization failure, destroy only successfully initialized owned beans in reverse order and leave the context closed. `shutdown` is idempotent.

`get!T` emits direct member access or an explicit interface conversion. Dynamic interface calls still have normal runtime dispatch cost; singleton construction still requires startup work. The zero-overhead claim is limited to removal of runtime discovery and proxy machinery. Do not advertise zero overall runtime cost. Struct beans are startup values and returned by value only if copyable; classes are used when identity/polymorphism requires it. No request-scoped objects live in a global singleton context. Each reactor core receives an explicit instance of stateful per-core services; immutable shared config may be shared across loops.

**Safety boundary:** Public DI APIs and generated application wiring are `@safe`. Metaprogramming remains within `flint.di.internal`; generated code contains no casts, pointer arithmetic or imports. The declaration contract private state pointer represents implementation storage, not permission for unsafe application code.

## 5. Compile-time, size and runtime budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are release gates on the designated reference runner, not observed performance results. Measure the package's fixed feature fixture, with dependencies frozen; cold/incremental definitions and statistical regression rules come from [CI budgets](../../docs/CI_PERFORMANCE_BUDGETS.md).

| Metric | Hard ceiling |
| --- | ---: |
| DMD cold build | 0.80 s |
| DMD incremental build | 0.60 s |
| LDC cold build | 4.80 s |
| LDC incremental build | 2.40 s |
| Marginal stripped linked bytes | 262,144 bytes |
| Compiler peak RSS | 536,870,912 bytes |
| Template instantiations | 2,000 |

The >10% compile/template/RSS regression rule and >5% binary growth rule also apply; passing a hard ceiling does not permit silent drift. Marginal size follows the provider-equivalent definition above; full native-provider and dependency footprints remain in the recorded complete binaries. Package deltas are not summed to estimate an application. Native shared-library bytes and static-dependency bytes must both be reported. BetterC core: **not claimed**.

**Benchmark fixture:** Compile contexts of 1/16/64/128 beans and report template counts and compile RSS. Runtime tests measure direct get separately from interface invocation; startup allocations are recorded but excluded from per-request zero-allocation assertions.

## 6. Required acceptance tests and edge cases

1. Compile-fail missing dependency, ambiguous constructor, duplicate service, two bindings of an interface, self-cycle and a 3-bean cycle.
2. Singleton get identity; supplied Pool/config returned unchanged; provide after start fails.
3. Startup hook failure rolls back exactly constructed beans once; shutdown called twice remains safe.
4. Factory/type list of 128 beans passes budget; 129 produces a useful limit diagnostic.
5. Mock replacement in a test context produces no production repository construction.

Every listed case becomes a named unittest or a compiler-negative fixture, with a deterministic seed for generated schedules/inputs. FFI/kernel lifetime tests run under the platform sanitizer jobs. Add regression fixtures for every corrected failure before closing the slice.

## 7. Agent implementation order and definition of done

1. Add the package modules and public declarations, compile the positive contract usage and the negative misuse fixtures, then implement the smallest deterministic behavior covered by the first acceptance group.
2. Complete ownership/error paths before adding throughput optimization; include bounded-resource exhaustion tests.
3. Add the fixed benchmark fixture, record raw samples and candidate baseline receipts, and complete all acceptance groups before activating this package for integration.

Run from `scaffold/` after implementing this package:

```bash
python3 tools/flint.py test --package di --compiler dmd
python3 tools/gates.py --package di --gate structural
```

The direct test equivalent is `dub test :di --compiler=dmd`. Repeat with `--compiler ldc2` through the orchestrator. A declaration-only contract pass is never a substitute for `dub test` on a runtime implementation. Full Gates 1–6 run for the integrated milestone once its canonical apps and runner baselines exist; absence of a required measurement blocks release rather than fabricating a zero measurement.

## Evidence and rationale

The D capability behind this design is documented at [https://dlang.org/spec/traits.html#getAttributes](https://dlang.org/spec/traits.html#getAttributes) (accessed 2026-11-21). Normative limits, failure codes and ownership policies above are Flint design decisions. See [core research evidence](../../research/core-sources.md) for precise capability claims and verification boundaries.
