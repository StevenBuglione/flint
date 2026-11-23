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

#### Linking: the DLL C runtime and `link.exe` (ADR-025 section 4a)

A cold link is slow because it is a full link with debug information. The dev profile's `-g` makes DMD pass `/DEBUG`, and on Windows debug information means a PDB, whose type records and symbols the linker merges. With the previous `.ilk` and `.pdb` present, `link.exe` links incrementally; a cold build never has them.

`install_toolchains.py --compiler lld` installs the pinned `lld-link` 22.1.8 on Windows: it streams the official `clang+llvm-22.1.8-x86_64-pc-windows-msvc.tar.xz` (GitHub release digest), keeps only `bin/lld-link.exe` and checks its version. The `lld-link` in DMD's Windows release is LLVM 9, which cannot link against the current MSVC runtime (`__guard_eh_cont_table`).

**The candidates.** ADR-025 section 4a names two candidates besides the full-PDB `link.exe`. Full links of the same `bench-cli` inputs into a new directory, median of five, each replacing only the `/DEBUG` option of DMD's link command:

| Linker | Link |
| --- | ---: |
| `link.exe /DEBUG` (full PDB) | 0.686 s |
| `link.exe /DEBUG:FASTLINK` | 0.681 s |
| `link.exe /DEBUG:FASTLINK /INCREMENTAL` | 0.683 s |
| `lld-link /DEBUG` | 0.261 s |
| `lld-link /DEBUG:GHASH` | 0.249 s |
| `lld-link /DEBUG:GHASH /threads:4` | 0.256 s |
| `lld-link /DEBUG:GHASH /threads:8` | 0.251 s |
| `link.exe /DEBUG:NONE` (reference, no PDB) | 0.137 s |

Every candidate qualifies: a project whose `main` and whose unittest throw an uncaught exception prints `app.d(7)` for the throw and the caller's line, in both `flint run` and `flint test`. For a while `lld-link` was the default, since it gives the fastest cold build. Its incremental build was worse, though (0.429 s against `link.exe`'s 0.237 s), because LLD always links in full.

**What the PDB is made of.** LLD's `/summary` for that link:

- inputs: 2,580 objects, 125 MB in all, read in 83 ms;
- type records: 91,012, totalling 6.8 MB, merged into 17,536 TPI and 8,265 IPI records;
- symbols: 110,777 module symbol records and 89,368 global symbol records;
- PDB emission: 149 ms, of which 9 ms hashing types, 36 ms merging them, 47 ms merging symbols and 44 ms writing the file.

A count of the COFF sections of every input shows where this comes from:

- `phobos64.lib` (17,492 members) carries no CodeView at all;
- Flint's libraries and `app.obj` carry 0.3 MB of `.debug$T`;
- the static Microsoft C runtime that DMD links by default carries almost everything. `libucrt.lib` alone has 15.3 MB of `.debug$T` and 17.4 MB of `.debug$S`, and `libcmt.lib` has 2.8 MB of `.debug$S`, which refers to a type-server PDB.

**The DLL C runtime.** DMD's `-mscrtlib=msvcrt` links the C runtime DLL instead, whose import libraries carry no CodeView. That link has:

- 2,327 input objects, 53 MB in all;
- 17,352 type records totalling 628 KB, all from D code;
- 4,444 global symbol records;
- 21 ms of PDB emission, within 71 ms of LLD time (0.097 s wall time).

One fix is needed. `lld-link` resolves `__acrt_iob_func` to druntime's `/alternatename` fallback before it loads the UCRT import library, and the program then dies with an illegal instruction at start-up. `link.exe` searches every library first. Naming `ucrt.lib` on the command line fixes it.

`install_toolchains.py --compiler dmd` therefore writes the 64-bit `DFLAGS` into DMD's `sc.ini`: the release's import paths, then `-mscrtlib=msvcrt -L/DEFAULTLIB:ucrt.lib`. An `sc.ini` value takes precedence over the environment, so flint, DUB and the measurement tools all build the same way. Executables built with DMD then need `vcruntime140.dll`, which the Visual Studio Build Tools install. Release builds use LDC and are unchanged. No Flint target builds a DLL with DMD; one would need `msvcrt.lib` named explicitly.

**The rest of `link.exe`'s cold time** is not the PDB's content. With the DLL runtime, `/DEBUG`, `/DEBUG:FASTLINK` and `/INCREMENTAL:NO` all take 0.61 s, against 0.11 s for `/DEBUG:NONE`. `/time+` puts it all in pass 1, at 196 MB of private bytes. The cost grows with the number of object modules: a hello-world program (1,093 objects) pays 0.13 s for `/DEBUG`, `bench-cli` (2,327) pays 0.5 s. Nearly all of those objects are `phobos64.lib` members, one per function.

**The default.** Until both builds beat Go, the default is the configuration with the best edit loop (the project owner's direction, relayed on 2026-11-22). That is `link.exe` with the DLL runtime: its incremental build beats Go. `sc.ini` sets no `LINKCMD64`. Setting `LINKCMD64` to the pinned `lld-link` in the environment selects the faster cold link, and flint records `LINKCMD64` among the influential variables of each build receipt. Both linkers write a complete, self-contained PDB, so `flint run --debug` needs no second link and no FASTLINK PDB is produced (decision 4).

**What was ruled out:**

- **Precomputed type hashes (`.debug$H`).** Hashing is 9 ms of LLD's 263 ms with the static runtime and 1 ms with the DLL runtime, so the DMD fork does not emit them.
- **A type server, or less CodeView for template instances.** D code's 628 KB of type records merge in 1 ms, which leaves nothing to save.
- **A druntime/Phobos DLL.** It carries no CodeView, but it would remove `link.exe`'s per-object cost for some 2,300 members. DMD ships no druntime or Phobos DLL for Windows, so that remains a lever for the cold build.
- **Mixed linkers.** A cold build with `lld-link` and edits with `link.exe /INCREMENTAL` do not combine. `link.exe` patches only an `.ilk` it wrote itself, so the first edit would be a full `link.exe` link. Writing that `.ilk` in the background after a cold build would make the output depend on timing.

`[profile.dev] debug = false` (decision 5) removes `-g`, `-gf`, `-gc`, `-gline-tables-only` and `-gdwarf=*` from the dev build. The build receipt lists it among the non-canonical reasons ("flint.toml turns off debug information (debug = false)"), and `flint run --debug` ignores it. `debug` is accepted only in `[profile.dev]`. On the VM it halves the trace project's executable (1.09 MB to 0.53 MB) and leaves no PDB, and an uncaught exception then shows only `app.d(7)` in its message.

#### The compile-speed gate on Windows

`tools/measure_builds.py --apps-only` measures ADR-025's gate on any tier-1 host, Windows included. It uses the full run's method:

- nine trials;
- a fresh workspace copy and an empty `DUB_HOME` per trial;
- the ADR-016 server priming before trial 0;
- the first build without a server, reported separately.

For each app it times the dev build cold and after the canonical edit. For Go it times the build cold, from a fresh clone of the standard-library-only primed cache, and after appending a declaration to `main.go`. It reports each ratio's median and bootstrap 99% upper bound (`tools/perf_stats.py`) against the 0.99 ceiling. On Windows a job object holding the build reports its peak committed memory, since there is no `/proc` to sample. Other changes:

- the native receipt is the host's (`windows-x86_64` here);
- `--app` restricts the run to one app, and the gate then reports failing;
- the full Linux run is unchanged.

`bench-cli` on the VM, nine trials each. `bench-rest` needs the IOCP reactor.

| Configuration | First build | Cold | Incremental | Go cold | Go incremental | Cold ratio (99% upper) | Incremental ratio (99% upper) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lld-link`, static runtime | 0.678 s | 0.656 s | 0.436 s | 0.250 s | 0.244 s | 2.62 (2.79) | 1.79 (1.94) |
| `lld-link`, DLL runtime (opt-in) | 0.506 s | 0.492 s | 0.258 s | 0.249 s | 0.247 s | 1.97 (2.08) | 1.05 (1.12) |
| `link.exe`, DLL runtime (default) | 1.177 s | 1.014 s | 0.214 s | 0.257 s | 0.239 s | 3.95 (4.18) | **0.89 (0.95), passes** |

The incremental build beats Go. The cold build does not, so the gate fails.

Traced builds with the DLL runtime, where planning takes about 20 ms and archiving 5 ms:

| | Compiling | Linking | Total |
| --- | ---: | ---: | ---: |
| `lld-link`, cold | 0.31–0.36 s (9 jobs; the longest is `flint:config`) | 0.11 s | 0.47–0.53 s |
| `lld-link`, incremental | 0.11 s (`app.d`) | 0.11 s | 0.26–0.29 s |
| `link.exe`, cold | 0.31–0.35 s | 0.65 s | 1.04 s |
| `link.exe`, incremental | 0.11 s | 0.07 s | 0.218 s |

Other levers, each measured on its own:

| Lever | Effect |
| --- | --- |
| no debug information at all, static runtime (not allowed; the bound of any CodeView work) | compile phase about 5% shorter, link 0.27 s to 0.12 s |
| linking without the DMD driver (a cached link command) | about 22 ms per link (0.299 s to 0.277 s with `lld-link`) |

The cold build's remaining cost has two parts:

- **`link.exe`'s per-object PDB cost.** A druntime/Phobos DLL, or fewer and larger runtime objects, would cut it.
- **The compile phase.** About 0.35 s, for the 61 modules of seven Flint packages in 9 jobs on 4 vCPUs (0.97 s of work in sequence). Go compiles only the app's own package against a primed standard library.

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

- **The reactor (`flint.engine.reactor`).**
  - Windows has one backend, the I/O completion port (`Backend.iocp`). It runs through the same completion path as io_uring.
  - Accepts use `AcceptEx` on worker 0, and reads and writes use overlapped `WSARecv` and `WSASend` into the worker's stable slots.
  - Cancellation is `CancelIoEx`, and storage is released only when the original packet is dequeued.
  - Completion tokens use the operation table's encoding (the generation above 13 slot bits). The first draft of `sys/windows.d` assumed a 32-bit slot field and refused every read and write.
  - `GetQueuedCompletionStatus` rounds its timeout to the system timer tick, 15.6 ms by default. While a completion port is open, the process asks for 1 ms ticks with `timeBeginPeriod`, loaded from winmm at run time. Since Windows 10 2004 the request affects only this process.
  - Accepted sockets get `TCP_NODELAY`, as on Linux and macOS.
  - **`stopAccepting` closes the listener, as on Linux and macOS.** The kernel then refuses new connections while admitted ones drain (ADR-028 section 10).
    - The listener holds the process's Winsock reference, which those connections still need. So its socket closes when the last owner retires its accept, and the reference is released only at `release`.
    - Before this, the listener stayed open until release, and the backlog kept admitting connections during a graceful drain.
  - Native descriptor watches stay Linux and macOS only (`Status.unsupported`).
  - Tests that asked for "the readiness backend" use IOCP on Windows. The cancellation race, the backpressured write drain, the foreign-worker close and the `TCP_NODELAY` check now run there, on DMD and LDC. Descriptor exhaustion has no Windows counterpart to `RLIMIT_NOFILE` and stays POSIX.
  - With a completion port, an OVERLAPPED's status is written only when its packet is dequeued. The low-level test of "a read completed before `CancelIoEx`" therefore waits for the loopback receive instead of observing it.

- **Wake-ups (`flint.engine.security`, `flint.engine.cache`).**
  - The JWKS worker and the cache monitor wait on an auto-reset event (`CreateEventW`, `SetEvent`, `WaitForSingleObject`) where Linux uses an eventfd and macOS a pipe.
  - Signals sent before a wait collapse into one wake-up, as an eventfd drain does.
- **Secure random bytes (`flint.conc`).** `BCryptGenRandom` with the system-preferred generator, resolved from System32's `bcrypt.dll` at run time.
- **IP literals (`flint.engine.security`).** Winsock's `inet_pton`, which needs no `WSAStartup`. The packages that call Winsock declare `libs "ws2_32" platform="windows"`.
- **Backend selection in packages and tests.** Code that picked kqueue on macOS and epoll elsewhere picks IOCP on Windows.
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

### 3a. Native providers and Flint's C under MSVC

`tools/native_build.py --profile ci --target windows-x86_64` builds all 17 providers of the `ci` closure with MSVC 14.44 and the Windows 11 SDK, against the C runtime DLL (`/MD`).

**Build tools.** Linux and macOS use the host's build tools; nothing pins them. On the VM:

| Tool | Version | Source |
| --- | --- | --- |
| Strawberry Perl, for OpenSSL's Configure | 5.42.3.1 portable | GitHub release asset; its published digest `6a081a81…10690` matched |
| NASM | 3.02 | nasm.us; no checksum is published, and the zip's SHA-256 is `161d0bfa…aee7` |
| Meson, for libpq | 1.12.1 | PyPI, as `ci.py windows-tools` installs it |
| winflexbison | 2.5.25 | the pinned asset `ci.py windows-tools` installs |

Only `perl\bin` from Strawberry Perl is put on the path, because its bundled MinGW toolchain would confuse CMake.

**Hardening.** Every provider builds with `/guard:cf /GS /sdl` and `/O2`. `/O2` is explicit because OpenSSL's Configure replaces its defaults with `CFLAGS` from the environment. `/sdl` turns some warnings into errors, and four stay warnings in third-party code:

- **C4703**, a possibly uninitialized pointer: a false positive in libpq's `fe-connect.c`.
- **C4996**, CRT and Winsock functions Microsoft deprecates in favour of its `_s` variants: used throughout librdkafka.
- **C4700**, an uninitialized local. This one is a real upstream bug: librdkafka's `rd_kafka_cgrp_rejoin` passes its `va_list` to the KIP-848 consumer path before `va_start`. Flint never takes that path, because it keeps the default classic group protocol. It should be reported upstream.
- **C4146**, unary minus on an unsigned value: protobuf-c's zigzag encoding, which is well defined.

**Flint's own C.** The shims, `flint_ffi_base` in `native/ffi` and `flint_ffi_framework` from the engines' `native/ffi`, build with `/W4 /WX /guard:cf /GS /sdl`. They keep every `/sdl` error. The only exception is C4200, which flags standard C99 flexible array members. Both ctest suites pass.

**Provider recipe fixes for Windows:**

- zlib installs `libzs.lib`, a name CMake's FindZLIB does not search. Dependents get `ZLIB_LIBRARY` explicitly, with forward slashes: a backslash path broke curl's generated CMake package.
- curl gets the Linux protocol set (HTTP and SMTP only), so it no longer builds LDAP through wldap32.
- libpq's Meson checks link static libcrypto with `ws2_32`, `crypt32`, `advapi32` and `user32`. libpq's zlib feature is off on Windows: the client library links no zlib, and Windows has no pkg-config for Meson.
- The emitted link set adds `secur32` (libpq's SSPI), `xmllite` (libarchive's XAR writer) and `iphlpapi` (curl).

**The C runtime.** Every Windows build uses the C runtime DLL, matching the `/MD` providers:

- DMD gets `-mscrtlib=msvcrt -L/DEFAULTLIB:ucrt.lib` from `sc.ini`;
- LDC gets `-mscrtlib=msvcrt` from a Flint fragment, `etc/ldc2.conf/60-flint-windows.conf`, which `install_toolchains.py --compiler ldc` writes. LDC 1.43 reads `ldc2.conf` as a directory of fragments.

Programs therefore need `vcruntime140.dll`, which the Visual Studio Build Tools install.

**The shims on Windows.** Thirteen shims were Linux and macOS only. They now build on Windows over `native/framework/include/flint_port.h`, a header of Flint's own that maps the POSIX subset they use onto Win32:

- pthread `once`, mutexes (SRWLOCK), condition variables with a clock-aware timed wait, and threads (`_beginthreadex`);
- `clock_gettime`, whose `CLOCK_MONOTONIC` reads `QueryPerformanceCounter` as D's MonoTime does;
- `nanosleep`, `sysconf(_SC_NPROCESSORS_ONLN)`, `poll` as `WSAPoll`, and the `strcasecmp`, `strdup` and `access` names.

Other per-shim changes:

- The eventfd wake-ups (`flint_wake.h`) are a connected, nonblocking loopback TCP pair, whose read end the reactor watches.
- The NATS socket uses Winsock: FIONBIO, `WSAGetLastError` and `closesocket`.
- SQLite's local-file-system check accepts a fixed or RAM disk formatted NTFS or ReFS.
- libarchive reads and writes header names as UTF-8 (`hdrcharset=UTF-8`), which POSIX gets from its private `C.UTF-8` locale.
- The desktop queue finds the process's first thread from a thread snapshot (Windows names no main thread).
- `hiredis` keeps no SIGPIPE mask, because Winsock raises none.

**Native watches.** The reactor's native descriptor watches now exist on Windows, for sockets. The owner polls the watched sockets with `WSAPoll` on every loop pass, and caps its completion-port wait at 1 ms while any is watched. `flint.engine.sql` and `flint.engine.cache` need them for libpq's and hiredis's sockets and for their wake-ups.

**Other D changes:**

- `flint.engine.sql`'s lock parking uses `WaitOnAddress`, resolved from KernelBase at run time.
- `flint.engine.storage` reads the wall clock with `GetSystemTimePreciseAsFileTime` in a new allowlisted `flint.engine.storage.sys.clock`, because `std.datetime`'s Windows clock is neither `nothrow` nor `@nogc`.
- Every D binding that enabled a provider on Linux and macOS (`FlintCurlOnLinux` and the like) enables it on Windows too.

**Results.** On the VM with LDC and the providers linked, 35 of the 37 packages pass `dub test`. The other two:

- `engine-web`'s HTTP/2 test calls an independent `curl` client, but the `curl.exe` Windows ships has no HTTP/2.
- `engine-wasi` needs wasmtime, which `ci.py`'s native step builds with the pinned Rust.

Both now pass:

- **curl.** `ci.py windows-tools` installs a pinned, sha256-checked curl 8.23.0 built with nghttp2 (`policy/toolchains.json`). The lane's test step points `FLINT_TEST_CURL` at it, because CreateProcess searches System32 before `PATH`.
- **wasmtime.** On Windows, wasmtime builds with Flint's Rust extensions, as on Linux and macOS (`flint_wasmtime_extensions.rs`). `flint_wasi.c` compiles there over `flint_port.h`.
  - **Preopens.** A preopen's host path is walked one directory at a time from its root, with `FILE_FLAG_OPEN_REPARSE_POINT`, and every component must be a plain directory, so a symbolic link or junction is refused. The walk's handles stay open without `FILE_SHARE_DELETE` while Wasmtime opens the path, so no component can be renamed or replaced in between.
  - **Refused paths.** UNC and device paths, drive-relative paths, alternate data streams, and components that Win32 would rewrite (a trailing dot or space).
  - **Bench reference.** The direct-provider reference archive stays Linux and macOS only, because no Windows bench lane uses it.
- **The UCRT's inline stdio.** The UCRT headers define `snprintf` and its relatives as external inline COMDATs. druntime references `snprintf`, so link.exe loaded the first shim object that defined it, together with that shim's provider: `engine-wasi`'s test pulled in libpq and SQLite. Both shim projects now build with `_NO_CRT_STDIO_INLINE`, so their printf-family calls bind to `legacy_stdio_definitions.lib`.
- **Link inputs as `libs`.** On Windows, `--emit-dub` writes each archive and system library as `libs "<path without .lib>"`, not `lflags`.
  - DUB concatenates the `lflags` of every path through a dependency graph and keeps the repeats. gs-relational-data-access, with about 30 packages, passed link.exe 7,705 library arguments, a 187 KB response-file line, and link.exe stops at 128 KiB (LNK1170).
  - DUB keeps `libs` unique: 43 arguments, 5.6 KB.
  - Linux and macOS keep `lflags`, whose order a single-pass static linker needs.
- **DMD and OpenSSL.** Static libcrypto calls `MessageBoxW` and `GetProcessWindowStation`. LDC links `user32.lib` by default and DMD does not, so the DUB blocks that `--emit-dub` writes for Windows now name `user32.lib` with the other system libraries. Packages that link OpenSSL then link with both compilers, which the cutover's `flint build` (DMD) needs.

### 4. The flint CLI

`flint_tool.sys.windows` is the Windows counterpart of `flint_tool.sys.posix`:

- Windows has no `exec`, so `flint run` starts the program with flint's standard handles and console, waits, and exits with its code. Ctrl+C reaches the program through the shared console, and flint's own handler keeps flint waiting.
- Output to a console is converted to UTF-16, and flint enables VT processing on its own consoles at start.
- The compile-server helpers report that no server exists.
- Standard input is read with `ReadFile` on the standard handle, not the C runtime's `stdin`. The C runtime opens `stdin` in text mode, which turns CRLF into LF, and `flint lsp`'s `Content-Length` framing ends its headers with CRLF CRLF. Over a text-mode `stdin`, `flint lsp` never answered `initialize`.
- `flint lsp` maps `file:///C:/a/b.d` to `C:\a\b.d` and back. It finds open buffers under the project's `src` with the platform separator.

Paths are compared with Windows separators and case rules: the workspace check (`filenameCmp`, `isDirSeparator`), the structural checker's `realPath` (the final path of the longest existing prefix) and `within`. Executables, test executables and libraries carry `.exe` and `.lib`. The host target is `windows-x86_64`, and a project may name it.

`tools/install_toolchains.py --compiler flint` bootstraps the CLI as on Linux: DUB builds stage 1, which rebuilds flint canonically and verifies its own receipt. `flint doctor`, `flint toolchain verify` and `flint toolchain info` run.

## Status of the port

Verified on the Windows VM:

- `tools/install_toolchains.py --compiler dmd`, `--compiler ldc` and `--compiler flint`; `flint toolchain install`, `flint toolchain verify` (receipt verified) and `flint doctor` (exit 0);
- `flint test --project apps/flint`: 17 of 17 modules;
- `dub test` with DMD and with LDC for all 16 stage-2 packages: `:arena`, `:conc`, `:validate`, `:config`, `:serde`, `:di`, `:log`, `:cli`, `:style`, `:term`, `:os`, `:test`, `:ui-signals`, `:widgets`, `:tui` and `:prompt`;
- `flint toolchain install` with the Flint DUB, and `dub test` through its pipeline for those 16 packages;
- `tools/native_build.py --profile tui --target windows-x86_64 --phase build --emit-dub` with MSVC: utf8proc, Flint's C shims and their ctest;
- `tools/gates.py --gate structural` for those 16 packages, and `tools/quality.py` over the whole tree (0 issues).

Two details of the MSVC build of Flint's C shims (`native/ffi`):

- MSVC's C mode has no `max_align_t`, so `flint_codec_core.c` declares one for MSVC from the most strictly aligned scalar types, and C11 atomics need `/experimental:c11atomics`;
- the providers are static archives whose Windows headers declare DLL imports by default, so the shims compile with `UTF8PROC_STATIC`, `CURL_STATICLIB`, `NGHTTP2_STATICLIB`, `YAML_DECLARE_STATIC`, `LIBARCHIVE_STATIC` and `SODIUM_STATIC`.

`flint.engine.prompt`'s secret store is `native/secret.c` on Linux and macOS. Windows has no C step in the package build, so `flint.engine.prompt.sys.secret` defines the same functions in D there, wiping with volatile stores.

Next, in ADR-025's order:

- the remaining cold-build levers of ADR-025 section 4a, with a breakdown after each: the warm worker pool and its template-instance ownership, parallel jobs, DMD's CodeView emission, process creation and a cached link command;
- the `windows-x86_64` platform lane for Gate 6.

### The Python suite on Windows

`python -m unittest discover -s tests` runs on Windows, the cutover rehearsal's `python suite`.
- Every text read, write and subprocess in `tests/` names UTF-8, because Windows' default code page is not UTF-8.
- Executables are `<name>.exe`, and an artifact's receipt is `<name>.exe.receipt.json` (`test_flint_cli.EXE`).
- DMD lives under `dmd2/windows/bin64`.
- Probe commands use the running interpreter, because Windows has no `python3` command.
- Recipes and DUB paths are written with `/`.

Known gaps: these tests are skipped on Windows, each with its reason.

| Test | Reason |
| --- | --- |
| `test_flint_watch.WatchTests` (2 tests) | `flint watch` stops on Ctrl+C. A test cannot send Ctrl+C to a child without sharing its console, and Ctrl+Break is SIGTERM, which `flint watch` leaves to the default handler. |
| `test_install_quality_tools`: the two libcurl tests | `install_quality_tools.py` checks for libcurl only off Windows, where DUB loads it at run time. |
| `engine-web` `http1_socket_behavior`, the delayed-echo CPU bound, with DMD only | Reported, not asserted (`FLINT-UNOPTIMIZED cpu bound met/not met`). The bound (30 ms over 200 rounds) tells event-driven wake apart from a 200 µs spin per wait, which costs at least 40 ms. A debug DMD build on the 4-vCPU VM measured 46.9 ms of whole-process CPU, test client included, at main as well. That is unoptimized code, not a spin: a spin is wall-clock-driven and would cost the same under LDC, which passes. The median-latency bound stays asserted with DMD, and the Windows Gate 6 lane (LDC) enforces the CPU bound. Decided by engine-web. |
| `framework/test_graceful_shutdown`: `test_sigint_behaves_the_same` | Ctrl+C cannot be sent to a single process group. The other graceful-shutdown tests run on Windows: they start the fixture with `CREATE_NEW_PROCESS_GROUP` and stop it with `CTRL_BREAK_EVENT`, which flint.os reads as SIGTERM. Exit codes 124 and 130 do not depend on which signal arrived. |
| `test_vibe_bench`: the queue-worker and tui-dashboard oracles | Their acceptance tests send SIGTERM and drive a pty. On Windows the test runs only the rest-notes oracle. |

`tools/load_bench.py` imports on Windows, so its parsers stay testable, but a load run stops with a plain error there: it uses `getrusage` and process groups.

### Path length

Windows paths stop at MAX_PATH (260 characters) unless a machine enables long paths. DUB's build cache nests the package, configuration and build-settings hash under `DUB_HOME`. A project inside a platform checkout, such as a Boot starter's example under `.flint/platform/boot-<commit>/legacy/...`, went past the limit with the project-local `.flint/dub`. On Windows, `flint build` therefore puts a project's DUB home at `<cache>/dub/<12 hex of the project path>` (FLINT_CACHE, else `<home>/.flint/cache`). Other hosts keep `<project>/.flint/dub`.

## Public API additions

None. `flint.engine.reactor.Backend.iocp` is already part of the frozen contract.

## Consequences for Linux and macOS

The Linux and macOS behaviour of every changed module is unchanged by construction: their code moved into `else` branches, re-indented only, apart from the `Thread`/`Fiber` import modules and the environment lookups in `flint.term`, which now call `core.stdc.stdlib.getenv`, the function `core.sys.posix.stdlib` re-exported. Every changed package and the CLI were type-checked for `-os=linux`, `-os=osx` and `-os=windows` with DMD's front end. They still have to run on venus (Linux) and pluto (macOS):

- `dub test` on both compilers for `:conc`, `:config`, `:log`, `:os`, `:prompt`, `:term` and `:test`, and for every package whose `core.thread` imports changed (all of them compile, but the import change touches tests across `:actuator`, `:cache`, `:codec`, `:mcp`, `:mq`, `:sql`, `:storage` and `:web`);
- `flint test --project apps/flint`, and `python3 -m unittest discover -s tests -p 'test_*.py'`;
- `python3 tools/gates.py --gate structural`;
- nothing for the DUB pipeline: the Windows overlay patch applies on Windows only, and the shared patch is unchanged;
- `flint build` and `flint test` for a project, since flint's DUB environment now skips `PATH` through a host check (identical on Linux);
- `flint test --project apps/flint` and a project build with `[profile.dev] debug = false`, since the manifest parser and the flag composition gained that key (a manifest without it builds exactly as before);
- `tools/native_build.py` with `ctest`, since `native/ffi/CMakeLists.txt` and `flint_codec_core.c` changed (both only under MSVC conditions);
- `dub test :reactor` on both compilers, since the accepted-socket `TCP_NODELAY` call and its test probe lost their POSIX guards and `accept_exhaustion.d` moved its watchdog out of the POSIX block (behaviour on Linux and macOS is unchanged);
- `flint toolchain install --plan`, `flint toolchain verify` and `tools/install_toolchains.py --compiler flint`, since `tools/install_toolchains.py` and the toolchain modules changed.
- one full `tools/measure_builds.py` run on the performance runner, to confirm unchanged output: the timing function now dispatches on the platform, the page size is read only where `os.sysconf` exists, and the native receipt path comes from `host_native_target()` (still `linux-x86_64-glibc` there);
