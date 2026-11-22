# ADR-026: Native Windows x86-64

Status: **proposed** on 2026-11-22. This is the Windows track of [ADR-021](ADR-021-flint-platform.md) section 9, started early at the project owner's request. Gate 6 keeps reporting `windows-x86_64` as failing ([ADR-017](ADR-017-milestone-6-decisions.md) decision 2) until the platform lane's receipt passes.

## Context

Flint is certified on Linux, and macOS arm64 is being brought up in parallel ([ADR-024](ADR-024-macos-arm64.md)). [ADR-025](ADR-025-fast-compiles-everywhere.md) makes development builds faster than Go on every tier-1 platform, Windows included, and section 4 there says how the toolchain fork's speed features are ported to Windows. Windows x86-64 needs:

- a toolchain;
- Win32 equivalents for the POSIX calls in the packages' `sys` and `ffi` modules;
- an IOCP reactor backend;
- native providers built with MSVC under the hardening rules;
- a platform lane whose receipt satisfies Gate 6.

The reference machine is a Windows 11 LTSC 2024 virtual machine (build 26100, 4 vCPUs, 8 GB), driven over OpenSSH from the Linux performance runner. Nothing is compiled on the runner itself.

## Decisions

### 1. Build machine

Everything was installed from official sources with its checksum or signature checked first. There is no `winget` on LTSC, so installers and archives were fetched with PowerShell.

| Component | Version | Source and verification | Location |
| --- | --- | --- | --- |
| Python | 3.14.10 | `python-3.14.10-amd64.exe` from python.org; SHA-256 `92480239…9965` from the python.org release API | `C:\flint-work\tools\python` (per user, not on the system `PATH`) |
| Visual Studio 2022 Build Tools | 17.14.45 | `vs_buildtools.exe` from `aka.ms/vs/17/release`, Authenticode signature valid for Microsoft Corporation; the installer verifies its own payloads. Workload `VCTools` with MSVC 14.44, the Windows 11 SDK 10.0.26100, clang-cl and the MSVC AddressSanitizer | `C:\BuildTools` |
| CMake | 4.5.1 | `cmake-4.5.1-windows-x86_64.zip`; SHA-256 `bfe6eadb…430c` matches the release's `cmake-4.5.1-SHA-256.txt` and the GitHub asset digest | `C:\flint-work\tools\cmake-4.5.1-windows-x86_64` |
| Ninja | 1.13.2 | `ninja-win.zip`; SHA-256 `07fc8261…dc65` is the GitHub asset digest | `C:\flint-work\tools\ninja` |
| DMD | 2.114.0 | `dmd.2.114.0.windows.7z` through `tools/install_toolchains.py --compiler dmd`; pinned in `policy/toolchains.json` | `.tools\dmd2\windows\bin64` |
| LDC | 1.43.0 | `ldc2-1.43.0-windows-x64.7z` through `--compiler ldc`; already pinned | `.tools\ldc2-1.43.0-windows-x64` |
| dfmt, D-Scanner | 0.15.2 | `tools/install_quality_tools.py` with the locked selections | `.tools\bin` |

The DMD archive's digest is the GitHub release asset digest of `dlang/dmd` v2.114.0. downloads.dlang.org publishes only a GPG signature for it, which was not checked. Windows has no `7z`, so `install_toolchains.py` extracts `.7z` archives with the `tar.exe` (libarchive 3.7) that Windows ships.

### 2. Toolchain: the upstream DMD, then the fork's speed features

The first stage built with the **upstream DMD 2.114.0 and its bundled DUB 1.43.0**, which matches the DUB pin, and LDC 1.43.0. ADR-025 section 4 then ports the toolchain fork's speed features to Windows, one at a time, each measured against Go on the VM. The VM gives diagnostic numbers only (ADR-025 section 5): 4 vCPUs on a shared host.

`install_toolchains.py --compiler dmd` refuses `--dmd-linker` on Windows (it selects an ELF linker). `--flint-fork` builds the experimental Windows server described below.

#### The Flint DUB and its pipeline (done)

`install_toolchains.py --compiler dub` builds the Flint DUB on Windows, as on macOS, from the pinned source with the pinned LDC, into `.tools\dub-1.43.0\bin`. Windows applies a second patch, `toolchain/dub-1.43.0-flint-windows.patch`, over the shared `dub-1.43.0-flint.patch`. Keeping it separate leaves the Linux and macOS patch hashes, and so their installed toolchains, unchanged. The overlay:

- runs the parallel pipeline on Windows. Each compile job starts with `CreateProcessW` through `std.process`, and jobs are reaped with `WaitForMultipleObjects`; the POSIX `posix_spawn`/`waitpid` path is unchanged;
- archives libraries in process in the Microsoft COFF format `lib.exe` writes: the big-endian first linker member, the little-endian second linker member with its sorted symbol table, NUL-terminated long names, and two-byte member alignment. Symbols come from the COFF or big-object COFF symbol table (external symbols defined in a section, and common symbols);
- reads `.obj` objects, hard-links targets with `CreateHardLinkW`, ends with `_Exit`, and caches the compiler probe under `%LOCALAPPDATA%\flint-dub`, keyed by `sc.ini`.

The receipt records the Flint DUB's hash and the SHA-256 of both patches concatenated in order, and `flint toolchain install` runs `--compiler dmd`, `--compiler ldc`, `--compiler dub` and the quality tools. `flint_tool.toolchain.host` has `dubPipelineHost`, so flint leaves the pipeline on on Windows. `FLINT_DUB_PIPELINE=0` still turns it off.

The DUB shared by `flint` and by `dub test` builds all 16 stage-2 packages on both compilers, and `flint test --project apps/flint` passes, through the pipeline.

`bench-cli` with the dev profile on the VM, median of five trials (`tools/measure_dev_builds.py`; each Flint row is set against the Go run made beside it):

| Toolchain | Cold | Incremental | Go cold | Go incremental | Cold ratio | Incremental ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| upstream DMD and DUB | 1.44 s | 0.292 s | 0.342 s | 0.249 s | 4.22 | 1.17 |
| upstream DMD, Flint DUB pipeline | 1.08 s | 0.237 s | 0.263 s | 0.271 s | 4.10 | 0.88 |

A traced cold pipeline build spends about 0.06 s planning, 0.31 s compiling 61 modules in 9 parallel jobs (0.97 s sequentially), 5 ms archiving, and about 0.75 s linking. The sequential build linked in a similar time, which the faster compile phase now exposes.

#### Linking (measured; the default awaits a decision)

The cold link is slow because it is a full link with debug information. The dev profile's `-g` makes DMD pass `/DEBUG`, and Windows debug information means a PDB, whose type records the linker merges. With the previous `.ilk` and `.pdb` present, `link.exe` links incrementally in about 0.03 s; a cold build never has them. Full links of the same `bench-cli` inputs into a new directory:

| Linker | No debug information | With a PDB |
| --- | ---: | ---: |
| MSVC `link.exe` 14.44 (`/OPT:REF`, `/DEBUG:FASTLINK` and `/INCREMENTAL:NO` change nothing) | 0.13 s | 0.67 s |
| LLD 22, the one inside `ldc2` (`ldc2 -link-internally`, so this includes LDC start-up) | 0.11 s | 0.26 s |

`install_toolchains.py --compiler lld` installs the pinned `lld-link` 22.1.8 on Windows: it streams the official `clang+llvm-22.1.8-x86_64-pc-windows-msvc.tar.xz` (GitHub release digest), keeps only `bin/lld-link.exe` and checks its version. DMD uses it for any link when `LINKCMD64` names it. On the VM, `bench-cli` with the Flint DUB and `LINKCMD64` set:

| Linker | Cold | Incremental | Go cold | Go incremental |
| --- | ---: | ---: | ---: | ---: |
| `link.exe` (default) | 1.08 s | 0.237 s | 0.263 s | 0.271 s |
| pinned `lld-link` | 0.656 s | 0.435 s | 0.273 s | 0.257 s |

LLD wins the cold build but loses the incremental one: `link.exe` links incrementally from its `.ilk` in about 0.03 s, while LLD always does a full link (LLD's `/time`: 72 ms reading inputs, mostly `phobos64.lib`, and 117 ms writing the PDB). `-allinst` makes no difference to the link. The PDB is the cost either way, so the default stays `link.exe`, the better edit loop, and `lld-link` is an opt-in until the owner decides whether Windows dev builds may defer their PDB (link without one, and write it on demand, as in `flint run --debug`). The `lld-link` in DMD's Windows release is LLVM 9, which cannot link against the current MSVC runtime (`__guard_eh_cont_table`). `/DEBUG:GHASH` gains nothing, because DMD writes no precomputed type hashes.

#### The compile server: a warm worker pool (experimental, opt-in)

`toolchain/dmd-2.114.0-flint-windows.patch` applies over the shared DMD patch on Windows only. `install_toolchains.py --compiler dmd --flint-fork` builds that DMD with the pinned LDC (no PGO or LTO yet), keeping `dmd.upstream.exe` beside it. The patch confines the POSIX server and the direct link to `version (Posix)` and adds ADR-025 section 4's pool of warm, single-use workers:

- **Workers.** A worker (`dmd -fork-server=<pipe> <key flags>`) takes one of the pool's slots, which are named mutexes the kernel releases if a worker dies. It loads and analyses the prelude below normal priority, then waits on an instance of the key's named pipe, with the ADR-016 idle timeout.
- **Requests.** The kernel connects each client to an idle instance. The worker raises itself to normal priority and takes the client's working directory, environment (through the C runtime, so `getenv` sees it) and standard handles. It compiles once with the ordinary driver, reports the exit status, hands its slot to a replacement and exits.
- **Clients.** The client computes the Linux key from the same eligibility rules and refuses the same requests. It duplicates its standard handles into the worker it reached. That only works for a worker of the same user, so a pipe squatted by another user fails `OpenProcess(PROCESS_DUP_HANDLE)`, and the client compiles in-process. A client finding no worker starts the pool if none of its slots exists, and compiles in-process either way.
- **Detachment.** Workers start detached, outside the caller's job object (flint's jobs allow breakaway), with only NUL and the server log inherited, and in a neutral working directory. An early version inherited the client's directory and kept project directories locked.

A warm worker compiles a module importing the whole prelude in 0.022 s, against 0.18 s for a plain compile. Compiler errors reach the caller's console and the exit status is preserved. The full picture on the VM (`bench-cli`, median of five, back-to-back cold and incremental builds as `measure_builds.py` runs them; Go cold 0.25–0.28 s, incremental 0.23–0.27 s):

| Toolchain | Cold | Incremental |
| --- | ---: | ---: |
| upstream DMD and DUB | 1.44 s | 0.292 s |
| Flint DUB pipeline, `link.exe` | 1.08 s | 0.237 s |
| Flint DUB pipeline, `lld-link` | 0.656 s | 0.435 s |
| pipeline, warm workers, `link.exe` | 1.06 s | 0.87 s |
| pipeline, warm workers, `lld-link` | 0.574 s | 0.589 s |

The workers cut the cold compile phase from 0.31 s to 0.20 s. Three things keep the pool from paying off on Windows:

- **Replacements cost a full analysis.** Each replacement costs a full prelude analysis (about 0.2 s of CPU) and about 105 MB, where Linux forks a pre-analysed worker almost for free. The 8 workers hold 840 MB, and a pool of 16 made things worse on this 8 GB, 4-vCPU VM.
- **Back-to-back builds miss the pool.** A back-to-back incremental build arrives while the replacements of the cold build's workers are still warming, so it compiles in-process.
- **Incremental linking breaks.** A worker's objects carry template instances the prelude instantiated (`core.checkedint.mulu`, for instance) that are also defined elsewhere in the link. COMDAT folding keeps the program correct, but `link.exe` answers "multiple definitions found ... performing full link", so incremental linking stops working (0.7 s per link).

So on Windows the pool is opt-in: the client uses it only when `FLINT_DMD_SERVER=1`, and `flint toolchain install` keeps installing the upstream DMD. Follow-ups:

- emit only the root modules' own template instances in workers, which restores `link.exe`'s incremental links;
- `flint daemon stop` on Windows, because `dmd.exe` cannot be replaced while workers run it;
- remeasure on a bare-metal Windows runner, where the replacement cost weighs less.

Until these stages land and are measured, the Windows compile-speed gate reports failing.

Consequences so far:

- `flint_tool.toolchain.host` has `upstreamDmdHost` and `dubPipelineHost`. On Windows, `dmd` resolves to `dmd2\windows\bin64`, `dub` to the Flint DUB in `dub-1.43.0\bin`, executables carry `.exe`, and `PATH` lists use `;`, including the environment flint gives DUB.
- The toolchain receipt records the DMD archive digest and the hashes of the installed `dmd.exe`, `dub.exe` and `ldc2.exe`, the DUB patch digest and an empty DMD patch, so canonical builds trace every binary to a pinned archive and patch.
- `flint daemon start` reports FLINT-E0810, as on macOS.

### 3. Win32 platform layer

Windows code sits behind `version (Windows)` in each package's own `sys` modules. Where a module is mostly POSIX, its POSIX code moved into the `else` branch unchanged (re-indented only), and larger Windows implementations live in sibling modules (`windows_process`, `windows_directories`, `windows_sinks`, `windows_console`) that the existing module publicly imports. Callers did not change. dfmt rewrites the `version (X):` and `else:` colon forms, so blocks are used.

One change applies to every package: `Thread` is imported from `core.thread.osthread` and `Fiber` from `core.thread.fiber`, the modules that declare them. DMD 2.114.0 on Windows fails to resolve `import core.thread : Thread` when another module of the same compilation has already imported `core.thread.osthread`, which `flint.conc` does.

Where Windows semantics differ, this is what Flint does:

- **Child processes (`flint.os`).** The supervisor and output pump stay unchanged. They wait on small integer descriptors, which on Windows name slots in a static table: an overlapped named-pipe reader with its own buffer, a process handle, or a manual-reset event.
  - Output pipes are named pipes, because anonymous pipes cannot be waited on. Each reader keeps one overlapped read outstanding. A read is cancelled with `CancelIoEx`, and its final completion is observed before the buffer and `OVERLAPPED` are released.
  - A child starts suspended with `CreateProcessW`, joins its own job object, the counterpart of the owned process group, and then resumes. The job kills every member when its last handle closes, and lets a deliberate daemon started with `CREATE_BREAKAWAY_FROM_JOB` leave, as `setsid` leaves a group.
  - Only the three standard handles are inherited, through `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`. Standard input is `NUL`.
  - The child runs in its own console process group. The graceful stop is `CTRL_BREAK_EVENT`, and a child that ends from it reports `signalled` with SIGTERM (15). The forced stop is `TerminateJobObject`, and a leader still running when it is issued reports `signalled` with SIGKILL (9), the Linux exit statuses for the same two steps. Without a shared console the break cannot be delivered, so the grace period ends in termination.
  - `argv` is quoted for the Microsoft C runtime's command-line rules. The executable search uses `PATH` with `;`, tries `.exe` and `.com` for a name without an extension, and never runs batch files, which would go through `cmd.exe` and its own quoting. A relative executable resolves against the child's working directory, as `exec` after `chdir` does.
  - Environment names compare without case: an override replaces an inherited variable that differs only in case, and `PATH` is found as `Path`.
  - `CreateProcessW` reports a failed start synchronously, so there is no startup receipt pipe.
- **Ctrl+C (`flint.os`).** A console control handler replaces the SIGINT handler. It runs on a console thread, sets the latch event and claims `CTRL_C_EVENT`; every other event keeps its default handling. Windows cannot inspect other handlers, so the POSIX conflict check has no counterpart.
- **Glob containment (`flint.os`).** Every open directory is pinned by a handle opened with backup semantics, and identified by volume serial number and file index for the cycle check. An entry is opened by path and accepted only if its final path (`GetFinalPathNameByHandleW`, after the kernel resolved every link) still lies beneath the root's final path. Without `followSymlinks`, a reparse point (symbolic link or junction) is refused, as `RESOLVE_NO_SYMLINKS` refuses one. Junctions count as links. Entries come from `FindFirstFileExW`.
- **Log sinks (`flint.log`).** Handles are stored as integers, so a `const` sink still copies, as POSIX descriptors do. Disk files append through the all-ones `OVERLAPPED` offset, the counterpart of `O_APPEND`. A console receives UTF-16 through `WriteConsoleW` whatever its code page. The consumer parks on `WaitOnAddress`, which is resolved from KernelBase at run time, so programs using the logger need no `synchronization.lib`. The wall clock is `GetSystemTimePreciseAsFileTime`. Windows has no SIGPIPE: a write to a closed pipe fails with an error.
- **Terminal (`flint.term`).** `flint.term.sys.windows_console` provides the session ABI that `native/linux.c` provides on Linux and macOS, so the session logic and the decoder are shared.
  - Input runs in virtual-terminal mode, so keys arrive as the VT sequences the decoder already parses. Records are converted from UTF-16 to UTF-8.
  - A window-size record reports a resize only when the window size actually changed, since the console also sends one when the mode changes.
  - Ctrl+C outside raw mode reports an interrupt through a console control handler. Raw mode turns off line input, echo and Ctrl+C processing, as `cfmakeraw` does.
  - The session switches output to virtual-terminal processing and both code pages to UTF-8, and restores them on close.
  - `describe` counts a console as a terminal only while it already interprets VT sequences, and never switches that on. With no `TERM` set, such a console reports true color. Environment variables are read from the process environment block, which `std.process` writes, not the C runtime's startup copy that `getenv` reads.
- **Configuration and the test runner.** File and environment reads use `CreateFileW`, `GetFileSizeEx`, `ReadFile` and `GetEnvironmentStringsW` with `std.file` and `std.process` semantics. The JUnit report is created exclusively with `_wopen`. `time_t` is 32 bits in the Microsoft C runtime, so the log clock test converts 64-bit seconds through `FileTimeToSystemTime`.

Tests that observed POSIX-only state have Windows suites with the same assertions:

| POSIX | Windows |
| --- | --- |
| `/bin/sh -c ...` children | the test executable re-launched as its own child, selected by an environment variable |
| `/proc/self/fd`, `/dev/full`, pipe sizes | named pipes with a 4 KiB buffer; a pipe whose reader closed |
| pseudo-terminal from `posix_openpt` | a 97×31 ConPTY running the test executable, which reports what `describe` and a raw `Session` saw |
| `kill(getpid(), SIGINT)` | a child that detaches, allocates its own console and raises `CTRL_C_EVENT` there, so no other process sees it |
| symbolic links | directory junctions, which need no privilege |

### 4. The flint CLI

`flint_tool.sys.windows` is the Windows counterpart of `flint_tool.sys.posix`:

- Windows has no `exec`, so `flint run` starts the program with flint's standard handles and console, waits, and exits with its code. Ctrl+C reaches the program through the shared console, and flint's own handler keeps flint waiting.
- Output to a console is converted to UTF-16, and flint enables VT processing on its own consoles at start.
- The compile-server helpers report that no server exists.

Paths are compared with Windows separators and case rules: the workspace check (`filenameCmp`, `isDirSeparator`), the structural checker's `realPath` (the final path of the longest existing prefix) and `within`. Executables, test executables and libraries carry `.exe` and `.lib`. The host target is `windows-x86_64`, and a project may name it.

`tools/install_toolchains.py --compiler flint` bootstraps the CLI as on Linux: DUB builds stage 1, which rebuilds flint canonically and verifies its own receipt. `flint doctor`, `flint toolchain verify` and `flint toolchain info` run.

## Status of the port

Verified on the Windows VM:

- `tools/install_toolchains.py --compiler dmd`, `--compiler ldc` and `--compiler flint`; `flint toolchain install`, `flint toolchain verify` (receipt verified) and `flint doctor` (exit 0);
- `flint test --project apps/flint`: 16 of 16 modules;
- `dub test` with DMD and with LDC for all 16 stage-2 packages: `:arena`, `:conc`, `:validate`, `:config`, `:serde`, `:di`, `:log`, `:cli`, `:style`, `:term`, `:os`, `:test`, `:ui-signals`, `:widgets`, `:tui` and `:prompt`;
- `flint toolchain install` with the Flint DUB, and `dub test` through its pipeline for those 16 packages;
- `tools/native_build.py --profile tui --target windows-x86_64 --phase build --emit-dub` with MSVC: utf8proc, Flint's C shims and their ctest;
- `tools/gates.py --gate structural` for those 16 packages, and `tools/quality.py` over the whole tree (0 issues).

Two details of the MSVC build of Flint's C shims (`native/ffi`):

- MSVC's C mode has no `max_align_t`, so `flint_codec_core.c` declares one for MSVC from the most strictly aligned scalar types, and C11 atomics need `/experimental:c11atomics`;
- the providers are static archives whose Windows headers declare DLL imports by default, so the shims compile with `UTF8PROC_STATIC`, `CURL_STATICLIB`, `NGHTTP2_STATICLIB`, `YAML_DECLARE_STATIC`, `LIBARCHIVE_STATIC` and `SODIUM_STATIC`.

`flint.prompt`'s secret store is `native/secret.c` on Linux and macOS. Windows has no C step in the package build, so `flint.prompt.sys.secret` defines the same functions in D there, wiping with volatile stores.

Next, in ADR-025's order:

- the owner's decision on PDBs in Windows dev builds, then the default linker and a cached link command; template-instance ownership in warm workers, so the pool can become the default;
- the IOCP reactor backend, then the packages above the reactor;
- the remaining native providers under MSVC hardening (`/guard:cf`, `/GS`, `/sdl`, and `/W4 /WX` for Flint's own C);
- the `windows-x86_64` platform lane for Gate 6.

## Public API additions

None. `flint.reactor.Backend.iocp` is already part of the frozen contract.

## Consequences for Linux and macOS

The Linux and macOS behaviour of every changed module is unchanged by construction: their code moved into `else` branches, re-indented only, apart from the `Thread`/`Fiber` import modules and the environment lookups in `flint.term`, which now call `core.stdc.stdlib.getenv`, the function `core.sys.posix.stdlib` re-exported. Every changed package and the CLI were type-checked for `-os=linux`, `-os=osx` and `-os=windows` with DMD's front end. They still have to run on venus (Linux) and pluto (macOS):

- `dub test` on both compilers for `:conc`, `:config`, `:log`, `:os`, `:prompt`, `:term` and `:test`, and for every package whose `core.thread` imports changed (all of them compile, but the import change touches tests across `:actuator`, `:cache`, `:codec`, `:mcp`, `:mq`, `:sql`, `:storage` and `:web`);
- `flint test --project apps/flint`, and `python3 -m unittest discover -s tests -p 'test_*.py'`;
- `python3 tools/gates.py --gate structural`;
- nothing for the DUB pipeline: the Windows overlay patch applies on Windows only, and the shared patch is unchanged;
- `flint build` and `flint test` for a project, since flint's DUB environment now skips `PATH` through a host check (identical on Linux);
- `tools/native_build.py` with `ctest`, since `native/ffi/CMakeLists.txt` and `flint_codec_core.c` changed (both only under MSVC conditions);
- `flint toolchain install --plan`, `flint toolchain verify` and `tools/install_toolchains.py --compiler flint`, since `tools/install_toolchains.py` and the toolchain modules changed.
