# flint:tui — implementation specification

Catalogue tier 4. Research cut: 2026-11-21. This file specifies implementation work; declarations in contracts are type-checking interfaces, not runtime implementations.

## 1. Purpose and reference parity

Supply an Elm-style model/update/view runtime with serial model ownership, bounded asynchronous commands and differential terminal rendering.

- [ ] Model-update-view lifecycle, typed events, asynchronous command effects, ticks and graceful quit.
- [ ] Differential cell rendering at a maximum configurable frame rate.
- [ ] Window resize, cancellation and alternate-screen restoration.
- [ ] Pure application model code remains ordinary D structs and methods.

## 2. Exact package recipe and dependency boundary

Write this recipe to `packages/tui/dub.sdl` in the implementation repository:

```sdl
name "tui"
description "Flint tui subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:conc" version="*"
dependency "flint:term" version="*"
dependency "flint:style" version="*"

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

Allowed direct Flint dependencies: `flint:arena`, `flint:conc`, `flint:term`, `flint:style`. The canonical allowlist is [packages.json](../../scaffold/policy/packages.json). Importing a higher catalogue tier or an unlisted same-tier package fails Gate 2.

## 3. Public D contract

Canonical declaration module: [flint.tui](../../contracts/source/flint/tui.d). These exact signatures are compiled with DIP1000. Implement the declarations with the semantics below; do not put unresolved declaration stubs into production artifacts.

```d
module flint.tui;
public import flint.term : Event, EventKind, KeyCode, Size;
import flint.style : Style;
import flint.arena : Error, Result;

@safe:
struct Cell
{
    dchar rune = ' ';
    uint foreground;
    uint background;
    ushort attributes;
}

struct Frame
{
    uint columns;
    uint rows;
    Error put(uint column, uint row, scope const(char)[] text, Style style = Style.init);
    Error clear(Style style = Style.init);
}

struct CommandId
{
    ulong value;
}

struct TimerId
{
    ulong value;
}

alias Command = Event delegate() @safe;
struct Effects
{
    Result!CommandId submit(Command command);
    Error cancel(CommandId id);
    void quit(int exitCode = 0);
    Result!TimerId tick(long intervalNanos);
    Error cancelTimer(TimerId id);
}

struct RuntimeOptions
{
    uint maxFramesPerSecond = 60;
    uint maxPendingCommands = 256;
    uint maxEventsPerFrame = 1024;
}

int run(M)(ref M model, RuntimeOptions options = RuntimeOptions.init);
```

## 4. Internal architecture, ownership and safety

1. run!M requires M.update(Event, ref Effects) and M.view(ref Frame) const. Compile-time traits check these two signatures once at the runtime entry; no reflection in the render loop. The model is owned exclusively by the UI thread.
2. Commands execute on flint.conc bounded workers and return an owned Event. They never receive ref M or Frame and must not capture mutable model storage. Command closures are GC-managed cold-path data; the TUI is not advertised as an allocation-free server hot path.
3. Queue size defaults to 256 commands and 1024 events consumed per frame. A full queue returns resourceExhausted. Timer events set Event.kind=timer and timerId from tick(); command events set kind=command and commandId from submit(). Event.payload is owned, capped at 65536 bytes, and error carries bounded status text. cancelTimer stops future timer events; already queued events carry a retired ID and are ignored. Resize and tick events coalesce; key and paste events retain order. submit returns a stable CommandId through the internal registry; cancel returns notFound for completed/unknown IDs.
4. Maintain front/back cell grids, compare dirty rows and emit merged spans. Resize invalidates both grids and triggers one full repaint. A Frame handle is valid only during its current view callback; a generation check rejects retained handles.
5. Effects.quit closes intake, cancels commands, drains completed events for at most 2s and restores terminal modes. Exceptions from command workers become bounded error events and never unwind through a native callback.
6. Use a monotonic clock; render at most 60Hz by default. No spinning while idle. All OS/terminal effects are delegated to term. Color and width policies come from style.

### Concrete implementation files

- `packages/tui/source/flint/tui/package.d`: public declarations, UDA definitions and entry points.
- `packages/tui/source/flint/tui/internal.d`: shared non-template state machines and checked arithmetic.
- `packages/tui/tests/contract_tests.d`: behavioral tests identified in section 6.
- `packages/tui/tests/fuzz/`: deterministic seed corpus and bounded fuzz entry points; no fuzz data downloaded at test time.

The public surface defaults to `@safe`. Pointer arithmetic and native handle conversions are confined to those reviewed boundaries. This full-D package may allocate where documented. Do not add `@nogc` to an API unless every implementation path and callback has that contract.

## 5. Measured budget contract

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are engineering ceilings, not measured performance claims. Use the fixed runner and sampling procedure in [CI performance budgets](../../docs/CI_PERFORMANCE_BUDGETS.md). Per-package timing excludes rebuilding dependencies; whole-application gates include the selected closure.

| Measurement | Ceiling |
| --- | --- |
| DMD cold / incremental package build | 0.90s / 0.60s |
| LDC cold / incremental package build | 5.40s / 2.70s |
| Incremental stripped linked bytes | 262144 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instantiations in the package fixture | 2000 |

Compile regression >10% or binary growth >5% fails independently of these hard ceilings. Native dependencies and final shared-library closure are reported separately and counted in the application deployment metric; they are never hidden by quoting only D wrapper size.

Required benchmark: Replay 10,000 model transitions at 80x24 and 200x60. Record rendering p50/p99, bytes emitted, allocations/frame and idle CPU. A one-cell ASCII mutation must emit less than 64 terminal bytes excluding initial setup.

## 6. Acceptance, edge cases and required tests

| Test ID | Stimulus | Required result |
| --- | --- | --- |
| TUI-01 | Same model and same terminal size rendered twice | Second diff emits zero cell updates. |
| TUI-02 | One character changes, including a width-2 grapheme | Only affected cells repaint; stale wide-cell continuation is cleared. |
| TUI-03 | Terminal resize during slow command | One full repaint; command event returns to the same UI thread. |
| TUI-04 | 257 submissions with maxPendingCommands=256 | Last submission fails without unbounded allocation or dropped key input. |
| TUI-05 | quit while workers run and while terminal input blocks | Shutdown completes within the 2s grace budget and restores terminal. |
| TUI-06 | Application retains a Frame past view | Later mutation returns invalidArgument; stale storage is never touched. |

The following is a real D test/usage fixture to place in the package tests. Runtime assertions become passing only after the specified implementation exists:

```d
import flint.tui : Event, EventKind, Effects, Frame, run;
struct Counter {
    uint count;
    void update(Event event, ref Effects effects) @safe {
        if (event.kind == EventKind.interrupt) effects.quit();
    }
    void view(ref Frame frame) const @safe {
        auto error = frame.put(0, 0, "Counter");
    }
}
int demo() @safe { Counter model; return run!Counter(model); }
```

For parser/codec boundaries fuzz every length from 0 through 256, then 1KiB/1MiB boundary seeds; reject overflows before allocation. Run a 60-second ASan smoke on every PR and a 30-minute corpus job nightly. A platform-specific test is required on the platform that owns the native boundary; a Linux compile-only job does not count as a Windows runtime pass.

From the implementation repository root:

```sh
dub test :tui --compiler=dmd
dub test :tui --compiler=ldc2
python3 tools/gates.py --package tui --gate structural
```

Do not mark this package complete until behavioral fixtures, compile-fail safety fixtures, the package budget fixture and all applicable native/WASM jobs pass. A declaration-only typecheck is API verification, not a package acceptance result.

## 7. Primary sources

- https://github.com/charmbracelet/bubbletea
- https://dlang.org/spec/traits.html
