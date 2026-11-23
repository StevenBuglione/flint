# Milestone 13, Phase 0: binary-size levers

ADR-030 section 5 adds two size levers and a size gate, landed before the Spring port adds thousands of classes:

1. RELR packed relocations for Linux glibc PIE outputs.
2. Collectable classes: `ModuleInfo.localClasses` left empty.
3. Per-module linked-bytes budgets.

All numbers below were measured on venus (Linux x86-64, Ubuntu glibc 2.39, GNU ld 2.42, mold 2.30.0, LDC 1.43.0, the DMD 2.114.0 fork). Sizes are stripped executable bytes, which are deterministic, so they do not depend on machine load.

## 1. RELR packed relocations

**What changed.**
- Each profile in `policy/profiles.toml` gains `glibc_lflags`. The dev, test, release and size profiles set it to `["-z", "pack-relative-relocs"]`.
- `flint build` adds these flags only for the host's native build on `linux-*-glibc` (`linksGlibcPie`). musl cross builds, macOS and Windows never get them.
- `tools/profiles.py` (`link_dflags`) applies the same flags for `measure_builds.py`, `measure_dev_builds.py` and the flint bootstrap.
- The sanitize profile keeps the default relocation format.
- DMD builds reach the fork's direct link as `-Xlinker` arguments, which it passes to mold or ld unchanged, so the DMD patch needs no change for RELR.

**Sizes.** Measured with `tools/measure_builds.py --app-sizes` (the release O3 and size Oz profiles, LDC with ThinLTO, stripped). `--apps-only` measures compile time only, so this run adds the size-only mode.

| App | Profile | Before | RELR | Saved |
| --- | --- | ---: | ---: | ---: |
| bench-cli | O3 | 1,294,032 | 1,146,648 | 147,384 (11.4%) |
| bench-cli | Oz | 1,212,352 | 1,064,968 | 147,384 (12.2%) |
| bench-rest | O3 | 6,670,024 | 5,904,144 | 765,880 (11.5%) |
| bench-rest | Oz | 6,620,872 | 5,854,992 | 765,880 (11.6%) |

Measured at `42f86d6` (before), `fa7437d` (RELR) and `cd9caff` (no localClasses) on base `966c4b7`. The same changes landed on `main` as `13d5d62`, `3eef2dc` and `fd4c5c5`, after rebasing. A re-measurement on top of `main` at `b6758fe` gives identical sizes.

**Hardening is unchanged.** Every output stays `DYN (Position-Independent Executable)` with `FLAGS BIND_NOW`, `FLAGS_1 NOW PIE` and a `GNU_RELRO` segment, and gains `.relr.dyn` plus a `GLIBC_ABI_DT_RELR` version need. bench-rest's 32,310 `R_X86_64_RELATIVE` entries (24 bytes each, 775,440 bytes) become 10,488 bytes of RELR.

**Start-up and the REST suite.**
- **REST suite.** `tools/load_bench.py --smoke` passed against the final bench-rest (RELR plus no localClasses) and the Go reference, with every response checked before load. It is a harness check, not performance evidence.
- **Start-up time is queued, not measured.** About ten sessions were building on venus, so timings taken then are not evidence. The proof-harness session's measurement queue runs it in a quiet window: wall time from exec to the first correct `GET /json`, for bench-rest at 13d5d62 against 3eef2dc, interleaved.
- **Relocations.** With RELR, the dynamic loader processes 4 relative relocations instead of 32,282 (`LD_DEBUG=statistics`). An unquiet 10-run check gave a median of 9.15 ms before and 9.14 ms with RELR.
- **DMD dev builds.** A canonical `flint build --verify` of flint itself, on the verified toolchain configured with `--dmd-linker mold`, links through the fork's direct mold link with RELR, `BIND_NOW` and `GNU_RELRO`.

**musl, measured separately.** `linux-x86_64-musl` static-PIE builds keep the default format. A relative measurement used the pinned Alpine 3.22 runtime and sysroot, with bench-cli and bench-rest built without native providers:

| App | Profile | musl | musl + RELR | Saved |
| --- | --- | ---: | ---: | ---: |
| bench-cli | O3 | 1,391,384 | 1,244,000 | 147,384 |
| bench-cli | Oz | 1,322,008 | 1,174,624 | 147,384 |
| bench-rest | O3 | 1,136,232 | 988,848 | 147,384 |
| bench-rest | Oz | 1,128,040 | 984,752 | 143,288 |

musl 1.2.5 relocates RELR in static-PIE executables, and the RELR bench-cli runs. Whether musl outputs adopt it is an open decision in ADR-030.

## 2. Collectable classes

**Why.** Each module's `ModuleInfo` lists every class it declares, which keeps every `TypeInfo_Class`, vtable and virtual method referenced. `--gc-sections` can then never drop an unused class.

**LDC.** LDC 1.43 has `-fno-moduleinfo-localclasses` upstream, so it needs no patch. The release and size profiles now pass it. This settles ADR-030's open decision on patching LDC.

**DMD fork.** `toolchain/dmd-2.114.0-flint.patch` adds the same switch, opt-in, about 20 lines:
- `dmd/mars.d` parses it;
- `dmd/glue/package.d` skips `getLocalClasses` in `genModuleInfo`.

druntime needs no change. `Object.factory` and `TypeInfo_Class.find` walk the lists, so they return null for classes of modules compiled with the switch. DMD itself never passes `--gc-sections`, and the release `dmd.conf` adds `--export-dynamic`, which roots every symbol. A DMD build therefore gains only with both changed. The dev profile keeps them, because druntime's backtraces name functions through the dynamic symbol table.

**Class-heavy fixture.** `tools/measure_class_gc.py` generates 2,000 final classes with three virtual methods each, in 40 modules. `main` instantiates 50 of them and throws and catches one exception, so exception handling is checked under `--gc-sections`. Every build prints the same result.

| Build | With localClasses | Without | Saved |
| --- | ---: | ---: | ---: |
| DMD fork, as configured (no `--gc-sections`, `--export-dynamic`) | 3,160,248 | 3,096,216 | 64,032 (2%) |
| DMD fork, `--gc-sections`, no `--export-dynamic` | 2,065,296 | 407,664 | 1,657,632 (80%) |
| LDC release (O3, ThinLTO) | 2,463,152 | 486,016 | 1,977,136 (80%) |
| LDC size (Oz, ThinLTO) | 2,463,152 | 486,016 | 1,977,136 (80%) |

Every build printed `1407979150736`. Command: `python3 tools/measure_class_gc.py --dmd .tools/dmd2/linux/bin64/dmd --ldc ldc2` (the installed fork, linking through mold).

**Apps.**

| App | Profile | RELR | RELR + no localClasses | Saved |
| --- | --- | ---: | ---: | ---: |
| bench-cli | O3 | 1,146,648 | 1,146,648 | 0 |
| bench-cli | Oz | 1,064,968 | 1,064,968 | 0 |
| bench-rest | O3 | 5,904,144 | 5,904,112 | 32 |
| bench-rest | Oz | 5,854,992 | 5,854,960 | 32 |

Today's apps barely move. Flint's engines are struct-based, and the prebuilt druntime and Phobos keep their own class lists. The lever is for the Spring port's class-heavy API: the fixture shows about 1 KB saved per unused class. Rebuilding the runtime libraries with the switch is an open decision in ADR-030.

## 3. Size gate

`policy/budgets.json` gains `module_linked_bytes`, validated by `tools/module_budgets.py`:
- `modules` maps a Flint module to a fixture, a baseline and a `linked_bytes` budget.
- `required_packages` lists packages whose every module must have a budget.

The pieces that use it:
- `tools/gates.py --gate structural` validates the policy.
- `tools/measure_builds.py` measures each module's O3/Oz stripped-size delta, as for packages.
- `tools/collect_evidence.py` checks the delta against the retained size observations.
- `tools/gates.py` fails a module over its budget, or one that grew past `binary_ratio_max` against the base commit.

Both lists start empty. The first flint-framework module that lands adds its entry, and its package joins `required_packages`. `tools/test_guards.py` covers the policy and the measured checks.

## Verification

On venus, against the private toolchain at `<worktree>/.tools`, installed with `flint toolchain install --dmd-linker mold`: the DMD fork from this patch, with PGO, plus LDC 1.43.0. The shared `.tools` was not modified.

- **Toolchain receipt.** `flint toolchain verify` reports "fork installed, receipt verified" (dmd patch `d2daebdf…`, dub patch `ff313ae7…`).
- **Package suites.** `dub test :<package> --build=unittest --force` passes for all 37 packages with DMD and with LDC, which is 74 runs, using the ci native profile.
  - `wasi` needs Wasmtime, which is in the `wasm-host` profile rather than `ci`. After `native_build.py --profile wasm-host` it passes on both compilers.
- **flint's own unit tests.** `flint test -C apps/flint --compiler both` passes, 21 modules on each compiler. This build uses the test profile, so its binaries carry RELR.
- **Gates.** `tools/gates.py --gate structural` passes for 37 packages.
- **Quality.**
  - `tools/quality.py` passes: 829 files, 0 issues.
  - `tools/test_guards.py` passes (30 tests) and `tools/test_evidence.py` passes.
  - The relevant `tests/` modules pass: `test_flint_cli`, `test_flint_toolchain`, `test_install_toolchains`, `test_package_templates` and `test_conan_index`.
- **Patch.** `toolchain/dmd-2.114.0-flint.patch` applies with `patch -p1 --forward` to the pinned release's `dmd2/src/dmd`. The result is identical to applying the change by hand onto the dmd-arm64 session's latest patch.
- **mold.** mold 2.30.0 was installed with apt for the direct-mold path. GNU ld 2.42 links the LDC profiles.

Commands, for reproducing:

```bash
python3 tools/measure_builds.py --app-sizes --output <dir>/result.json
python3 tools/measure_class_gc.py --dmd .tools/dmd2/linux/bin64/dmd --ldc ldc2 --output <dir>/class-gc.json
python3 tools/gates.py --gate structural
flint toolchain verify
```
