# Milestone 11 · Native macOS arm64

Native macOS arm64 was built on `main`, with each verified stage pushed straight to `main`. It was verified on `pluto`:

- Apple M1 (8 cores), 16 GB;
- macOS 26.4, Xcode 26.6 (Apple clang 21, ld-1267);
- LDC 1.43.0 and the Flint-patched DUB 1.43.0.

It is the macOS track of [ADR-021](../adr/ADR-021-flint-platform.md) section 9, started early at the project owner's request. Decisions and platform differences are recorded in [ADR-024](../adr/ADR-024-macos-arm64.md). The compile-speed work that follows is [ADR-025](../adr/ADR-025-fast-compiles-everywhere.md) section 3.

## What was built

- **Toolchain.**
  - LDC 1.43.0 for macOS arm64.
  - LDC's `ldmd2` fills the dev and test profiles' DMD role, as an interim setting until DMD arm64 lands (ADR-025).
  - The Flint-patched DUB 1.43.0 is built from source with LDC.
  - `flint toolchain install|verify`, `doctor`, `build`, `test` and `check` all work, and `flint` bootstraps itself.
- **All 37 packages** pass `dub test` on `ldmd2` and `ldc2`.
- **The packages that declare fixture peers** in `policy/test-peers.toml` also pass with those peers through `flint test --compiler both`: `ai`, `cache`, `data`, `http`, `mail`, `migrate`, `security`, `sql` and `storage`.
- **The reactor** has a kqueue backend with the epoll backend's semantics, including native descriptor watches.
- **Native providers.** `tools/native_build.py` builds all 17 C providers of the `ci` closure and wasmtime with Apple clang. Flint's C shims build on Darwin; ADR-024 section 4 lists the differences they absorb.
- **Build measurement.** `tools/measure_builds.py` and `tools/compare_go_builds.py` run on pluto against the pinned Go 1.27.4 darwin-arm64.

## Evidence

The platform lane:

```bash
export PATH="$PWD/.tools/dub-1.43.0/bin:$PWD/.tools/ldc2-1.43.0-osx-arm64/bin:$PWD/.tools/bin:$PATH"
python3 tools/ci.py platform --target macos-arm64
```

At `e8be84d` its receipt `artifacts/platforms/macos-arm64.json` records exit code 0 after 400 s. The artifact `macos-arm64.log` has sha256 `1aeacff30a3f6625fdf38dfc7b095d70d38b9fa15112b9cbc711abd42a614d36`. The run covered:

1. the native providers and wasmtime, built or verified from their receipts;
2. 74 `dub test` runs, every package on `ldmd2` and on `ldc2`;
3. 18 peered `flint test` runs, the nine peered packages on both compilers, against PostgreSQL 18.7, Valkey 9.1.2, MinIO and the Go protocol peers;
4. the five compile-negative fixtures and the BetterC fixtures, on both compilers.

`tools/collect_evidence.py` verifies that receipt, so Gate 6's `macos-arm64` entry is true. Gate 6 as a whole still fails while Windows x86-64 has no receipt. As with the other platforms (ADR-017 decision 4), the receipt and its log are kept on the runner rather than committed. Re-run the lane after every rebase, because the receipt is bound to its commit.

## Build performance on pluto

A full `tools/measure_builds.py` production run at `84a8a26` made 1558 timed trials and 152 size trials. App medians:

| App | Dev (`ldmd2`) cold | Dev incremental | Release (LDC `-O3`) cold | Go cold | Stripped `-O3` | Go binary |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `bench-cli` | 1.785 s | 0.377 s | 2.639 s | 0.165 s | 1,236,968 B | 2,631,442 B |
| `bench-rest` | 2.142 s | 0.470 s | 3.077 s | 0.298 s | 5,405,096 B | 6,252,914 B |

`bench-wasm` builds cold in 0.254 s. Its `-O3` output is 8,343 bytes and its `-Oz` output 9,905 bytes.

Flint's binaries are smaller than Go's, but its development builds are far slower. With `ldmd2`, 23 of the 37 packages take longer than 0.90 s to build their probe cold. That figure is the DMD cold ceiling the reactor specification sets, and the per-package ceilings were set for the forked DMD.

The paired comparison (`tools/compare_go_builds.py`, 9 trials) gives the baseline the DMD arm64 work has to beat:

| App | Flint cold | Go cold | Flint edit | Go edit |
| --- | ---: | ---: | ---: | ---: |
| `bench-cli` | 1736 ms | 163 ms | 376 ms | 169 ms |
| `bench-rest` | 2067 ms | 431 ms | 460 ms | 296 ms |

### Where the cold `bench-cli` build spends its 1.7 s

DUB runs eight compiler invocations in sequence, one per library and one for the app, then one link. Timed one at a time, with the front end measured by the same command with `-o-`:

| Phase | Time | Share |
| --- | ---: | ---: |
| Front end (8 invocations) | 0.97 s | 58% |
| Code generation and archiving | 0.55 s | 33% |
| Link (Apple ld-prime) | 0.16 s | 9% |
| DUB itself | about 0.1 s | |

Findings for ADR-025:

- **Parallel compilation is the largest available gain.** Running the eight compiles concurrently on the 8 cores, then linking, takes 0.67 s against 1.65 s sequentially. That is what the fork's DUB pipeline does on Linux. On macOS the pipeline is off only because its in-process archiver writes the GNU format. A Darwin archiver (ADR-025 section 3, stage 3) would give `ldmd2` builds most of that gain, before DMD arm64 exists.
- **Each invocation pays about 0.09 s of front end** to re-analyse druntime and Phobos (`flint:arena`'s whole front end is 0.094 s). That is about 0.7 s of the 0.97 s, the cost the compile server's preloaded prelude removes on Linux.
- **The link is not the bottleneck.** LDC's built-in LLD links the same objects in 0.126 s against ld-prime's 0.153 s, saving about 27 ms or 2% of the build. `ld64.lld` is worth adopting only together with the fork's direct linking.

## Not done

- **Live `mq` scenarios** (`flint test --scenarios`) are not part of the macOS lane:
  - the JRE in `policy/peer-lock.json` is the Linux x64 build;
  - the scenario's `[binary.dub]`, `[binary.dmd]` and `[binary.native]` entries name Linux paths.

  The `mq` unit and loopback JetStream tests do run on macOS.
- **Embedded C in projects** (`policy/native-c.toml`) needs Darwin rules:
  - the pinned compiler is the Linux LLVM release;
  - Apple clang rejects `-fstack-clash-protection` on arm64;
  - `-z relro -z now` are ELF-only.
- **The desktop WebView backend** is GTK and WebKitGTK only. macOS runs the SDL canvas backend, and a WKWebView backend is future work.
- **WASI preopens** keep a narrow rename race on macOS until the Wasmtime C API can take a directory descriptor (ADR-024 section 4).
- **DMD arm64** is the dmd-arm64 session's work. These packages will be run on it as soon as druntime and Phobos land for macOS.

## Linux reruns

ADR-024's "Consequences for Linux" lists every Linux suite to rerun on venus for the shared changes. Since then, the macOS platform lane gained the peered `flint test` step. It runs only when the target is `macos-arm64`, so Linux lanes are unchanged.
