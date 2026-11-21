# flint:prompt — implementation specification

Catalogue tier 4. Research cut: 2026-11-21. This file specifies implementation work; declarations in contracts are type-checking interfaces, not runtime implementations.

## 1. Purpose and reference parity

Build typed terminal forms from the TUI widgets while making cancellation, noninteractive usage and secret lifetime explicit.

- [ ] Confirm, input, single-select, multi-select, password and grouped forms.
- [ ] Required field validation, defaults and keyboard navigation.
- [ ] Standalone terminal ownership or embedding in an existing TUI through widget composition.
- [ ] Cancelled prompts return cancelled; they never invent a default answer.

## 2. Exact package recipe and dependency boundary

Write this recipe to `packages/prompt/dub.sdl` in the implementation repository:

```sdl
name "prompt"
description "Flint prompt subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:term" version="*"
dependency "flint:tui" version="*"
dependency "flint:widgets" version="*"
dependency "flint:validate" version="*"

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

Allowed direct Flint dependencies: `flint:arena`, `flint:term`, `flint:tui`, `flint:widgets`, `flint:validate`. The canonical allowlist is [packages.json](../../scaffold/policy/packages.json). Importing a higher catalogue tier or an unlisted same-tier package fails Gate 2.

## 3. Public D contract

Canonical declaration module: [flint.prompt](../../contracts/source/flint/prompt.d). These exact signatures are compiled with DIP1000. Implement the declarations with the semantics below; do not put unresolved declaration stubs into production artifacts.

```d
module flint.prompt;
import flint.arena : Result, Error;

@safe:
struct Choice
{
    string value;
    string label;
    bool disabled;
}

struct FormOptions
{
    bool requireTerminal = true;
    uint maxInputBytes = 4096;
}

Result!bool confirm(scope const(char)[] title, bool defaultValue = false);
Result!string input(scope const(char)[] title, scope const(char)[] defaultValue = "",
        FormOptions options = FormOptions.init);
Result!string select(scope const(char)[] title, scope const Choice[] choices);
Result!(string[]) multiSelect(scope const(char)[] title, scope const Choice[] choices, uint maxSelections = 64);
struct Secret
{
    @disable this(this);
    Error read(scope void delegate(scope const(ubyte)[]) @safe consumer) const;
    void clear();
}

Result!Secret password(scope const(char)[] title, FormOptions options = FormOptions.init);
struct Field
{
    string key;
    string title;
    bool required;
    bool secret;
}

struct Answer
{
    string key;
    string value;
    Secret secret;
    bool isSecret;
}

Result!(Answer[]) form(scope const Field[] fields, FormOptions options = FormOptions.init);
void clear(ref Answer[] answers);
```

## 4. Internal architecture, ownership and safety

1. Standalone functions acquire exactly one term.Session and close it on every return path. Embedded forms expose the same widget state through the TUI package and reuse the caller's session; nested raw-terminal acquisition fails conflict.
2. When stdin is not a terminal and requireTerminal=true, return unsupported before printing terminal control sequences. Never silently read passwords from command-line arguments or environment variables. Applications can explicitly provide a noninteractive answer through their configuration path.
3. Secret uses a move-only native allocation. read accepts a scope callback and never returns a string/slice. clear zeroes bytes through an explicit non-elidable native primitive and marks the handle closed; subsequent read returns invalidArgument. Secret content cannot enter Error.message, logs, history or completion output.
4. Fields with secret=true return Answer.isSecret=true, an empty Answer.value and an owned Secret. clear(ref answers) wipes every secret and releases storage. Application code must call it in scope(exit); no guarantee depends on GC finalizer timing.
5. Default input limit is 4096 bytes. maxSelections defaults to 64 and must not exceed choices.length. Duplicate choice values and duplicate field keys are invalidArgument; disabled choices are excluded from submission.
6. Form validation is synchronous and deterministic. Network lookups are external explicit application steps; a prompt cannot acquire an HTTP or data package transitively. Errors preserve the field key and redact the submitted value when secret=true.

### Concrete implementation files

- `packages/prompt/source/flint/prompt/package.d`: public declarations, UDA definitions and entry points.
- `packages/prompt/source/flint/prompt/internal.d`: shared non-template state machines and checked arithmetic.
- `packages/prompt/tests/contract_tests.d`: behavioral tests identified in section 6.
- `packages/prompt/tests/fuzz/`: deterministic seed corpus and bounded fuzz entry points; no fuzz data downloaded at test time.
- `packages/prompt/source/flint/prompt/ffi/` and `sys/`: allowlisted native boundaries; every trusted function has an adjacent `// SAFETY:` proof and a matching ASan test.

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

Required benchmark: Benchmark validation of a 100-field form and list selection of 10,000 choices using a fake terminal. Track display bytes per key and memory high-water for repeatedly opening/closing 10,000 password prompts.

## 6. Acceptance, edge cases and required tests

| Test ID | Stimulus | Required result |
| --- | --- | --- |
| PROMPT-01 | Ctrl-C at every wizard page | Return cancelled, wipe partial secret answers and restore terminal modes. |
| PROMPT-02 | Password paste and editing with echo disabled | No secret bytes in captured stdout/stderr, logs or Error.message. |
| PROMPT-03 | Pipe stdin into password() | Return unsupported; never hang awaiting a terminal. |
| PROMPT-04 | Duplicate keys/choice values and too many selections | Fail before terminal mutation with invalidArgument. |
| PROMPT-05 | Call Secret.clear twice and read after clear | Idempotent zero/release; read fails safely. |
| PROMPT-06 | Group has public and secret fields | Only public fields populate Answer.value; clear wipes all secret storage. |

For parser/codec boundaries fuzz every length from 0 through 256, then 1KiB/1MiB boundary seeds; reject overflows before allocation. Run a 60-second ASan smoke on every PR and a 30-minute corpus job nightly. A platform-specific test is required on the platform that owns the native boundary; a Linux compile-only job does not count as a Windows runtime pass.

From the implementation repository root:

```sh
dub test :prompt --compiler=dmd
dub test :prompt --compiler=ldc2
python3 tools/gates.py --package prompt --gate structural
```

Do not mark this package complete until behavioral fixtures, compile-fail safety fixtures, the package budget fixture and all applicable native/WASM jobs pass. A declaration-only typecheck is API verification, not a package acceptance result.

## 7. Primary sources

- https://github.com/charmbracelet/huh
- https://dlang.org/spec/memory-safe-d.html
