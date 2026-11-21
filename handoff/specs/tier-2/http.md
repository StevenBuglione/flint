# flint:http — Reactor-integrated HTTP client and declarative typed exchanges

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] Fluent request/response transport with bounded body buffering and streaming consumers.
- [ ] @HttpExchange, @GetExchange/@PostExchange and @HeaderParam produce statically typed client adapters.
- [ ] HTTP/1.1 and HTTP/2, certificate and hostname verification, connection reuse and monotonic timeouts.
- [ ] Explicit cancellation, deadline propagation, content limits and per-origin concurrency bounds.
- [ ] JSON encoding/decoding delegates to flint:serde; provider-specific requests use ordinary D structs.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/http/dub.sdl inside the Flint root that declares all subpackages. Module: flint.http. Direct allowed dependencies: flint:arena, flint:reactor, flint:conc, flint:serde.

```sdl
name "http"
description "Flint http subpackage"
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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/http.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.http;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct HttpExchange
{
    string baseUrl;
}

struct GetExchange
{
    string path;
}

struct PostExchange
{
    string path;
}

struct HeaderParam
{
    string name;
}

enum HttpMethod : ubyte
{
    get,
    post,
    put,
    patch,
    delete_,
    head,
    options
}

struct Header
{
    string name;
    string value;
}

struct ClientOptions
{
    uint maxConnections = 64;
    uint maxConnectionsPerOrigin = 16;
    size_t maxResponseBytes = 8 * 1024 * 1024;
    long connectTimeoutNanos = 5_000_000_000L;
    bool followRedirects = false;
    bool verifyPeer = true;
}

struct HttpRequest
{
    HttpMethod method = HttpMethod.get;
    string url;
    Header[] headers;
    Buffer body;
}

struct HttpResponse
{
    ushort status;
    Buffer headers;
    Buffer body;
}

alias ChunkConsumer = Error delegate(scope const(ubyte)[] chunk) @safe nothrow @nogc;
struct HttpClient
{
    private ulong slot;
    private ulong generation;
    Error open(ClientOptions options);
    Result!HttpResponse send(scope const ref HttpRequest request, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Result!ushort stream(scope const ref HttpRequest request, ref scope RequestArena arena,
            ref Context context, scope ChunkConsumer consume) nothrow @nogc;
    Error close() nothrow @nogc;
}

Client bindHttpClient(Client)(ref HttpClient transport);
```

## 4. Internal architecture and observable semantics

Create one CURLM multi handle per reactor core and reuse a bounded pool of easy handles. A request progresses created → queued → connecting → sending → receiving → completed, failed or cancelled. No easy or multi handle is used concurrently from two threads. Socket and timer callbacks update reactor registrations; all curl_multi_socket_action calls run outside curl callbacks on the owner core. Completion is taken from curl_multi_info_read, never inferred from a decreasing running-handle count.

HttpRequest URL/header strings and its body handle remain live for the entire call. send and stream may suspend the pinned calling fiber but return only after completion or cancellation has been acknowledged by the transport. No caller slice is retained after return. A cancellation request removes the easy handle, waits for callback quiescence, marks its generation dead, then releases arena borrows. Response headers and buffered bodies are copied into the caller's arena; maxResponseBytes is checked before each copy. The streaming callback sees a scope byte slice valid only for that invocation and may ask to stop by returning a non-ok Error.

Limits: 64 active connections/client, 16/origin, 8 MiB buffered response, 5-second connect deadline plus the Context deadline for the entire request. The request queue capacity equals twice maxConnections. Queue exhaustion returns resourceExhausted before starting a network operation. Slow consumers apply libcurl pause/resume or stop socket reads while preserving timer progress; they do not block the entire reactor.

Redirects default off. If enabled by a future options extension, cap them at five, strip Authorization and cookies on origin changes, forbid HTTPS→HTTP downgrade and revalidate the target against application destination policy. Retry policy is external to the transport. A response body observed by the caller makes the operation nonretryable by default. Certificate verification cannot be silently disabled by a missing CA path. Configure a supplied CA bundle or the platform trust store explicitly and test both.

Generated interface clients must implement only supported annotated methods. Body and response conversion happens at the generated boundary. Unannotated interface methods, multiple bodies and ambiguous header names are compile errors. A URL template expands each path component with RFC3986 encoding; it never concatenates an unescaped user-supplied path into the authority.

### Required implementation layout

- source/flint/http.d: handles, options, exchange UDAs and public transport.
- source/flint/http/client.d: easy-handle pool and completion states.
- source/flint/http/exchange.d: generated interface adapters.
- source/flint/http/ffi/shim.d and c/http.c: non-varargs libcurl shim.

## 5. Native boundary, ownership and safety

Use libcurl multi-socket APIs with OpenSSL, HTTP and HTTPS enabled. Disable FTP, LDAP, file, gopher and other unused protocols in the minimal client build; SMTP belongs only to the mail adapter's explicit build profile. The C shim wraps variadic curl_easy_setopt/curl_multi_setopt in typed functions so D never guesses C vararg promotions. Run curl_global_init before worker/reactor threads start and curl_global_cleanup after all clients join. Set CURLOPT_NOSIGNAL=1L and use a threaded or c-ares resolver; a blocking resolver on the reactor is forbidden. The shared ABI in contracts/c/http.h is the base loop/cancellation contract; request header/body setters must be typed and checked in the C implementation. C malloc/realloc activity is recorded separately from D @nogc compliance.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

| Lock ID | Version | License selection | Link profile |
| --- | --- | --- | --- |
| curl | 8.23.0 | curl | static-runtime-library |
| nghttp2 | 1.71.0 | MIT | static-runtime-library |
| openssl | 3.5.9 | Apache-2.0 | static-runtime-library |
| zlib | 1.4 | Zlib | static-runtime-library |

Immutable commit/source IDs, artifact digests, notices and target recipes are authoritative in scaffold/policy/native-lock.json and docs/C_FFI_PINNING_MATRIX.md. A source digest check is not evidence that every target binary was built or audited.

### Flint C shim ABI

This stable Flint-facing header is compiled by the target C compiler against the selected upstream headers. Its opaque pointers are internal; the public D API exposes only checked handles.

```c
/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_HTTP_ABI_H
#define FLINT_HTTP_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_curl_loop flint_curl_loop;
typedef int (*flint_curl_data_cb)(void *user, const uint8_t *data, size_t length);
flint_curl_loop *flint_curl_new(void);
int flint_curl_start(flint_curl_loop *loop, const char *url, const char *method,
                    flint_curl_data_cb callback, void *user, uint64_t *request_id);
int flint_curl_socket(flint_curl_loop *loop, intptr_t socket, int events);
int flint_curl_timeout(flint_curl_loop *loop);
int flint_curl_cancel(flint_curl_loop *loop, uint64_t request_id);
void flint_curl_free(flint_curl_loop *loop);
#ifdef __cplusplus
}
#endif
#endif
```

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --profile http --target linux-x86_64-glibc --phase build --emit-dub
```

Use --phase plan to inspect resolved commands without claiming a build. The build installs pinned archives and a verified libflint_ffi.a from implemented native shims, then writes a delimited platform-specific lflags block into affected DUB recipes. Installation receipts are cumulative. Cross-target commands replace the target with the exact central matrix target and use its SDK/toolchain. C shim source must exist at the implementation milestone; missing shims must fail the build rather than produce a fake library.

## 6. Numeric compile and size budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

| Measurement | Hard ceiling |
| --- | --- |
| Cold DMD fixture build | 1.80 s |
| Incremental DMD leaf edit | 0.60 s |
| Cold LDC fixture build | 10.80 s |
| Incremental LDC leaf edit | 5.40 s |
| Incremental linked code/data contribution | 1048576 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instances per canonical fixture | 2000 |

These are engineering ceilings from scaffold/policy/packages.json, measured with the fixed runner/toolchain/workload policy. They are not measured achievements of these declarations. Also fail >10% compile-time/compiler-RSS/template growth or >5% binary growth against the approved baseline. The whole selected application includes native libraries in its cap; a smaller wrapper-only delta cannot excuse a larger deployment artifact. A changed profile is a different benchmark identity and cannot be compared as if equivalent.

## 7. Required unit, protocol, fuzz and benchmark acceptance

| Test identity | Passing condition |
| --- | --- |
| tls_policy | Expired, hostname-mismatched and untrusted certificates fail; configured private CA succeeds; redirects do not leak Authorization. |
| http2_multiplex | 64 logical requests share one negotiated h2 connection without cross-request header/body corruption. |
| stream_chunks | Feed every split of a two-byte UTF-8 sequence and 1..4096-byte body chunks; consumer receives exact original bytes. |
| cancel_stages | Cancel while queued, resolving, connecting, receiving and paused; one completion is delivered and no borrowed memory remains. |
| curl_thread_owner | Instrument each easy/multi call; all operations for one handle have the recorded owner thread ID. |
| body_limit | 8388608 bytes succeeds; the next byte returns resourceExhausted and stops the upstream transfer. |
| exchange_negative | Unknown parameter UDA, two body arguments and unsupported return type fail compile with method identity. |
| transport_bench | Warm reused HTTPS connections and compare 1 KiB/64 KiB streaming allocation counts; no D GC allocation on send/stream. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :http --compiler=dmd
dub test :http --compiler=ldc2
python3 tools/gates.py --package http --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [curl threading](https://curl.se/libcurl/c/threadsafe.html) — A handle cannot be used concurrently on multiple threads.
- [multi-socket action](https://curl.se/libcurl/c/curl_multi_socket_action.html) — Socket and timeout notifications drive asynchronous transfer progress.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
