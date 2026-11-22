# flint:desktop — Optional native window shell with explicit backend and licensing boundary

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] Portable native-window/event abstraction, bounded command buffers and application IPC.
- [ ] SDL3 is the default permissive backend; system WebView is a separate explicit profile.
- [ ] Main-thread UI ownership, shutdown coordination and deny-by-default host capabilities.
- [ ] No claim that a WebView shell, SDL GPU UI and a DOM frontend are identical renderers.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/desktop/dub.sdl inside the Flint root that declares all subpackages. Module: flint.desktop. Direct allowed dependencies: flint:arena, flint:conc, flint:os, flint:wasm-bridge.

```sdl
name "desktop"
description "Flint desktop subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:conc" version="*"
dependency "flint:os" version="*"
dependency "flint:wasm-bridge" version="*"

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

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/desktop.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.desktop;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
enum DesktopBackend : ubyte
{
    sdl,
    systemWebView
}

enum EventKind : ubyte
{
    close,
    resize,
    key,
    pointer,
    message
}

struct DesktopEvent
{
    EventKind kind;
    int x;
    int y;
    uint keyCode;
    Buffer message;
}

struct WindowOptions
{
    string title = "Flint";
    uint width = 1024;
    uint height = 768;
    DesktopBackend backend = DesktopBackend.sdl;
    bool resizable = true;
    string entryAsset = "index.html";
}

alias DesktopHandler = Error delegate(ref DesktopEvent event, ref scope RequestArena arena) @safe nothrow @nogc;
struct Window
{
    private ulong slot;
    private ulong generation;
    Error open(WindowOptions options);
    Error run(DesktopHandler handler, ref Context context) nothrow @nogc;
    Error submit(scope const(ubyte)[] commandBuffer) nothrow @nogc;
    Error close() nothrow @nogc;
}
```

## 4. Internal architecture and observable semantics

Window.open must execute on the platform UI/main thread. SDL3 supplies the default cross-platform window, events and renderer/GPU integration. The default command vocabulary is a versioned 2D draw list: clear, rectangle, text-glyph run, image and clip stack. Window.submit validates the whole command buffer (lengths, resource IDs, stack depth and coordinates) before queueing it; it is not a JavaScript evaluator. The renderer owns textures/fonts and presents once per frame. A WASM frontend can emit compatible commands through wasm-bridge, but native SDL does not implement browser DOM APIs.

Window.run consumes UI events on the owner thread and dispatches bounded application messages. Slow business work runs on flint:conc workers and posts owned results; no request arena or stack pointer crosses to the UI thread. Queue capacity is 256 events/4 MiB, with pointer-motion coalescing and explicit overload failure for semantic messages. Resize and close events carry generations. Graceful close stops new work, cancels window-owned tasks, joins them, drains resource destruction on the UI thread and closes the native window exactly once.

The optional systemWebView profile maps Windows to WebView2 and macOS to WKWebView. It loads packaged application assets or an explicit allowlisted HTTPS origin. Navigation, file URLs, downloads, external window creation and native message calls default denied. Host bridge messages are versioned JSON/binary commands with generated schema validation and an allowlisted method registry. Never expose a general shell/file read primitive merely because the page is local. CSP and per-window origin checks apply before dispatch; untrusted remote content has no host capability.

Linux WebKitGTK carries LGPL components and is excluded from the permissive default. Enabling it is an explicit separately documented licensing profile; it cannot pass the permissive-only release job. The systemWebView option is unsupported on Linux in the default distribution. Platform SDK/framework/runtime terms for WebView2/WKWebView are recorded as system dependencies, not mislabeled MIT/BSD libraries. If all three OSes must use the same permissive implementation, choose SDL3 and the specified native draw-list UI.

SDL's renderer/GPU API is the first backend; wgpu-native can be added only as a separately pinned optional adapter with its Rust build toolchain and ABI tests. It is not silently required to open a window. Desktop assets, fonts and icons each have provenance/license entries and do not inflate CLI/server artifacts because desktop is an optional Tier 8 package.

The supplied native CI profile builds SDL on Linux for windows, input and rendering. It disables optional ALSA/PulseAudio/PipeWire/JACK/sndio, libusb, FriBidi/libthai, Wayland/KMS and board-specific backends to keep discovery from adding unreviewed runtime dependencies; configured SDL system linker flags come from the built `sdl3.pc` and are retained with a hash. macOS/Windows system audio remains platform-owned. The optional `webview` helper is source-fetch-only on Linux and Windows until the separate LGPL/SDK deployment profiles are implemented and validated; `--allow-webview` currently enables the actual macOS native build. The Windows WebView2 API and Linux exception profile below remain implementation acceptance requirements, not completed build claims.

### Required implementation layout

- source/flint/desktop.d: window/event/submit contract.
- source/flint/desktop/commands.d: versioned command decoder and bounds.
- source/flint/desktop/ffi/sdl.d and c/desktop.c: SDL3 C shim.
- source/flint/desktop/ffi/webview2.d plus C++ shim, wkwebview.d plus Objective-C shim: optional system profile.
- tests/ui: headless validation plus platform interactive smoke harness.

## 5. Native boundary, ownership and safety

Use contracts/c/desktop.h for SDL3. Windows COM and macOS Objective-C are wrapped in small platform-native C ABI shims compiled by the platform SDK compiler; they are not treated as plain ImportC-readable headers. Raw COM/ObjC objects remain inside those shims, reference counts are paired there, and callback lifetime is tied to window generation. GTK/WebKit is excluded unless the user explicitly chooses the separate LGPL profile. A platform's ordinary system libraries may remain dynamic; a fully static desktop binary is not a portable promise.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

| Lock ID | Version | License selection | Link profile |
| --- | --- | --- | --- |
| sdl3 | 3.4.20 | Zlib | static-runtime-library |
| webview | 0.12.0 | MIT | static-optional-runtime-library |
| wgpu-native | 29.0.1.1 | MIT OR Apache-2.0 | static-optional-runtime-library |

Immutable commit/source IDs, artifact digests, notices and target recipes are authoritative in scaffold/policy/native-lock.json and docs/C_FFI_PINNING_MATRIX.md. A source digest check is not evidence that every target binary was built or audited.

### Flint C shim ABI

This stable Flint-facing header is compiled by the target C compiler against the selected upstream headers. Its opaque pointers are internal; the public D API exposes only checked handles.

```c
/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_DESKTOP_ABI_H
#define FLINT_DESKTOP_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_window flint_window;
typedef struct flint_window_event {
    uint32_t kind; int32_t x; int32_t y; uint32_t key_code;
} flint_window_event;
flint_window *flint_window_new(const char *title, uint32_t width,
                               uint32_t height, uint32_t flags);
int flint_window_poll(flint_window *window, flint_window_event *event);
int flint_window_submit(flint_window *window, const uint8_t *commands,
                        size_t command_bytes);
void flint_window_free(flint_window *window);
#ifdef __cplusplus
}
#endif
#endif
```

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --profile desktop --target linux-x86_64-glibc --phase build --emit-dub
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
| main_thread | Opening/destroying windows from a worker returns a deterministic error instead of violating platform UI rules. |
| command_fuzz | Malformed lengths/resource IDs/clip underflow/oversized strings are rejected before native calls; fuzz with ASan. |
| event_bound | Flood pointer events while blocking a worker; queue stays bounded and close remains responsive. |
| shutdown_race | Close with 256 in-flight owned messages; no callback touches a destroyed window or stale arena. |
| webview_origin | Navigate to an unapproved origin and attempt host IPC; both are denied in the system profile. |
| platform_smoke | Linux x86_64, macOS arm64 and Windows x86_64 open, resize, render and close the SDL profile. |
| license_gate | Default artifact has no GTK/WebKitGTK link entries; enabling that profile fails permissive-only packaging. |
| desktop_bench | Measure startup/frame submission/RSS separately from core server budgets; no D allocations in steady draw-list processing. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :desktop --compiler=dmd
dub test :desktop --compiler=ldc2
python3 tools/gates.py --package desktop --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [SDL homepage](https://www.libsdl.org/) — SDL3 provides portable C window/input/render interfaces.
- [SDL license](https://www.libsdl.org/license.php) — SDL2 and newer use the zlib license.
- [WebKitGTK license](https://webkitgtk.org/reference/webkit2gtk/unstable/) — WebKitGTK includes BSD and LGPL-2.1 licensing; it is not wholly permissive.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
