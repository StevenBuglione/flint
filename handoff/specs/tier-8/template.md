# flint:template — Compile-time checked HTML/email templates and explicit output contexts

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] Embedded HTML/email templates, typed model fields, conditionals, bounded loops and includes.
- [ ] Default contextual escaping, compile-time unknown-field errors and explicit unsafe-content policy.
- [ ] SSR/HTMX output written into a caller arena; no runtime template parse/scan.
- [ ] D module is flint.templates because template is a D keyword.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/template/dub.sdl inside the Flint root that declares all subpackages. Module: flint.templates. Direct allowed dependencies: flint:arena, flint:serde.

```sdl
name "template"
description "Flint template subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/templates.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.templates;
import flint.arena : Buffer, Error, RequestArena, Result;

@safe:
struct HtmlTemplate
{
    string fileName;
}

struct TrustedHtml
{
    private Buffer content;
}

Result!Buffer render(string fileName, Model)(scope const ref Model model, ref scope RequestArena arena) nothrow @nogc;
Result!Buffer escapeHtml(scope const(ubyte)[] text, ref scope RequestArena arena) nothrow @nogc;
Error validateUrl(scope const(char)[] url) nothrow @nogc;
```

## 4. Internal architecture and observable semantics

The grammar is deliberately finite: {{model.path}} interpolation, {% if model.flag %}...{% else %}...{% end %}, {% for item in model.items %}...{% end %}, and {% include "relative/file.html" %}. Expressions are typed member access and boolean fields only. There is no arbitrary D eval, runtime code execution, recursive includes, function call syntax or hidden I/O. The compiler parser tracks byte offsets and reports source file, line and column for unknown fields, bad blocks and context errors.

Allowed interpolation contexts are HTML text and quoted HTML attribute values. Escape &, <, >, double quote and apostrophe appropriately. Dynamic attribute names, tag names, unquoted attributes, script/style bodies and event-handler attributes are compile errors. URL attributes pass validateUrl with allowed relative/http/https/mailto schemes under a fixed policy; javascript/data are rejected in the initial profile. Raw TrustedHtml cannot be constructed from an ordinary Buffer through a public @safe function. Applications needing raw HTML must provide an audited sanitizer adapter in an allowlisted unsafe boundary; it is not a default escape hatch.

render!(fileName,Model) compiles the template into literal chunks and direct field-writing functions. It checks all includes under one -J templates directory and rejects .. traversal/absolute paths. Each include path is canonicalized before cycle detection; maximum include depth is 16 and total source bytes 1 MiB. Model arrays/strings must be owned or explicit arena handles. A render pass either reserves bounded output and succeeds or returns outOfMemory/resourceExhausted without exposing a partial successful Buffer.

Compile-time work is bounded by one descriptor per template/model combination. Reuse a generated helper module for shared template layouts and do not instantiate the same megabyte source string at every call site. Incremental rebuild depends on template content hash and compiler flags, not only the D module timestamp. The framework can serve HTMX fragments as ordinary HTML responses; no browser/runtime HTMX library is silently shipped by this package.

There is no dependency from flint:web or flint:mail into templates. Applications invoke render and pass its Buffer to the lower-tier transport. Rendering is @safe nothrow @nogc after startup and does not use reflection or allocate a runtime parse tree. The initial grammar deliberately limits template programmability to keep escaping proofs, compile cost and agent code generation tractable.

### Required implementation layout

- source/flint/templates.d: public render/escape API.
- source/flint/templates/parser.d: CTFE grammar and context tracker.
- source/flint/templates/emit.d: bounded source/helper generation.
- tests/templates: accepted and compile-fail files, escaping golden outputs.

## 5. Native boundary, ownership and safety

No new C library and no system calls in the render path. Input templates are UTF-8 source resources embedded by string import. HTML escaping is a small D byte transformation, not a cryptographic/transport reinvention. Tier 8 may consume serde descriptors, but application model reflection remains behind the framework emitter. Optional sanitization must be a separately audited adapter with an explicit dependency/license review; it is not provided by this base contract.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

No additional native dependency; consume only the lower-tier packages listed above.

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
| field_compile | Unknown/nested-missing model field reports template file+line+column during compilation. |
| context_compile | Interpolation in tag/attribute name, unquoted attribute, script/style and on* attribute fails compile. |
| xss_escape | Payloads containing quotes, ampersands, angle brackets and UTF-8 are escaped exactly once in text/attribute contexts. |
| url_policy | javascript/data/embedded-control URLs fail; approved relative/http/https/mailto cases pass their exact policy. |
| include_graph | Cycle, depth17, absolute path and ../ traversal fail; shared acyclic includes compile once. |
| output_capacity | Exactly fitting output succeeds; one-byte-short arena returns error without an exposed partial result. |
| compile_scaling | 1/10/100 templates track cold/incremental compile time and instance counts; no monolithic all-template instantiation. |
| render_bench | Render 1-KiB/64-KiB fixtures for 100k iterations; zero D allocations, exact bytes and bounded arena reset. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :template --compiler=dmd
dub test :template --compiler=ldc2
python3 tools/gates.py --package template --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [D string import](https://dlang.org/spec/expression.html#import_expressions) — Templates can consume compile-time source resources.
- [D templates](https://dlang.org/spec/template.html) — Template bodies need explicit instantiation for semantic verification.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
