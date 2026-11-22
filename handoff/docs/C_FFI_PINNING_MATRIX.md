# C FFI pinning, native build and license matrix

Research cut: **2026-11-21**. The lock contains **24 exact source artifacts**. Every archive was downloaded from the listed upstream endpoint and hashed during handoff preparation; Git sources are also pinned to full immutable commit IDs. SQLite's `sqlite3.c` SHA3-256 was additionally matched against its official release page. Those observations establish reproducible source bytes. They do not establish that every library has passed every target runtime, that an upstream signing key was independently authenticated, or that a binary is vulnerability-free.

Machine-readable source: [c-libraries.json](../research/c-libraries.json). The build tool uses the identical [native-lock.json](../scaffold/policy/native-lock.json). Files in [research/licenses](../research/licenses) retain the observed notices.

## Selected artifacts

| Library | Exact selected release | License selected | Header/boundary |
| --- | --- | --- | --- |
| brotli | 1.2.1 | MIT | brotli/encode.h, brotli/decode.h |
| curl | 8.23.0 | curl | curl/curl.h |
| hiredis | 1.5.1 | BSD-3-Clause | hiredis/hiredis.h, hiredis/async.h |
| libarchive | 3.8.11 | BSD-2-Clause AND BSD-3-Clause AND ISC AND MIT | archive.h, archive_entry.h |
| libpq | 18.7 | PostgreSQL | libpq-fe.h |
| librdkafka | 2.16.0 | BSD-2-Clause AND MIT AND Apache-2.0 | librdkafka/rdkafka.h |
| libsodium | 1.0.22 | ISC | sodium.h |
| liburing | 2.15 | MIT | liburing.h plus liburing-ffi or Flint C shim |
| libyaml | 0.2.5 | MIT | yaml.h |
| llhttp | 9.4.4 | MIT | llhttp.h (generated release C sources) |
| nghttp2 | 1.71.0 | MIT | nghttp2/nghttp2.h |
| openssl | 3.5.9 | Apache-2.0 | openssl/ssl.h, openssl/evp.h |
| protobuf-c | 1.5.2 | BSD-2-Clause | protobuf-c/protobuf-c.h |
| protoc | 30.2 | BSD-3-Clause | Host executable; no runtime D linkage |
| sdl3 | 3.4.20 | Zlib | SDL3/SDL.h |
| sqlite | 3.54.1 | blessing | sqlite3.h from the verified amalgamation |
| stb | snapshot-2026-11-21 | MIT | stb_image.h compiled in one C unit |
| utf8proc | 2.12.0 | MIT AND LicenseRef-Unicode-Data | utf8proc.h |
| wamr | 2.4.6 | Apache-2.0 WITH LLVM-exception | wasm_export.h |
| wasmtime | 51.0.0 | Apache-2.0 WITH LLVM-exception | wasmtime.h, wasmtime/component.h, wasi.h |
| webview | 0.12.0 | MIT | webview.h; C++ implementation behind C exports |
| wgpu-native | 29.0.1.1 | MIT OR Apache-2.0 | webgpu.h and wgpu.h |
| zlib | 1.4 | Zlib | zlib.h |
| zstd | 1.5.7 | BSD-3-Clause | zstd.h |

OpenSSL uses the 3.5 LTS line, specifically 3.5.9, instead of the separately observed 4.1.0 major release. PostgreSQL libpq uses the patched 18.7 branch even though PostgreSQL 19 had just been released. The protobuf-c 1.5.2 generator release explicitly added protobuf 30.x compatibility; the codegen tool therefore pins protoc 30.2 rather than assuming compatibility with the independently observed 36.2. These are compatibility selections, not claims that selected versions are the newest available. ([OpenSSL release policy](https://openssl-library.org/policies/releasestrat/), [PostgreSQL 18.7 release](https://www.postgresql.org/docs/release/18.7/), [protobuf-c release](https://github.com/protobuf-c/protobuf-c/releases/tag/v1.5.2))

## Immutable revisions and archive hashes

The full lock also records source URLs, license-file hashes, source archive sizes, consumers and native dependencies. The digest below is SHA256 of the downloaded compressed archive, not a fabricated upstream signature or the Git commit digest.

| Library | Immutable revision | Source archive SHA256 |
| --- | --- | --- |
| brotli | `db24a98aed38a16de78cc05ca15cdd8dc2a0d92d` | `113b9685dfc14dd2f3360d077283266eec2fbdfb0fe3e5600f11be151da0d68e` |
| curl | `3163ec065643ba20709f190111f42c3e1fe95273` | `9dc0b74994d293d99dd57ec46193b8c9017298b8bc2481d026ef5a2b5edeb759` |
| hiredis | `644e39907c7722a992a51e54f892f4d416a910bd` | `1b8076f2a942b3e3e2ef68ce3d46a92f7d31cea10e6e61fece170ed367b1db3f` |
| libarchive | `03036ffa409a2aa1c5bbad35be2202641a040fda` | `87d05df74305b7f16b784852e49f434e09ce2b3bb29423461f717fc988742a78` |
| libpq | `f5c41f6681c910b3f69951bf6fb97c6d74605d25` | `0965aef2822a806df22d2994792f29e387eb4161e15a545ad6e2b94a4ecb79ed` |
| librdkafka | `c6c9973cf1b25394c58e0cade13a36f386856f77` | `72eb5f92c77381e17216613c67cc064029483bc85af79dc11de39e98834e1876` |
| libsodium | `77e1ce5d6dee871c49ef211222ba18ef0c486bda` | `58cb82cc07e45e296cd9c02446452d82dd2a5c5ecba9ff10a23ed8ee183d55b0` |
| liburing | `d41bf9220ec39277ff235379e9089d9e0fd6c2a5` | `e4db39641298c90f42c29e264bd1057d0342380e712d56dfd9049da953637f48` |
| libyaml | `2c891fc7a770e8ba2fec34fc6b545c672beb37e6` | `77987051b6f5bee8ba472f1efbe0053663a58d8d3e7a2f0f4a27d178adbf8844` |
| llhttp | `816485216511b86459b2e6478190e14c38c14891` | `b7b066789a497396aa6a49394fbe75dc8342bf71a29c5da6ac58c0075f3de3f9` |
| nghttp2 | `80dcb8140af050fac91a7e6af4fc6dd013404bd1` | `9af1a23010509f5d8218643336ea3ee1aaf9f2ad26d1fe352af72e3fe17d6de2` |
| openssl | `45e844fa2a14ec92d146bd8f5778ac130b6625fb` | `f54250b21795bb01240f3f9b42c384868d04460e339e39275aaaf93487f2d903` |
| protobuf-c | `4719fdd7760624388c2c5b9d6759eb6a47490626` | `8043151b04013373eae3e7b886701acb6ad62d3f4e75d0c69d9434a92ae476e5` |
| protoc | `43e1626812c1b543e56a7bec59dc09eb18248bd2` | `2cf234a7ec13eda439eaaf03d7b4dbcd71bd2940e70e9bedd1cda0ff116e3676` |
| sdl3 | `f00dc919ca35b9756316e86c4777392de442f9b2` | `e6a9c4e75de8fe719f922dddc208627f77754a502909f457a1355981f20c21e0` |
| sqlite | `555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76` | `926ef8d3eab93fbf6e06011901273eec076b25594a4e1cdadd50c987f4f6d64e` |
| stb | `6b5799bae8a1fe3792691ef4b72ae26434c3e799` | `87e9ecd2d2e0cb8fa35bf5a93ea6ca3999595ea4f0a4738ed1aac0a34cbd4da9` |
| utf8proc | `79cdd5ab40c79afa559f689ffc13b76812dee1ac` | `e8fadfcd531d65525cbef157b866c5408e2e3f0d7c0f3aefb0bce01a7a08e35d` |
| wamr | `0fa421193212b3fb45c7f59ec53662cc2851fcc7` | `b88e781ec4b27fc568de0f758a87dd1be13e8b275efaa32bcf9d5046493dc9e7` |
| wasmtime | `32656dc4873fcec5c8662aa937bd01acda3b2e85` | `471666d7ac62a381fa5e436062025e95913d6ab84b679c5fdeb61128c0b7ccb6` |
| webview | `3ab4b5d722438fc8a13e6ca830c5e2372d19a01d` | `3668dca249ce182803fe886c9c9e8e27d2c278a52a647198b947ed9d415019d5` |
| wgpu-native | `6aed50955d934ac36049ba8d002034841633ae02` | `bff001ca2f891d13dd9b5bd1fd6efc2003c54cfed9cdb21d3f84fc16d549e335` |
| zlib | `99623ef7097352da7993ba614161fd6a311e046e` | `f0d590dd90243a12f551ee13359bf6c634249c55b316fa2b7dbecabe7ae9a904` |
| zstd | `f8745da6ff1ad1e7bab384bd1f9d742439278e99` | `4b0bd1f0cfb25e61b9103c35f27395530ff5b4c0d2513a00fd745849e85ea52c` |

## Default boundary policy

1. **Compile a narrow C shim against pinned headers.** D declarations use `extern(C)` and opaque handles. The C compiler owns bitfields, macro expansions, platform layouts, TLS library structures, compiler intrinsics and C++/Objective-C implementation details. D uses `core.stdc.config.c_long`/`c_ulong` where the ABI needs C long; D `long` remains 64-bit and is not the Windows C `long`.
2. **ImportC is optional only for the sanitized Flint shim header.** Do not import a large OpenSSL, OS SDK or C++ header graph into every D package. Pin the preprocessing flags, header digest and C compiler with the binding output. No generated bindings are downloaded at app startup.
3. **No native exception unwinds across the boundary.** D callbacks are `extern(C) nothrow @nogc` when called on the hot path. Foreign threads do not call D GC/TLS code until explicitly attached to druntime and dispatched through the owning reactor/worker contract. Callback closure/context ownership is held by a concrete owner until unregister completion.
4. **Opaque state stays opaque.** For llhttp and nghttp2 public records whose layout is genuinely needed, the delivered C/D ABI probe reports size/alignment. A D `static assert` is insufficient to prove C agreement; run the probe on each target. Native output buffers carry pointer+length and documented release function; a `char*` is never treated as a NUL-terminated unbounded string.
5. **Allocator pairs are fixed.** OpenSSL/SQLite/libpq/curl/runtime objects are freed with their own release APIs. C library malloc allocations do not count as D GC allocations, but do count in process RSS and native allocation gates. Request arenas never retain arbitrary GC object references.
6. **Narrow installed profiles.** CLI uses no native library unless requested. REST adds OpenSSL/llhttp/nghttp2 and the OS reactor backend; HTTP client adds curl. SQL, Kafka, compression, plugin engines, image decoding and desktop are explicit. No `pragma(lib)` in an application silently pulls all native libraries into a binary.

## License decisions and exclusions

The brief's word “permissive” is interpreted as a license class, not as an exhaustive four-item SPDX list. libsodium is ISC, curl has the curl license, PostgreSQL has the PostgreSQL license, utf8proc includes a permissive Unicode-data notice, and SQLite is public domain. They are named explicitly in the lock. Selecting these upstream libraries while claiming they are all MIT would be inaccurate. If a deployment requires literally only MIT/BSD/Apache/Zlib identifiers, exclude these providers and narrow the feature profile before release.

liburing 2.15 offers a **MIT alternative** for its code and the Linux UAPI header; Flint selects that alternative and retains the MIT notice. It is not necessary to reimplement io_uring merely because the repository also contains LGPL/GPL license files. zstd and stb similarly use the permissive alternatives selected in the lock. Wasmtime/WAMR use Apache-2.0 with LLVM exception. ([liburing license statement](https://github.com/axboe/liburing/tree/liburing-2.15), [pinned license files](../research/licenses))

Webview's MIT wrapper does not relicense WebKitGTK/GTK. Linux WebKitGTK is excluded from the default strict permissive profile; `--allow-webview` permits source fetching on all listed targets and an optional macOS build against system WebKit. The strict native builder rejects Linux/Windows webview builds until a separate LGPL runtime inventory or pinned WebView2 SDK profile is supplied; it never lets upstream CMake silently fetch an unverified Windows SDK. This flag does not declare LGPL compliance complete. Windows WebView2 and macOS WKWebView require their respective platform SDK/runtime terms. SDL3 is the default shell backend; its third-party/system dependency inventory must still be recorded. Disable SDL libudev, D-Bus, IBus, external libiconv, libusb, FriBidi and libthai. The Linux window-only profile also disables ALSA/PulseAudio/PipeWire/JACK/sndio, Wayland/KMS and board-specific video backends, so host package discovery does not silently add these optional runtime dependencies. This is a window/event/rendering profile; Linux audio is outside it. On Linux the default selected SDL build uses X11, whose actual linked runtime libraries are inventoried. System libc, kernels and the Windows/macOS OS frameworks are platform prerequisites; they are not represented as permissively licensed vendored Flint code.

For libarchive, disable external iconv, ACL/xattr helpers, Nettle, mbedTLS/OpenSSL archive crypto, libxml2, expat, LZMA, LZ4 and bzip2 in this profile. Link the pinned zlib/zstd closure. Register only tar/zip readers and writers through individual `archive_read_support_format_*` calls; never use `*_all`. Build options select external dependencies and tools, not every archive parser source file. GNU libiconv and optional system helpers create LGPL concerns; liblzma must be assessed by its own license rather than automatically labeled LGPL. No GPL executable is redistributed as a runtime dependency.

Cargo-based native engines use the exact upstream Cargo.lock checksums and pinned gitlinks in their immutable source revision. Protoc's build dependencies use its pinned submodule revisions. Those transitive notices must be emitted into the final runtime/tool SBOM from the actual build; a root-project license badge does not establish every transitive dependency's license. CI fails a distributable if its inventory contains an unapproved license or missing source identity.

## Native build orchestration

The executable [native_build.py](../scaffold/tools/native_build.py) resolves dependencies, verifies source digests before extraction, builds into a target-specific prefix, records installed archive digests and can inject platform-specific linker flags into DUB recipes. It uses argv arrays, a safe archive extractor and no shell command interpolation. It does not reset the Flint repository. `--phase plan` is read-only planning; `fetch` verifies/extracts sources; `build` runs configuration/compilation/installation. Failed tools or missing expected archives are errors.

Baseline host tools: Python3.12+, C/C++ compiler for the target, CMake3.31.10, Ninja1.11.1, Perl5.40, GNU make4.4 (nmake/MSBuild on Windows), Autoconf2.72/Automake1.17/Libtool2.5 for libsodium, Meson1.9 for libpq, Git2.47+ for immutable submodules, Rust1.97.0+ for Wasmtime51, and a matching Rust target standard library. These are concrete minimum/selected build inputs; record the exact installed versions in CI evidence. The handoff locally exercised CMake3.31.10 and Ninja1.11.1 on Linux; it did not execute all these optional toolchains.

Run in the generated Flint repository root:

```sh
python3 tools/native_build.py --profile rest --target linux-x86_64-glibc --phase plan
python3 tools/native_build.py --profile rest --target linux-x86_64-glibc --phase build --emit-dub
python3 tools/native_build.py --profile sql --target linux-x86_64-glibc --phase build --emit-dub
dub test :web --compiler=ldc2
dub test :sql --compiler=ldc2
```

`--library` is repeatable. `--profile codec` includes zlib/zstd/brotli/libarchive; compression-only builds specify the first three individually. `--library protobuf-c --with-codegen` adds the protoc30.2 host build and enables protoc-gen-c. The library consumer still links only the protobuf-c C runtime. `--profile wasm-host` builds Wasmtime from its locked Rust source. `--library wamr` selects the alternative engine. `--profile tui` prepares utf8proc. `--profile yaml` prepares libyaml. `--profile ci` selects the strict C-provider test closure: REST, SQL, MQ, codecs/archive, terminal Unicode, YAML, SDL3, protobuf-c and hiredis; Linux adds liburing. Every all-package native CI invocation adds `--library wasmtime`, because wasi defaults to Wasmtime and requires actual successful plugin execution. Image, GPU, webview and the alternative WAMR engine remain explicit optional profiles. Missing Wasmtime, unsupported default-engine calls or skipped wasi tests fail acceptance.

`--emit-dub` appends/replaces only a `// BEGIN FLINT NATIVE` block in affected package recipes. The block contains DUB `lflags` using verified absolute archive paths plus required OS linker flags, guarded by a DUB platform selector. It also adds `FlintNative` provider version identifiers by capitalizing name segments, for example `FlintNativeLibpq`, `FlintNativeLlhttp`, `FlintNativeLibyaml` and `FlintNativeWgpuNative`. Optional provider implementation modules compile only when that provider version is enabled; absent providers report unsupported, never resolve to missing C symbols. Linux preparation adds liburing when a selected native consumer has reactor in its declared D dependency closure. Original dependencies and public package names are preserved. The prefix receipt is cumulative, so preparing SQL after REST retains both providers. These machine-local linker blocks are regenerated on each CI target; do not commit them as portable source. SDL3 records its actual configured `sdl3.pc` SDK/framework flags; unexpected external pkg-config requirements fail. Rust engines use `cargo rustc --lib --crate-type staticlib --locked`, overriding upstream mixed staticlib/cdylib outputs so the musl build does not attempt a shared library, and record the native linker requirements reported by `--print native-static-libs`. These metadata files are hashed in the installation receipt and rechecked before emission. Wasmtime uses its pinned upstream header-install script to generate feature-matched `conf.h`; wgpu installs both its wrapper header and the pinned WebGPU header. The helper selects static archives even for optional engines; dynamic deployment is a separate explicitly inventoried profile. Each native shim added under `native/ffi/flint_*.c` is included in `libflint_ffi.a`/`flint_ffi.lib`; application bindings must call only functions defined by those compiled shims.

## Target and linking matrix

| Target | Build location/toolchain | Native linkage and required proof |
| --- | --- | --- |
| Linux x86_64 glibc | x86_64 glibc runner, GCC/Clang | Static third-party .a archives; glibc app linking may remain dynamic. Run ABI/parser tests and record ELF dependencies. |
| Linux aarch64 glibc | Native aarch64 runner; CMake cross file allowed for CMake-only dependency closure | Same; execute on aarch64. An x86 build artifact is not accepted by filename alone. |
| Linux x86_64 musl | Alpine x86_64 runner/container, musl C toolchain and musl-built LDC druntime/Phobos | All archives compiled for musl; final application uses static linker mode and must have no PT_INTERP/DT_NEEDED. |
| Linux aarch64 musl | Alpine aarch64 runner/container with matching compiler/runtime archives | Same; execute on real/emulated aarch64 and retain architecture evidence. |
| macOS arm64 | macOS arm64 with Xcode/SDK; deployment target13.0 | Static third-party archives; OS frameworks/libSystem remain dynamic. Run otool and codesign/ad-hoc checks where required. |
| Windows x86_64 | VS2022 developer environment, MSVC ABI, /MD CRT, NMake/MSBuild, NASM for OpenSSL asm | .lib archives built against matching CRT; OS DLL imports are expected. Do not mix MinGW .a files with MSVC LDC runtime. |
| Browser wasm32 | LDC BetterC+internal LLD; no native engine or TLS libraries | Link only arena/serde/validate/bridge/signals core implementations and explicit tiny C support if required; inspect imports and run in Node/browser. |

The default WASI provider is Wasmtime 51.0.0. It requires Rust/Cargo 1.97.0, the matching target standard library, the native C/C++ toolchain/SDK, CMake, Ninja and Git. The pinned Wasmtime manifest declares rust-version 1.97.0. The official Rust 1.97.0 distribution manifest observed on this research cut advertises native x86_64/aarch64 glibc and musl, macOS arm64 and Windows MSVC toolchains. CI installs the exact 1.97.0 minimal toolchain through rustup and sets `RUSTUP_TOOLCHAIN=1.97.0`; missing prerequisites fail. ([pinned Wasmtime manifest](https://github.com/bytecodealliance/wasmtime/blob/32656dc4873fcec5c8662aa937bd01acda3b2e85/Cargo.toml), [official Rust manifest](https://static.rust-lang.org/dist/channel-rust-1.97.0.toml), [Cargo static library override](https://doc.rust-lang.org/cargo/commands/cargo-rustc.html))

For complete native test preparation, use `python3 tools/native_build.py --profile ci --library wasmtime --target linux-x86_64-glibc --phase build --emit-dub`. Use the matching tuple and Rust target on each native runner.

For the C/D sanitizer lane, preserve real Wasmtime behavior while distinguishing instrumentation scope:

```sh
RUSTUP_TOOLCHAIN=1.97.0 python3 tools/native_build.py --profile wasm-host --target linux-x86_64-glibc --phase build --work-dir .native-sanitized/engine-build --prefix .native-sanitized/install/linux-x86_64-glibc
RUSTUP_TOOLCHAIN=1.97.0 python3 tools/native_build.py --profile ci --target linux-x86_64-glibc --phase build --emit-dub --sanitize address,undefined --cc clang --cxx clang++ --work-dir .native-sanitized
```

The first command builds the Rust engine without sanitizer instrumentation in a separate build directory. The second reuses its installed archive/headers and cumulative receipt, instruments C dependencies and Flint C shims in its own build directory, runs CTest, and emits all available providers including Wasmtime. CI then runs all 37 D package tests with D ASan; wasi is included and must make successful calls to the real engine. Each library receipt records `requested_sanitizers`, while the final shim receipt states the scope. This is D/C boundary instrumentation with an uninstrumented Rust engine, not Rust-internal sanitizer coverage. liburing uses libc, with its sanitizer option, so sanitizer support code can link. Asking this helper to instrument Wasmtime directly remains an error; a future Rust sanitizer claim needs its own pinned lane and proof.

The builder requires a native runner for OpenSSL/autotools/Meson/Cargo recipes. A `--cmake-toolchain` file permits cross-host CMake-only closures; it never claims a glibc object becomes musl merely by passing `-static` or using zig as the final linker. For complete musl applications use the actual musl LDC runtime build, pinned C dependencies and CA/DNS configuration. Zig is optional C compilation tooling, not a replacement for target-matched druntime.

Wasmtime, WAMR, SDL3, wgpu and full static crypto/database closures can exceed the tiny binary targets. Gate4 always records the declared feature profile and full deployment closure. A library is not made “small” by omitting its shared library from reported bytes. Windows/macOS applications cannot be marketed as having no OS runtime dependencies merely because third-party libraries are static.

## WASI and Component Model boundary

WASI0.3 is a stable standard in this research cut; official guidance identifies Wasmtime46+ as implementing final0.3. The guest D compiler target remains a core WASM target. A WIT package, generated C/Canonical ABI adapter, component assembly and runtime import conformance are required for a WASI component. Core wasm32 success is not that evidence. ([WASI releases](https://wasi.dev/releases), [WASI0.3](https://wasi.dev/releases/wasi-p3))

Pinned Wasmtime51 source includes a C component API. Its C linker offers `wasmtime_component_linker_add_wasip2` and the async counterpart. The checked C-API manifest selects p1/p2 integrations and does not expose an equivalent complete WASIp3 linker helper. Therefore the Milestone6 p3 host adapter must use a small C ABI Rust shim against **the same Wasmtime51.0.0 crates**, enable `wasmtime-wasi/p3`, and run the shared WASI conformance fixtures before enabling GuestAbi.wasi03Component. Do not hand-write WASI syscalls in D or invent an upstream C symbol. Until that adapter passes, the explicit p3 request returns unsupported. ([pinned C linker](https://github.com/bytecodealliance/wasmtime/blob/32656dc4873fcec5c8662aa937bd01acda3b2e85/crates/c-api/include/wasmtime/component/linker.h), [pinned C manifest](https://github.com/bytecodealliance/wasmtime/blob/32656dc4873fcec5c8662aa937bd01acda3b2e85/crates/c-api/Cargo.toml))

WAMR is the core/Preview1 alternative in this handoff. Do not assign it component support based on its general WebAssembly feature list. All plugin engines run with explicit preopens, disabled ambient environment/network, memory/table/fuel limits, monotonic wall deadlines and bounded host callbacks. The native engine and any extra host shim are part of the distributed size/SBOM.

## Verification and refresh rules

The source-verification receipt is the lock itself. Native build/runtime receipts are separate: [native smoke verification](../verification/native-smoke.json), [native sanitizer verification](../verification/native-sanitizers.json), [six-target plan generation](../verification/native-build-plans.json), [actual DUB linker-block parsing](../verification/native-dub-emission.json) and [D/TUI/WASM contract checks](../verification/tui-wasm-contracts.json). The local native sanitizer run used GCC14.2.0 on Linux x86_64 glibc and passed two CTests for ABI bounds, llhttp parsing and zlib roundtrip. LeakSanitizer could not run under executor ptrace restrictions, so that local rerun records `ASAN_OPTIONS=detect_leaks=0`; CI retains normal leak checks. liburing was compiled with instrumentation but its kernel I/O behavior was not exercised. A plan receipt is never a native cross-platform test result. A missing or unexecuted platform check remains unverified and cannot be used to advertise support.

For a pin update, change the immutable revision and exact archive hash together, fetch and verify, rebuild affected target prefixes, regenerate bindings only if the sanitized shim ABI changes, run ABI/ASan/fuzz/integration jobs, refresh the SBOM and compare full feature-profile size/runtime budgets. Keep the old baseline available for comparisons using the documented independent-sample procedure. A release agent must not silently accept a moved tag, changed archive digest, new transitive license or absent compile/runtime evidence.
