# flint:ai — Provider-specific streaming LLM adapters and typed tool dispatch

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] Unified chat/event facade for OpenAI, Anthropic, Gemini and OpenRouter.
- [ ] SSE streaming, Context cancellation, typed tools and compile-time JSON Schema.
- [ ] Provider capability checks, explicit model/version strings and bounded tool loops.
- [ ] No assumption that OpenAI-compatible endpoints share every protocol/event/error shape.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/ai/dub.sdl inside the Flint root that declares all subpackages. Module: flint.ai. Direct allowed dependencies: flint:arena, flint:http, flint:serde, flint:conc, flint:validate.

```sdl
name "ai"
description "Flint ai subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:http" version="*"
dependency "flint:serde" version="*"
dependency "flint:conc" version="*"
dependency "flint:validate" version="*"

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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/ai.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.ai;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct Tool
{
    string name;
    string description;
}

enum Provider : ubyte
{
    openAI,
    anthropic,
    gemini,
    openRouter
}

enum Role : ubyte
{
    system,
    user,
    assistant,
    tool
}

enum EventKind : ubyte
{
    textDelta,
    toolDelta,
    usage,
    completed,
    failed
}

struct ChatMessage
{
    Role role;
    Buffer content;
    string toolCallId;
}

struct ChatOptions
{
    string model;
    uint maxOutputTokens = 1024;
    double temperature = 0;
    uint maxToolRounds = 8;
    size_t maxEventBytes = 1024 * 1024;
}

struct ChatEvent
{
    EventKind kind;
    Buffer text;
    string toolCallId;
    uint inputTokens;
    uint outputTokens;
}

alias EventConsumer = Error delegate(ref ChatEvent event, ref scope RequestArena arena) @safe nothrow @nogc;
struct AiOptions
{
    Provider provider;
    string baseUrl;
    string apiKey;
    string apiVersion;
    uint maxConcurrentRequests = 32;
}

struct ChatClient
{
    private ulong slot;
    private ulong generation;
    Error open(AiOptions options);
    Error stream(scope const(ChatMessage)[] messages, ChatOptions options, ref scope RequestArena arena,
            ref Context context, scope EventConsumer consume) nothrow @nogc;
    Error close() nothrow @nogc;
}

Result!Buffer jsonSchema(T)(ref scope RequestArena arena) nothrow @nogc;
Result!Buffer dispatchTool(T)(ref T tools, scope const(char)[] name, scope const(ubyte)[] jsonArguments,
        ref scope RequestArena arena, ref Context context) nothrow @nogc;
```

## 4. Internal architecture and observable semantics

Provider adapters own request and event schemas independently. The initial OpenAI adapter targets /v1/responses semantic SSE events; Anthropic targets /v1/messages with its version header; Gemini targets models/{model}:streamGenerateContent?alt=sse; OpenRouter defaults to its /api/v1/responses adapter with a separately tested Chat Completions compatibility mode only when requested. A model is always supplied by the application; the framework never silently changes it. Unsupported options fail before sending a request.

ChatClient.stream uses the common HTTP byte stream and an incremental SSE parser. Keep partial UTF-8, partial lines and multi-line data fields across callbacks; ignore comment/heartbeat lines. Cap one event at 1 MiB and total tool-call arguments at 1 MiB. Unknown event types are ignored only when the provider's documented forward-compatibility rule permits it; malformed known events return invalidArgument/protocol error. EOF before an explicit terminal provider event is incomplete output, not completed.

Text and tool arguments arrive as arena Buffer handles. The consumer must copy retained data into its own arena/owned storage before resetting an event arena. Tool deltas accumulate by stable call ID/index until that provider's completed-arguments signal; parse and validate the final JSON exactly once. Never execute a partially received tool. Tool dispatch uses an explicit compile-time registry of @Tool methods, schema from serde descriptors, strict argument validation and a Context deadline. Unknown tools and duplicate names fail deterministically. Default orchestration permits at most eight tool rounds and 32 concurrent requests.

Tool execution is an application-controlled action: the library returns tool events and exposes dispatchTool but does not autonomously invoke tools solely because a model requested them. A caller installs its own authorization policy, allowlist and idempotency handling. Credentials, hidden provider tokens and full prompts are redacted from default logs. Stream replay after any delivered text/tool side effect is disabled by default; retry only known prestream transient failures with a fresh request identity.

Usage events are provider-specific and may be cumulative. Normalize them once at terminal completion and do not sum cumulative deltas. Distinguish completed, failed, incomplete and cancelled. The base EventKind.failed includes a structured reason in the content envelope; never represent a refused or truncated response as a successful parsed DTO. JSON Schema covers the implemented serde subset (objects, required fields, scalars, enums, bounded arrays); reject unsupported recursive/pointer polymorphism at compile time.

### Required implementation layout

- source/flint/ai.d: options, events and explicit tool dispatch.
- source/flint/ai/providers/openai.d, anthropic.d, gemini.d, openrouter.d: independent schema/event adapters.
- source/flint/ai/sse.d: bounded streaming parser.
- source/flint/ai/tools.d: serde-descriptor registry and invocation glue.

## 5. Native boundary, ownership and safety

No native AI runtime is linked. Reuse flint:http for HTTP/TLS and flint:serde/validate for schemas/arguments. Heavy type reflection remains in serde's descriptor generator; ai consumes generated descriptors and explicit method tuples rather than scanning every symbol in the application. The client does not use a provider's SDK as an unpinned transitive dependency. Live API smoke tests are optional credentialed tests; mandatory CI runs recorded, versioned, sanitized protocol fixtures and a local fake server.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

No additional native dependency; consume only the lower-tier packages listed above.

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
| Cold DMD fixture build | 1.40 s |
| Incremental DMD leaf edit | 0.60 s |
| Cold LDC fixture build | 8.40 s |
| Incremental LDC leaf edit | 4.20 s |
| Incremental linked code/data contribution | 524288 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instances per canonical fixture | 2000 |

These are engineering ceilings from scaffold/policy/packages.json, measured with the fixed runner/toolchain/workload policy. They are not measured achievements of these declarations. Also fail >10% compile-time/compiler-RSS/template growth or >5% binary growth against the approved baseline. The whole selected application includes native libraries in its cap; a smaller wrapper-only delta cannot excuse a larger deployment artifact. A changed profile is a different benchmark identity and cannot be compared as if equivalent.

## 7. Required unit, protocol, fuzz and benchmark acceptance

| Test identity | Passing condition |
| --- | --- |
| provider_fixtures | Each adapter has success, prestream error, midstream error, usage and tool-call fixtures with documented protocol date. |
| sse_split | Every byte split of UTF-8, CRLF, comments and multiline data parses identically to unsplit input. |
| tool_arguments | Interleaved two-call argument deltas assemble by ID; incomplete/malformed JSON never invokes a tool. |
| tool_authorization | A model-emitted destructive tool name alone causes no execution; only the explicit application dispatcher path can invoke it. |
| limits | Event byte 1048577, tool round 9 and concurrent request 33 return bounded overload errors. |
| usage_accounting | Cumulative usage is not double-counted; OpenRouter compatibility terminal usage chunk cannot emit duplicate completion. |
| cancel_no_replay | Cancel after a text delta or tool side effect; request closes and is not automatically replayed. |
| schema_negative | Unsupported pointer/delegate/cyclic DTO shapes fail compile with a named field path. |
| ai_parser_bench | Replay 100 MiB of 64-byte SSE deltas from memory; bounded scratch, no D allocations on parser callback path. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :ai --compiler=dmd
dub test :ai --compiler=ldc2
python3 tools/gates.py --package ai --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [OpenAI streaming](https://developers.openai.com/api/docs/guides/streaming-responses) — Responses uses typed semantic streaming events.
- [Anthropic streaming](https://platform.claude.com/docs/en/build-with-claude/streaming) — Content blocks, incremental tool JSON and cumulative usage require distinct handling.
- [Gemini REST streaming](https://colab.research.google.com/github/google-gemini/gemini-api-cookbook/blob/main/quickstarts/rest/Streaming_REST.ipynb/) — streamGenerateContent supports SSE with alt=sse.
- [OpenRouter streaming](https://github.com/OpenRouterTeam/docs/blob/main/api_reference/streaming.mdx) — Endpoint-specific terminal and usage events differ.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
