# Flint DMD and DUB toolchain fork

This directory holds the Flint fork of the pinned D toolchain as patches against unmodified upstream sources:

- `dmd-2.114.0-flint.patch` applies to the compiler source bundled in the pinned `dmd.2.114.0.linux.tar.xz` release (`dmd2/src/dmd`).
- `dub-1.43.0-flint.patch` applies to the DUB v1.43.0 source archive pinned in `policy/toolchains.json`.
- `dmd-server-prelude.txt` lists the druntime and Phobos modules the compile server keeps analysed.
- `dmd-2.114.0-flint-darwin.patch`, `druntime-2.114.0-flint.patch` and `phobos-2.114.0-flint.patch` support arm64 hosts. The first is the macOS overlay of the compile server and direct linking; the other two apply to the runtime libraries built for AArch64. `arm64/` holds the AArch64 regression tests and their documentation.
- `dub-1.43.0-flint-darwin.patch` is the macOS overlay of the DUB patch: the parallel pipeline's in-process archiver writes Apple's BSD format, with a sorted `__.SYMDEF SORTED` table of contents and every member's data aligned to 8 bytes, which Apple's linker requires. `tools/install_toolchains.py --compiler dub` applies it on macOS after the shared patch.

- `dfmt-0.15.2-stack-udas.patch` applies to dfmt 0.15.2. Its `dfmt_stack_udas` option, which `.editorconfig` turns on, puts each user-defined attribute (`@Name`, `@Name(args)`) of a class, struct, union, interface, enum, template, function, constructor, destructor or field on its own line above the declaration, as Java lays out annotations. The compiler's attributes (`@safe`, `@nogc`, `@property`, ...), parameter attributes, `@("name") unittest` and declarations inside function bodies keep their layout, and the stack stops at the first other attribute (`public @Bean` stays on one line). `tools/install_quality_tools.py` builds it with `libdparse-0.25.1-named-uda.patch` into `.tools/bin/dfmt`, whose `--version` ends in `+flint.stack-udas`; `tools/quality.py`, `flint check` and `flint fmt` refuse any other dfmt. Format with `flint fmt`, or `.tools/bin/dfmt --config . -i <files>`.

The D language and the build commands developers run do not change. The compiler's diagnostics change only with the fork's own `-verror-hide` switch. Applications still run `dub build`. The fork changes how the toolchain schedules and reuses work.

## Install

On Linux x86-64 glibc, from the checkout root:

```bash
python3 tools/install_toolchains.py --compiler dmd --flint-fork
export PATH="$PWD/.tools/dmd2/linux/bin64:$PATH"
```

The installer extracts the checksum-locked DMD, LDC and DUB sources, applies the patches, builds DMD with LTO and profile-guided optimisation trained on this repository's applications, builds DUB with LDC, and installs both over the pinned executables. The upstream executables remain beside them as `dmd.upstream` and `dub.upstream`. `--no-pgo` skips the profile training, which takes about three minutes. On Linux x86-64 the installer also installs the pinned mold (`policy/toolchains.json`, `--compiler mold`) and configures DMD to link with it, as the Milestone 6 measurements did. `--dmd-linker <ld.lld or mold>` selects another installed linker, and `--dmd-linker system` keeps the C compiler's default (usually ld.bfd, several times slower). `flint doctor` warns with FLINT-E0823 when DMD links with the default.

## What the DMD fork changes

**Resident toolchain compile server.** The first compile starts a background server for its compiler flags and compiles normally. The server parses and semantically analyses the modules in `dmd-server-prelude.txt`, then keeps two pre-forked workers per hardware thread waiting on a private Unix socket under `$XDG_RUNTIME_DIR/flint-dmd`. Later compiles with the same flags hand their arguments, working directory, environment and standard streams to a worker. The worker continues the ordinary driver as if earlier imports had already loaded those toolchain modules, then reports the exit status. Diagnostics go to the caller's terminal unchanged.

The server holds druntime and Phobos, plus the platform modules a build names in `FLINT_DMD_SERVER_PRELUDE` (below). Project and application modules are compiled from source by every build. A worker refuses the request before producing output, and the caller compiles in-process with the upstream driver path, when:

- a `-version=` or `-debug=` identifier was evaluated while the prelude loaded, unless the platform prelude defines it,
- an extra import path contains an entry that could shadow a preloaded package,
- a root module belongs to a preloaded package,
- the request lacks one of the platform prelude's import paths or version identifiers.

**Platform prelude (ADR-030 section 5).** `flint build` writes `.flint/generated/platform/dmd-server-prelude.txt` and passes it as `FLINT_DMD_SERVER_PRELUDE`: `-I<dir>` and `-version=<id>` lines, the build's DFLAGS, then the platform's module names. The server applies the paths and versions, then analyses those modules after the toolchain's, so an edit build analyses only the project's own modules. Windows' worker pool does not read it yet. The file's content and `DFLAGS` are part of the server key, so a platform change starts a new server. A request may name the prelude's import paths by any spelling that resolves to the same directory, as DUB's relative paths do. These rules keep a served compile's objects byte-identical to an in-process compile's:

- `-allinst` compiles (packages DUB splits into chunks, and Flint AOT's generated platform library) use the toolchain-only server. Under `-allinst` an import makes the root module emit every instance the imported module instantiates, and a preloaded module's instances would escape that.
- DMD skips an instance that a non-root module also instantiates, because that module's object emits it. The server ignores such instantiations by preloaded modules the request does not import, directly or not, because those modules would not have been loaded in-process.
- A speculative instance the server created while preloading (inside CTFE or `__traits(compiles)`) sits in the members of the module that declares the template, because no root module existed yet. In-process it would sit in a root module's. When a request instantiates it for real, the fork moves it to the root module, so it gets the same code generation chance. Before this, a served object left druntime instances such as `core.checkedint.mulu` and `__arrayAlloc!char` undefined, which an in-process object emits as weak symbols. The linker then pulled different archive members, and in one petclinic static link a different set of modules.
- The server runs `backend_init` before preloading, as an ordinary compile runs it before semantic analysis: the inline assembler encodes addresses by the target's pointer size, and without it, preloaded instances such as `mulu` held 16-bit addressing. Each request restores the backend state of a fresh process before its own `backend_init` (which accumulates configuration flags), so the request's switches alone decide it.

`CompileServerPreludeTests` compiles a module using those instances once in-process and twice served, plain and with `-O -g -release`, and requires byte-identical objects.

A server that cannot load its prelude, for example a missing module, leaves `<socket>.failed`. Clients then compile in-process for ten minutes instead of starting it again. gs-rest-service's edit build compiles its one project job in 72 ms instead of 141 ms with the toolchain-only server (186 ms in-process).

The caller never uses the server for `-v`, `-deps`, `-makedeps`, `-X`, `-H`, `-D`, `-i`, `-run`, `-mixin`, `-mv`, `-lowmem`, `-conf`, `-vtemplates`, standard input, ImportC sources, or when a `dmd.conf` exists in the working directory or `$HOME`. The server key includes the compiler executable's identity, its configuration file and every semantic flag. Servers exit after 30 idle minutes.

**Direct linking.** The first link asks the C compiler driver, once, which linker command `cc -###` would run for marker inputs, and caches that expansion under `$XDG_CACHE_HOME/flint-dmd`. Later links execute that linker directly with the same startup files, search paths and libraries, instead of the `cc` → `gcc` → `collect2` → `ld` process chain. The cache key covers the driver executable, its `-B`/`-fuse-ld` switches and the toolchain environment variables it reads. Shared libraries, static executables, a custom `CC` and any unrecognised driver switch use `cc` as before. mold runs with four threads.

**Side-effect-free `-ftime-trace` names.** Upstream DMD 2.114.0 names an event only when it lasted longer than the trace granularity. Naming a template instance prints its arguments, and printing a variable argument expands its value. When that variable is a manifest constant whose initializer is still being evaluated, as `core.lifetime.hasContextPointers` is while `move` instantiates over a struct's fields, the expansion reports a spurious "recursive initialization of constant" and the compile fails. Whether it fails depends on how long the instantiation took, so it struck about one traced compile in 250 under load and nearly every compile with `-ftime-trace-granularity=0`. While the profiler names an event, the fork prints such an argument as written instead of expanding it. Nothing changes without `-ftime-trace`: object files are byte-identical to the previous build.

**Condensed library errors: `-verror-hide=<directory>`.** An error raised inside a hidden directory is reported at the innermost frame of its instantiation trace outside the hidden directories, which is the user's line. The hidden frames collapse into one line naming where the error was raised, and a library `static assert` message loses DMD's `static assert:  "…"` wrapper. flint passes the switch for druntime, Phobos and the Flint packages unless `--verbose` is given. Only diagnostic text changes: object files are byte-identical with and without the switch, and with the previous build (ADR-027 section 5).

**AArch64 code generator (ADR-025 section 3).** Upstream DMD 2.114.0's unfinished `-marm64` back end is completed for Linux AArch64 (ELF) and macOS arm64 (Mach-O). The changes include object files, relocations, DWARF exception handling, thread-local storage, the AAPCS64 and Apple calling conventions, and code generation fixes, each with a regression test in `arm64/`. On arm64 hosts, `tools/install_toolchains.py --compiler dmd` builds the fork, druntime and Phobos from source. x86-64 code generation is unchanged. [arm64/README.md](arm64/README.md) gives the status, the decisions and the list of fixes offered upstream.

**Collectable classes: `-fno-moduleinfo-localclasses` (ADR-030 section 5).** Each module's `ModuleInfo` lists every class the module declares, so every `TypeInfo_Class`, vtable and virtual method stays referenced, and the linker's `--gc-sections` cannot drop a class that nothing uses. With the switch, the fork leaves that list empty, as LDC's switch of the same name does, so the release and size profiles pass one flag on either compiler. Nothing else changes: `Object.factory` and `TypeInfo_Class.find` return null for classes of modules compiled with it, and Flint never constructs from a string name. druntime needs no change for that. DMD itself links without `--gc-sections`, and the release `dmd.conf` adds `--export-dynamic`, which keeps every symbol. A DMD build therefore gains only when it also links with `-L--gc-sections` and without `--export-dynamic`. The dev profile keeps both, because druntime's backtraces name functions through the dynamic symbol table. `tools/measure_class_gc.py` measures the gain on a generated program of 2,000 classes, of which 50 are used.

**Native Flint AOT extraction: `-flint-aot-extract=<request file>` (design 3A).** Flint AOT's extraction compile evaluates a CTFE describer (`apps/flint/src/flint_tool/engine/aot/extract.d`) over the modules it needs and prints their models (`flint.aot.model/1`) with `pragma(msg)`. With the switch, the fork prints the same lines (`FLINT-AOT-MODULE`, `FLINT-AOT-TYPE` and `FLINT-AOT-ANNOTATION`, on stderr as `pragma(msg)` prints them) from the analysed AST after semantic2, without instantiating or interpreting the describer.
- The request file has one line per module to describe (`module <name>`; the root module imports each one) and one per annotation type the generator already holds (`known <name>`). Class-presence answers stay `pragma(msg)` lines in the root.
- Every question the describer asks with a trait is asked with the same trait, evaluated in the root module's scope. The few it asks through CTFE or `__traits(compiles)` (an enum-like struct's `name()`, the runtime's `canonicalTypeName`) are evaluated the same way. The describer's rules carry over: a `@property` function lists no return type or parameters, a type passed to a template loses parameter names, and an attribute that fails to evaluate fails the compile.
- The output is byte-identical to the describer's on the 395 platform modules of petclinic-rest's closure, on the three Phase 1 applications and on the `tests/aot` fixtures that compile (the others fail with the same first error under both). `AotExtractionTests` compares the two on a fixture that reaches every rule, using the describer taken from `extract.d`, so the two cannot drift apart unnoticed. `aot-extract/parity.py` reproduces the comparison and the timing; its README keeps the results.
- Served with the platform prelude on venus, petclinic-rest's 15 modules take 31 ms, against 283 ms for the describer. The import floor alone is 20 ms.
- An output switch like `-X`: it changes no object file and no D semantics. The describer remains the generator's path for compilers without the switch, and unforked DMD rejects it as an unrecognized switch.

## What the DUB fork changes

**Parallel build pipeline.** For DMD builds of executables and static libraries without post-build commands, DUB plans every out-of-date target up front, splits their sources into chunks sized for the machine's hardware threads, and compiles all chunks concurrently with `posix_spawn`. D separate compilation only needs dependency sources, not their objects, so every package compiles at the same time. A package split into several chunks is compiled with `-allinst`, so template instances that more than one chunk could assume another chunk emits are always available to the linker; the linker folds the duplicates. A target whose files are not all resolvable through its import paths, such as a test root importing modules whose names differ from their paths, compiles in a single invocation as before. Up-to-date checks, rebuild propagation to dependents, cache directories and the static libraries in the DUB cache are unchanged. Libraries are archived in-process with a GNU symbol index. A target's pre-build commands run as the sequential build runs them: only when the target is out of date, through the same `runBuildCommands`, in its package directory with DUB's environment. They run in dependency order before any compile job starts, so a command that writes a file another package string-imports is done before that package compiles. C sources (flint:os's `interrupt_latch.c`) compile through ImportC in their target's jobs, and a target with a C source compiles in one job. Before this, flint:term's pre-build script and flint:os's C source sent every application that used them down the sequential path, about 4.8 s of serial compiles for petclinic-rest's scratch build.

**Smaller overheads.** The compiler platform probe is cached by the compiler executable's identity. Targets are hard-linked rather than copied out of the cache. DUB exits without druntime teardown once its output is complete.

## Controls

| Variable | Effect |
| --- | --- |
| `FLINT_DMD_SERVER=0` | Never use or start the compile server |
| `FLINT_DMD_SERVER_IDLE=<seconds>` | Server idle lifetime (default 1800) |
| `FLINT_DMD_SERVER_POOL=<n>` | Pre-forked workers per server |
| `FLINT_DMD_SERVER_TRACE=<file>` | Append worker timing events (`compiled` or `refused` per request) |
| `FLINT_DMD_SERVER_PRELUDE=<file>` | Platform prelude: import paths, versions and modules the server also preloads |
| `FLINT_DMD_DIRECT_LINK=0` | Always link through `cc` |
| `FLINT_LINK_THREADS=<n>` | mold thread count (default 4) |
| `FLINT_DUB_PIPELINE=0` | Use DUB's sequential build |
| `FLINT_DUB_TRACE=1` | Print DUB phase and per-job timings |

Measurements, test evidence and the remaining caveats are in [the Linux compile-time fork report](../docs/milestones/06-linux-compile-fork.md). The measurement interpretation is recorded in [ADR-016](../docs/adr/ADR-016-resident-toolchain-compile-server.md).

## Sanitizer lane toolchain

`python3 tools/ci.py check --gate sanitizers` runs on Linux x86-64 glibc only. It builds the locked C providers and Flint's C shims with Clang ASan and UBSan, then runs every package's `dub test` with LDC ASan. Neither the D language nor the normal lanes change: only sanitizer-lane test binaries use the pieces below.

**Clang 22.1.8.** The C side must use the LLVM major version of LDC 1.43 (LLVM 22.1.8). The gate uses `clang` from `PATH` when it reports 22.1.8. Otherwise it runs `python3 tools/install_toolchains.py --compiler clang`, which verifies the pinned official `LLVM-22.1.8-Linux-X64.tar.xz` and extracts only `bin/clang`, `bin/clang++`, `bin/clang-22`, `bin/llvm-symbolizer` and `lib/clang/22/` (about 380 MB of the 1.9 GB archive) into `.tools/LLVM-22.1.8-Linux-X64`, then puts that `bin` first on `PATH`. Hosts where the release binaries cannot locate the system C library and GCC installation, such as NixOS, need a `clang`/`clang++` wrapper that reports 22.1.8 placed first on `PATH`. The gate also checks that `ldc2` is LDC 1.43.0 on LLVM 22.1.8.

**Sanitizer-aware druntime and Phobos.** ASan's `detect_stack_use_after_return=1` moves function locals into heap-allocated "fake stack" frames. The druntime shipped in the LDC release does not scan those frames, so the GC can free objects that are only referenced from locals. The actuator suite crashed this way under the option. LDC's runtime source contains the scanner (`scanStackForASanFakeStack` in `core/thread/threadbase.d`), compiled only with `-d-version=SupportSanitizers`.

```bash
python3 tools/install_toolchains.py --compiler ldc-sanitizer-runtime [--build-dir /path/without/spaces]
```

This verifies the pinned LDC binary release and the pinned `ldc-1.43.0-src.tar.gz`, then runs the release's own `ldc-build-runtime` with the upstream CMake options `RT_SUPPORT_SANITIZERS=ON BUILD_SHARED_LIBS=OFF BUILD_LTO_LIBS=OFF`. `RT_SUPPORT_SANITIZERS` adds `-d-version=SupportSanitizers`. All other flags are the upstream release defaults, and the runtime itself is not instrumented, like the shipped one. The installer refuses a druntime that lacks the scanner symbol. It installs `libdruntime-ldc-sanitizers.a`, `libphobos2-ldc-sanitizers.a` and `flint-sanitizer-runtime.json` (input and output hashes) into `.tools/ldc-1.43.0-sanitizer-runtime/` (about 13 MB). It never writes into the LDC installation. It needs `cmake`, `ninja` and a C compiler, and takes about 20 seconds on 24 hardware threads. Because the upstream archive rules pass the compiler path to the shell unquoted, the disposable build directory (the system temporary directory, or `--build-dir`) must not contain whitespace. A rerun is a no-op while the receipt matches the lock and the installed files. The gate runs this step itself before any build.

`run_tests(..., sanitize=True)` links the result by adding `-defaultlib=phobos2-ldc-sanitizers,druntime-ldc-sanitizers` to `DFLAGS` and prepending the runtime directory to `LIBRARY_PATH`. DUB splits `DFLAGS` on whitespace, so a `-L-L` path containing a space would break, while the Clang link driver reads `LIBRARY_PATH` directly. The distinct library names mean a missing runtime fails the link rather than silently resolving to the shipped runtime. The lane also sets `ASAN_SYMBOLIZER_PATH` to the `llvm-symbolizer` that `clang -print-prog-name` reports, so reports carry file and line numbers.

**Vendor UBSan scope.** `-fsanitize=function` reports calls through a function pointer whose type differs from the callee's definition. Two pinned providers rely on that pattern in their own code:

- OpenSSL 3.5.9 calls typed free functions as `void (*)(void *)` in `OPENSSL_sk_pop_free` (`crypto/stack/stack.c`), typed leaf callbacks in `ossl_sa_doall_arg` (`crypto/sparse_array.c`), and provider digest update functions through a generic signature in `EVP_DigestUpdate` (`crypto/evp/digest.c`).
- protobuf-c 1.5.2 calls each message's generated `foo__init(Foo *)` through `ProtobufCMessageInit`, `void (*)(ProtobufCMessage *)`, in `protobuf_c_message_init`.

These calls work on every supported ABI, and removing them would mean patching upstream sources. `tools/native_build.py` therefore builds exactly these two providers with `-fno-sanitize=function` appended (`VENDOR_UBSAN_EXCLUSIONS`) and keeps every other requested check for them. All other providers keep the full ASan and UBSan set. Flint's own shims in `native/ffi` always do, so a function-type mismatch in Flint code still fails the lane. The install receipt records `sanitizer_exclusions` for each affected library and `vendor_ubsan_exclusions` for the prefix. Add a provider to that table only with the upstream call sites named in the comment there.

In the sanitizer lane, `:desktop` runs on SDL's offscreen video driver with software rendering and no framebuffer acceleration. That covers every Flint window, event and teardown path without loading the host's uninstrumented X11 and EGL drivers. Those drivers make one-time internal allocations that LeakSanitizer reports once SDL unloads them. No leak suppressions are used. Real displays are covered by the ordinary test lanes.
