# flint:data — Compile-time entities and SQL repositories without runtime ORM proxies

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] @Table/@Id/@Column/@Version/@ReadOnly mappings and typed CrudRepository!(T,ID).
- [ ] @Query binding, deterministic SQL generation and explicit optimistic concurrency.
- [ ] Compile-time field/type validation and direct row-to-DTO assignments.
- [ ] No lazy loading, identity-map magic, runtime reflection scan or implicit relationship traversal.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/data/dub.sdl inside the Flint root that declares all subpackages. Module: flint.data. Direct allowed dependencies: flint:arena, flint:sql, flint:serde, flint:validate, flint:di, flint:conc.

```sdl
name "data"
description "Flint data subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:sql" version="*"
dependency "flint:serde" version="*"
dependency "flint:validate" version="*"
dependency "flint:di" version="*"
dependency "flint:conc" version="*"

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

The source library has no executable main. Native build/link selection follows the central C-FFI matrix. Public imports are explicit; transitive dependency reachability does not authorize undeclared direct imports. No package in this specification may import a higher catalog tier or introduce a cycle.

## 3. Concrete public D contract

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/data.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.data;
import flint.arena : Error, RequestArena, Result;
import flint.conc : Context;
import flint.sql : Pool;

@safe:
struct Table
{
    string name;
}

struct Id
{
}

struct Column
{
    string name;
}

struct Query
{
    string sql;
}

struct Version
{
}

struct ReadOnly
{
}

struct PageRequest
{
    uint limit = 100;
    ulong offset;
}

struct Page(T)
{
    T[] items;
    bool hasMore;
}

interface CrudRepository(T, ID)
{
    Result!T findById(ID id, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Result!T save(scope const ref T entity, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error deleteById(ID id, ref Context context) nothrow @nogc;
    Result!bool existsById(ID id, ref Context context) nothrow @nogc;
}

final class SqlRepository(T, ID) : CrudRepository!(T, ID)
{
    this(ref Pool pool);
    override Result!T findById(ID id, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    override Result!T save(scope const ref T entity, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    override Error deleteById(ID id, ref Context context) nothrow @nogc;
    override Result!bool existsById(ID id, ref Context context) nothrow @nogc;
}

Error mapRow(T)(ref T entity, ref scope RequestArena arena, scope const(char)[] column, scope const(ubyte)[] value) nothrow @nogc;
```

## 4. Internal architecture and observable semantics

An entity is a struct with exactly one @Id field and one @Table name. Table/column identifiers must match ASCII identifier grammar [A-Za-z_][A-Za-z0-9_]*; qualified schema names are represented by a separately validated pair, not unescaped text. Duplicate mapped columns, missing IDs, unsupported types and multiple @Version fields fail compile. Supported persisted fields are signed integer scalars, bool, double, Text/Buffer and an explicit nullable wrapper supplied by generated metadata; pointers/classes/delegates are rejected. ID type must match the @Id field and fit backend integer rules.

SqlRepository stores a value-copied Pool handle, not a pointer to the caller's stack variable. Startup validates generated table/column metadata against a prepared zero-row query. findById returns notFound for no row and conflict for multiple rows. save inserts when the chosen explicit ID policy is unset, updates otherwise; never guess existence by catching arbitrary SQL errors. For the initial unsigned integer ID profile, id=0 denotes generated identity and any nonzero ID is an explicit value. PostgreSQL uses RETURNING; SQLite uses the same modern returning support where pinned, with transaction-scoped last-insert-rowid fallback only if explicitly selected. deleteById is idempotent for absent rows. existsById returns bool without materializing an entity.

A versioned update predicates on both ID and previous version, increments the version exactly once and reports conflict when affected rows are zero. No update performs a hidden unbounded SELECT. Every generated query uses bound parameters and stable column order; every prepared statement cache key includes the SQL/type list. Text/bytes are copied into the caller's RequestArena. Returning an entity with arena handles does not extend the arena lifetime, so repositories cannot place that entity into a singleton cache without an owned copy.

@Query applies only to a generated repository method whose arguments/return shape are supported. Named parameters are recognized by a lexer that understands quoted strings, quoted identifiers and SQL comments; a simple regular expression is forbidden. Missing/extra parameters and repeated incompatible parameter types fail compile. Arbitrary user SQL remains backend-validated at startup/test; compile-time D type checks cannot prove schema correctness. Join projections require an explicit DTO and column aliases. Page/collection convenience APIs are outside the @nogc base contract until an arena-aware collection handle is introduced; the declared Page!T owned array is startup/worker-profile only.

Repository wiring is an explicit DI binding from CrudRepository!(T,ID) to SqlRepository!(T,ID), with a provided Pool. Direct calls are direct virtual/interface calls where a contract is used; generated concrete call sites may devirtualize. The claim is no runtime proxy generation, not that every interface dispatch disappears.

### Required implementation layout

- source/flint/data.d: entity UDAs and repository contracts.
- source/flint/data/schema.d: bounded entity descriptor generation.
- source/flint/data/sqlgen.d: dialect-specific SQL literals and binding plans.
- source/flint/data/mapper.d: direct typed row assignments.

## 5. Native boundary, ownership and safety

No new native library. All database calls flow through flint:sql; the package does not import libpq/sqlite3 bindings directly. Mappers consume typed row values and only expose arena handles. Generator output is split by entity into small modules; do not instantiate a single template over all application modules. SQL migrations are not discovered by repositories and remain the application's flint:migrate responsibility.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

No additional native dependency; consume only the lower-tier packages listed above.

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --profile sql --target linux-x86_64-glibc --phase build --emit-dub
```

Use --phase plan to inspect resolved commands without claiming a build. The build installs pinned archives and a verified libflint_ffi.a from implemented native shims, then writes a delimited platform-specific lflags block into affected DUB recipes. Installation receipts are cumulative. Cross-target commands replace the target with the exact central matrix target and use its SDK/toolchain. C shim source must exist at the implementation milestone; missing shims must fail the build rather than produce a fake library.

## 6. Numeric compile and size budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

| Measurement | Hard ceiling |
| --- | --- |
| Cold DMD fixture build | 1.40 s |
| Incremental DMD leaf edit | 0.60 s |
| Cold LDC fixture build | 8.40 s |
| Incremental LDC leaf edit | 4.20 s |
| Incremental linked code/data contribution | 786432 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instances per canonical fixture | 2000 |

These are engineering ceilings from scaffold/policy/packages.json, measured with the fixed runner/toolchain/workload policy. They are not measured achievements of these declarations. Also fail >10% compile-time/compiler-RSS/template growth or >5% binary growth against the approved baseline. The whole selected application includes native libraries in its cap; a smaller wrapper-only delta cannot excuse a larger deployment artifact. A changed profile is a different benchmark identity and cannot be compared as if equivalent.

## 7. Required unit, protocol, fuzz and benchmark acceptance

| Test identity | Passing condition |
| --- | --- |
| entity_negative | Missing/duplicate ID, duplicate column, pointer/class/delegate field and invalid identifier all fail compile. |
| repository_roundtrip | Insert→find→update→delete→exists exercises Text bytes, booleans, null wrapper and integer boundaries on PostgreSQL and SQLite. |
| identity_policy | id=0 returns generated nonzero ID; explicit nonzero IDs are preserved and duplicates report conflict. |
| optimistic_lock | Two writers read one version; one update succeeds, the stale update returns conflict without overwriting data. |
| query_lexer | Colons in quoted literals/comments are ignored; named repeated params bind consistently; unknown params fail compile. |
| schema_drift | Drop/rename a mapped column after generation; startup validation fails before accepting requests. |
| ownership | Result DTO Text handles fail generation checks after arena reset and cannot be cached by a raw struct copy. |
| compile_bench | Generate 1/10/100 small entity repositories and track template counts; 100 entities must stay within manifest memory/count caps. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :data --compiler=dmd
dub test :data --compiler=ldc2
python3 tools/gates.py --package data --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [D compile-time attributes](https://dlang.org/spec/attribute.html) — UDA metadata is available to compile-time descriptors.
- [PostgreSQL parameters](https://www.postgresql.org/docs/current/libpq-exec.html) — Parameterized query APIs separate data from SQL command text.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
