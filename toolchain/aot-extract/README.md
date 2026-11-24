# Native Flint AOT extraction: parity and timing evidence

`parity.py` checks the DMD fork's `-flint-aot-extract` against the CTFE describer in
`apps/flint/src/flint_tool/engine/aot/extract.d`, which remains the normative definition of the model. For each
set, it compiles the same modules with the same flags twice, once through a describer root and once through the
native switch, and compares the `FLINT-AOT-*` lines byte for byte, order included. It is evidence, not a gate.
The regression fixture lives in `tests/test_flint_toolchain.py` (`AotExtractionTests`).

```bash
python3 toolchain/aot-extract/parity.py all                    # every set below; exit status 1 on a difference
python3 toolchain/aot-extract/parity.py run <app> [--prelude-modules | --modules a,b] [--src DIR --like APP]
python3 toolchain/aot-extract/parity.py timing benchmarks/spring/flint/petclinic-rest
```

- **Flags.** Each app's flags and known annotation types come from one cold `flint build` under `strace -f`, run with
  the compile server off so the trace ends with the build. This needs Linux and `strace`. The capture is kept in
  `.flint/aot-parity/<app>/capture.json`; `parity.py capture <app>` refreshes it.
- **`tests/aot` fixtures.** They take petclinic-rest's flags and known types and put their own sources first on the
  import path.
- **Excluded module.** The platform set is petclinic-rest's compile-server prelude without
  `flint.arena.sys.gc.counting`, on which the describer itself fails.
- **Failing compiles.** When both compiles fail, the set counts as matching if the first error is the same once its
  location is removed. The describer may print lines for the modules before the error, and the native walker
  prints nothing (it runs only after a clean semantic2). A failed extraction is an error either way.

## Results

Fork built from `toolchain/dmd-2.114.0-flint.patch` (sha256 `8466554b…`), on venus (Linux x86-64, PGO build),
2026-11-24. In-process compiles (`FLINT_DMD_SERVER=0`):

| Set | Modules | Lines | Result | Describer ms | Native ms |
| --- | --- | --- | --- | --- | --- |
| petclinic-rest-platform | 395 | 2444 | identical | 5038 | 339 |
| petclinic-rest | 15 | 111 | identical | 392 | 130 |
| gs-rest-service | 1 | 4 | identical | 88 | 81 |
| gs-relational-data-access | 1 | 3 | identical | 95 | 92 |
| tests-aot-annotations | 23 | 85 | identical | 55 | 10 |
| tests-aot-autoconfig | 1 | 4 | identical | 78 | 75 |
| tests-aot-date | 3 | 7 | identical | 84 | 82 |
| tests-aot-diagnostics | 1 | 0 | both fail, same first error | 27 | 24 |
| tests-aot-exporter | 1 | 2 | both fail, same first error | 79 | 76 |
| tests-aot-gs-rest-service | 3 | 7 | identical | 90 | 82 |
| tests-aot-hierarchy | 3 | 8 | both fail, same first error | 91 | 78 |
| tests-aot-imports | 3 | 12 | identical | 91 | 78 |
| tests-aot-petclinic-rest | 9 | 29 | identical | 128 | 91 |
| tests-aot-sample | 6 | 0 | both fail, same first error | 28 | 27 |

Cold (`parity.py all --cold`: no known annotation types, as a cold build's extraction has none, so every annotation type reached is announced and its position compared), after the announcement-order fix below:

| Set | Modules | Lines | Result | Describer ms | Native ms |
| --- | --- | --- | --- | --- | --- |
| cold-petclinic-rest-platform | 397 | 2494 | identical | 5202 | 347 |
| cold-petclinic-rest | 15 | 153 | identical | 474 | 136 |
| cold-gs-rest-service | 1 | 21 | identical | 94 | 75 |
| cold-gs-relational-data-access | 1 | 13 | identical | 100 | 89 |
| cold-tests-aot-annotations | 23 | 92 | identical | 51 | 10 |
| cold-tests-aot-autoconfig | 1 | 12 | identical | 85 | 73 |
| cold-tests-aot-date | 3 | 23 | identical | 92 | 74 |
| cold-tests-aot-diagnostics | 1 | 0 | both fail, same first error | 25 | 26 |
| cold-tests-aot-exporter | 1 | 3 | both fail, same first error | 78 | 72 |
| cold-tests-aot-gs-rest-service | 3 | 23 | identical | 90 | 85 |
| cold-tests-aot-hierarchy | 3 | 20 | both fail, same first error | 88 | 79 |
| cold-tests-aot-imports | 3 | 25 | identical | 90 | 75 |
| cold-tests-aot-petclinic-rest | 9 | 57 | identical | 129 | 100 |
| cold-tests-aot-sample | 6 | 0 | both fail, same first error | 30 | 29 |

Served through the compile server (`parity.py timing`, petclinic-rest's 15 modules, median of 7 after two warm-ups):

| Root | With the platform prelude | Without |
| --- | --- | --- |
| Imports only (the floor) | 20.3 ms | 85.3 ms |
| Native (`-flint-aot-extract`) | 30.8 ms | 94.6 ms |
| Describer | 282.9 ms | 348.9 ms |

The rules runs found. flint-aot's cold parity found the first: the describer announces an annotation type when the compiler analyses `annotationValue!T`, which happens when `value!F` for a field type is analysed, whatever the value. So an empty `ClassRef[]` default announces `ClassRef` before the annotation it belongs to. The walker now reaches annotation types by type, as that analysis does. The second: until a `shared(ProcessSlot!(…))` field reached the platform closure, the native walker gave a
qualified template instance no `template`, `arguments` or `canonical` fields. The describer's
`is(T == X!Args, alias X, Args...)` matches through every qualifier, so now the walker does too, and the fixture
has `shared` and `const` instances.

The same patch builds on macOS arm64 (pluto: 28 of 28 toolchain tests, the extraction tests included). On Windows
x86-64 (the Windows lane's private clone, with the pinned LDC) it builds at 2d86b2d7, one change before the
qualified-instance fix, and the three extraction tests pass there.
