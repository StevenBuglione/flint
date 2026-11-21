# flint:validate — implementation specification

Status: normative design for agents; contract declarations have been syntax checked. Runtime behavior below is an acceptance requirement, not a claim that a framework implementation already exists. The compiler receipt is [core-contracts.json](../../verification/core-contracts.json).

## 1. Purpose and reference parity

Unroll bounded DTO validation using field UDAs and write deterministic violations into caller-supplied storage.

- [ ] Bean Validation-style NotBlank, Min/Max, Email, Pattern, Size and nested Valid metadata.
- [ ] Validation groups are deliberately absent from the initial public API; explicit DTO types define distinct validation contracts.
- [ ] Zero GC allocation and BetterC operation, including arena-backed Text values.

## 2. Package boundary and exact DUB recipe

Catalog tier: **1**. Direct allowed Flint dependencies: **flint:arena**. No transitive import is an excuse to add a direct import without updating the dependency policy. Production code may not depend on flint:test. Recipe path: `packages/validate/dub.sdl`, invoked from the monorepo root.

```sdl
name "validate"
description "Flint validate subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"

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

The root manifest registers the subpackage path. Fully qualified flint:<name> sibling dependencies resolve in the parent package; do not turn these dependencies into independently fetched registry packages. The recipe and [packages policy](../../scaffold/policy/packages.json) are authoritative.

## 3. Public D API and UDA definitions

These are concrete signatures in the contract fixture, not executable implementations. Internal representation may change while preserving signatures and semantics. Source: `contracts/source/flint/validate.d`.

```d
/// Public API contract; declarations are not runtime implementations.
module flint.validate;
import flint.arena : Error, Text, RequestArena;

@safe:
struct Valid
{
}

struct NotBlank
{
}

struct Min
{
    long value;
}

struct Max
{
    long value;
}

struct Email
{
}

struct Pattern
{
    string value;
}

struct Size
{
    size_t min;
    size_t max;
}

struct Violation
{
    string field;
    string constraint;
    string message;
    uint[8] indexes;
    ubyte indexCount;
}

struct ValidationReport
{
    size_t written;
    size_t total;
    bool valid;
}

ValidationReport validate(T)(scope const ref T value, scope Violation[] output) nothrow @nogc;
ValidationReport validateIn(T)(scope const ref T value, ref scope RequestArena arena, scope Violation[] output) nothrow @nogc;
```

## 4. Internal architecture, ownership and safety

Build a flat constraint descriptor per DTO, with one generated validation routine and precomputed field paths. `validate` operates on ordinary caller-owned values; `validateIn` additionally resolves Text handles through the given arena. Iteration order is declaration order then UDA order. Fill output until its capacity is reached, continue counting up to the hard limit, and report `written`, `total` and `valid` separately. A zero-sized output is a valid counting-only call. Field/constraint/message strings are immutable static literals, not runtime formatting. Nested array paths use static `items[].field` plus up to eight indexes in Violation; do not allocate formatted path strings.

NotBlank uses Unicode 17.0.0 White_Space: U+0009..000D, U+0020, U+0085, U+00A0, U+1680, U+2000..200A, U+2028, U+2029, U+202F, U+205F and U+3000, then requires at least one non-whitespace code point. Size on strings counts Unicode scalar values, not bytes; byte arrays count bytes; numeric Min/Max are checked comparisons in the declared numeric type without unsafe signed conversion. Email is a documented pragmatic ASCII addr-spec validator, maximum 254 bytes, exactly one unquoted @, local part at most 64 bytes, nonempty domain labels of at most 63 characters and no leading/trailing hyphen. Internationalized mailboxes require prior explicit normalization; Email does not claim deliverability or DNS validation.

Pattern is a bounded compile-time Thompson-NFA compiler, not std.regex. Supported syntax is ASCII literals/escapes, dot, character classes with ranges/negation, concatenation, alternation, grouping, anchors, ?, *, + and {m,n}. Reject backreferences, look-around, Unicode property escapes and expression sizes above 256 NFA states at compile time with field-local diagnostics. Matching costs O(input bytes × states), uses fixed work arrays and caps input at 16384 bytes. A full match is required unless the pattern explicitly includes .*; no exponential backtracking. The pattern compiler is a build-time internal module so applications import only generated descriptors.

Reject nonsensical UDA/type combinations at compile time: Min on struct, NotBlank on int, invalid min/max intervals, Pattern on bytes without text semantics, or duplicate contradictory constraints. Nested Valid recursion is bounded at eight collection-index levels and 64 struct depth; recursive type cycles fail generation. Limit total violations to 4096 and set total to 4097 as the overflow sentinel, `valid=false`; the report never silently claims completeness beyond that limit.

**Safety boundary:** All public and generated routines are `@safe nothrow @nogc`. The core requires no C library and no @trusted block. It uses checked Text access via arena callbacks. Compiler-generated static Unicode and pattern tables are immutable.

## 5. Compile-time, size and runtime budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are release gates on the designated reference runner, not observed performance results. Measure the package's fixed feature fixture, with dependencies frozen; cold/incremental definitions and statistical regression rules come from [CI budgets](../../docs/CI_PERFORMANCE_BUDGETS.md).

| Metric | Hard ceiling |
| --- | ---: |
| DMD cold build | 0.35 s |
| DMD incremental build | 0.35 s |
| LDC cold build | 2.10 s |
| LDC incremental build | 1.05 s |
| Marginal stripped linked bytes | 262,144 bytes |
| Compiler peak RSS | 536,870,912 bytes |
| Template instantiations | 2,000 |

The >10% compile/template/RSS regression rule and >5% binary growth rule also apply; passing a hard ceiling does not permit silent drift. Marginal size follows the provider-equivalent definition above; full native-provider and dependency footprints remain in the recorded complete binaries. Package deltas are not summed to estimate an application. Native shared-library bytes and static-dependency bytes must both be reported. BetterC core: **required; native and wasm32 profiles**.

**Benchmark fixture:** Measure 8/32/128-field DTOs in all-valid and all-invalid modes with full and zero output buffers. Pattern cases include a 16 KiB adversarial string; gate linear growth rather than a misleading average on tiny inputs.

## 6. Required acceptance tests and edge cases

1. Empty/ASCII/Unicode whitespace; invalid UTF-8; string scalar versus byte counts; signed minimum, unsigned maximum, NaN and infinity.
2. Email boundaries and pathological invalid input; NFA state limit, nested quantifiers and rejection of backreferences/lookaround.
3. 0/1/N output slots, more violations than capacity, 4096 violation limit and deterministic field ordering.
4. Nested DTO/arrays and wrong arena owner/stale Text handle; invalid handles produce a validation failure, never a dereference.
5. Compile-fail incompatible UDA/type and recursive descriptor cycle; BetterC native and wasm32 object/link checks.

Every listed case becomes a named unittest or a compiler-negative fixture, with a deterministic seed for generated schedules/inputs. FFI/kernel lifetime tests run under the platform sanitizer jobs. Add regression fixtures for every corrected failure before closing the slice.

## 7. Agent implementation order and definition of done

1. Add the package modules and public declarations, compile the positive contract usage and the negative misuse fixtures, then implement the smallest deterministic behavior covered by the first acceptance group.
2. Complete ownership/error paths before adding throughput optimization; include bounded-resource exhaustion tests.
3. Add the fixed benchmark fixture, record raw samples and candidate baseline receipts, and complete all acceptance groups before activating this package for integration.

Run from `scaffold/` after implementing this package:

```bash
python3 tools/flint.py test --package validate --compiler dmd
python3 tools/gates.py --package validate --gate structural
```

The direct test equivalent is `dub test :validate --compiler=dmd`. Repeat with `--compiler ldc2` through the orchestrator. A declaration-only contract pass is never a substitute for `dub test` on a runtime implementation. Full Gates 1–6 run for the integrated milestone once its canonical apps and runner baselines exist; absence of a required measurement blocks release rather than fabricating a zero measurement.

## Evidence and rationale

The D capability behind this design is documented at [https://dlang.org/spec/traits.html#getAttributes](https://dlang.org/spec/traits.html#getAttributes) (accessed 2026-11-21). Normative limits, failure codes and ownership policies above are Flint design decisions. See [core research evidence](../../research/core-sources.md) for precise capability claims and verification boundaries.
