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

### 2. Toolchain: the upstream DMD and DUB first

The first stage builds with the **upstream DMD 2.114.0 and its bundled DUB 1.43.0**, which matches the DUB pin, and LDC 1.43.0. `install_toolchains.py --compiler dmd` refuses `--flint-fork` and `--dmd-linker` on Windows for now.

The Flint toolchain fork (ADR-016, `toolchain/README.md`) does not build on Windows as it stands:

- **The compile server** forks pre-analysed workers, which take over a caller's file descriptors through a Unix socket. Windows has no `fork`. ADR-025 section 4 replaces it there with a pool of pre-warmed, single-use worker processes reached through named pipes.
- **The parallel DUB pipeline** spawns compilers with `posix_spawn` and archives in process in the GNU `ar` format. Windows needs `CreateProcessW` and COFF archives.
- **Direct linking** caches the expansion of the `cc` → `collect2` → `ld` chain. On Windows the cached command is `lld-link` or `link.exe`.

Those ports are later stages of this Windows track (ADR-025's order of work, item 3). Until they land and are measured, the Windows compile-speed gate reports failing. The Windows VM gives diagnostic numbers only (ADR-025 section 5).

Consequences of the first stage:

- `flint_tool.toolchain.host` gains `upstreamDmdHost`. On Windows, `dmd` and `dub` resolve to `dmd2\windows\bin64`, executables carry `.exe`, and `PATH` lists use `;`.
- There is no fork to verify. The toolchain receipt records the DMD archive digest and the hashes of the installed `dmd.exe`, `dub.exe` and `ldc2.exe`, with empty patch hashes, so canonical builds still trace every binary to a pinned archive.
- `flint toolchain install` runs `--compiler dmd`, `--compiler ldc` and the quality tools, calling Python as `python`, the name python.org installs.
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

Verified on the Windows VM at the commit that adds this ADR:

- `tools/install_toolchains.py --compiler dmd`, `--compiler ldc` and `--compiler flint`; `flint toolchain install`, `flint toolchain verify` (receipt verified) and `flint doctor` (exit 0);
- `flint test --project apps/flint`: 15 of 15 modules;
- `dub test` with DMD and with LDC for `:arena`, `:conc`, `:validate`, `:config`, `:serde`, `:di`, `:log`, `:cli`, `:os`, `:test`, `:ui-signals` and `:term`;
- `tools/gates.py --gate structural` for those 12 packages, and `tools/quality.py` over the whole tree (0 issues).

Next:

- `:style` links the utf8proc provider, so it waits for the MSVC native build, and `:tui`, `:widgets` and `:prompt` wait for `:style`;
- the IOCP reactor backend, then the packages above the reactor;
- the native providers under MSVC hardening (`/guard:cf`, `/GS`, `/sdl`, and `/W4 /WX` for Flint's own C);
- the `windows-x86_64` platform lane for Gate 6;
- ADR-025's Windows speed features (compile server, pipeline, direct linking).

## Public API additions

None. `flint.reactor.Backend.iocp` is already part of the frozen contract.

## Consequences for Linux and macOS

The Linux and macOS behaviour of every changed module is unchanged by construction: their code moved into `else` branches, re-indented only, apart from the `Thread`/`Fiber` import modules and the environment lookups in `flint.term`, which now call `core.stdc.stdlib.getenv`, the function `core.sys.posix.stdlib` re-exported. Every changed package and the CLI were type-checked for `-os=linux`, `-os=osx` and `-os=windows` with DMD's front end. They still have to run on venus (Linux) and pluto (macOS):

- `dub test` on both compilers for `:conc`, `:config`, `:log`, `:os`, `:term` and `:test`, and for every package whose `core.thread` imports changed (all of them compile, but the import change touches tests across `:actuator`, `:cache`, `:codec`, `:mcp`, `:mq`, `:sql`, `:storage` and `:web`);
- `flint test --project apps/flint`, and `python3 -m unittest discover -s tests -p 'test_*.py'`;
- `python3 tools/gates.py --gate structural`;
- `flint toolchain install --plan`, `flint toolchain verify` and `tools/install_toolchains.py --compiler flint`, since `tools/install_toolchains.py` and the toolchain modules changed.
