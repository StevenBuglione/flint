# flint:codec — Streaming compression with bounded decompression and C backends

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] zlib/gzip, Zstandard and Brotli streaming encoder/decoder handles.
- [ ] Input/output progress, flush/end states, configurable level and output limits.
- [ ] No reimplementation of compression algorithms; per-codec selective linking.
- [ ] ZIP and tar streaming readers/writers through the optional pinned libarchive profile; image decoding remains disabled by default.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/codec/dub.sdl inside the Flint root that declares all subpackages. Module: flint.codec. Direct allowed dependencies: flint:arena.

```sdl
name "codec"
description "Flint codec subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"

configuration "library" {
    targetType "library"
}
configuration "unittest" {
    targetType "library"
    sourcePaths "source" "tests"
    importPaths "source" "tests"
    excludedSourceFiles "tests/betterc.d"
}
```

The source library has no executable main. Native build/link selection follows the central C-FFI matrix. Public imports are explicit; transitive dependency reachability does not authorize undeclared direct imports. No package in this specification may import a higher catalog tier or introduce a cycle.

## 3. Concrete public D contract

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/codec.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.codec;
import flint.arena : Error, Result, Buffer, RequestArena;

@safe:
enum Codec : ubyte
{
    gzip,
    zstd,
    brotli
}

enum Finish : ubyte
{
    more,
    flush,
    end
}

struct CodecOptions
{
    Codec codec = Codec.gzip;
    int level = 3;
    ulong maxOutputBytes = 64 * 1024 * 1024;
    uint maxExpansionRatio = 100;
}

struct CodecStep
{
    size_t consumed;
    size_t produced;
    bool finished;
}

struct Encoder
{
    private ulong slot;
    private ulong generation;
    Error open(CodecOptions options);
    Result!CodecStep process(scope const(ubyte)[] input, scope ubyte[] output, Finish finish) nothrow @nogc;
    Error close() nothrow @nogc;
}

struct Decoder
{
    private ulong slot;
    private ulong generation;
    Error open(CodecOptions options);
    Result!CodecStep process(scope const(ubyte)[] input, scope ubyte[] output, Finish finish) nothrow @nogc;
    Error close() nothrow @nogc;
}

enum ArchiveFormat : ubyte
{
    zip,
    tar
}

struct ArchiveEntry
{
    Buffer path;
    ulong uncompressedBytes;
    bool directory;
}

alias ArchiveSource = Result!size_t delegate(scope ubyte[] output) @safe nothrow @nogc;
alias ArchiveSink = Error delegate(scope const(ubyte)[] input) @safe nothrow @nogc;
struct ArchiveOptions
{
    uint maxEntries = 10000;
    ulong maxTotalBytes = 1024UL * 1024 * 1024;
    size_t maxPathBytes = 4096;
    bool allowSymlinks = false;
}

struct ArchiveReader
{
    private ulong slot;
    private ulong generation;
    Error open(ArchiveFormat format, ArchiveOptions options, ArchiveSource source);
    Result!ArchiveEntry next(ref scope RequestArena arena) nothrow @nogc;
    Error read(scope ArchiveSink sink) nothrow @nogc;
    Error close() nothrow @nogc;
}

struct ArchiveWriter
{
    private ulong slot;
    private ulong generation;
    Error open(ArchiveFormat format, ArchiveSink sink);
    Error entry(scope const(char)[] relativePath, ulong size, bool directory) nothrow @nogc;
    Error write(scope const(ubyte)[] bytes) nothrow @nogc;
    Error close() nothrow @nogc;
}
```

## 4. Internal architecture and observable semantics

Encoder/Decoder.open selects one codec and allocates its native state. process accepts caller-owned input/output slices and returns consumed/produced/finished, allowing exact backpressure without retaining a slice after return. A zero-sized output buffer reports no progress; it cannot spin internally. The state machine is open → streaming → finishing → finished → closed; calls after end/close or a fatal native error return invalidArgument. close is idempotent and invalidates every copied generation token.

For decompression, maintain cumulative output bytes, input bytes and frame count using checked arithmetic. Stop at min(maxOutputBytes=64 MiB, maxExpansionRatio=100 times max(inputBytes,1024)); the 1-KiB denominator floor prevents tiny valid inputs from being rejected solely due to startup ratio. The absolute limit always applies. Dictionary IDs and required dictionaries are explicit; missing dictionaries return unsupported/invalidArgument, never corrupted output. Reject trailing garbage by default. Concatenated frames/members require an explicit future option; do not accidentally accept them through a library default.

gzip verifies header flags and CRC/trailer through zlib. Zstandard and Brotli use upstream streaming APIs and bounded native window allocations. Set maximum decompression window as well as output limits: a small output can otherwise request huge decoder state. Defaults target a 16-MiB maximum window and fail larger-window frames. Encode level validation is codec-specific; do not pass one codec's valid range into another library unchecked.

Compression state is owned by one thread/stream and never shared concurrently. Reset/reuse an initialized state only after the preceding stream completes and all callbacks are quiescent. C allocations are permitted at state creation and measured separately; process is @safe nothrow @nogc and should reuse native state. A no-allocation native configuration must be demonstrated by library allocator hooks, not inferred from @nogc.

The package does not import web, rpc or storage. Applications inject a streaming transform or explicitly compress a Buffer. This direction preserves catalog tier rules and makes a CLI that does not import codec avoid native compression dependencies. Security-sensitive compression choices, such as mixing secrets with attacker-controlled content over compressed TLS, remain an explicit application policy.

ArchiveReader/ArchiveWriter are an explicit native profile, not inferred from gzip support. Wrap libarchive and register only tar and zip formats, never the all-formats/all-filters helpers. Readers expose entry metadata and streamed bytes; they never extract files directly. Reject absolute paths, drive prefixes, NUL, backslash-separated traversal and any .. component. Disallow symlinks/hardlinks, devices and FIFOs in the default policy, enforce 10,000 entries, 4,096 path bytes and 1 GiB cumulative decoded bytes. A caller that writes entries to disk must use a directory-handle-relative no-follow API in flint:os and recheck containment; string normalization alone is insufficient against symlink races.

ArchiveSource returns the number of bytes written into its scoped buffer; zero means EOF. ArchiveSink sees a scoped input span and may stop with an Error. The callbacks are retained as rooted D state until close, not raw unregistered delegate contexts in C memory. next returns notFound at end of archive. An entry body must be consumed or explicitly skipped before next. Writer entry declares its size up front; writing too few/many bytes is invalidArgument. close flushes trailers and may report I/O failure. Optional archive profile native size is reported separately from compression-only profile and still participates in the selected product's whole-binary cap.

### Required implementation layout

- source/flint/codec.d: streaming state/step API.
- source/flint/codec/runtime.d: generation/state/limit enforcement.
- source/flint/codec/ffi/shim.d and c/codec.c: zlib/zstd/Brotli selection.
- tests/corpora: valid/truncated/corrupt/window-bomb/ratio-bomb seeds.

## 5. Native boundary, ownership and safety

Use contracts/c/codec.h with separate C translation units and link archives per selected codec. zlib uses deflateInit2/inflateInit2 for gzip; Zstandard uses stream contexts; Brotli uses encoder/decoder streaming state. Allocate/free matching library state exactly once and never free a library buffer with the D GC. The selected Brotli decoder exposes a maximum-window guard; if a pinned API cannot enforce it before allocation, wrap its allocator with a hard byte budget and test rejection. Optional stb_image is disabled; enabling it requires separate dimensions/decompression-budget fuzzing and its own manifest entry.

libarchive is separately pinned in native-lock.json; disable iconv, liblzma, lz4, bzip2, XML and unused external filters in the strict build. Dependency switches do not remove format parsers by themselves: runtime registration is explicitly tar+zip. Do not invoke external decompressor programs. The archive C shim uses libarchive read/write callbacks and converts all paths to validated UTF-8 handles before application exposure.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

| Lock ID | Version | License selection | Link profile |
| --- | --- | --- | --- |
| brotli | 1.2.1 | MIT | static-runtime-library |
| libarchive | 3.8.11 | BSD-2-Clause AND BSD-3-Clause AND ISC AND MIT | static-runtime-library |
| stb | snapshot-2026-11-21 | MIT | static-runtime-library |
| zlib | 1.4 | Zlib | static-runtime-library |
| zstd | 1.5.7 | BSD-3-Clause | static-runtime-library |

Immutable commit/source IDs, artifact digests, notices and target recipes are authoritative in scaffold/policy/native-lock.json and docs/C_FFI_PINNING_MATRIX.md. A source digest check is not evidence that every target binary was built or audited.

### Flint C shim ABI

This stable Flint-facing header is compiled by the target C compiler against the selected upstream headers. Its opaque pointers are internal; the public D API exposes only checked handles.

```c
/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_CODEC_ABI_H
#define FLINT_CODEC_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_codec_state flint_codec_state;
flint_codec_state *flint_codec_new(int codec, int encode, int level);
int flint_codec_step(flint_codec_state *state, const uint8_t *input,
                     size_t input_length, size_t *consumed,
                     uint8_t *output, size_t output_capacity,
                     size_t *produced, int finish);
void flint_codec_free(flint_codec_state *state);
typedef struct flint_archive flint_archive;
typedef int (*flint_archive_read_cb)(void *user, uint8_t *output,
                                     size_t capacity, size_t *written);
typedef int (*flint_archive_write_cb)(void *user, const uint8_t *input,
                                      size_t length);
flint_archive *flint_archive_reader_new(int format, flint_archive_read_cb read,
                                        void *user, uint64_t max_output_bytes);
flint_archive *flint_archive_writer_new(int format, flint_archive_write_cb write,
                                        void *user);
int flint_archive_next(flint_archive *archive, uint8_t *path,
                        size_t path_capacity, size_t *path_length,
                        uint64_t *size, int *directory);
int flint_archive_read(flint_archive *archive, uint8_t *output,
                        size_t capacity, size_t *written);
int flint_archive_entry(flint_archive *archive, const char *path,
                         uint64_t size, int directory);
int flint_archive_write(flint_archive *archive, const uint8_t *input, size_t length);
int flint_archive_close(flint_archive *archive);
#ifdef __cplusplus
}
#endif
#endif
```

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --profile codec --target linux-x86_64-glibc --phase build --emit-dub
```

Use --phase plan to inspect resolved commands without claiming a build. The build installs pinned archives and a verified libflint_ffi.a from implemented native shims, then writes a delimited platform-specific lflags block into affected DUB recipes. Installation receipts are cumulative. Cross-target commands replace the target with the exact central matrix target and use its SDK/toolchain. C shim source must exist at the implementation milestone; missing shims must fail the build rather than produce a fake library.

For compression-only use --library zstd --library zlib --library brotli instead of --profile codec. The full codec profile includes libarchive; register ZIP/tar explicitly.

## 6. Numeric compile and size budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

| Measurement | Hard ceiling |
| --- | --- |
| Cold DMD fixture build | 1.50 s |
| Incremental DMD leaf edit | 0.60 s |
| Cold LDC fixture build | 9.00 s |
| Incremental LDC leaf edit | 4.50 s |
| Incremental linked code/data contribution | 1048576 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instances per canonical fixture | 2000 |

These are engineering ceilings from scaffold/policy/packages.json, measured with the fixed runner/toolchain/workload policy. They are not measured achievements of these declarations. Also fail >10% compile-time/compiler-RSS/template growth or >5% binary growth against the approved baseline. The whole selected application includes native libraries in its cap; a smaller wrapper-only delta cannot excuse a larger deployment artifact. A changed profile is a different benchmark identity and cannot be compared as if equivalent.

## 7. Required unit, protocol, fuzz and benchmark acceptance

| Test identity | Passing condition |
| --- | --- |
| roundtrip | Empty, 1-byte, random, repetitive and 64-MiB data round-trip for all selected codecs. |
| stream_progress | Every input/output chunk size from 0..257 has correct consumed/produced progress and no infinite loop. |
| corruption | Truncated headers/body/trailers, checksum errors and trailing garbage return error and release native state. |
| bomb_limits | Output, ratio, frame-count and window limits reject crafted streams before crossing their byte budgets. |
| state_calls | Process after finished/closed or double close cannot use freed C memory. |
| native_allocator | Count C heap allocations during repeated process calls; distinguish state creation from steady-state behavior. |
| codec_fuzz | Fuzz decoder streaming transitions with ASan and allocation caps; every C backend gets the same corpus. |
| archive_paths | ZIP/tar fixtures with ../, absolute/drive paths, links and device entries are rejected; regular entries stream without touching disk. |
| archive_limits | Entry10001, path4097 and decoded byte1073741825 fail before exposing the excess entry/data. |
| codec_bench | Measure throughput/ratio/RSS for standard 1-KiB, 64-KiB and 1-MiB fixtures at documented levels. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :codec --compiler=dmd
dub test :codec --compiler=ldc2
python3 tools/gates.py --package codec --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [Zstandard upstream](https://github.com/facebook/zstd) — Use the maintained C implementation and its documented streaming interfaces.
- [zlib manual](https://zlib.net/manual.html) — gzip framing and streaming state are handled by zlib.
- [Brotli upstream](https://github.com/google/brotli) — Brotli C encoder/decoder APIs are the native backend.
- [libarchive upstream](https://github.com/libarchive/libarchive) — Optional ZIP/tar support wraps the maintained C archive implementation.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
