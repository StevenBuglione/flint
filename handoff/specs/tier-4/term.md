# flint:term — implementation specification

Catalogue tier 4. Research cut: 2026-11-21. This file specifies implementation work; declarations in contracts are type-checking interfaces, not runtime implementations.

## 1. Purpose and reference parity

Provide the small, cross-platform terminal boundary used by CLI, TUI and prompts: raw input, size detection, input decoding and terminal-state restoration.

- [ ] Open/close raw sessions; query terminal dimensions; ANSI/16/256/truecolor detection.
- [ ] Keyboard, mouse, resize, paste, EOF and interrupt events.
- [ ] Alternate-screen and bracketed-paste mode with deterministic teardown.
- [ ] Nonterminal streams produce unsupported for raw operations; ordinary output remains available.

## 2. Exact package recipe and dependency boundary

Write this recipe to `packages/term/dub.sdl` in the implementation repository:

```sdl
name "term"
description "Flint term subpackage"
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

Allowed direct Flint dependencies: `flint:arena`. The canonical allowlist is [packages.json](../../scaffold/policy/packages.json). Importing a higher catalogue tier or an unlisted same-tier package fails Gate 2.

## 3. Public D contract

Canonical declaration module: [flint.term](../../contracts/source/flint/term.d). These exact signatures are compiled with DIP1000. Implement the declarations with the semantics below; do not put unresolved declaration stubs into production artifacts.

```d
module flint.term;
import flint.arena : Error, Result;

@safe:
enum EventKind : ubyte
{
    key,
    resize,
    paste,
    mouse,
    eof,
    interrupt,
    timer,
    command
}

enum KeyCode : ushort
{
    unknown,
    character,
    enter,
    escape,
    tab,
    backspace,
    up,
    down,
    left,
    right,
    home,
    end,
    pageUp,
    pageDown,
    delete_,
    functionKey
}

struct KeyEvent
{
    KeyCode code;
    dchar character;
    bool control;
    bool alt;
    bool shift;
}

struct Size
{
    uint columns;
    uint rows;
}

struct MouseEvent
{
    uint column;
    uint row;
    ubyte button;
    bool pressed;
}

struct Event
{
    EventKind kind;
    KeyEvent key;
    Size size;
    MouseEvent mouse;
    string paste;
    ulong timerId;
    ulong commandId;
    ubyte[] payload;
    Error error;
}

enum ColorProfile : ubyte
{
    none,
    ansi16,
    ansi256,
    trueColor
}

struct Options
{
    bool raw = true;
    bool alternateScreen = true;
    bool mouse = false;
    bool bracketedPaste = true;
}

struct Session
{
    @disable this(this);
    static Result!Session open(Options options = Options.init);
    Result!Event next(long timeoutNanos);
    Error write(scope const(char)[] text);
    Result!Size size() const;
    ColorProfile colors() const;
    Error close();
}
```

## 4. Internal architecture, ownership and safety

1. Session is move-only. open snapshots original POSIX termios or Windows console input/output modes; close is idempotent and restores them exactly once. A deterministic scope guard closes the session on ordinary returns and D exceptions. Fatal process termination cannot guarantee restoration; print a reset recipe in the troubleshooting guide.
2. POSIX uses termios, ioctl(TIOCGWINSZ), poll and a nonblocking self-pipe for signals. The signal handler writes a byte only; it does not allocate, log, invoke user code, or call D runtime APIs. SIGWINCH coalesces into one resize event.
3. Windows uses GetConsoleMode/SetConsoleMode and ReadConsoleInputW where native event decoding is selected; VT input/output is enabled only after capability checks. UTF-16 surrogate pairs become Unicode scalars. The binary stays on the MSVC ABI used by LDC.
4. Decoder state is bounded: 64-byte escape sequence, 25ms standalone ESC timeout, 1MiB bracketed-paste cap, 32KiB read slab. Incomplete UTF-8 waits for more bytes; invalid bytes emit replacement character events with an error counter. Unknown CSI sequences are ignored, not executed.
5. next(timeoutNanos) uses a monotonic deadline, returns timedOut without closing, and copies paste data into an owned string. ANSI output is trusted application formatting; widgets must sanitize user-supplied control sequences before passing them to the terminal.
6. Raw OS handles, termios layout and syscall pointers live only in flint.term.sys modules. A tiny C shim owns platform-dependent layout; no hand-copied struct termios definition. Every trusted call validates length, descriptor ownership and callback lifetime.

### Concrete implementation files

- `packages/term/source/flint/term/package.d`: public declarations, UDA definitions and entry points.
- `packages/term/source/flint/term/internal.d`: shared non-template state machines and checked arithmetic.
- `packages/term/tests/contract_tests.d`: behavioral tests identified in section 6.
- `packages/term/tests/fuzz/`: deterministic seed corpus and bounded fuzz entry points; no fuzz data downloaded at test time.
- `packages/term/source/flint/term/ffi/` and `sys/`: allowlisted native boundaries; every trusted function has an adjacent `// SAFETY:` proof and a matching ASan test.

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

Required benchmark: Replay a 10MiB input trace in 1-, 4- and 4096-byte chunks through the internal decoder. Measure bytes/s and bounded allocations separately from OS read cost. Measure idle CPU for a blocked next call; it must remain below 1% of one core over 10s.

## 6. Acceptance, edge cases and required tests

| Test ID | Stimulus | Required result |
| --- | --- | --- |
| TERM-01 | PTY child exits normally and by throwing a D exception | Original canonical/echo flags and alternate-screen state are restored. |
| TERM-02 | Split UTF-8 scalar and split CSI escape at each byte boundary | One correct event is produced for each input; no busy loop. |
| TERM-03 | Single ESC, followed by no byte for 25ms | One escape key event; timeout measured on monotonic clock. |
| TERM-04 | Paste exceeds 1MiB or contains terminal escape sequences | Bounded error/termination; pasted content is data, not terminal control. |
| TERM-05 | Windows surrogate pair, mouse record and resize record | Same normalized Event semantics as POSIX. |
| TERM-06 | stdout pipe and stdin EOF | No raw-mode crash; unsupported for raw setup and deterministic eof. |
| TERM-07 | Repeated close, cancellation while blocked, SIGWINCH storm | No double-close or deadlock; at most one pending resize event. |

For parser/codec boundaries fuzz every length from 0 through 256, then 1KiB/1MiB boundary seeds; reject overflows before allocation. Run a 60-second ASan smoke on every PR and a 30-minute corpus job nightly. A platform-specific test is required on the platform that owns the native boundary; a Linux compile-only job does not count as a Windows runtime pass.

From the implementation repository root:

```sh
dub test :term --compiler=dmd
dub test :term --compiler=ldc2
python3 tools/gates.py --package term --gate structural
```

Do not mark this package complete until behavioral fixtures, compile-fail safety fixtures, the package budget fixture and all applicable native/WASM jobs pass. A declaration-only typecheck is API verification, not a package acceptance result.

## 7. Primary sources

- https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/termios.h.html
- https://learn.microsoft.com/en-us/windows/console/setconsolemode
- https://learn.microsoft.com/en-us/windows/console/readconsoleinput
