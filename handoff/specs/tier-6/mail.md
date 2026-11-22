# flint:mail — Bounded SMTP and transactional-provider email delivery

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] One message abstraction for SMTP, SES, Resend and Postmark.
- [ ] Text/HTML alternatives, attachments, recipient groups and provider delivery receipts.
- [ ] TLS-required credentials, cancellation, limits and idempotency-aware retry policy.
- [ ] Message accepted by provider is distinguished from final inbox delivery.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/mail/dub.sdl inside the Flint root that declares all subpackages. Module: flint.mail. Direct allowed dependencies: flint:arena, flint:http, flint:reactor, flint:conc.

```sdl
name "mail"
description "Flint mail subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:http" version="*"
dependency "flint:reactor" version="*"
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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/mail.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.mail;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
enum MailBackend : ubyte
{
    smtp,
    ses,
    resend,
    postmark
}

struct MailAddress
{
    string address;
    string displayName;
}

struct Attachment
{
    string fileName;
    string contentType;
    Buffer content;
}

struct MailMessage
{
    MailAddress from;
    MailAddress[] to;
    MailAddress[] cc;
    MailAddress[] bcc;
    string subject;
    Buffer text;
    Buffer html;
    Attachment[] attachments;
    string idempotencyKey;
}

struct MailOptions
{
    MailBackend backend = MailBackend.smtp;
    string endpoint;
    string username;
    string password;
    bool requireTls = true;
    size_t maxMessageBytes = 10 * 1024 * 1024;
}

struct DeliveryReceipt
{
    Buffer providerId;
    bool accepted;
}

struct MailSender
{
    private ulong slot;
    private ulong generation;
    Error open(MailOptions options);
    Result!DeliveryReceipt send(scope const ref MailMessage message, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error close() nothrow @nogc;
}
```

## 4. Internal architecture and observable semantics

MailSender validates backend/endpoint once and owns a bounded delivery queue. send borrows message fields and arena content until the transport completes; attachments are streamed from owned Buffer handles without concatenating the entire MIME message into another allocation. maxMessageBytes defaults to 10 MiB including encoded MIME overhead, and recipient count is capped at 100. Reject CR/LF in addresses, display names and subject before building headers. Address parsing is a documented practical mailbox parser; it is not a claim of validating deliverability.

MIME emits CRLF, encoded UTF-8 headers, multipart/alternative for text+HTML and multipart/mixed when attachments exist. Boundaries come from the secure-random service and are checked against emitted payload content or generated long enough for a tested collision policy. Base64 wraps at 76 characters; dot-stuff only SMTP DATA transport, not HTTP JSON. BCC participates in envelope recipients and must not appear in delivered headers. Attachment filenames remove path separators/control characters and use standards-compatible encoding.

SMTP runs a pinned OpenSSL-protected state machine on the reactor: greeting → EHLO → required STARTTLS → TLS handshake → EHLO again → AUTH → envelope → DATA → final reply → QUIT/reuse. Never send AUTH before verified TLS unless an explicit local-test policy selects a loopback-only fixture. EHLO capabilities drive authentication and size limits. Per-command deadline is min(10 seconds, remaining Context). Parse multiline replies with consistent status codes; unexpected 2xx/3xx ordering is an error.

SES/Resend/Postmark adapters build provider-specific payloads over flint:http. Credentials are configured per provider; the unified layer never treats their error/status or idempotency formats as interchangeable. Preserve a returned provider message ID. A 2xx receipt indicates acceptance, not delivery; bounce/delivery webhook verification belongs to a separate explicit application endpoint.

Default automatic retries cover transient rejection before message acceptance. Losing the connection after the final DATA bytes or provider request body is an ambiguous outcome and may duplicate mail; send returns unavailable with a stable ambiguous-delivery category rather than retrying silently. An application may retry with a supported provider idempotency key. Cancellation stops work but cannot retract mail already accepted. Shutdown drains admitted messages under a bounded deadline and reports unresolved receipts.

### Required implementation layout

- source/flint/mail.d: unified message/receipt API.
- source/flint/mail/mime.d: bounded MIME/base64/header encoder.
- source/flint/mail/smtp.d: SMTP state machine on reactor TLS.
- source/flint/mail/providers.d: distinct SES/Resend/Postmark serializers.

## 5. Native boundary, ownership and safety

SMTP TLS wraps the pinned OpenSSL shim already used by reactor/http; do not write TLS/cryptography in D. Native sockets remain in flint:reactor. SMTP framing/MIME are a narrow application protocol implementation with fixture/fuzz coverage. Provider HTTP adapters reuse flint:http. Mail does not depend on Tier 8 template: an application renders HTML into a Buffer before constructing MailMessage. The default SDK does not import a JavaMail clone or a general-purpose XML engine.

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
| header_injection | CR/LF in any address/subject/display name is rejected before opening a connection. |
| bcc_privacy | BCC recipients appear in SMTP/provider envelope only, never in MIME headers. |
| mime_vectors | UTF-8 subject, alternative bodies, zero-byte/binary attachment and boundary-shaped payload match canonical MIME fixtures. |
| smtp_tls | Missing STARTTLS, invalid certificate and downgraded capabilities fail before AUTH. |
| smtp_reply | Fragmented multiline replies, transient 4xx, permanent 5xx and wrong state codes map to exact errors. |
| ambiguous_delivery | Drop TCP after DATA or HTTP request body; no automatic duplicate send occurs and receipt is explicitly ambiguous. |
| provider_parity | Recorded accepted/rejected/rate-limited responses for SES, Resend and Postmark preserve provider IDs/categories. |
| mail_bench | Send 1/8-MiB attachments to a local SMTP sink; peak memory grows by bounded chunk size, not encoded message size. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :mail --compiler=dmd
dub test :mail --compiler=ldc2
python3 tools/gates.py --package mail --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [SMTP](https://www.rfc-editor.org/rfc/rfc5321.html) — SMTP replies and final acceptance are protocol-level states.
- [SMTP TLS](https://www.rfc-editor.org/rfc/rfc3207.html) — STARTTLS changes protocol state and requires capability renegotiation.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
