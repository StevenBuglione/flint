# Serde

[`flint.serde`](source/flint/serde/package.d) implements the [Serde contract](../../handoff/specs/tier-1/serde.md) for bounded JSON, TOML, and a deterministic JSON Schema subset. The shared field descriptors apply rename, ignore, required, default, and flatten metadata. Compile-time validation checks conflicting annotations, duplicate effective names, invalid defaults, and unsupported mapped types.

The hot decoders validate input before committing a DTO or copying text into the request arena. JSON performs a sizing pass when the output contains arena handles. TOML indexes tokens before binding them. The arena preflight accounts for the full set of decoded bytes and preserves earlier allocations after capacity or syntax errors. Inputs stay borrowed for the duration of the call.

JSON and TOML read finite IEEE 754 binary32 and binary64 numbers using locale-independent decimal conversion. Encoders emit deterministic exact decimal values, including signed zero. TOML also supports explicit infinity and NaN, tagged local calendar values, dotted keys, inline tables, arrays of tables, and multiline strings. The BetterC TOML parser uses a fixed index of 1,536 nodes, including the document root, in addition to its configured size, nesting, and member limits.

## Native adapters

[`flint.serde.owned`](source/flint/serde/owned.d) supplies GC-owned JSON and TOML startup decoders. `readTomlEntries` supplies decoded key paths, normalized JSON values, and key byte offsets for configuration precedence. In that view, calendar values become JSON strings and an empty table becomes `{}`. JSON normalization requires values expressible as JSON, so a TOML infinity or NaN remains available through the typed TOML decoder.

[`flint.serde.yaml`](source/flint/serde/yaml.d) uses the optional checksum-pinned libyaml 0.2.5 provider. The C shim supplies bounded event views to a scoped D visitor; temporary normalization storage is freed before return. The data profile accepts one document with string keys and supported core scalar tags. It rejects aliases, anchors, custom tags, complex map keys, and duplicate mappings. The encoder emits the JSON-compatible YAML flow form.

## Verification

- The pinned DMD and LDC passed the native DUB tests, portable BetterC fixtures, and the optional libyaml unit and BetterC fixtures.
- The package exercised JSON and TOML byte-for-byte under wasm32 BetterC. The optional libyaml fixture linked with WASI SDK 34.0 and executed under Node’s WASI preview1 host.
- LDC ASan and instrumented C ASan and UBSan verified seeded mutation and ownership tests across the decoders. The native run enabled leak and stack-use-after-return detection.
- Both compilers rejected metadata collisions, invalid defaults, unsupported hot types, and libyaml event and scratch escape fixtures. The generated dependency audit and pinned formatter and scanner passed.
- The native parser accepted 205 valid and rejected 474 invalid TOML 1.0 input fixtures from the upstream `toml-test` v2.2.0 grammar corpus. Separate typed fixtures exercise normalization and round trips.

Exact commands, exits, logs and artifact digests are retained in `artifacts/tasks/m2-serde/results.json` on the development host. The receipt SHA-256 is `e20c39425ee0133d525d43b5e4ee6bd2affc4bb93f2fb284c5834612735c9559`. The toolchain lock SHA-256 is `6a049639e452c0e7b9b98175faf1abff69613bdc2d04e0602e0d71923e6111d6`.

## Probes

From the repository root, run `dub run --root=packages/serde/bench --compiler=ldc2` for the feature workload and `dub run --root=packages/serde/bench/baseline --compiler=ldc2` for its arena-only control. Both execute plain and escaped 64-byte, 1 KiB, and 16 KiB fixtures with observed output checksums and per-case arena peaks. The feature also instantiates and exercises schemas with 8, 32, and 128 fields.

Local ThinLTO feature-minus-control size deltas were 65,816 stripped bytes at O3 and 41,240 at Oz. Cross-platform acceptance and designated-runner release measurements are pending.
