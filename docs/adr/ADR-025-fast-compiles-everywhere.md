# ADR-025: Compile speed is the selling point on every platform

Status: accepted by the project owner on 2026-11-22.

## Context

Flint's headline claim is that it builds faster than Go. Milestone 6 proved it on Linux x86-64:

- the forked DMD with its resident compile server, the parallel DUB pipeline and direct linking build the canonical CLI cold in about 0.10 s against Go's 0.11 s, a median ratio of 0.92;
- REST builds at 0.68 of Go.

The claim doesn't hold anywhere else yet:

- **macOS arm64:** DMD has no released arm64 code generator, so [ADR-024](ADR-024-macos-arm64.md) uses LDC through `ldmd2` there. On pluto, `bench-cli` builds cold in 1.71 s and incrementally in 0.38 s. DMD x86-64 under Rosetta takes 3.44 s and 0.70 s, and Apple's linker rejects DMD's archives: 64-bit Mach-O archive members are not 8-byte aligned.
- **Linux aarch64:** the same missing code generator. The Milestone 6 lanes ran under emulation and measured correctness only.
- **Windows x86-64:** DMD's x86-64 backend works, but the fork's compile server relies on `fork()` and Unix sockets, and its pipeline on `posix_spawn`. None of that exists on Windows.

DMD 2.114.0 does contain an **in-progress AArch64 backend** (`src/dmd/dmd/backend/arm/`, about 15,800 lines, selected with `-marm64`). A probe on 2026-11-22 gave three results:

- it produced a Linux AArch64 ELF object and a macOS arm64 Mach-O object from a small program;
- it compiled a module importing Phobos;
- three `extern(C)` functions (integer arithmetic, a slice loop, and a struct member function) linked with Apple clang on pluto and returned the correct results (`add=42 sum=15 usep=35`).

No druntime or Phobos library for arm64 is shipped, and the backend's coverage of real programs is unknown.

## Decision

### 1. The goal and how it is measured

On every tier-1 platform, the development profile must build the canonical apps faster than Go on the same machine:

- the platforms are Linux x86-64, Linux aarch64, macOS arm64 and Windows x86-64;
- the comparison is the cold and incremental builds of `bench-cli` and `bench-rest`;
- the gate is the same as Gate 6's build comparison: median ratio ≤ 0.99 and 99% upper bound ≤ 0.99.

"The same speed everywhere" means the same advantage over Go on each machine. Absolute times depend on hardware, so they are reported per runner, never compared across runners.

Each platform's report also gives the first build without a compile server (ADR-016) and the incremental edit build.

A platform that has not met the gate is reported as **failing**, never omitted, in the same way as ADR-017's platform decision.

### 2. One compiler family for development builds

The forked DMD is the development compiler on every platform. Release builds stay on LDC (`-O3`, ThinLTO). Development builds are about edit-compile-run speed, and DMD's front end and backend are the fastest available.

### 3. arm64: the fork completes DMD's AArch64 backend

These stages apply to both macOS arm64 and Linux aarch64, in order. Each lands on `main` when it is verified.

1. **Runtime libraries.** Build druntime and Phobos with `dmd -marm64` for `macos-arm64` and `linux-aarch64`, and pass their unittests. This needs, at least:
   - fiber context switching (assembly for the platform);
   - DWARF exception handling;
   - thread-local storage (Mach-O TLV on macOS, ELF TLS on Linux);
   - the ABI details in `argtypes_aarch64`.

   Every backend defect found is fixed in the fork, with a regression test in `toolchain/`, and offered upstream to dlang/dmd.
2. **Flint on DMD arm64.** The 37 packages pass `flint test` with the test profile on DMD arm64 natively:
   - on pluto for macOS;
   - on an arm64 Linux machine or VM for Linux. QEMU user mode is acceptable for correctness only.
3. **Linkable archives.** The fork writes Mach-O archives whose 64-bit members are 8-byte aligned, so Apple's current linker accepts them without `-ld_classic`. That also helps x86-64 Mach-O.
4. **The fork's speed features.** The compile server, the parallel DUB pipeline and direct linking run on macOS:
   - `fork()` and Unix sockets exist there;
   - the archiver writes the Darwin format;
   - the linker is Apple's `ld` or a pinned `ld64.lld`, since mold is Linux-only.
5. **Measurement.** Measure against Go on pluto and on an arm64 Linux machine.

Until stage 2 passes on a platform, that platform's development profile stays on `ldmd2` (ADR-024) as an **interim** setting, and its compile-speed gate reports failing.

### 4. Windows: port the fork's speed features

DMD's x86-64 backend already targets Windows. The fork's speed features change as follows:

- **Compile server without `fork()`.**
  - The server keeps a pool of pre-warmed, single-use worker processes. Each worker loads and analyses the druntime/Phobos prelude before any request arrives, then waits on a named pipe.
  - A request is handed to a warm worker, which compiles once and exits. The pool starts a replacement in the background.
  - The analysis cost leaves the critical path, which is the server's whole benefit, without copy-on-write cloning.
  - The same ADR-016 rules apply: the server holds only druntime and Phobos, and it refuses requests whose flags or import paths could change prelude semantics.
- **Parallel DUB pipeline:** `CreateProcess` instead of `posix_spawn`, and in-process COFF archiving.
- **Direct linking:** cache the expanded link command, and use a pinned `lld-link` or MSVC `link.exe`, with no `cl`/driver chain per link.

### 4a. Windows debug information in development builds

Decided on 2026-11-22 under the project owner's direction that compile time, developer experience and debugging all come first.

Measured on the Windows VM, with diagnostic numbers only, a cold `bench-cli` dev build is dominated by the link. The reason is that writing a full PDB merges every CodeView type and symbol:

| Full link of the same inputs | With PDB | Without |
| --- | ---: | ---: |
| `link.exe` | 0.67 s | 0.13 s |
| `lld-link` 22 | 0.25 s | 0.10 s |

An incremental `link.exe` link from its `.ilk` takes 0.03 s.

The decision:

1. **Development builds always keep file-and-line stack traces.** Debugging is not traded away for a benchmark, so linking without debug information is never the default.
2. **The default is the fastest configuration that keeps those traces.** The candidates are:
   - `link.exe /DEBUG:FASTLINK /INCREMENTAL`: a partial PDB that references the objects' CodeView instead of merging it, read by dbghelp;
   - `lld-link /DEBUG:GHASH` with parallel threads.

   A candidate qualifies only if an uncaught exception in `flint run` and in `flint test` prints file and line. Among qualifying candidates, the fastest cold build wins, and a tie goes to `link.exe`, whose incremental links give the fastest edit loop. Today's default, a full PDB with `link.exe`, stays until the measurement is done.
3. **Remaining cold-build time is removed by speed work, not by dropping debug information:**
   - the compile server's warm worker pool (section 4);
   - parallel compile jobs;
   - reusing unchanged objects and archives between links.
4. **Debugger and release builds:** `flint run --debug` and release builds always write a complete, self-contained PDB. A FASTLINK PDB depends on the object files staying in place, so it is never shipped.
5. **Opting out:** `[profile.dev] debug = false` drops debug information for anyone who wants the raw speed. It is recorded in the build receipt and is never the default.

Linux and macOS have no equivalent cost. DWARF stays in the objects and executables without a merge step, so their development builds keep `-g`.

### 5. Runners

| Platform | Performance runner |
| --- | --- |
| Linux x86-64 | `flint-perf-x86_64-v1`, the project workstation (ADR-017) |
| macOS arm64 | pluto (`flint-perf-macos-arm64-v1`), non-ephemeral, recorded as such |
| Linux aarch64 | an arm64 Linux machine or a hardware-virtualised arm64 Linux VM, for example under Apple's Virtualization framework on pluto. QEMU-emulated runs are diagnostic only. |
| Windows x86-64 | the Windows VM gives diagnostic numbers only (4 vCPUs, shared host). A bare-metal Windows runner is needed for a certifying result. |

### 6. Staying close to upstream

The fork follows each DMD release:
- AArch64 work is upstreamed wherever dlang/dmd accepts it, so the fork's patch stays small;
- the fork's patch hashes stay in `toolchain/` and the toolchain receipt (ADR-018).

## Order of work

1. **arm64 runtime and Flint on DMD arm64** (section 3, stages 1–2). This is the largest gain, and Apple Silicon is where most developers and coding agents work.
2. **Mach-O archives and the macOS speed features** (section 3, stages 3–4).
3. **The Windows speed features** (section 4), in the Windows port.
4. **Per-platform compile-speed gates** on each runner.

## Consequences

- This is compiler work of real size. The backend exists, but its maturity on whole programs is unproven. Druntime's platform pieces (fibers, exception handling, TLS) are where the effort concentrates.
- Development and release builds use different compilers on every platform, as they already do on Linux. The test profile keeps running on both compilers, so code generation differences are caught.
- Until a platform meets the gate, the "faster than Go" claim is stated per platform, with evidence, and never in general.
