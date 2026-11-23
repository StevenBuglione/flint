# ADR-020: Build Flint desktop apps the way Tauri v2 does, in D over the system C libraries

Status: accepted on 2026-11-21. It implements the project owner's direction to follow Tauri's architecture in D over the platform C libraries, never wrapping Rust (ADR-017 decision 6).

## Context

`flint:desktop` shipped two backends. The default was a static SDL3 build limited to its X11, offscreen and dummy video drivers, drawing a Flint-specific binary draw list. The other was an opt-in WebKitGTK profile written as a separate C adapter with its own build script and DUB block. The webview profile had no typed host bridge: JavaScript sent raw byte arrays to a single `app.message` method.

On the reference Linux desktop (NixOS, Hyprland on Wayland, NVIDIA) the SDL profile could not open a window. SDL `dlopen`s `libX11.so.6`, which NixOS does not put on a default library path. Xwayland also listened on a nonstandard socket, while a stale server held the abstract socket. The package tests passed only with `SDL_VIDEO_DRIVER=offscreen`, so the real platform path was never exercised. The draw list was also a renderer Flint had to own: text shaping, input methods, accessibility, high-DPI and every widget would have had to be written from scratch.

Tauri v2 (<https://v2.tauri.app/concept/architecture/>) is the best-known answer to "native shell, web UI, typed host code":

- **Windows and event loop.** `tao`, a fork of winit, uses GTK on Linux. It therefore runs natively on Wayland and on X11 through GDK, without its own Wayland client.
- **System webview.** `wry` embeds WebKitGTK on Linux, WebView2 on Windows and WKWebView on macOS. Nothing is bundled; the OS runtime renders the UI.
- **Typed commands.** A Rust function marked `#[tauri::command]` is called from JavaScript with `invoke("name", { args })`. Its arguments are deserialised with serde, its result serialised back, and the returned `Promise` resolves or rejects (<https://v2.tauri.app/develop/calling-rust/>).
- **Events in both directions.** The frontend calls `emit` and `listen`, the backend calls `app.emit` and `listen` (<https://v2.tauri.app/develop/calling-frontend/>).
- **Capabilities.** IPC is denied by default. Capability files bind a set of permissions (allowed commands, events and scopes) to window labels and, optionally, to remote URLs. Commands outside a window's capabilities are rejected before they run (<https://v2.tauri.app/security/capabilities/>, <https://v2.tauri.app/security/permissions/>).
- **Asset protocol.** The frontend is served from embedded assets through a custom scheme (`tauri://localhost`, `http://tauri.localhost` on Windows) rather than `file://` or a local HTTP server. Responses carry a Content-Security-Policy, and navigation away from the app origin is policed (<https://v2.tauri.app/security/csp/>).
- **Bundling.** `tauri build` produces `.deb`, `.rpm` and AppImage packages on Linux, MSI/NSIS on Windows, and `.app`/`.dmg` on macOS. The system webview is declared as a dependency, not shipped (<https://v2.tauri.app/distribute/>).

The obvious port is to wrap `tao` and `wry` in a Rust static library. The user rejected that: Flint desktop code is D, and it may call C libraries but not wrap Rust. What Flint copies from Tauri is the architecture, and `tao` and `wry` are themselves thin layers over the C libraries listed above.

## Decision

Rebuild `flint:desktop` on the Tauri v2 architecture, implemented in D, binding the platform C libraries directly. There is no Rust, and no Flint C shim on the webview path.

### Platform layer

| Platform | Windows and event loop | Webview | Binding |
| --- | --- | --- | --- |
| Linux (implemented) | GTK 3 (`libgtk-3`, GDK picks Wayland or X11) | WebKitGTK `webkit2gtk-4.1` | `extern(C)` declarations in `flint.desktop.ffi.webkit` |
| Windows (later) | Win32 | WebView2 through its COM C ABI (`ICoreWebView2*` vtables) | `extern(Windows)` vtable structs in D |
| macOS (implemented, ADR-024) | AppKit | WKWebView | Objective-C runtime C ABI (`objc_msgSend`, `sel_registerName`) from D, in `flint.desktop.ffi.wkwebview` |

These are the same libraries `tao` and `wry` use on each platform. Only GLib, GObject, GTK and WebKitGTK functions are declared, each with the exact C signature. Raw pointers and callbacks stay in `flint.desktop.ffi`, already an allowlisted low-level prefix. Every `@trusted` function carries its adjacent `// SAFETY:` note and stays under 60 lines. GTK signal callbacks are `extern(C) nothrow @nogc` D functions. They do not call application code: they copy the IPC message or window event into a window-owned ring, and the owner loop dispatches it after the GTK iteration returns. A D exception therefore cannot unwind through GTK.

On macOS the same contract is implemented without Objective-C source. `objc_msgSend` is cast to each call's exact C prototype, as arm64 requires. One `NSObject` subclass, registered at run time with `objc_allocateClassPair`, is the script message handler, the `flint` URL scheme handler, and the navigation, UI and window delegate. Its methods are `extern(C) nothrow @nogc` D functions that only copy into the window-owned ring or record an event, as the GTK callbacks do. Decision handlers are Objective-C blocks; Flint calls each one exactly once through the block's `invoke` slot. Assets are served from `flint://localhost` with the same headers and content-security policy. Downloads, new windows and media-capture requests are refused. The owner loop drains queued AppKit events and one run-loop pass on every poll. The bridge script is unchanged, because WKWebView exposes the same `window.webkit.messageHandlers` interface as WebKitGTK. WKWebView has no setting that copies console output to stdout, so `FLINT_DESKTOP_CONSOLE` has no effect there. `FLINT_DESKTOP_DEVTOOLS=1` makes the view inspectable.

The webview path still links the existing generation-checked C queue in `libflint_ffi.a` (`flint_desktop_queue.c`), which carries `postMessage` and worker results across threads for both backends.

One driver mitigation is built in. On NVIDIA's driver under Wayland, the driver's EGL explicit-sync path makes GTK/WebKit surfaces fail the compositor's `wp_linux_drm_syncobj` check ("Missing acquire timeline", Wayland protocol error 71). GDK then exits the process. Before GTK starts, Flint therefore sets `__NV_DISABLE_EXPLICIT_SYNC=1`, only when `/proc/driver/nvidia/version` exists, `WAYLAND_DISPLAY` is set and the variable is unset. Tauri applications apply the same opt-out. Rendering stays on the GPU with DMA-BUF buffers. The other common fix, `WEBKIT_DISABLE_DMABUF_RENDERER=1`, would fall back to shared-memory rendering. Neither is an offscreen or X11 fallback.

The webview backend opens on Wayland directly. Nothing is `dlopen`ed by soname: the executable links `libgtk-3` and `libwebkit2gtk-4.1` with `DT_NEEDED` entries. `tools/native_build.py` records an rpath for each provider library directory, so the binary runs on NixOS without `LD_LIBRARY_PATH`.

### Application model

The developer ergonomics match `flint:web`: annotated structs, explicit composition, typed DTOs through `flint:serde`, and `@safe`/DIP1000 rules unchanged.

```d
struct AddRequest { long a; long b; }
struct Sum { long value; }

@DesktopCommands
struct Calculator
{
    @Command("add")
    Result!Sum add(scope const ref AddRequest request, ref scope InvokeContext context) nothrow @nogc
    {
        return Result!Sum(Sum(request.a + request.b));
    }

    @Listen("clicked")
    Error clicked(scope const ref Click click, ref scope InvokeContext context) nothrow @nogc
    {
        return context.emit("count", Sum(click.count));
    }
}

struct Application { Calculator calculator; }

static immutable Asset[] assets = [Asset("index.html", import("index.html"))];
static immutable Capability[] capabilities = [
    Capability("main", windows: ["main"], commands: ["add"], events: ["clicked"]),
];

Window window;
window.open(WindowOptions(title: "Calculator", backend: DesktopBackend.systemWebView,
        assets: assets, capabilities: capabilities));
Application app;
window.serve(app, context);
```

```js
const sum = await flint.invoke("add", { a: 2, b: 40 });   // {value: 42}
flint.listen("count", (payload) => render(payload));
flint.emit("clicked", { count: 3 });
```

- **Commands.** `@Command("name")` on a method of a `@DesktopCommands` struct. The method takes either `(ref scope InvokeContext)` or `(scope const ref Dto, ref scope InvokeContext)`. It returns `Result!T`, encoded with `flint:serde`, or `Error`, which resolves to `null`. The args object is decoded into `Dto` by `flint.serde.decodeInto` with unknown fields rejected, which plays the role of the `@RequestBody` binding in `flint:web`. A failed decode rejects the promise with `invalidArgument` before the method runs. Duplicate command names and unsupported signatures are compile errors. The binder is a compile-time walk of the explicit `Application` struct's fields, like `flint.web.internal.controllers`. It never scans modules or constructs from strings.
- **Events.** D→JS: `Window.emit(name, value)` or `InvokeContext.emit`, owner thread only. JS→D: `flint.emit(name, payload)` reaches the `@Listen("name")` methods, typed the same way as commands.
- **Capabilities.** `Capability { identifier, windows, commands, events, origins }` values are composed explicitly in D. They are matched on the window's `label` and the page's origin: the app origin, or exact HTTPS origins listed in `origins`. An invoke or emit is dispatched only when some capability for that window and origin lists the name. Otherwise it is rejected with `permissionDenied` before decoding, so unknown and forbidden commands look the same. With no capabilities, every invoke is denied.
- **Asset protocol.** `Asset { path, content, mime }` values are served by D from the `flint://localhost/` scheme. Each response carries `Content-Security-Policy`, `X-Content-Type-Options: nosniff` and `Cache-Control: no-store`. The default CSP allows only same-origin scripts, styles, images and fonts, plus inline scripts and styles. Navigation is limited to the app origin and the window's exact `httpsOrigin`. New windows, downloads (unsupported MIME responses) and permission requests (camera, geolocation, notifications) are denied.
- **Bridge.** A frozen `window.flint = { invoke, emit, listen }` object is injected into the top frame at document start; it is not injected into subframes. Frames are also blocked by the CSP. The wire format is a framed text message (`F1`, kind, id, name, then the JSON body), at most 16 KiB. D validates names against `[A-Za-z0-9_.:-]{1,64}` and replies through a single `window.__FLINT__.resolve(id, ok, json)` evaluation. JSON responses are valid JavaScript literals.
- **Developer switches.** `FLINT_DESKTOP_CONSOLE=1` copies page console messages to stdout, and `FLINT_DESKTOP_DEVTOOLS=1` enables the WebKit inspector. Both are off by default.
- **Threading.** As in Tauri and the existing contract, the window and webview belong to the process main thread. Opening, closing or emitting from another thread returns `permissionDenied`. `postMessage` and `submitWork` keep their bounded cross-thread queues.

### Licensing and bundling

WebKitGTK and GTK are LGPL-2.1+ system libraries. Flint links them dynamically, as it already links glibc (also LGPL-2.1). It never links them statically and never ships modified copies, which keeps the default artifact within the LGPL relinking terms. WebView2 and WKWebView are platform components under their vendors' terms. The permissive packaging gate changes accordingly: the old gate refused any GTK or WebKit `NEEDED` entry. `native/check_permissive.py` now refuses a static GTK, WebKit or JavaScriptCore archive in the link and reports the dynamic system webview entries, so the runtime dependency list is explicit.

Bundling follows Tauri's targets: a later `flint desktop bundle` CLI writes `.deb`/`.rpm` control files declaring `libwebkit2gtk-4.1-0` and `libgtk-3-0`, and an AppImage recipe. This ADR does not implement bundling. It records the target so the asset, icon and capability files are laid out compatibly.

### SDL backend

`DesktopBackend.sdl` and the version-1 draw list stay, unchanged, as an optional canvas backend for applications that want immediate-mode drawing. It is no longer the default and no longer part of the default `desktop` native profile. Enabling Wayland in the pinned SDL build is a separate follow-up.

## Alternatives

- **Wrap `tao` and `wry` in a Rust staticlib with a C ABI.** Rejected by the user: Flint does not wrap Rust. It would also add a Cargo build and roughly 300 transitive crates to a package whose real dependencies are GTK and WebKit.
- **Keep the WebKitGTK C adapter.** It worked, but it duplicated in C what D can express directly with the same safety boundary, and kept the host bridge outside the typed D layer.
- **`webview/webview` (pinned, MIT).** It is C++ with a C API, offers only string-in/string-out bindings, and on Linux still requires GTK and WebKitGTK. Its Linux native build was never enabled. It stays in the lock for macOS evaluation only.
- **Fix SDL on Wayland and keep the draw list as the default.** That repairs window creation but still leaves Flint owning a UI toolkit.

## Consequences

- Policy changes needing integration-owner review:
  - `desktop` gains a direct `flint:serde` dependency (tier 1, so the graph stays acyclic) in `policy/packages.json` and `packages/desktop/dub.sdl`.
  - `flint.desktop.internal` joins the approved reflection internals in `AGENTS.md`. The command-table walk is reflection; it uses no string mixins, so `policy/safety-policy.json` is unchanged.
  - `policy/native-lock.json` gains a `webkitgtk` system-provider row: pkg-config modules, minimum versions and license.
  - The `desktop` profile in `tools/native_build.py` resolves that provider through pkg-config, records the resolved versions, the digests of the `.pc` files and the link flags in the install receipt, and emits the `FlintNativeWebkitgtk` DUB version.
  - SDL moves to a new `desktop-canvas` profile. The `ci` closure still builds it.
- Public API additions: `WindowOptions.label`, `assets` and `capabilities`; `Asset`, `Capability`, `DesktopCommands`, `Command`, `Listen`, `InvokeContext`; `Window.serve` and `Window.emit`. Existing declarations keep their meaning. The raw `window.webkit.messageHandlers.flint.postMessage([...])` byte protocol of the old adapter is replaced by the `flint` bridge object.
- `packages/desktop/native/webkitgtk.c`, `build_webkitgtk.py` and the fixtures that drove it are removed; D tests cover the same origin and navigation denials.
- The desktop suite runs against the real display. With no display it fails, rather than skipping, as the old SDL suite did.

## Specification changes for review

`handoff/` is the frozen, manifest-pinned bootstrap contract, so this branch leaves it untouched. The integration owner should apply these changes to `specs/tier-8/desktop.md` and `contracts/source/flint/desktop.d` and refresh `MANIFEST.sha256`:

- **§1 parity checklist.** "System WebView is the default frontend (GTK + WebKitGTK on Linux, WebView2, WKWebView). Typed commands, events both ways and capabilities are the host bridge. SDL3 is an optional canvas backend."
- **§2 dependencies.** Add `flint:serde`.
- **§3 public contract.** Add `Asset`, `Capability`, `DesktopCommands`, `Command`, `Listen`, `InvokeContext`; `WindowOptions.label`, `assets`, `capabilities` (with the existing `html` and `httpsOrigin`); `Window.serve(App)`, `Window.emit(T)`, `Window.postMessage` and `Window.submitWork`.
- **§4 architecture.** Replace "SDL3 supplies the default…" with the platform table and application model above. Replace the WebKitGTK exclusion paragraph with the licensing section above. Keep the SDL draw-list text as the canvas backend.
- **§5 native boundary.** The webview binds GLib, GTK and WebKitGTK directly from D (`ffi/webkit.d`). Add the `webkitgtk` row (`dynamic-system-library`, LGPL-2.1-or-later AND BSD-2-Clause) to the native selections table. Change the preparation command's profile description to "desktop = system webview, desktop-canvas = SDL3".
- **§7 acceptance.** Replace `license_gate` with: "No GTK/WebKit symbols are defined in the artifact (dynamic only); `--no-system-webview` refuses them for canvas artifacts." Add `command_typed`, `event_roundtrip`, `capability_denial`, `asset_protocol` and `navigation_policy` rows matching the tests below. `webview_origin` and `main_thread` keep their meaning for the webview. `platform_smoke` gains the webview on Linux Wayland, X11, Windows and macOS.

## Acceptance evidence

- `dub test :desktop` on DMD 2.114 (Flint fork) and LDC 1.43, on the reference Hyprland Wayland session (NixOS, RTX 3070, WebKitGTK 2.54.1, GTK 3.24.52), with no `SDL_VIDEO_DRIVER`, offscreen or X11 fallback variables. The suite asserts that GDK chose `GdkWaylandDisplay`. It covers:
  - window lifecycle: wrong-thread open, close and emit are denied, cross-thread messages are copied, native resize and a window-manager close are observed, and the slot reopens;
  - typed JS→D commands with decoded arguments and arena-encoded results;
  - D→JS and JS→D events;
  - capability denial: an ungranted command, an unknown command and an ungranted event; a granted but unimplemented command returns `notFound`; a malformed argument is rejected before the method runs;
  - navigation denial, with the page origin and location checked;
  - external script and stylesheet assets served under `nosniff`;
  - a 300-call invoke burst with queued messages and worker tickets that ends in a close while frames are still in flight.
- The same suite passes on macOS 26.4 arm64 with the WKWebView backend, on `ldmd2` and `ldc2` (LDC 1.43), in pluto's AppKit session. It asserts that the backend is AppKit (ADR-024).
- `python3 tools/gates.py --package desktop --gate structural` and `python3 tools/quality.py` are clean.
- `examples/golden-desktop` builds and completes its scripted session on the same desktop.
