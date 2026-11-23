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

### 3. The kqueue reactor backend

`Backend.kqueue` is the readiness backend on macOS, and `automatic` selects it. It shares the owner loop, operation table, timers, mailboxes, fibers and cancellation of the epoll backend. Only the kernel interface in `flint.engine.reactor.sys` differs.

- **Readiness and EOF.** Filters are level-triggered, like epoll without `EPOLLET`. A read or write operation registers `EVFILT_READ` or `EVFILT_WRITE` while it is active, and the owner removes the filter when the direction goes idle. `EV_EOF` and `EV_ERROR` are reported as faults, as epoll's `HUP`, `RDHUP` and `ERR` are. EOF with data still delivers the data first, because the next `recv` returns it before 0.
- **Listener.** Each owner registers the listener in its own kqueue. kqueue has no `EPOLLEXCLUSIVE`, so every owner may wake for one connection. The losers' `accept` returns `EAGAIN`, which is ignored.
- **Descriptor exhaustion.** When `accept` fails with `EMFILE`, XNU drops the pending connection (`accept_nocancel`) instead of leaving it in the backlog. The reactor's behaviour is the same as on Linux: it backs off for one loop budget and keeps serving. The test therefore checks that the next connection is admitted.
- **Native watches.** A nested kqueue, registered in the owner's kqueue, replaces the nested epoll. Error readiness is always delivered, as on Linux: without read interest, the read filter stays registered with `NOTE_LOWAT` set to `INT_MAX`, so it fires only on EOF or a pending error.
- **Sockets.** Accepted and listening sockets are made nonblocking and close-on-exec with `fcntl`, and get `SO_NOSIGPIPE`, since Darwin has neither `accept4` nor `MSG_NOSIGNAL`.
- **Fiber pool.** Darwin's `MADV_DONTNEED` leaves pages resident. Parked pool stacks are replaced with a fresh fixed anonymous mapping instead, which keeps 1024 preallocated fibers out of resident memory, as on Linux.
- **Worker statistics.** CPU time comes from the Mach thread's basic info. Darwin exposes no per-thread context-switch counts, so those stay zero, and CPU pinning is unavailable (`affinityPinned` is false).

The reactor's tests that were Linux-only now run on macOS against `readinessBackend` (`tests/support.d`): epoll on Linux and kqueue on macOS. On Linux they still run against epoll, and against io_uring where liburing is linked.

### 4. Native providers and the C shims

`tools/native_build.py --target macos-arm64` builds all 17 C providers of the `ci` profile, plus wasmtime, with Apple clang (Xcode 26.6) and the existing per-library steps. That covers OpenSSL, libsodium, llhttp, nghttp2, curl, SQLite, libpq, librdkafka, zstd, zlib, brotli, libarchive, utf8proc, libyaml, SDL3, protobuf-c and hiredis. The macOS deployment target is 13.0, as the CMake recipe already set. There is no parallel build system, and Milestone 8's Conan recipes reuse the same steps.

Two changes in `native_build.py` were needed:

- curl gets the Linux protocol set: HTTP, HTTPS, WS, WSS, SMTP and SMTPS. It previously fell back to every protocol on macOS, including LDAP.
- curl links Apple's SystemConfiguration framework for its proxy settings.

The wasmtime extension overlay is portable Rust, so macOS builds it too, together with the WASI reference archive.

Flint's own shims in `native/ffi` were gated on `__linux__`. They now also build under `__APPLE__`, and the Linux text is unchanged. Three private headers carry the Darwin pieces:

- **`flint_wake.h`:** a nonblocking, close-on-exec pipe pair in place of `eventfd`, for the SQLite, PostgreSQL and Redis wake-ups. The read end is the descriptor exported for polling; the write end stays private. As with `eventfd`, a full pipe already holds a pending wake-up.
- **`flint_socket.h`:** a nonblocking, close-on-exec stream socket with `SO_NOSIGPIPE`, in place of `SOCK_NONBLOCK | SOCK_CLOEXEC` and `MSG_NOSIGNAL`.
- **`flint_clock.h`:** `FLINT_DEADLINE_CLOCK`, the clock that D's `MonoTime` reads:
  - `CLOCK_MONOTONIC` on Linux;
  - `CLOCK_UPTIME_RAW`, that is `mach_absolute_time`, on Darwin.

  Darwin's `CLOCK_MONOTONIC` also counts time asleep. On pluto it ran 44 s ahead of `MonoTime`, so every deadline D passed to a shim looked already expired to the shim. The SQLite offload test showed it: a `ROLLBACK` was reported as cancelled.

Where a shim uses a monotonic condition-variable clock (`pthread_condattr_setclock`), Darwin waits with `pthread_cond_timedwait_relative_np` instead, since it has no such attribute. The shims compile with `_DARWIN_C_SOURCE`, so Darwin's declarations stay visible next to the POSIX.1-2008 set.

Platform differences the shims absorb:

- **libarchive pathnames.** libarchive converts UTF-8 header names to NFC on Linux and to NFD on Darwin (`archive_string.c`), and has no option to change that. The archive reader recomposes them to NFC with CoreFoundation's `CFStringNormalize`, which every macOS native package already links, so a reader sees the same bytes on both platforms.
- **SQLite and WAL.** The local file systems allowed to use WAL are identified by `f_fstypename` (`apfs`, `hfs`, `tmpfs`) instead of Linux magic numbers.
- **Redis.** The connection socket gets `SO_NOSIGPIPE`, because the thread's SIGPIPE mask cannot contain a process-wide signal.
- **Desktop.** The SDL3 canvas backend builds on macOS, and `flint_desktop_main_thread` uses `pthread_main_np`. Its tests use SDL's dummy driver, because macOS has no EGL for the offscreen driver. The default system-webview backend is WKWebView, in `flint.engine.desktop.ffi.wkwebview`, bound through the Objective-C runtime as ADR-020 planned (described there). On macOS the `desktop` native profile selects the `wkwebview` system provider in place of `webkitgtk`. `native_build.py` records the SDK path and the SHA256 of each framework's `.tbd` stub (WebKit, AppKit and Foundation), links them with `-lobjc`, and sets version `FlintNativeWkwebview`. The emitted DUB block re-checks those digests. The thread-local allowlist gains `flint.engine.desktop.ffi.wkwebview.initialized`, the main-thread root matching the WebKitGTK module's entry. The platform lane builds the provider, and the desktop suite opens real AppKit windows in the GUI session the lane runs in.

On the D side, each package's `ffi`/`sys` module enables its native path on macOS next to Linux. Pipe-based wake-ups replace `eventfd` in `flint.engine.cache` and `flint.engine.security`. `os_sync_wait_on_address` replaces the futex in `flint.engine.sql`. `flint.engine.mcp` starts children with `posix_spawn`. `flint.engine.web` keeps its lazily zero-filled `mmap` connection slots, and `flint.conc` reads secure random bytes with `getentropy`, which previously returned `unsupported` on macOS.

Tests that selected `Backend.epoll` select `Backend.kqueue` on macOS. The `cache` package's remote store does the same in its source. That keeps the readiness backend under test on Linux unchanged.

Providers keep the flags `native_build.py` gives them on Linux. C inside a Flint project follows `policy/native-c.toml`, whose `[macos]` table replaces the Linux fields on macOS:

- **Compiler.** The pinned LLVM 22.1.8 release for macOS arm64 (`LLVM-22.1.8-macOS-ARM64.tar.xz`, sha256 in `policy/toolchains.json`, checked against the release's `.jsonl` attestation). `tools/install_toolchains.py --compiler clang` installs it to `.tools/LLVM-22.1.8-macOS-ARM64`, with `clang`, `clang-tidy`, `lld` and `ld64.lld`. `flint build` passes `-isysroot` with the SDK that `xcrun --show-sdk-path` names, and reports `FLINT-E0816` when no SDK is installed.
- **Hardening.** The Linux set without `-fstack-clash-protection`, which LLVM rejects for Darwin arm64. `_FORTIFY_SOURCE=3`, `-fstack-protector-strong`, `-fPIE` and `-ftrivial-auto-var-init=zero` are kept.
- **Link hardening.** None is passed. `-z relro -z now` are ELF-only. Apple's linker already writes position-independent executables whose imports bind through chained fixups (`LC_DYLD_CHAINED_FIXUPS`), and dyld maps those pages read-only after binding, which is what full RELRO gives on Linux. `tests/test_flint_native_c.py` checks for the `PIE` flag and the chained-fixups load command on macOS, where it checks `BIND_NOW` and `GNU_RELRO` on Linux.
- **clang-tidy.** On macOS, `flint check` runs it with `-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0`. The Darwin SDK's fortify macros turn `strcpy` into `__builtin___strcpy_chk`, which hides the call from the `insecureAPI` checks the policy enables.

ld64 drops C functions that the executable never calls. The native-C test therefore looks for the fixture's symbol in the cached object on macOS, not in the dev binary.

### 5. The platform lane

`python3 tools/ci.py platform --target macos-arm64` builds the providers and wasmtime with the pinned Rust. It then runs every package's `dub test`, the compile-negative fixtures and the BetterC fixtures. Each runs on both compilers available on macOS:

- `ldmd2`, which fills the dev and test profiles' DMD role;
- `ldc2`.

On macOS it then runs `flint test` for the packages with fixture peers and `flint test mq --scenarios`, after installing those peers, NATS, Kafka and the Temurin aarch64 macOS JRE. The JRE is a `macos-arm64` host override in `policy/peer-lock.json`, and `policy/test-peers.toml` names scenario binaries through the `{dub}`, `{dmd}` and `{host}` placeholders that `flint` expands.

Linux lanes keep running `ldc2` only. On macOS the lane sets `FLINT_DUB_PIPELINE=0`. Its receipt, `artifacts/platforms/macos-arm64.json`, is what Gate 6's `macos-arm64` entry reads. The lane expects `ldc2`, `ldmd2` and the Flint DUB first on `PATH`:

```bash
export PATH="$PWD/.tools/dub-1.43.0/bin:$PWD/.tools/ldc2-1.43.0-osx-arm64/bin:$PWD/.tools/bin:$PATH"
python3 tools/ci.py platform --target macos-arm64
```

### 6. Build measurements on pluto

ADR-025 names pluto (`flint-perf-macos-arm64-v1`) as the macOS measurement runner, so the measurement tools run there.

- **Go.** `install_toolchains.py --compiler go` installs the pinned Go 1.27.4 darwin-arm64 archive. Its digest comes from go.dev's listing, whose linux-amd64 digest equals the existing lock entry.
- **`tools/compare_go_builds.py`.** It uses `ldmd2` on macOS and turns the DUB pipeline off.
- **`tools/measure_builds.py`.** It accepts the macOS runner and changes these pieces:
  - process-tree RSS comes from libproc's task info, which is what psutil reports as RSS on macOS;
  - the size audit uses Apple `strip` and `otool -L`, and only `/usr/lib` and system frameworks may stay dynamic;
  - `ldmd2` is the default DMD-role compiler.
- **Benchmark probes.** All of them build on both profiles. The reactor's provider-equivalent baseline gained a kqueue branch, and it echoes the same checksum as the Flint probe. The security probe counts native allocations through libSystem's `malloc_logger` hook, because Apple's linker has no `--wrap`.

Baseline on pluto, 9 paired trials, medians. Flint is the `ldmd2` dev profile; Go builds from a primed standard-library cache:

| App | Flint cold | Go cold | Ratio | Flint edit | Go edit | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `bench-cli` | 1736 ms | 163 ms | 10.66 | 376 ms | 169 ms | 2.23 |
| `bench-rest` | 2067 ms | 431 ms | 4.79 | 460 ms | 296 ms | 1.56 |

This is the baseline the DMD arm64 work (ADR-025 section 3) has to beat. `ldmd2` misses the compile-speed gate by a wide margin, which is why ADR-025 keeps it as an interim setting only.

### 7. The flint CLI

`apps/flint/src/flint_tool/toolchain/host.d` describes the toolchain layout per host. On macOS:

- `dmd` resolves to `ldc2-1.43.0-osx-arm64/bin/ldmd2`, pinned to the LDC version;
- `dub` resolves to `dub-1.43.0/bin/dub`;
- the "fork" is the patched DUB alone, and the toolchain receipt records the LDC archive, the `ldmd2` and `dub` hashes and the DUB patch hash, with an empty DMD patch.

`flint toolchain install` runs `--compiler ldc`, `--compiler dub` and the quality tools. `flint toolchain verify`, `flint doctor`, `flint build`, `flint test` and `flint check` then work, and `tools/install_toolchains.py --compiler flint` bootstraps the CLI as on Linux. The host target is `macos-arm64`, and the native-provider check looks for that install.

## Public API additions

None so far. `flint.engine.reactor.Backend.kqueue` is already part of the frozen contract.

## Consequences for Linux

The Linux behaviour of every changed module is unchanged by construction. The Linux branches were type-checked by cross-compiling with LDC for `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu` and `x86_64-unknown-linux-musl`. They still have to run on venus:

- `dub test` on both compilers for `:log`, `:os`, `:term`, `:prompt` and `:test` (their C files changed under `#if defined(__APPLE__)` only);
- `dub test :reactor` on both compilers, with and without liburing. The Linux-only test blocks became `version (Posix)` and use `readinessBackend` (epoll) where they named `Backend.epoll`, and the native-watch code moved under `version (ReactorNativeWatches)`;
- `python3 tools/native_build.py --profile ci --phase build --emit-dub` and `ctest` of `native/ffi`, followed by `dub test` on both compilers for every package with a native provider: `:http`, `:web`, `:sql`, `:cache`, `:mq`, `:rpc`, `:mail`, `:security`, `:codec`, `:wasi` and `:desktop`. Every shim's Linux text is unchanged under `#if`, except that monotonic clock reads name `FLINT_DEADLINE_CLOCK`, which is `CLOCK_MONOTONIC` on Linux;
- `dub test` on both compilers for `:conc`, `:mcp` and `:schedule`;
- the platform and sanitizer lanes of `tools/ci.py` (its macOS-only branches do not run on Linux);
- `flint test --project apps/flint`, and `python3 -m unittest discover -s tests -p 'test_*.py'`;
- `python3 tools/gates.py --gate structural`, since `tools/gates.py` changed;
- `flint toolchain install --plan`, `flint toolchain verify` and `tools/install_toolchains.py --compiler flint`, since `tools/install_toolchains.py` and the toolchain modules changed;
- `dub test :desktop` on both compilers, with and without the `desktop` profile's WebKitGTK provider. `platform.d` and the tests now select the webview through `FlintSystemWebView`, which `FlintNativeWebkitgtk` sets on Linux, so the Linux text is equivalent. The `native/conan-index` recipes were regenerated for the new `native_build.py` hash, so Conan rebuilds its packages;
- `python3 -m unittest tests.test_flint_native_c` and `flint check` on a project with embedded C, since `cbuild.d` reads the new `[macos]` table (ignored on Linux) and `tools/install_toolchains.py --compiler clang` gained the Darwin download.
