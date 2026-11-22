# ADR-024: Native macOS arm64

Status: **proposed** on 2026-11-22. This is the macOS track of [ADR-021](ADR-021-flint-platform.md) section 9, started early at the project owner's request. Gate 6 keeps reporting `macos-arm64` as failing ([ADR-017](ADR-017-milestone-6-decisions.md) decision 2) until the platform lane's receipt passes.

## Context

Flint is certified on Linux. macOS arm64 needs:

- a toolchain;
- Darwin equivalents for the Linux-only calls in the packages' `sys` and `ffi` modules;
- a kqueue reactor backend;
- native providers built with Apple clang;
- a platform lane whose receipt satisfies Gate 6.

The reference machine is `pluto`:

- Apple M1 (8 cores), 16 GB;
- macOS 26.4, Xcode 26.6, Apple ld-1267.

DMD has no arm64 code generator. That leaves two candidates for the development profile:

- LDC, native, with its fastest debug settings;
- the official DMD x86-64 release under Rosetta 2.

## Decisions

### 1. Toolchain

**LDC 1.43.0 for macOS arm64** is the only compiler. `tools/install_toolchains.py --compiler ldc` installs `ldc2-1.43.0-osx-arm64.tar.xz`. Its checksum in `policy/toolchains.json` (`5e3323…5fed`) equals both the GitHub release asset digest and the entry in the release's `ldc2-1.43.0.sha256sums.txt`.

**The DMD role of the dev and test profiles is filled by `ldmd2`**, LDC's DMD-compatible driver. It accepts the canonical flags in `policy/profiles.toml` unchanged, so the profile file stays the single source of flags and has no per-host variant.

| Build on pluto (median) | Cold | Incremental |
| --- | ---: | ---: |
| `bench-cli`, LDC `-d-debug -g -boundscheck=on` | 1.66 s | 0.42 s |
| `bench-cli`, LDC, same, `-link-defaultlib-shared` | 1.65 s | 0.41 s |
| `bench-cli`, LDC, without `-g` | 1.48 s | 0.40 s |
| `bench-cli`, `ldmd2` with the dev profile flags | 1.71 s | 0.38 s |
| `bench-cli`, DMD 2.114.0 x86-64 under Rosetta | 3.44 s | 0.70 s |
| `:serde` unittest build, LDC / DMD under Rosetta | 0.86 s / 1.26 s | |
| `:cli` unittest build, LDC / DMD under Rosetta | 0.77 s / 1.43 s | |

Cold runs use five trials (three for the unittest builds) with an empty DUB cache. Incremental runs touch the application source. The Rosetta numbers include `-Xcc=-arch -Xcc=x86_64 -Xcc=-Wl,-ld_classic`, which DMD needs to link at all.

DMD under Rosetta is rejected:

- It is about twice as slow.
- Apple ld-1267 rejects every archive DMD writes, including the release's own `libphobos2.a`, because 64-bit Mach-O members are not 8-byte aligned. Linking needs the deprecated `-ld_classic`, which Apple is removing.
- It produces x86-64 binaries that run emulated, so they test neither arm64 code generation nor the arm64 ABI.

The development profile keeps `-g`. Debug information costs 0.18 s of a cold build, and `flint run --debug` needs it. A shared default library saves only 1%, and the executable would then depend on the LDC installation at run time.

**DUB is the Flint-patched DUB 1.43.0**, built from the pinned source archive with LDC (`--compiler dub`, into `.tools/dub-1.43.0`). The DUB bundled with LDC is 1.42.0, which does not match the pin.

The fork's parallel DUB pipeline stays off on macOS (`FLINT_DUB_PIPELINE=0`):

- DUB treats `ldmd2` as DMD, so the pipeline would engage;
- it archives in process in the GNU format, with a `/` symbol index member, which Apple ld rejects.

Sequential `ldmd2` builds are as fast as plain LDC builds (table above). Porting the pipeline's archiver to the Darwin format is possible future work.

There is no compile server on macOS. It is a feature of the forked DMD. `flint daemon start` reports FLINT-E0810 there instead of trying to start one.

The structural gate's mixin audit runs DMD's front end only. `tools/gates.py` and `flint check` use `ldmd2` when no `dmd` is installed, and skip expansions under LDC's `import/` directory, as they already skip DMD's `src/`.

The tools need Python 3.12 or newer (`tarfile` extraction filters, `tomllib`). macOS ships 3.9, so `python3` must resolve to a newer interpreter, such as Homebrew's.

### 2. Darwin platform layer

Darwin paths sit behind `version (OSX)` in D and `__APPLE__` in C, inside each package's own `sys`/`ffi` modules. Linux code is unchanged apart from moving Linux-only imports into their branches. Values druntime omits for Darwin are declared locally with their `<sys/*.h>` source: `O_CLOEXEC`, `O_DIRECTORY`, `F_DUPFD_CLOEXEC`, `MSG_DONTWAIT`, `clock_gettime`, `flock` and so on.

Where Darwin semantics differ, this is what Flint does:

- **SIGPIPE.** Darwin raises SIGPIPE for a pipe write at the whole process, so a thread's signal mask cannot contain it, as the log sink's worker and the terminal session do on Linux. Both mark their descriptors with `F_SETNOSIGPIPE`, and writes to a closed reader then fail with EPIPE. The mark belongs to the open file description, so an inherited standard stream the logger duplicated shares it with the rest of the process. Writes to it then also fail with EPIPE instead of raising SIGPIPE.
- **Child processes (`flint.os`).** Children start with `posix_spawn`, using `POSIX_SPAWN_CLOEXEC_DEFAULT`, `SETPGROUP`, `SETSIGDEF` and `SETSIGMASK`. This replaces `fork` plus `close_range` in the child, and Darwin has no `close_range`.
  - Exec failures are reported synchronously with the same status and message the Linux startup receipt gives.
  - The working directory is opened with `O_SEARCH` before spawning, so a bad directory reports the same error as Linux's `chdir`, then applied with `posix_spawn_file_actions_addfchdir_np`.
  - Exit notification uses a kqueue `EVFILT_PROC`/`NOTE_EXIT` descriptor in place of a pidfd, and the supervisor's wake-up uses a kqueue `EVFILT_USER` descriptor in place of an eventfd. Each kqueue is one pollable descriptor, so the supervisor loop is unchanged.
  - Darwin's `kill` returns EPERM, not ESRCH, for a process group whose only members are zombies. That counts as delivered once the leader has exited.
- **Glob containment (`flint.os`).** `openat` with `O_RESOLVE_BENEATH | O_NOFOLLOW_ANY`, and `fstatat` with `AT_RESOLVE_BENEATH`, give the guarantees `openat2` with `RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS` gives on Linux. They were checked against escaping symbolic links, `..` and absolute paths. An escape fails with ENOTCAPABLE instead of EXDEV, and both mean the entry is no longer inside the root. `fstatat` needs only search permission, like `O_PATH`.
- **`siginfo_t`.** druntime declares Darwin's `siginfo_t` as 72 bytes; `<sys/signal.h>` makes it 104. `waitid` overwrote the stack until `flint.os` used its own layout. This should be reported upstream to druntime.
- **Futex.** The log consumer's park and wake use `os_sync_wait_on_address_with_timeout` and `os_sync_wake_by_address_all`, documented in libSystem since macOS 14.4.
- **`pipe2`.** Darwin has none. Pipes are created with `pipe` and then marked close-on-exec, so a concurrent `fork` and `exec` elsewhere could inherit them for that instant. Children Flint starts never do, because of `POSIX_SPAWN_CLOEXEC_DEFAULT`.
- **Terminal.** The PTY-master check uses `TIOCPTYGNAME` instead of `TIOCGPTN`, `poll` with a rounded-up millisecond timeout replaces `ppoll`, and `/proc/self/fd` reopening falls back to `ttyname_r`, as it already did where `/proc` is missing.
- **Secrets.** `explicit_bzero` becomes `memset_s`.

Tests that observed Linux-only state use Darwin equivalents with the same assertions:

| Linux | macOS |
| --- | --- |
| `/proc/<pid>` | `kill(pid, 0)`, and `sysctl` `kinfo_proc` for zombie state |
| `/proc/self/fd` | `/dev/fd` |
| `/dev/full` | a pipe without a reader |
| `F_SETPIPE_SZ` | pre-filling a nonblocking pipe |

### 3. The flint CLI

`apps/flint/src/flint_tool/toolchain/host.d` describes the toolchain layout per host. On macOS:

- `dmd` resolves to `ldc2-1.43.0-osx-arm64/bin/ldmd2`, pinned to the LDC version;
- `dub` resolves to `dub-1.43.0/bin/dub`;
- the "fork" is the patched DUB alone, and the toolchain receipt records the LDC archive, the `ldmd2` and `dub` hashes and the DUB patch hash, with an empty DMD patch.

`flint toolchain install` runs `--compiler ldc`, `--compiler dub` and the quality tools. `flint toolchain verify`, `flint doctor`, `flint build`, `flint test` and `flint check` then work, and `tools/install_toolchains.py --compiler flint` bootstraps the CLI as on Linux. The host target is `macos-arm64`, and the native-provider check looks for that install.

## Public API additions

None so far. `flint.reactor.Backend.kqueue` is already part of the frozen contract.

## Consequences for Linux

The Linux behaviour of every changed module is unchanged by construction. The Linux branches were type-checked by cross-compiling with LDC for `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu` and `x86_64-unknown-linux-musl`. They still have to run on venus:

- `dub test` on both compilers for `:log`, `:os`, `:term`, `:prompt` and `:test` (their C files changed under `#if defined(__APPLE__)` only);
- `flint test --project apps/flint`, and `python3 -m unittest discover -s tests -p 'test_*.py'`;
- `python3 tools/gates.py --gate structural`, since `tools/gates.py` changed;
- `flint toolchain install --plan`, `flint toolchain verify` and `tools/install_toolchains.py --compiler flint`, since `tools/install_toolchains.py` and the toolchain modules changed.
