# flint:os — implementation specification

Catalogue tier 4. Research cut: 2026-11-21. This file specifies implementation work; declarations in contracts are type-checking interfaces, not runtime implementations.

## 1. Purpose and reference parity

Offer argv-based cancellable subprocesses, simultaneous output streaming, predictable signal handling and bounded recursive globbing.

- [ ] Process execution with working directory, environment and explicit argument vector.
- [ ] Concurrent stdout/stderr draining, bounded captures, cancellation and process-tree termination.
- [ ] Graceful interrupt hooks and recursive glob patterns.
- [ ] No implicit shell invocation or string command parsing.

## 2. Exact package recipe and dependency boundary

Write this recipe to `packages/os/dub.sdl` in the implementation repository:

```sdl
name "os"
description "Flint os subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:conc" version="*"

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

Allowed direct Flint dependencies: `flint:arena`, `flint:conc`. The canonical allowlist is [packages.json](../../scaffold/policy/packages.json). Importing a higher catalogue tier or an unlisted same-tier package fails Gate 2.

## 3. Public D contract

Canonical declaration module: [flint.os](../../contracts/source/flint/os.d). These exact signatures are compiled with DIP1000. Implement the declarations with the semantics below; do not put unresolved declaration stubs into production artifacts.

```d
module flint.os;
import flint.arena : Error, Result;
import flint.conc : Context;

@safe:
struct EnvVar
{
    string name;
    string value;
}

struct ProcessOptions
{
    string workingDirectory;
    EnvVar[] environment;
    bool inheritEnvironment = true;
    ulong maxCaptureBytes = 1048576;
    long terminateGraceNanos = 2000000000;
}

struct ExitStatus
{
    int code;
    bool signalled;
    bool timedOut;
}

alias OutputSink = void delegate(scope const(ubyte)[]) @safe;
Result!ExitStatus run(ref scope Context context, scope const(char[])[] argv, ProcessOptions options = ProcessOptions
        .init);
Result!ExitStatus stream(ref scope Context context, scope const(char[])[] argv,
        scope OutputSink stdoutSink, scope OutputSink stderrSink, ProcessOptions options = ProcessOptions.init);
struct GlobOptions
{
    bool followSymlinks = false;
    uint maxDepth = 64;
    uint maxResults = 100000;
}

Result!(string[]) glob(scope const(char)[] root, scope const(char)[] pattern, GlobOptions options = GlobOptions.init);
struct InterruptSubscription
{
    @disable this(this);
    Error close();
}

Result!InterruptSubscription onInterrupt(void delegate() @safe callback);
```

## 4. Internal architecture, ownership and safety

1. run/stream execute argv directly. POSIX uses posix_spawn or a tightly controlled fork/exec shim; Windows uses CreateProcessW with one tested quoting implementation and a Job Object for tree termination. A command string requiring a shell must explicitly name that shell in argv.
2. Drain stdout and stderr concurrently with bounded queues; a full callback sink backpressures both readers without consuming reactor cores. OutputSink receives a borrowed scope slice valid only for the callback. The child cannot deadlock merely by filling stderr while stdout is read.
3. Cancellation sends SIGTERM to an owned process group on POSIX, waits terminateGraceNanos (default 2s), then SIGKILL and reaps. Windows sends supported graceful console control when applicable, then terminates the owned Job Object. Never signal the parent's process group.
4. Context deadline uses monotonic time; deadline expiration returns ExitStatus.timedOut=true after cleanup. Start failure returns Error; a nonzero child exit is a successful Result containing that exit code. EnvVar rejects NUL and = in names; argv and workingDirectory reject NUL.
5. glob roots all traversal at its supplied directory. followSymlinks=false by default; depth<=64 and result count<=100000 bound work. When following symlinks, use visited device/inode or Windows file IDs to break cycles. Pattern semantics: *, ?, character classes within one segment and ** across segments; no shell expansion.
6. Signal hooks run on a coordinator thread/event dispatcher after a signal-safe notifier. No D function/delegate is invoked from a native POSIX signal handler. flint.os.sys holds the platform ABI; application callbacks remain @safe.

### Concrete implementation files

- `packages/os/source/flint/os/package.d`: public declarations, UDA definitions and entry points.
- `packages/os/source/flint/os/internal.d`: shared non-template state machines and checked arithmetic.
- `packages/os/tests/contract_tests.d`: behavioral tests identified in section 6.
- `packages/os/tests/fuzz/`: deterministic seed corpus and bounded fuzz entry points; no fuzz data downloaded at test time.
- `packages/os/source/flint/os/ffi/` and `sys/`: allowlisted native boundaries; every trusted function has an adjacent `// SAFETY:` proof and a matching ASan test.

The public surface defaults to `@safe`. Pointer arithmetic and native handle conversions are confined to those reviewed boundaries. This full-D package may allocate where documented. Do not add `@nogc` to an API unless every implementation path and callback has that contract.

## 5. Measured budget contract

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are engineering ceilings, not measured performance claims. Use the fixed runner and sampling procedure in [CI performance budgets](../../docs/CI_PERFORMANCE_BUDGETS.md). Per-package timing excludes rebuilding dependencies; whole-application gates include the selected closure.

| Measurement | Ceiling |
| --- | --- |
| DMD cold / incremental package build | 0.90s / 0.60s |
| LDC cold / incremental package build | 5.40s / 2.70s |
| Incremental stripped linked bytes | 262144 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instantiations in the package fixture | 2000 |

Compile regression >10% or binary growth >5% fails independently of these hard ceilings. Native dependencies and final shared-library closure are reported separately and counted in the application deployment metric; they are never hidden by quoting only D wrapper size.

Required benchmark: Spawn 1000 empty commands and stream 100MiB from a child. Track startup p50/p99, peak RSS and read buffer reuse. Benchmark glob on 100K entries while enforcing result/depth limits.

## 6. Acceptance, edge cases and required tests

| Test ID | Stimulus | Required result |
| --- | --- | --- |
| OS-01 | Child emits 10MiB to stdout and stderr concurrently | No deadlock; both streams reach sinks in per-stream order. |
| OS-02 | Arguments containing spaces, quotes, semicolons and $() | Child receives exact argv values and no shell expansion. |
| OS-03 | Deadline cancels child that creates a grandchild | Owned process tree terminates; every waitable child is reaped. |
| OS-04 | Executable absent versus child exits 127 | Absent is Error.notFound; child exit 127 is an ExitStatus. |
| OS-05 | Symlink loop, deep tree and excessive matches | Bounded failure without recursion overflow or outside-root traversal. |
| OS-06 | Sink throws, closes early or blocks | Child is cancelled and reaped; failure propagates once. |

For parser/codec boundaries fuzz every length from 0 through 256, then 1KiB/1MiB boundary seeds; reject overflows before allocation. Run a 60-second ASan smoke on every PR and a 30-minute corpus job nightly. A platform-specific test is required on the platform that owns the native boundary; a Linux compile-only job does not count as a Windows runtime pass.

From the implementation repository root:

```sh
dub test :os --compiler=dmd
dub test :os --compiler=ldc2
python3 tools/gates.py --package os --gate structural
```

Do not mark this package complete until behavioral fixtures, compile-fail safety fixtures, the package budget fixture and all applicable native/WASM jobs pass. A declaration-only typecheck is API verification, not a package acceptance result.

## 7. Primary sources

- https://dlang.org/phobos/std_process.html
- https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects
- https://pubs.opengroup.org/onlinepubs/9799919799/functions/posix_spawn.html
