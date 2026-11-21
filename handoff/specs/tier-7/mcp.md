# flint:mcp — Versioned MCP server/client with modern and compatibility transports

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] stdio and Streamable HTTP clients/servers with @McpTool/@McpResource registries.
- [ ] Pinned modern revision 2026-07-28 plus explicit compatibility revision 2025-11-25.
- [ ] Typed schemas, tools/resources, pagination, cancellation and protocol-specific errors.
- [ ] No mixing modern stateless metadata with legacy initialize/session semantics.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/mcp/dub.sdl inside the Flint root that declares all subpackages. Module: flint.mcp. Direct allowed dependencies: flint:arena, flint:http, flint:web, flint:serde, flint:validate, flint:conc.

```sdl
name "mcp"
description "Flint mcp subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:http" version="*"
dependency "flint:web" version="*"
dependency "flint:serde" version="*"
dependency "flint:validate" version="*"
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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/mcp.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.mcp;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
struct McpTool
{
    string name;
    string description;
    bool readOnly = false;
}

struct McpResource
{
    string uri;
    string mimeType = "text/plain";
}

enum ProtocolRevision : ubyte
{
    modern20260728,
    legacy20251125
}

enum Transport : ubyte
{
    stdio,
    streamableHttp
}

struct McpOptions
{
    string name;
    string versionString;
    ProtocolRevision revision = ProtocolRevision.modern20260728;
    bool acceptLegacy = true;
    Transport transport = Transport.stdio;
    string address = "127.0.0.1";
    ushort port = 3000;
    string path = "/mcp";
    size_t maxMessageBytes = 4 * 1024 * 1024;
    uint maxInFlight = 64;
    string[] allowedOrigins;
}

struct ToolResult
{
    Buffer content;
    Buffer structuredContent;
    bool isError = false;
}

struct McpServer
{
    private ulong slot;
    private ulong generation;
    Error open(McpOptions options);
    Error run(ref Context context) nothrow @nogc;
    Error close(ref Context context) nothrow @nogc;
}

struct McpClient
{
    private ulong slot;
    private ulong generation;
    Error connect(string endpoint, ProtocolRevision revision, ref Context context);
    Result!Buffer listTools(ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Result!ToolResult callTool(string name, scope const(ubyte)[] arguments,
            ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Result!Buffer readResource(string uri, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error close(ref Context context) nothrow @nogc;
}

Error registerMcp(T)(ref McpServer server, ref T provider);
```

## 4. Internal architecture and observable semantics

The wire revision is a first-class enum, not a best-effort string inferred from one successful request. Modern mode targets the published 2026-07-28 revision: every request carries protocol metadata, HTTP duplicates the version in MCP-Protocol-Version, and server/discover advertises supported capabilities. There is no initialize handshake or protocol session in this mode. The HTTP endpoint accepts POST; GET/DELETE return 405. Request-scoped JSON or SSE carries its result and related notifications. Modern server-to-client interactions use MRTR input requests/results, not independent JSON-RPC requests on the stream.

Compatibility mode targets exactly 2025-11-25 and implements initialize/initialized, negotiated capabilities, optional Mcp-Session-Id, its GET stream rules and its explicit cancellation semantics. Mode-specific states and codecs live in separate modules; a legacy request cannot enter modern handlers merely because it has a familiar method name. Dual-mode server dispatch chooses the era from required modern metadata versus a valid legacy opening. A client probes modern discovery and follows the documented transport-specific fallback only on a nonmodern failure; a recognized unsupported-version error triggers supported-version selection.

stdio frames one UTF-8 JSON-RPC object per line, rejects batches in the pinned revisions, caps the message at 4 MiB and reserves stdout strictly for protocol messages. Logs go to stderr. A child-process client inherits only explicitly provided environment values and has a bounded stderr drain to avoid deadlock. A closed pipe cancels admitted work and joins the process by deadline.

Streamable HTTP binds 127.0.0.1 by default, validates every supplied Origin against an exact allowlist and applies configured authentication on externally reachable listeners. Reject missing/conflicting modern metadata or header/body version mismatch before invoking a tool. The modern response stream ending early signals cancellation under its rules; legacy disconnect/resume semantics remain confined to that adapter. SSE proxy buffering is disabled and heartbeat comments preserve idle connections without inventing JSON-RPC messages.

The registry is a fixed generated table with unique method names and resource URIs. Tools/list and resources/list paginate with opaque cursors bound to one registry generation. Tool inputs are validated against generated schemas; tool application failures set isError in the tool result, while malformed protocol requests use JSON-RPC errors. A tool is not automatically safe because readOnly=true; that field is descriptive metadata and application authorization still decides invocation. Resources are served from explicit providers, never arbitrary local file paths. Maximum 64 in-flight operations and a 4-MiB message cap bound memory.

Required modern methods are server/discover, tools/list, tools/call, resources/list, resources/read and subscriptions/listen when change notifications are advertised. MRTR capability may be absent; if absent, reject operations needing it with the protocol-supported error and do not advertise sampling/elicitation support. Implement every advertised feature; unsupported optional capabilities are omitted rather than falsely claimed. Versioned fixtures lock exact method schemas and errors.

### Required implementation layout

- source/flint/mcp.d: public API/UDAs and revision enum.
- source/flint/mcp/modern.d: 2026-07-28 metadata/discovery/MRTR binding.
- source/flint/mcp/legacy.d: 2025-11-25 initialize/session adapter.
- source/flint/mcp/stdio.d and http.d: separate transport state machines.
- tests/fixtures/mcp/2026-07-28 and 2025-11-25: protocol fixtures and negotiation matrix.

## 5. Native boundary, ownership and safety

No new native library. JSON/schema generation reuses serde; HTTP reuses web/http; stdio descriptors and process ownership use existing core OS boundaries. Do not depend on flint:ai: MCP must be usable independently of an LLM provider. The server's tools are explicit D methods; it never synthesizes shell commands or opens filesystem resources from an unvalidated tool/resource name.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

No additional native dependency; consume only the lower-tier packages listed above.

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
| modern_discovery | First request can be tools/list with required metadata; server/discover works without initialize. |
| modern_http | GET/DELETE produce 405; conflicting header/body revision fails; no session header is minted. |
| legacy_compat | Initialize→initialized→tools/list works with exactly 2025-11-25 semantics and no modern-only fields. |
| era_fallback | Matrix modern/legacy/dual client and server combinations matches the two pinned specifications, including unsupported-version retry. |
| stdio_clean | All stdout lines are valid JSON-RPC; logs and compiler diagnostics cannot leak into the protocol stream. |
| origin_auth | Invalid supplied Origin returns 403; nonlocal listener without configured auth fails startup. |
| tool_errors | Unknown method/invalid params use JSON-RPC errors; application tool failure returns isError, and malformed inputs never invoke tool code. |
| registry_pagination | Cursor from another generation is rejected; full pagination yields every tool exactly once. |
| cancellation_versions | Modern SSE close and legacy explicit cancel take their own correct path; cancellation cannot cross request IDs. |
| mcp_bench | Local stdio and HTTP loopback perform 100k 1-KiB tool calls with fixed registry, bounded queues and no hot D allocations. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :mcp --compiler=dmd
dub test :mcp --compiler=ldc2
python3 tools/gates.py --package mcp --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [Modern transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) — 2026 revision removes GET/session transport behavior and defines request-scoped responses.
- [Modern versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning) — Per-request metadata replaces initialization; dual-era compatibility is explicit.
- [Legacy transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) — Compatibility behavior must remain version-specific.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
