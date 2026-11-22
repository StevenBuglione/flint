# flint:serde — implementation specification

Status: normative design for agents; contract declarations have been syntax checked. Runtime behavior below is an acceptance requirement, not a claim that a framework implementation already exists. The compiler receipt is [core-contracts.json](../../verification/core-contracts.json).

## 1. Purpose and reference parity

Generate bounded typed JSON/TOML conversion and JSON Schema from DTOs, with a separate optional YAML C adapter and an explicit native-owned decoding adapter.

- [ ] Jackson-style field rename, ignore, required/default and flatten metadata; typed struct mapping without runtime reflection.
- [ ] JSON and TOML encoding/decoding, strict limits, duplicate-key policy and caller-supplied memory.
- [ ] JSON Schema for DTOs; full-D owned string adapter; optional libyaml-backed YAML events rather than a bespoke YAML engine.

## 2. Package boundary and exact DUB recipe

Catalog tier: **1**. Direct allowed Flint dependencies: **flint:arena**. No transitive import is an excuse to add a direct import without updating the dependency policy. Production code may not depend on flint:test. Recipe path: `packages/serde/dub.sdl`, invoked from the monorepo root.

```sdl
name "serde"
description "Flint serde subpackage"
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

These are concrete signatures in the contract fixture, not executable implementations. Internal representation may change while preserving signatures and semantics. Source: `contracts/source/flint/serde/package.d`.

```d
/// Public API contract; declarations are not runtime implementations.
module flint.serde;
import flint.arena : Error, Result, Buffer, Text, RequestArena;

@safe:
struct JsonName
{
    string value;
}

struct JsonIgnore
{
}

struct JsonDefault
{
    string value;
}

struct JsonRequired
{
}

struct JsonFlatten
{
}

struct TomlDate
{
    ushort year;
    ubyte month;
    ubyte day;
}

struct TomlTime
{
    ubyte hour;
    ubyte minute;
    ubyte second;
    uint nanosecond;
}

struct TomlDateTime
{
    TomlDate date;
    TomlTime time;
    short offsetMinutes;
    bool hasOffset;
}

enum UnknownFields
{
    reject,
    ignore
}

struct DecodeOptions
{
    uint maxDepth = 64;
    uint maxMembers = 1024;
    size_t maxBytes = 1048576;
    UnknownFields unknownFields = UnknownFields.reject;
    bool rejectDuplicateKeys = true;
}

struct EncodeOptions
{
    bool canonical = false;
    bool omitIgnored = true;
    uint maxDepth = 64;
}

Error decodeInto(T)(scope const(ubyte)[] input, ref T destination, ref scope RequestArena arena,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc;
Result!Buffer encodeJson(T)(scope const ref T value, ref scope RequestArena arena,
        EncodeOptions options = EncodeOptions.init) nothrow @nogc;
Error decodeTomlInto(T)(scope const(ubyte)[] input, ref T destination, ref scope RequestArena arena,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc;
Result!Buffer encodeToml(T)(scope const ref T value, ref scope RequestArena arena,
        EncodeOptions options = EncodeOptions.init) nothrow @nogc;
Result!Buffer jsonSchema(T)(ref scope RequestArena arena) nothrow @nogc;
```

## 4. Internal architecture, ownership and safety

Core `flint.serde` lives in `flint/serde/package.d`, allowing `flint.serde.owned` and `flint.serde.yaml` alongside it. Export no startup/runtime adapter from package.d. JSON decoding is an iterative token scanner with a fixed-depth stack and checked integer/UTF-8 paths; it neither allocates an intermediate GC object tree nor uses std.json. Compile one field-name lookup table and one typed binder per DTO. Reject duplicate JsonName values, contradictory required/default annotations and flatten-name collisions at compile time. Support scalars, enums, fixed arrays and nested structs in the hot profile. Bounded variable-length collections are explicit handles/counts; do not smuggle D resizable arrays into BetterC.

`decodeInto` copies decoded text and variable byte content into the arena and writes `Text`/Buffer handles into the DTO. `string` or ordinary dynamic-array output fields are a compile-time error in the hot decoder. The native `deserialize!T` adapter creates owned GC strings/arrays and is allowed only at startup or in a worker profile. Encoding may read owned strings as input while retaining no reference. Handle fields are read against the same live arena; invalid owner/epoch returns an Error. Decode failure leaves the destination equal to its original value: use a temporary DTO and a saved arena cursor, committing only after complete input acceptance. Existing handles/allocations before the decode attempt remain valid on rollback.

JSON uses RFC 8259 syntax: strict UTF-8, complete input consumption, invalid surrogate rejection, finite numeric values, checked integer range and consistent negative-zero behavior. Defaults are compile-time JSON literals converted to the target field type; no expression evaluation. Limits are 1 MiB input, depth 64, 1024 members per object and fixed error messages with offsets. JsonSchema emits a deterministic supported subset of JSON Schema 2020-12: type/properties/required/items/enum/minimum/maximum/minLength/maxLength/additionalProperties. Do not emit a schema keyword unless runtime validation implements it.

TOML uses version 1.0 semantics, including duplicate table/key rejection, dotted keys, numeric syntax and multiline strings. Date/time values bind to explicit tagged value structs, not timezone-dependent local time. Unsupported target field mapping is a compile-time error. JSON/TOML encoders share typed field descriptors and bounded byte writer; `encodeToml` uses the same Buffer/arena contract. TOML 1.0 is a deliberate compatibility target; newer TOML syntax is rejected until a separately reviewed parser upgrade.

YAML is an explicit import of `flint.serde.yaml` over the pinned libyaml C API. It rejects application-defined tags, all alias/anchor expansion, duplicate mapping keys and documents beyond the same depth/size budgets. This adapter implements a safe YAML data profile rather than YAML object deserialization. libyaml may allocate with C malloc: `@nogc` does not mean allocation-free. Native YAML and separately built WASM YAML can use the same C adapter, but YAML is excluded from the 100 KB browser core. No YAML adapter is linked merely by importing JSON. A native `-betterC` link test and a WASM link test are required when enabling that optional profile.

**Safety boundary:** Core scanning, field matching, writing and DTO binding are `@safe nothrow @nogc` and BetterC-compatible. Unsafe calls are only in optional `flint.serde.ffi` bindings with matching safe facade. No dynamic runtime type inspection.

## 5. Compile-time, size and runtime budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are release gates on the designated reference runner, not observed performance results. Measure the package's fixed feature fixture, with dependencies frozen; cold/incremental definitions and statistical regression rules come from [CI budgets](../../docs/CI_PERFORMANCE_BUDGETS.md).

| Metric | Hard ceiling |
| --- | ---: |
| DMD cold build | 0.80 s |
| DMD incremental build | 0.60 s |
| LDC cold build | 4.80 s |
| LDC incremental build | 2.40 s |
| Marginal stripped linked bytes | 262,144 bytes |
| Compiler peak RSS | 536,870,912 bytes |
| Template instantiations | 2,000 |

The >10% compile/template/RSS regression rule and >5% binary growth rule also apply; passing a hard ceiling does not permit silent drift. Marginal size follows the provider-equivalent definition above; full native-provider and dependency footprints remain in the recorded complete binaries. Package deltas are not summed to estimate an application. Native shared-library bytes and static-dependency bytes must both be reported. BetterC core: **required; native and wasm32 profiles**.

**Benchmark fixture:** Use fixed 64-byte, 1 KiB and 16 KiB fixtures; measure bytes/sec, arena high-water mark and ns/field. Test strings needing escaping and not needing escaping separately. Compare schema/serde generation at 8/32/128 fields; unbounded recursive templates are forbidden.

## 6. Required acceptance tests and edge cases

1. RFC JSON corpus: escaped Unicode/surrogate pairs, invalid UTF-8, duplicate fields, embedded NUL, depth/byte/member limits, trailing garbage, large integers and negative zero.
2. Fuzz encode/decode roundtrip for every supported DTO shape and feed malformed bytes into each decoder under ASan.
3. Destination and prior arena allocations unchanged after every injected parse/allocation failure.
4. Compile-fail duplicate rename, flatten collision, unsafe type, hot output string/dynamic array and unknown UDA combinations.
5. JSON/TOML config fixtures preserve canonical values; YAML alias bomb/custom tag/duplicate map rejected before materialization.

Every listed case becomes a named unittest or a compiler-negative fixture, with a deterministic seed for generated schedules/inputs. FFI/kernel lifetime tests run under the platform sanitizer jobs. Add regression fixtures for every corrected failure before closing the slice.

## 7. Agent implementation order and definition of done

1. Add the package modules and public declarations, compile the positive contract usage and the negative misuse fixtures, then implement the smallest deterministic behavior covered by the first acceptance group.
2. Complete ownership/error paths before adding throughput optimization; include bounded-resource exhaustion tests.
3. Add the fixed benchmark fixture, record raw samples and candidate baseline receipts, and complete all acceptance groups before activating this package for integration.

Run from `scaffold/` after implementing this package:

```bash
python3 tools/flint.py test --package serde --compiler dmd
python3 tools/gates.py --package serde --gate structural
```

The direct test equivalent is `dub test :serde --compiler=dmd`. Repeat with `--compiler ldc2` through the orchestrator. A declaration-only contract pass is never a substitute for `dub test` on a runtime implementation. Full Gates 1–6 run for the integrated milestone once its canonical apps and runner baselines exist; absence of a required measurement blocks release rather than fabricating a zero measurement.

## Evidence and rationale

The D capability behind this design is documented at [https://dlang.org/spec/betterc.html](https://dlang.org/spec/betterc.html) (accessed 2026-11-21). Normative limits, failure codes and ownership policies above are Flint design decisions. See [core research evidence](../../research/core-sources.md) for precise capability claims and verification boundaries.

## Optional public adapters

```d
/// Native startup/worker adapter; intentionally uses D GC.
module flint.serde.owned;
import flint.arena : Result;
import flint.serde : DecodeOptions;

@safe:
Result!T deserialize(T)(scope const(char)[] input, DecodeOptions options = DecodeOptions.init);
```

```d
/// Optional libyaml adapter contract; requires the pinned C archive.
module flint.serde.yaml;
import flint.arena : Error, Result, Buffer, RequestArena;
import flint.serde : DecodeOptions, EncodeOptions;

@safe:
Error decodeYamlInto(T)(scope const(ubyte)[] input, ref T destination, ref scope RequestArena arena,
        DecodeOptions options = DecodeOptions.init) nothrow @nogc;
Result!Buffer encodeYaml(T)(scope const ref T value, ref scope RequestArena arena,
        EncodeOptions options = EncodeOptions.init) nothrow @nogc;
```

