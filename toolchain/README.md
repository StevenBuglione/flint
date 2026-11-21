# Flint DMD and DUB toolchain fork

This directory holds the Flint fork of the pinned D toolchain as patches against unmodified upstream sources:

- `dmd-2.114.0-flint.patch` applies to the compiler source bundled in the pinned `dmd.2.114.0.linux.tar.xz` release (`dmd2/src/dmd`).
- `dub-1.43.0-flint.patch` applies to the DUB v1.43.0 source archive pinned in `policy/toolchains.json`.
- `dmd-server-prelude.txt` lists the druntime and Phobos modules the compile server keeps analysed.

The D language, the compiler's diagnostics and the build commands developers run do not change. Applications still run `dub build`. The fork changes how the toolchain schedules and reuses work.

## Install

On Linux x86-64 glibc, from the checkout root:

```bash
python3 tools/install_toolchains.py --compiler dmd --dmd-linker mold --flint-fork
export PATH="$PWD/.tools/dmd2/linux/bin64:$PATH"
```

The installer extracts the checksum-locked DMD, LDC and DUB sources, applies the patches, builds DMD with LTO and profile-guided optimisation trained on this repository's applications, builds DUB with LDC, and installs both over the pinned executables. The upstream executables remain beside them as `dmd.upstream` and `dub.upstream`. `--no-pgo` skips the profile training, which takes about three minutes. `--dmd-linker` is optional; the direct-link path uses whichever linker the DMD configuration selects.

## What the DMD fork changes

**Resident toolchain compile server.** The first compile starts a background server for its compiler flags and compiles normally. The server parses and semantically analyses the modules in `dmd-server-prelude.txt`, then keeps two pre-forked workers per hardware thread waiting on a private Unix socket under `$XDG_RUNTIME_DIR/flint-dmd`. Later compiles with the same flags hand their arguments, working directory, environment and standard streams to a worker. The worker continues the ordinary driver as if earlier imports had already loaded those toolchain modules, then reports the exit status. Diagnostics go to the caller's terminal unchanged.

The server only ever holds druntime and Phobos. Project and application modules are compiled from source by every build. A worker refuses the request before producing output, and the caller compiles in-process with the upstream driver path, when:

- a `-version=` or `-debug=` identifier was evaluated while the prelude loaded,
- an extra import path contains an entry that could shadow a preloaded package,
- a root module belongs to a preloaded package.

The caller never uses the server for `-v`, `-deps`, `-makedeps`, `-X`, `-H`, `-D`, `-i`, `-run`, `-mixin`, `-mv`, `-lowmem`, `-conf`, `-vtemplates`, standard input, ImportC sources, or when a `dmd.conf` exists in the working directory or `$HOME`. The server key includes the compiler executable's identity, its configuration file and every semantic flag. Servers exit after 30 idle minutes.

**Direct linking.** The first link asks the C compiler driver, once, which linker command `cc -###` would run for marker inputs, and caches that expansion under `$XDG_CACHE_HOME/flint-dmd`. Later links execute that linker directly with the same startup files, search paths and libraries, instead of the `cc` → `gcc` → `collect2` → `ld` process chain. The cache key covers the driver executable, its `-B`/`-fuse-ld` switches and the toolchain environment variables it reads. Shared libraries, static executables, a custom `CC` and any unrecognised driver switch use `cc` as before. mold runs with four threads.

## What the DUB fork changes

**Parallel build pipeline.** For DMD builds of executables and static libraries without pre- or post-build commands, DUB plans every out-of-date target up front, splits their sources into chunks sized for the machine's hardware threads, and compiles all chunks concurrently with `posix_spawn`. D separate compilation only needs dependency sources, not their objects, so every package compiles at the same time. A package split into several chunks is compiled with `-allinst`, so template instances that more than one chunk could assume another chunk emits are always available to the linker; the linker folds the duplicates. A target whose files are not all resolvable through its import paths, such as a test root importing modules whose names differ from their paths, compiles in a single invocation as before. Up-to-date checks, rebuild propagation to dependents, cache directories and the static libraries in the DUB cache are unchanged. Libraries are archived in-process with a GNU symbol index.

**Smaller overheads.** The compiler platform probe is cached by the compiler executable's identity. Targets are hard-linked rather than copied out of the cache. DUB exits without druntime teardown once its output is complete.

## Controls

| Variable | Effect |
| --- | --- |
| `FLINT_DMD_SERVER=0` | Never use or start the compile server |
| `FLINT_DMD_SERVER_IDLE=<seconds>` | Server idle lifetime (default 1800) |
| `FLINT_DMD_SERVER_POOL=<n>` | Pre-forked workers per server |
| `FLINT_DMD_SERVER_TRACE=<file>` | Append worker timing events |
| `FLINT_DMD_DIRECT_LINK=0` | Always link through `cc` |
| `FLINT_LINK_THREADS=<n>` | mold thread count (default 4) |
| `FLINT_DUB_PIPELINE=0` | Use DUB's sequential build |
| `FLINT_DUB_TRACE=1` | Print DUB phase and per-job timings |

Measurements, test evidence and the remaining caveats are in [the Linux compile-time fork report](../docs/milestones/06-linux-compile-fork.md). The measurement interpretation is recorded in [ADR-016](../docs/adr/ADR-016-resident-toolchain-compile-server.md).
