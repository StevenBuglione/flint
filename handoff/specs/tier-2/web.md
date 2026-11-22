# flint:web — Compile-time REST server and bounded HTTP transport

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] Spring-style @RestController, @RequestMapping, @Get/@Post/@Put/@Delete, typed @PathVariable/@QueryParam/@RequestBody and @ControllerAdvice.
- [ ] Compile-time route collisions, unsupported handler signatures and ambiguous parameter binding are compiler errors, with controller/method names.
- [ ] HTTP/1.1 keep-alive, content-length and chunked request framing through llhttp; HTTP/2 multiplexing and HPACK through nghttp2.
- [ ] Header- or path-based API versioning is explicit via @ApiVersion; a deployment chooses one policy and freezes it in the generated route table.
- [ ] @Valid invokes flint:validate before a controller; error-to-status mapping follows the table below; request IDs propagate through explicit RequestContext.
- [ ] Hot controllers are @safe nothrow @nogc. @WorkerController is the opt-in full-D profile for GC-allocating business code and uses a bounded worker pool.
- [ ] No runtime classpath scanning, expression-language evaluation, dynamic proxies, or generation of HTTP/2 frame parsers in D.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/web/dub.sdl inside the Flint root that declares all subpackages. Module: flint.web. Direct allowed dependencies: flint:arena, flint:reactor, flint:conc, flint:di, flint:serde, flint:validate, flint:log.

```sdl
name "web"
description "Flint web subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:reactor" version="*"
dependency "flint:conc" version="*"
dependency "flint:di" version="*"
dependency "flint:serde" version="*"
dependency "flint:validate" version="*"
dependency "flint:log" version="*"

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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/web.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.web;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct RestController
{
    string path;
}

struct RequestMapping
{
    string path;
}

struct Get
{
    string path;
}

struct Post
{
    string path;
}

struct Put
{
    string path;
}

struct Delete
{
    string path;
}

struct PathVariable
{
    string name;
}

struct QueryParam
{
    string name;
    bool required = false;
}

struct RequestBody
{
}

struct ControllerAdvice
{
}

struct ApiVersion
{
    uint major;
}

struct WorkerController
{
}

enum Method : ubyte
{
    get,
    post,
    put,
    patch,
    delete_,
    head,
    options
}

struct ServerOptions
{
    string address = "127.0.0.1";
    ushort port = 8080;
    uint cores = 1;
    uint maxConnectionsPerCore = 4096;
    uint maxStreamsPerConnection = 100;
    size_t maxHeaderBytes = 16384;
    size_t maxBodyBytes = 1048576;
    size_t writeQueueBytes = 262144;
    long headerTimeoutNanos = 5_000_000_000L;
    long idleTimeoutNanos = 30_000_000_000L;
    bool http2 = true;
}

struct RequestContext
{
    RequestArena arena;
    Context cancellation;
    ulong requestId;
}

struct Request
{
    private ulong slot;
    private ulong generation;
    Method method() const nothrow @nogc;
    Result!Buffer path() const nothrow @nogc;
    Result!Buffer header(scope const(char)[] name) const nothrow @nogc;
    Result!Buffer body() const nothrow @nogc;
}

struct Response
{
    ushort status = 200;
    string contentType = "application/json";
    Buffer body;
}

alias Handler = Result!Response delegate(ref Request request, ref RequestContext context) @safe nothrow @nogc;
struct Server
{
    private ulong slot;
    private ulong generation;
    Error start(ServerOptions options);
    Error route(Method method, string path, Handler handler);
    Error poll(ref Context context) nothrow @nogc;
    Error shutdown(long deadlineNanos) nothrow @nogc;
}

Error registerController(C)(ref Server server, ref C controller);
int runApplication(App)(ref App app, ServerOptions options = ServerOptions.init);
```

## 4. Internal architecture and observable semantics

The owning reactor core creates one connection state machine: accepted → TLS handshake (if configured) → protocol negotiated → reading headers → reading body → handler → queued write → keep-alive, or draining → closed. TLS uses the pinned OpenSSL shim. HTTP/2 creates independent stream records under that connection owner. A connection and each stream carry a monotonically increasing generation; completion events with an older generation are discarded.

Every request owns a RequestContext with a noncopyable arena. Request, header and payload views are opaque generation-checked handles. No C parser callback exposes a pointer to application D. The callback appends bytes into the request arena, then records a Buffer; partial token callbacks are joined before routing. Response.body must belong to that request arena. The runtime holds the arena until all socket writes complete, all child tasks join, and every borrow ends. A handler return is not sufficient to reset it. If a response is to be cached, queued or sent to another thread, copy it into that subsystem's owned storage first.

The radix router is generated once from an explicit controller tuple. Order is literal segment before named segment, with a final catch-all allowed only as the last segment. /a and /a/ are distinct by default. The decoder rejects encoded slashes and NUL; it normalizes neither path case nor dot segments. Duplicate method+version+normalized route patterns are compile errors. A route hit executes a fixed sequence: authenticate adapter → bind → validate → invoke → serialize → error advice. DI is startup-only. Direct calls to a controller method are ordinary D calls; annotations affect only generated invocation entry points.

Limits are enforced before allocation: 16 KiB combined request headers, 64 header fields, 1 MiB nonstreamed body, 100 concurrent HTTP/2 streams, 256 KiB queued output per connection, 4,096 connections per core. A full output queue suspends only its local fiber. Exhausted connection capacity closes new accepts; exhausted request capacity produces 503 when framing permits. A 5-second header deadline and 30-second idle deadline are monotonic, independent of wall-clock jumps. RST_STREAM or connection shutdown cancels the corresponding context and waits for admitted child work.

The error translation is fixed: invalidArgument→400, permissionDenied→403 (authentication failures are explicit 401 with WWW-Authenticate), notFound→404, conflict→409, resourceExhausted→429 when a policy quota caused it and 503 when server capacity caused it, timedOut→504, unavailable→503, ioError/outOfMemory/unsupported→500. cancelled after disconnect writes no response. ControllerAdvice may replace the public error envelope, never reveal SQL, secrets or pointer values. Successful Result!T defaults to 200; @Post defaults to 201 only when a concrete returned entity was created. An empty successful Error return is 204.

### Required implementation layout

- source/flint/web.d: UDAs, request/response handles, bootstrap API.
- source/flint/web/router.d: typed route descriptors and radix table emission.
- source/flint/web/binding.d: parameter decoding and validation invocation.
- source/flint/web/runtime.d: per-core connection/stream state machines.
- source/flint/web/ffi/shim.d and c/web.c: llhttp/nghttp2/OpenSSL entry points only.
- tests/fixtures/http1, http2, router, cancellation: exact input/output protocol cases.

## 5. Native boundary, ownership and safety

Bind llhttp and nghttp2 through the versioned contracts/c/web.h ABI. Compile the C shim against the pinned headers; do not copy llhttp_t or nghttp2_session layouts into D. nghttp2 handles parsing, HPACK and flow-control bookkeeping; Flint supplies I/O and enforces per-connection ownership. Do not call nghttp2 receive/send entry points recursively from its callbacks. TLS ALPN selects h2 or http/1.1; cleartext h2 prior-knowledge is an explicit test configuration, not guessed from arbitrary requests. C callbacks are extern(C) nothrow @nogc functions using numeric connection tokens. They neither throw nor capture a D delegate in unregistered C memory. Compression is a caller-injected body transform; web cannot import Tier 8 codec. HTML handlers invoke Tier 8 templates in application code, not inside web.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

| Lock ID | Version | License selection | Link profile |
| --- | --- | --- | --- |
| llhttp | 9.4.4 | MIT | static-runtime-library |
| nghttp2 | 1.71.0 | MIT | static-runtime-library |
| openssl | 3.5.9 | Apache-2.0 | static-runtime-library |

Immutable commit/source IDs, artifact digests, notices and target recipes are authoritative in scaffold/policy/native-lock.json and docs/C_FFI_PINNING_MATRIX.md. A source digest check is not evidence that every target binary was built or audited.

### Flint C shim ABI

This stable Flint-facing header is compiled by the target C compiler against the selected upstream headers. Its opaque pointers are internal; the public D API exposes only checked handles.

```c
/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_WEB_ABI_H
#define FLINT_WEB_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_http1_parser flint_http1_parser;
typedef struct flint_h2_session flint_h2_session;
typedef int (*flint_http_event_cb)(void *user, uint32_t event,
                                 const uint8_t *bytes, size_t length);
flint_http1_parser *flint_http1_new(flint_http_event_cb callback, void *user);
int flint_http1_feed(flint_http1_parser *parser, const uint8_t *data, size_t length);
void flint_http1_free(flint_http1_parser *parser);
flint_h2_session *flint_h2_new(uint32_t max_streams, flint_http_event_cb callback,
                             void *user);
int flint_h2_feed(flint_h2_session *session, const uint8_t *data, size_t length);
int flint_h2_send(flint_h2_session *session, uint8_t *output, size_t capacity,
                 size_t *written);
void flint_h2_free(flint_h2_session *session);
#ifdef __cplusplus
}
#endif
#endif
```

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --profile rest --target linux-x86_64-glibc --phase build --emit-dub
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
| route_compile_fail | Two @Get patterns with identical literal/parameter structure fail compilation and name both handlers. |
| binding_limits | Boundary values for signed/unsigned IDs pass; overflow, invalid percent escapes, missing required queries, duplicate scalar queries return 400. |
| http1_smuggling | Conflicting Content-Length values, Transfer-Encoding plus Content-Length, invalid header bytes, and unsupported transfer coding are rejected and connection closed. |
| http2_conformance | h2spec runs against the server; SETTINGS, HPACK limits, GOAWAY, window updates, RST_STREAM, fragmented headers and interleaving are covered. |
| slow_receiver | Stop reading after headers; output queue never exceeds 262144 bytes plus one protocol frame, and unrelated connections progress. |
| arena_lifetime | Delay kernel completion after handler return; arena generation remains unchanged until completion. Late completions after cancel cannot read reset memory. |
| request_shutdown | Cancel 1024 admitted requests during shutdown; every child joins, every connection closes, and no callback runs after teardown. |
| json_validation | Missing/blank @NotBlank Text fields produce deterministic field paths; validation does not write a partial successful response. |
| hot_path | After startup/warm-up, one million 128-byte JSON replies produce zero D GC allocation calls/collections and zero leaked arena generations. |
| head_to_head | Run identical plaintext 128-byte JSON workloads with 1, 8 and 64 keep-alive connections against the Go reference; use the global nine-run statistical gate. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :web --compiler=dmd
dub test :web --compiler=ldc2
python3 tools/gates.py --package web --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [nghttp2 programmer guide](https://nghttp2.org/documentation/programmers-guide.html) — nghttp2 is I/O-agnostic and a session has one owner at a time.
- [D parameter attributes](https://dlang.org/spec/function.html) — Function parameters can carry UDAs; scope/return are compiler-checked attributes, not ownership magic.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
