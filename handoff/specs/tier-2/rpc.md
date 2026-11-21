# flint:rpc — WebSocket, SSE and gRPC transport with generated Protobuf codecs

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] @WebSocket/@Sse handler registration and explicit stream ownership.
- [ ] Protobuf-generated typed messages, unary/client-streaming/server-streaming/bidirectional gRPC.
- [ ] Deadlines, cancellation, trailers/status, per-stream flow control and message-size limits.
- [ ] No handwritten HTTP/2 frame parser and no C++ gRPC runtime in the default binary.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/rpc/dub.sdl inside the Flint root that declares all subpackages. Module: flint.rpc. Direct allowed dependencies: flint:arena, flint:reactor, flint:conc, flint:web, flint:http, flint:serde.

```sdl
name "rpc"
description "Flint rpc subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:reactor" version="*"
dependency "flint:conc" version="*"
dependency "flint:web" version="*"
dependency "flint:http" version="*"
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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/rpc.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.rpc;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct WebSocket
{
    string path;
}

struct Sse
{
    string path;
}

struct GrpcService
{
    string serviceName;
}

enum RpcCode : uint
{
    ok = 0,
    cancelled = 1,
    unknown = 2,
    invalidArgument = 3,
    deadlineExceeded = 4,
    notFound = 5,
    alreadyExists = 6,
    permissionDenied = 7,
    resourceExhausted = 8,
    failedPrecondition = 9,
    aborted = 10,
    outOfRange = 11,
    unimplemented = 12,
    internal = 13,
    unavailable = 14,
    dataLoss = 15,
    unauthenticated = 16
}

struct RpcStatus
{
    RpcCode code;
    Buffer message;
}

struct StreamLimits
{
    size_t maxMessageBytes = 4 * 1024 * 1024;
    uint queuedMessages = 16;
    size_t queuedBytes = 1024 * 1024;
}

struct RpcStream
{
    private ulong slot;
    private ulong generation;
    Error send(Buffer message, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Result!Buffer receive(ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error finish(RpcStatus status) nothrow @nogc;
    Error cancel() nothrow @nogc;
}

struct WebSocketPeer
{
    private ulong slot;
    private ulong generation;
    Error text(Buffer text, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error binary(Buffer payload, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error close(ushort code = 1000, string reason = "") nothrow @nogc;
}

struct SseEvent
{
    string event;
    string id;
    Buffer data;
    uint retryMillis;
}

Error sendEvent(ref RpcStream stream, scope const ref SseEvent event, ref scope RequestArena arena, ref Context context) nothrow @nogc;
Result!Buffer encodeProto(T)(scope const ref T message, ref scope RequestArena arena) nothrow @nogc;
Error decodeProto(T)(scope const(ubyte)[] wire, ref T message, ref scope RequestArena arena) nothrow @nogc;
```

## 4. Internal architecture and observable semantics

gRPC is layered above the existing HTTP/2 session and validates :method=POST, a /package.Service/Method path, content-type and TE trailers. Messages use the gRPC compression flag and four-byte big-endian length prefix. Enforce maxMessageBytes=4 MiB before allocating, reject unsupported compression, and produce final grpc-status/grpc-message trailers exactly once. A clean TCP close without a valid terminal status is unavailable, never success. Decode grpc-timeout into the smaller of transport and caller deadlines, with saturating arithmetic.

RpcStream is a generation-checked stream token. A send copies or pins its payload until the corresponding frame bytes are accepted; returning from send means transport ownership is resolved, not remote application execution. The queue is bounded by both 16 messages and 1 MiB total; oversized but permitted messages require chunked framing without queuing the entire item twice. A blocked writer yields its fiber while readers continue. Cancellation closes the stream and joins child work; already committed business side effects are not rolled back automatically.

WebSocket v13 upgrade checks method, Upgrade/Connection tokens, version and Sec-WebSocket-Key. The accept-key hash uses the existing OpenSSL backend. Client-to-server masking is required; RSV bits are zero unless an explicitly enabled extension owns them. Cap aggregate fragmented message length at 4 MiB. Validate UTF-8 across fragmented text frames, enforce control-frame limits, answer ping/pong, and complete the close handshake with a 5-second bound. Extension negotiation defaults empty.

SSE has a separate encoder/parser with incremental UTF-8 handling, LF/CRLF, comments, multiple data lines, event/id/retry fields and configurable heartbeat comments. Newlines in data are encoded as separate data lines; CR/LF in event/id are rejected. Server disconnects terminate its Context. Reconnection/resume is an application contract; no generic message is declared exactly-once.

Protobuf schema compilation is an offline build step. protoc descriptors feed a pinned protobuf-c generator and a small Flint adapter generator producing D DTO mappings plus C codecs. Generated artifacts are committed with input hash and generator versions; CI regenerates and diffs them. Supported initial schema is proto3 scalar/enums/nested messages/repeated/map/oneof; reject groups, required proto2 fields and unsupported editions explicitly. Unknown fields are preserved only when the chosen protobuf-c descriptor model supports it; never assert bit-for-bit reserialization without a test.

### Required implementation layout

- source/flint/rpc.d: RPC/WS/SSE API.
- source/flint/rpc/grpc.d: framing/status/deadline state machine above web HTTP/2.
- source/flint/rpc/websocket.d and sse.d: bounded protocol adapters.
- source/flint/rpc/ffi/protobuf.d and c/rpc.c: generated-code adapters.
- tools/protoc-gen-flint: descriptor-driven D mapping generator; tests/proto include golden schemas.

## 5. Native boundary, ownership and safety

Use contracts/c/rpc.h over the pinned protobuf-c C codec; protoc and protoc-c are build tools, not target runtime dependencies. nghttp2 remains owned by flint:web. Generated C unpacking receives an arena allocator whose allocations are bounded and pointer-free from the GC's perspective; wrappers convert all C-owned data into D Text/Buffer handles. The D business API never exposes a ProtobufCMessage pointer. C codecs and generated adapters are ASan/fuzz targets. Compression is explicitly injected; Tier 2 rpc cannot import Tier 8 codec.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

| Lock ID | Version | License selection | Link profile |
| --- | --- | --- | --- |
| nghttp2 | 1.71.0 | MIT | static-runtime-library |
| protobuf-c | 1.5.2 | BSD-2-Clause | static-runtime-library |
| protoc | 30.2 | BSD-3-Clause | host-tool-only |

Immutable commit/source IDs, artifact digests, notices and target recipes are authoritative in scaffold/policy/native-lock.json and docs/C_FFI_PINNING_MATRIX.md. A source digest check is not evidence that every target binary was built or audited.

### Flint C shim ABI

This stable Flint-facing header is compiled by the target C compiler against the selected upstream headers. Its opaque pointers are internal; the public D API exposes only checked handles.

```c
/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_RPC_ABI_H
#define FLINT_RPC_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_proto_descriptor flint_proto_descriptor;
int flint_proto_pack(const flint_proto_descriptor *descriptor, const void *message,
                     uint8_t *output, size_t capacity, size_t *written);
int flint_proto_unpack(const flint_proto_descriptor *descriptor,
                       const uint8_t *input, size_t input_length,
                       void *arena_context, void **message);
void flint_proto_release(const flint_proto_descriptor *descriptor,
                        void *message, void *arena_context);
#ifdef __cplusplus
}
#endif
#endif
```

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --library protobuf-c --with-codegen --target linux-x86_64-glibc --phase build --emit-dub
```

Use --phase plan to inspect resolved commands without claiming a build. The build installs pinned archives and a verified libflint_ffi.a from implemented native shims, then writes a delimited platform-specific lflags block into affected DUB recipes. Installation receipts are cumulative. Cross-target commands replace the target with the exact central matrix target and use its SDK/toolchain. C shim source must exist at the implementation milestone; missing shims must fail the build rather than produce a fake library.

This prepares the C codec plus host generators; prepare --profile rest as well when the application enables the gRPC/HTTP2 transport. Runtime links protobuf-c only; protoc/protoc-gen-c run on the build host.

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
| grpc_interop | Official grpc-go client/server fixtures exercise all four RPC shapes, metadata, deadlines, cancellation and trailers. |
| grpc_wire_errors | Truncated prefix/body, unsupported flag, >4 MiB length and missing terminal status return documented errors without leaks. |
| grpc_flow | Both peers write large streams while consuming; no mutual write deadlock and queued bytes remain within configured bounds. |
| protobuf_roundtrip | Scalar boundary, unknown enum, repeated/map/oneof/nested and malformed-varint fixtures match generated C codec behavior. |
| websocket_autobahn | Run applicable Autobahn server/client cases; fragmented UTF-8, masking, control frames and close races must pass. |
| sse_boundaries | Split every field delimiter/UTF-8 code unit across input chunks; canonical events and heartbeats are emitted exactly once. |
| stream_teardown | Cancel before first byte, mid-message and after trailers; once-only completion and no post-reset arena use. |
| rpc_bench | Measure unary 128-byte and streaming 64-KiB messages with 1/64 streams; record C and D allocations separately. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :rpc --compiler=dmd
dub test :rpc --compiler=ldc2
python3 tools/gates.py --package rpc --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [gRPC concepts](https://grpc.io/docs/what-is-grpc/core-concepts/) — gRPC supports four call shapes and independent local completion outcomes.
- [gRPC flow control](https://grpc.io/docs/guides/flow-control/) — Bounded streams must keep readers making progress to avoid mutual writer stalls.
- [protobuf-c](https://github.com/protobuf-c/protobuf-c) — Generated C codec supplies the Protobuf runtime boundary.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
