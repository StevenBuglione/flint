# flint:cache — Bounded local/RESP3 cache and explicit cached invocations

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] Local LRU/TTL cache and Redis/Valkey RESP3 backend behind one binary-key API.
- [ ] @Cacheable/@CacheEvict metadata for generated invokers, plus explicit getOrLoad.
- [ ] Byte/entry capacity, TTL, monotonic local expiry and duplicate-load suppression.
- [ ] No implicit application consistency guarantee or unlimited key allocation.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/cache/dub.sdl inside the Flint root that declares all subpackages. Module: flint.cache. Direct allowed dependencies: flint:arena, flint:reactor, flint:conc, flint:serde.

```sdl
name "cache"
description "Flint cache subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:reactor" version="*"
dependency "flint:conc" version="*"
dependency "flint:serde" version="*"

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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/cache.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.cache;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct Cacheable
{
    string cache;
}

struct CacheEvict
{
    string cache;
    bool allEntries = false;
}

enum CacheBackend : ubyte
{
    local,
    redis
}

struct CacheOptions
{
    CacheBackend backend = CacheBackend.local;
    size_t byteCapacity = 64 * 1024 * 1024;
    uint entryCapacity = 65536;
    uint stripes = 64;
    long defaultTtlNanos = 60_000_000_000L;
    string redisUrl;
}

struct Cache
{
    private ulong slot;
    private ulong generation;
    Error open(CacheOptions options);
    Result!Buffer get(scope const(ubyte)[] key, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error put(scope const(ubyte)[] key, scope const(ubyte)[] value, long ttlNanos, ref Context context) nothrow @nogc;
    Error evict(scope const(ubyte)[] key, ref Context context) nothrow @nogc;
    Error clear(ref Context context) nothrow @nogc;
    Error close() nothrow @nogc;
}

alias CacheLoader = Result!Buffer delegate(ref scope RequestArena arena, ref Context context) @safe nothrow @nogc;
Result!Buffer getOrLoad(ref Cache cache, scope const(ubyte)[] key, long ttlNanos,
        ref scope RequestArena arena, ref Context context, scope CacheLoader load) nothrow @nogc;
```

## 4. Internal architecture and observable semantics

Local storage is divided into 64 stripes; each owns a hash table, intrusive LRU list and preallocated metadata slots. Capacity is bounded by both 65,536 entries and 64 MiB payload bytes. A stripe operation holds its lock only while touching its own table/list. Copy bytes out before invoking a loader or network function; never call user code under a cache lock. Values are owned copies, never request-arena slices. get copies a hit into the caller arena and returns notFound for a miss/expired entry. A key may contain NUL; its length participates in hashing/equality.

A local expiry is insertion monotonic time plus TTL with checked saturation. TTL=0 means immediate expiry/no storage; negative TTL is invalidArgument; the initial API has no unbounded forever value. Lazy deletion on read is supplemented by a 64-entry-per-tick sweep. LRU eviction chooses only unborrowed owned entries; pinned/copying entries count against capacity. Oversized values return resourceExhausted without evicting the entire cache to fit a value that can never fit.

getOrLoad coalesces concurrent loads by key, with at most 1,024 in-flight keys. The first admitted call runs its loader outside the lock, then stores a successful result as owned bytes. Other waiters retain independent cancellation/deadlines. Cancellation of one waiter does not cancel a load needed by other waiters; when all cancel, the load context cancels. Loader failure is not cached by default. A per-key generation prevents a late loader from repopulating a key after an explicit evict.

The remote backend uses hiredis async RESP3 parsing and reactor socket integration. Run HELLO 3, authenticate with supplied credentials and require TLS for nonlocal endpoints by default. Replies have a 16 MiB aggregate limit, nesting depth 32 and 1,024 pending requests/connection. PUSH messages are routed separately from request replies. Unknown response types fail the affected connection safely. Initial scope is one configured primary endpoint; Redis Cluster MOVED/ASK is reported as unsupported unless the explicit cluster adapter is implemented and tested. Do not falsely advertise cluster support.

@Cacheable and @CacheEvict wrap registered DI calls only. The key descriptor is explicit and deterministic; serialize parameter values with the canonical serde profile and prefix the method/schema version. Eviction after a transaction is scheduled only after confirmed commit. Cached values do not imply database transaction isolation or distributed exactly-once behavior.

### Required implementation layout

- source/flint/cache.d: cache options, binary-key operations and UDAs.
- source/flint/cache/local.d: striped owned LRU+TTL store.
- source/flint/cache/remote.d: RESP3 request queue and push dispatcher.
- source/flint/cache/ffi/hiredis.d and c/cache.c: async hiredis adapter.

## 5. Native boundary, ownership and safety

Use hiredis with its matching TLS support and pinned OpenSSL. contracts/c/cache.h defines opaque connection/argv-length calls; do not build commands with format strings containing untrusted bytes. Owned reply trees are freed after conversion into arena handles. C async callbacks use connection/request generation IDs. The local backend links no hiredis when built in its local-only configuration; measure both profiles separately.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

| Lock ID | Version | License selection | Link profile |
| --- | --- | --- | --- |
| hiredis | 1.5.1 | BSD-3-Clause | static-runtime-library |

Immutable commit/source IDs, artifact digests, notices and target recipes are authoritative in scaffold/policy/native-lock.json and docs/C_FFI_PINNING_MATRIX.md. A source digest check is not evidence that every target binary was built or audited.

### Flint C shim ABI

This stable Flint-facing header is compiled by the target C compiler against the selected upstream headers. Its opaque pointers are internal; the public D API exposes only checked handles.

```c
/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_CACHE_ABI_H
#define FLINT_CACHE_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_redis_connection flint_redis_connection;
flint_redis_connection *flint_redis_new(const char *host, uint16_t port, int tls);
int flint_redis_command(flint_redis_connection *connection, size_t argc,
                        const char *const *argv, const size_t *lengths,
                        uint64_t *request_id);
int flint_redis_readable(flint_redis_connection *connection);
int flint_redis_writable(flint_redis_connection *connection);
void flint_redis_free(flint_redis_connection *connection);
#ifdef __cplusplus
}
#endif
#endif
```

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --library hiredis --target linux-x86_64-glibc --phase build --emit-dub
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
| binary_keys | Empty and NUL-containing keys/values preserve lengths; independent byte keys never alias. |
| capacity_bound | Insert beyond both entry/byte caps; memory stays bounded and LRU eviction selects the expected stripe victim. |
| ttl_clock | Use fake monotonic time at exact TTL boundary; wall-clock changes do not extend local life. |
| single_flight | 100 waiters on one key invoke the loader once; cancel 99 and the remaining call still succeeds. |
| evict_loader_race | Evict while a loader is running; its stale generation cannot resurrect the entry. |
| resp3_push | Interleave PUSH with ordinary replies; requests receive the correct response IDs. |
| remote_failure | Disconnect between request and reply; pending operations fail once and no automatic mutation retry occurs. |
| cache_bench | Hit/miss/evict contention at 1/8/32 threads for 64-byte and 4-KiB values; report p99 and lock wait. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :cache --compiler=dmd
dub test :cache --compiler=ldc2
python3 tools/gates.py --package cache --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [hiredis](https://github.com/redis/hiredis) — hiredis provides async parsing and length-aware command APIs; its README is the upstream integration source.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
