# flint:widgets — implementation specification

Catalogue tier 4. Research cut: 2026-11-21. This file specifies implementation work; declarations in contracts are type-checking interfaces, not runtime implementations.

## 1. Purpose and reference parity

Implement reusable, bounded terminal components on the shared TUI event and rendering contract.

- [ ] Text input, password masking, multiline textarea, scrollable viewport.
- [ ] Filterable list and table with stable item IDs and keyboard navigation.
- [ ] Progress bar, spinner and paginator.
- [ ] Every widget works as part of an application model without owning the process event loop.

## 2. Exact package recipe and dependency boundary

Write this recipe to `packages/widgets/dub.sdl` in the implementation repository:

```sdl
name "widgets"
description "Flint widgets subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:tui" version="*"
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

Allowed direct Flint dependencies: `flint:arena`, `flint:tui`, `flint:style`. The canonical allowlist is [packages.json](../../scaffold/policy/packages.json). Importing a higher catalogue tier or an unlisted same-tier package fails Gate 2.

## 3. Public D contract

Canonical declaration module: [flint.widgets](../../contracts/source/flint/widgets.d). These exact signatures are compiled with DIP1000. Implement the declarations with the semantics below; do not put unresolved declaration stubs into production artifacts.

```d
module flint.widgets;
import flint.tui : Frame, Effects, Event;
import flint.arena : Error;

@safe:
struct TextInput
{
    string value;
    string placeholder;
    bool password;
    uint maxBytes = 4096;
    void update(Event event, ref Effects effects);
    Error view(ref Frame frame, uint column, uint row, uint width) const;
}

struct TextArea
{
    string value;
    uint maxBytes = 1048576;
    void update(Event event, ref Effects effects);
    Error view(ref Frame frame, uint column, uint row, uint width, uint height) const;
}

struct ListItem
{
    ulong id;
    string label;
    bool disabled;
}

struct List
{
    ListItem[] items;
    size_t selected;
    string filter;
    void update(Event event, ref Effects effects);
    Error view(ref Frame frame, uint column, uint row, uint width, uint height) const;
}

struct Column
{
    string title;
    uint width;
}

struct Table
{
    Column[] columns;
    string[][] rows;
    size_t selected;
    void update(Event event, ref Effects effects);
    Error view(ref Frame frame, uint column, uint row, uint width, uint height) const;
}

struct Viewport
{
    string text;
    size_t firstLine;
    void update(Event event, ref Effects effects);
    Error view(ref Frame frame, uint column, uint row, uint width, uint height) const;
}

struct Progress
{
    double fraction;
    Error view(ref Frame frame, uint column, uint row, uint width) const;
}

struct Spinner
{
    uint frame;
    void tick();
    Error view(ref Frame frame, uint column, uint row) const;
}

struct Paginator
{
    size_t page;
    size_t pageCount;
    Error view(ref Frame frame, uint column, uint row) const;
}
```

## 4. Internal architecture, ownership and safety

1. Each widget owns its state and exposes update and view. view is const and returns errors for out-of-bounds geometry. A common geometry helper clips cells to Frame dimensions.
2. Text cursor movement, backspace, selection and truncation operate on grapheme boundaries, using style width/segmentation. TextInput caps UTF-8 bytes at 4096 and TextArea at 1MiB by default; paste truncation never splits a grapheme.
3. Filter list by deterministic case-folded Unicode text; normalization/case-folding is delegated to pinned Unicode helpers. Preserve selected stable id if visible; otherwise select first enabled visible item. Disabled items cannot be submitted.
4. Table rows are read-only snapshots during view, stable selection uses row identity in the application, and the widget renders only visible rows. A million-row dataset must not be scanned per frame when filter text is unchanged.
5. Progress rejects NaN/infinity at its internal validation boundary and clamps finite values to [0,1]. Paginator.pageCount=0 yields an empty state with page=0. Spinner only advances on explicit tick.
6. Password display is masking only; secure ownership belongs to flint.prompt.Secret. Never claim string storage inside TextInput is securely zeroed. No terminal output is emitted by update; all output goes through Frame in view.

### Concrete implementation files

- `packages/widgets/source/flint/widgets/package.d`: public declarations, UDA definitions and entry points.
- `packages/widgets/source/flint/widgets/internal.d`: shared non-template state machines and checked arithmetic.
- `packages/widgets/tests/contract_tests.d`: behavioral tests identified in section 6.
- `packages/widgets/tests/fuzz/`: deterministic seed corpus and bounded fuzz entry points; no fuzz data downloaded at test time.

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

Required benchmark: Benchmark list filtering separately from cached rendering. Record view latency for 20 visible rows from 1K/1M total rows and text editing at the 1MiB textarea cap. Require frame outputs to match golden terminal cell snapshots.

## 6. Acceptance, edge cases and required tests

| Test ID | Stimulus | Required result |
| --- | --- | --- |
| WIDGET-01 | Backspace an emoji ZWJ sequence and a combining sequence | Delete one grapheme, not one byte or scalar fragment. |
| WIDGET-02 | Paste at 4096-byte limit and within a multibyte character | Accept complete graphemes only; bytes never exceed cap. |
| WIDGET-03 | Filter removes selected item; all remaining items disabled | Deterministic empty/no-selection state; Enter does not submit a disabled item. |
| WIDGET-04 | Table with empty columns, short rows and oversized cell | Stable clipping/padding; no bounds access. |
| WIDGET-05 | Progress -1, 2, NaN; paginator zero pages | Clamped finite output or invalidArgument; no division by zero. |
| WIDGET-06 | Million-row table with 20 visible rows | Render visits O(visible rows), confirmed by instrumentation. |

For parser/codec boundaries fuzz every length from 0 through 256, then 1KiB/1MiB boundary seeds; reject overflows before allocation. Run a 60-second ASan smoke on every PR and a 30-minute corpus job nightly. A platform-specific test is required on the platform that owns the native boundary; a Linux compile-only job does not count as a Windows runtime pass.

From the implementation repository root:

```sh
dub test :widgets --compiler=dmd
dub test :widgets --compiler=ldc2
python3 tools/gates.py --package widgets --gate structural
```

Do not mark this package complete until behavioral fixtures, compile-fail safety fixtures, the package budget fixture and all applicable native/WASM jobs pass. A declaration-only typecheck is API verification, not a package acceptance result.

## 7. Primary sources

- https://github.com/charmbracelet/bubbles
- https://www.unicode.org/reports/tr29/
