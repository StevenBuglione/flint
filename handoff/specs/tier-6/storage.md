# flint:storage — S3-compatible streaming object storage and SigV4 signing

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] S3/R2/MinIO get/head/delete, multipart upload and presigned GET.
- [ ] SigV4 with temporary credentials, explicit endpoint/region/path-style settings and TLS verification.
- [ ] Bounded part concurrency and streaming body ownership, cancellation and abort.
- [ ] No promise that every S3-compatible provider implements every AWS extension.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/storage/dub.sdl inside the Flint root that declares all subpackages. Module: flint.storage. Direct allowed dependencies: flint:arena, flint:http, flint:security, flint:conc.

```sdl
name "storage"
description "Flint storage subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:http" version="*"
dependency "flint:security" version="*"
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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/storage.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.storage;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;
import flint.http : ChunkConsumer;

@safe:
struct Credentials
{
    string accessKeyId;
    string secretAccessKey;
    string sessionToken;
    long expiresAtUnixSeconds;
}

alias CredentialProvider = Result!Credentials delegate(ref Context context) @safe nothrow;
struct StorageOptions
{
    string endpoint;
    string region = "us-east-1";
    bool pathStyle = false;
    size_t partBytes = 8 * 1024 * 1024;
    uint concurrentParts = 4;
    bool verifyPeer = true;
}

struct ObjectInfo
{
    ulong size;
    Buffer etag;
    Buffer versionId;
}

struct Upload
{
    private ulong slot;
    private ulong generation;
    Error write(scope const(ubyte)[] chunk, ref Context context) nothrow @nogc;
    Result!ObjectInfo complete(ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error abort(ref Context context) nothrow @nogc;
}

struct ObjectStorage
{
    private ulong slot;
    private ulong generation;
    Error open(StorageOptions options, CredentialProvider credentials);
    Result!ObjectInfo head(string bucket, string key, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error get(string bucket, string key, scope ChunkConsumer consume, ref Context context) nothrow @nogc;
    Result!Upload beginUpload(string bucket, string key, string contentType, ref Context context) nothrow @nogc;
    Error remove(string bucket, string key, ref Context context) nothrow @nogc;
    Result!Buffer presignGet(string bucket, string key, uint expiresSeconds, long nowUnixSeconds,
            ref scope RequestArena arena) nothrow @nogc;
    Error close() nothrow @nogc;
}
```

## 4. Internal architecture and observable semantics

ObjectStorage owns an HTTP client and a startup-configured credential snapshot/provider. Credential refresh runs on a management worker before expiry; request @nogc paths read immutable current credentials and return unavailable if none is valid. The CredentialProvider callback is not @nogc, so it is never called directly from a marked request path. Signing uses OpenSSL-backed HMAC/SHA primitives; canonical method, URI, sorted query, normalized header set, signed-header list and payload hash are constructed in bounded scratch.

Preserve S3 object-key semantics. Do not normalize repeated slashes or dot segments as if the key were a filesystem path. Percent-encode bytes according to AWS signing rules and avoid double-encoding an already encoded canonical query. Credentials and signatures are never logged. Redirects are disabled by default because a changed authority/region requires resigning and can expose credentials; an explicit redirect handler revalidates the destination and regenerates the signature.

Multipart Upload allocates at most concurrentParts=4 buffers of partBytes=8 MiB, plus metadata. beginUpload obtains the upload ID. write streams caller chunks into available owned part buffers, blocks only the local fiber on backpressure and records each part number/ETag. complete sorts and validates parts, submits completion, parses the full response body even on HTTP 200 and exposes final object identity. abort cancels pending parts, issues AbortMultipartUpload and surfaces cleanup failures so the caller can retry cleanup by upload ID. The SDK does not assert that every in-flight part disappears immediately after an abort.

Use at least 5 MiB for every nonfinal part, no more than 5 GiB per part and at most 10,000 parts; adapt part size before uploading a known-length object. A provider capability record may reduce limits. Empty objects use a single PUT with an empty checksum. Streaming aws-chunked SigV4 is an optional explicitly negotiated capability; multipart with full per-part hashing is the required portable initial implementation.

A download consumer is scope and may return an error to stop. Byte ranges validate start/end and preserve ETag/version conditions. An ETag is treated as opaque, not as an MD5 checksum. Presigned URLs expire within credentials' lifetime and at most seven days for SigV4; query authorization is redacted in logs. Public ACL changes and bucket creation are outside this API; data transfer must not silently widen access.

### Required implementation layout

- source/flint/storage.d: object/multipart contracts.
- source/flint/storage/sigv4.d: canonical request construction using C crypto.
- source/flint/storage/multipart.d: bounded upload state machine.
- source/flint/storage/xml.d: tiny bounded parser for S3 response envelopes with DTD/entities disabled.

## 5. Native boundary, ownership and safety

No new native runtime. HTTP/TLS comes from flint:http and cryptographic operations from flint:security. C crypto is used for signing; D implements protocol canonicalization only. XML processing is intentionally limited to documented S3 envelopes, depth 32 and 1 MiB maximum; reject DTD/external entity constructs rather than implementing a general XML engine. Credential provider integrations (environment/explicit/metadata/assume-role) are separate adapters with bounded metadata timeouts; no ambient fallback is allowed after explicit credentials fail.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

| Lock ID | Version | License selection | Link profile |
| --- | --- | --- | --- |
| openssl | 3.5.9 | Apache-2.0 | static-runtime-library |

Immutable commit/source IDs, artifact digests, notices and target recipes are authoritative in scaffold/policy/native-lock.json and docs/C_FFI_PINNING_MATRIX.md. A source digest check is not evidence that every target binary was built or audited.

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
| Cold DMD fixture build | 1.50 s |
| Incremental DMD leaf edit | 0.60 s |
| Cold LDC fixture build | 9.00 s |
| Incremental LDC leaf edit | 4.50 s |
| Incremental linked code/data contribution | 1048576 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instances per canonical fixture | 2000 |

These are engineering ceilings from scaffold/policy/packages.json, measured with the fixed runner/toolchain/workload policy. They are not measured achievements of these declarations. Also fail >10% compile-time/compiler-RSS/template growth or >5% binary growth against the approved baseline. The whole selected application includes native libraries in its cap; a smaller wrapper-only delta cannot excuse a larger deployment artifact. A changed profile is a different benchmark identity and cannot be compared as if equivalent.

## 7. Required unit, protocol, fuzz and benchmark acceptance

| Test identity | Passing condition |
| --- | --- |
| sigv4_vectors | AWS canonical-request/signature examples match byte-for-byte, including empty payload and temporary session token. |
| key_encoding | Space, plus, percent, UTF-8, repeated slash and dot segments round-trip identically on MinIO and recorded AWS/R2 fixtures. |
| multipart_limits | 5 MiB nonfinal boundary, small final part, 10,000-part cap and invalid part order behave deterministically. |
| completion_error | HTTP 200 with an error XML body is a failure; malformed XML is never treated as success. |
| abort_race | Cancel while four parts are in flight; no request-arena pointer survives and orphan upload ID is reported if cleanup fails. |
| credential_rotation | Refresh credentials concurrently; every signature uses one complete snapshot and no expired session is signed. |
| presign_bounds | Reject >604800 seconds and expiry beyond credential lifetime; logged URL omits authentication query fields. |
| storage_bench | Upload/download 1 GiB using four 8-MiB buffers; live payload memory remains under 40 MiB plus fixed transport buffers. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :storage --compiler=dmd
dub test :storage --compiler=ldc2
python3 tools/gates.py --package storage --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [AWS SigV4 authorization](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-auth-using-authorization-header.html) — Signing mode and payload checksum semantics are explicit protocol choices.
- [S3 multipart limits](https://docs.aws.amazon.com/AmazonS3/latest/userguide/qfacts.html) — Multipart part size and count constraints are upstream-defined.
- [SigV4 streaming](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-streaming.html) — Chunk signatures are chained; ordinary chunked HTTP is not automatically SigV4 streaming.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
