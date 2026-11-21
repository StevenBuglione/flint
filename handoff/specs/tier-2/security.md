# flint:security — Authentication, authorization, CORS and cryptographic service boundary

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] JWT and OAuth/OIDC bearer validation, @RolesAllowed and registered @PreAuthorize policies.
- [ ] Composable authentication verdicts without a dependency on flint:web or a runtime expression interpreter.
- [ ] Explicit CORS policy with allowlisted origins/methods/headers and credentials restrictions.
- [ ] Argon2id password hashing/verification through libsodium and SHA-256/HMAC/JWS verification through OpenSSL.
- [ ] Fail-closed startup validation and bounded JWKS refresh; no handwritten cryptographic primitives.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/security/dub.sdl inside the Flint root that declares all subpackages. Module: flint.security. Direct allowed dependencies: flint:arena, flint:http, flint:serde, flint:conc.

```sdl
name "security"
description "Flint security subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:http" version="*"
dependency "flint:serde" version="*"
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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/security.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.security;
import flint.arena : Buffer, Error, RequestArena, Result, Text;
import flint.conc : Context;

@safe:
struct RolesAllowed
{
    string[] roles;
}

struct PreAuthorize
{
    string policy;
}

enum JwtAlgorithm : ubyte
{
    rs256,
    es256,
    eddsa
}

struct JwtPolicy
{
    string issuer;
    string audience;
    JwtAlgorithm[] algorithms;
    long clockSkewSeconds = 30;
    uint maxTokenBytes = 16384;
    bool requireExpiry = true;
}

struct Principal
{
    Text subject;
    Buffer roles;
    long expiresAtUnixSeconds;
}

struct JwtVerifier
{
    private ulong slot;
    private ulong generation;
    Error open(scope const ref JwtPolicy policy, string jwksUrl);
    Result!Principal verify(scope const(char)[] bearer, long nowUnixSeconds, ref scope RequestArena arena) nothrow @nogc;
    Error refresh(ref Context context) nothrow @nogc;
    Error close() nothrow @nogc;
}

struct CorsPolicy
{
    string[] origins;
    string[] methods;
    string[] headers;
    bool credentials = false;
    uint maxAgeSeconds = 600;
}

bool originAllowed(scope const ref CorsPolicy policy, scope const(char)[] origin) nothrow @nogc;
bool hasRole(scope const ref Principal principal, scope const(char)[] role, ref scope RequestArena arena) nothrow @nogc;
Error sha256(scope const(ubyte)[] input, ref ubyte[32] output) nothrow @nogc;
Error hmacSha256(scope const(ubyte)[] key, scope const(ubyte)[] input, ref ubyte[32] output) nothrow @nogc;
Result!Buffer hashPassword(scope const(ubyte)[] password, ref scope RequestArena arena, ref Context context) nothrow @nogc;
Result!bool verifyPassword(scope const(ubyte)[] password, scope const(char)[] encoded, ref Context context) nothrow @nogc;
```

## 4. Internal architecture and observable semantics

Security exports Principal and policy operations, not an HTTP middleware type. Application composition maps verifier results into web's auth stage, preserving the package DAG and allowing storage signing to use the crypto boundary without importing a web server. @PreAuthorize(policy) selects a compile-time registered policy function with a Principal/context signature. The policy string is an identifier, never an expression language program. Unknown policies and invalid role metadata fail compile.

JwtVerifier.open snapshots and validates issuer, audience, algorithm allowlist and HTTPS JWKS URL. It refuses an empty issuer/audience/algorithm list. The default algorithms exposed are RS256, ES256 and EdDSA; RSA keys must meet the chosen minimum of 2048 bits. The key type and curve must match the selected algorithm; alg=none, symmetric-asymmetric confusion and unsupported crit headers are rejected. Check signature, exact issuer, audience membership, exp (required), nbf when present, and configured 30-second skew. Reject duplicate security-critical JSON keys, noncanonical base64url padding, >16 KiB tokens and >64 KiB decoded claims. Error responses disclose only a stable category.

JWKS is a startup-owned immutable snapshot replaced atomically after validation. A verify call never downloads keys synchronously. Unknown kid returns permissionDenied and requests a single-flight background refresh; refresh is limited to once per issuer per 30 seconds, capped at 64 keys and 1 MiB response. Key data cannot be fetched from a token-supplied jku/x5u URL. Existing keys may be used through their configured cache lifetime; expired snapshots fail closed. Key-retirement policy is explicit and testable, not an unbounded stale cache.

Principal subject and roles are copied into request arena handles. A bearer token, password or secret key is never logged. Crypto scratch and private-key memory use library-provided secure erasure. Password hashing runs in a bounded worker queue (default two jobs per CPU, hard cap 16 concurrent jobs) because Argon2 memory/CPU work must not block reactor cores. Start with libsodium's interactive limits and test the deployment's latency budget; never silently lower work factors under load.

CORS wildcard origins cannot combine with credentials. Exact origin comparison uses parsed scheme/host/port; it does not accept suffix matches. Preflight responses use Vary: Origin and the requested headers must be a subset of the policy. CORS grants browser access; it does not authenticate a request.

### Required implementation layout

- source/flint/security.d: public policies and crypto service API.
- source/flint/security/jwt.d: strict JWS/claims and JWKS snapshot policy.
- source/flint/security/authorization.d: compile-time policy registry.
- source/flint/security/ffi/crypto.d and c/security.c: OpenSSL/libsodium only.

## 5. Native boundary, ownership and safety

Use contracts/c/security.h. OpenSSL EVP/EVP_MAC performs hashing, HMAC and signature verification. Validate DER/key type in C using pinned OpenSSL APIs, convert backend errors into bounded stable categories, and drain the OpenSSL error queue at the call boundary. Password functions wrap sodium_init, crypto_pwhash_str_alg with Argon2id and crypto_pwhash_str_verify; store the full encoded verifier. Do not implement RSA padding, ECDSA arithmetic or random-number generation in D. Crypto library initialization occurs before concurrent use. The calling D wrapper's @trusted body validates slices/capacity, pins synchronous buffers, makes one C call and returns; each wrapper has a SAFETY rationale and negative-length/ASan tests.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

| Lock ID | Version | License selection | Link profile |
| --- | --- | --- | --- |
| libsodium | 1.0.22 | ISC | static-runtime-library |
| openssl | 3.5.9 | Apache-2.0 | static-runtime-library |

Immutable commit/source IDs, artifact digests, notices and target recipes are authoritative in scaffold/policy/native-lock.json and docs/C_FFI_PINNING_MATRIX.md. A source digest check is not evidence that every target binary was built or audited.

### Flint C shim ABI

This stable Flint-facing header is compiled by the target C compiler against the selected upstream headers. Its opaque pointers are internal; the public D API exposes only checked handles.

```c
/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_SECURITY_ABI_H
#define FLINT_SECURITY_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int flint_sha256(const uint8_t *input, size_t input_length, uint8_t output[32]);
int flint_hmac_sha256(const uint8_t *key, size_t key_length,
                      const uint8_t *input, size_t input_length, uint8_t output[32]);
int flint_jws_verify(int algorithm, const uint8_t *key_der, size_t key_length,
                     const uint8_t *input, size_t input_length,
                     const uint8_t *signature, size_t signature_length);
int flint_password_hash(const uint8_t *password, size_t password_length,
                         char *output, size_t output_capacity,
                         uint64_t opslimit, size_t memlimit);
int flint_password_verify(const char *encoded, const uint8_t *password,
                           size_t password_length);
#ifdef __cplusplus
}
#endif
#endif
```

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --library openssl --library libsodium --target linux-x86_64-glibc --phase build --emit-dub
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
| jwt_confusion | alg=none, RS256 token with HMAC key, wrong curve, unknown crit and duplicate alg/iss/aud claims all fail. |
| jwt_claims | Exact exp/nbf skew boundaries, wrong audience, wrong issuer and missing expiry are covered with a fake clock. |
| jwks_rotation | Rotate keys while 256 requests verify; readers see whole snapshots, expired unknown keys fail and refresh is single-flight. |
| jwks_ssrf | Token-supplied jku/x5u never triggers a request; configured JWKS redirects cannot escape issuer destination policy. |
| cors_matrix | Credentialed wildcard, malicious suffix origin, null origin and disallowed requested headers fail; Vary is correct. |
| password_vectors | Correct and incorrect passwords, malformed verifier, embedded NUL and maximum configured length are tested. |
| secret_lifetime | Secure buffers are zeroed on error and cancellation; no log/test artifact includes raw passwords or bearer tokens. |
| crypto_vectors | RFC/AWS HMAC/SHA vectors and upstream signature vectors pass; signature bit flips always fail. |
| verification_bench | 10,000 cached-key RS256/ES256 verifies benchmark median/p99 and C heap counts; zero D allocations after warm-up. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :security --compiler=dmd
dub test :security --compiler=ldc2
python3 tools/gates.py --package security --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [JWT best practices](https://www.rfc-editor.org/rfc/rfc8725.html) — Algorithm, issuer and audience validation must be explicit.
- [libsodium password hashing](https://doc.libsodium.org/password_hashing/default_phf) — Use the library password verifier format and high-level functions.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
