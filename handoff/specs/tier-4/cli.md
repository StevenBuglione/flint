# flint:cli — implementation specification

Catalogue tier 4. Research cut: 2026-11-21. This file specifies implementation work; declarations in contracts are type-checking interfaces, not runtime implementations.

## 1. Purpose and reference parity

Compile a typed command struct into a deterministic CLI parser, help generator, and completion model. Cobra/pflag and picocli are behavioral references; the application imports only the parser and explicitly selected configuration/logging packages.

- [ ] UDA commands, long/short options, positional arguments, required values, typed defaults and environment bindings.
- [ ] Boolean flags support --flag and --no-flag; short boolean flags can cluster; an option consuming a value ends a cluster.
- [ ] Nested commands are represented by a command registry generated at build time; duplicate names or short aliases are compile errors.
- [ ] Help, version and shell completion select ParseAction and never execute the business callback. --completion bash/zsh/powershell sets completionShell. @Subcommand fields are explicit typed child command DTOs, and commandName identifies the selected child path.

## 2. Exact package recipe and dependency boundary

Write this recipe to `packages/cli/dub.sdl` in the implementation repository:

```sdl
name "cli"
description "Flint cli subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
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

Allowed direct Flint dependencies: `flint:arena`, `flint:validate`. The canonical allowlist is [packages.json](../../scaffold/policy/packages.json). Importing a higher catalogue tier or an unlisted same-tier package fails Gate 2.

## 3. Public D contract

Canonical declaration module: [flint.cli](../../contracts/source/flint/cli.d). These exact signatures are compiled with DIP1000. Implement the declarations with the semantics below; do not put unresolved declaration stubs into production artifacts.

```d
module flint.cli;
import flint.arena : Error;

@safe:
struct Command
{
    string name;
    string description;
    string versionText = "0.1.0";
}

struct Subcommand
{
    string name;
    string description;
}

struct Option
{
    string longName;
    char shortName;
    string help;
}

struct Arg
{
    size_t index;
    string help;
}

struct Required
{
}

struct Environment
{
    string name;
}

enum ParseAction : ubyte
{
    run,
    help,
    version_,
    completion
}

struct ParseOptions
{
    bool allowUnknown = false;
    bool readEnvironment = false;
}

struct ParseResult(T)
{
    T options;
    ParseAction action;
    Error error;
    Shell completionShell = Shell.bash;
    string commandName;
}

ParseResult!T parse(T)(scope const(char[])[] arguments, ParseOptions options = ParseOptions.init);
void writeHelp(T)(scope void delegate(scope const(char)[]) @safe sink);
enum Shell : ubyte
{
    bash,
    zsh,
    powershell
}

void writeCompletion(T)(Shell shell, scope void delegate(scope const(char)[]) @safe sink);
```

## 4. Internal architecture, ownership and safety

1. Perform UDA reflection only over T.tupleof and the explicit command registry, never all modules. Generate one lookup table and a shared non-template lexical scanner; instantiate a conversion function once per distinct field type. A 64-option fixture must stay below 2000 template instances.
2. parse owns all returned strings and arrays. It may allocate at startup and is not an @nogc API. Errors contain the original argument index, option name and conversion reason; sensitive values are replaced by <redacted>.
3. Precedence is command line > Environment UDA when readEnvironment=true > struct default. Configuration merging remains the caller's job. Duplicate scalar options are invalidArgument; arrays append in order. Unknown options fail unless allowUnknown=true, which skips the token only and never guesses its arity.
4. Integer parsing uses checked multiply/add and rejects overflow, locale separators and trailing data. Floating values must be finite. Enum matching is exact and case-sensitive. -- terminates option scanning; negative values immediately following a value option are data.
5. Help rendering is stable: command declaration order, 80-column fallback, NO_COLOR respected by the output layer. Completion emits bash complete -F, zsh _arguments and PowerShell Register-ArgumentCompleter without eval of user input. Completion arguments are shell-escaped.
6. Internal modules are flint.cli.scan, flint.cli.metadata and flint.cli.emit. No web/data imports and no C dependency. Root config/log integration belongs in the golden CLI.

### Concrete implementation files

- `packages/cli/source/flint/cli/package.d`: public declarations, UDA definitions and entry points.
- `packages/cli/source/flint/cli/internal.d`: shared non-template state machines and checked arithmetic.
- `packages/cli/tests/contract_tests.d`: behavioral tests identified in section 6.
- `packages/cli/tests/fuzz/`: deterministic seed corpus and bounded fuzz entry points; no fuzz data downloaded at test time.

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

Required benchmark: Parse 10, 64 and 256 declared options over 10,000 invocations. Record parsing ns/op, startup allocation bytes and generated module size. Compile the 64-option fixture as the package budget specimen; compare command metadata generated bytes against the committed baseline.

## 6. Acceptance, edge cases and required tests

| Test ID | Stimulus | Required result |
| --- | --- | --- |
| CLI-01 | --count 2 and --count=2 with an int field | Both yield 2; bare --count, overflow, and 2x fail. |
| CLI-02 | -abc with three booleans; -nSteve with string n | Booleans all true; n consumes the rest; no ambiguous fallback. |
| CLI-03 | Duplicate long name, duplicate short alias, duplicate positional index | Compilation rejects each fixture with a field-qualified diagnostic. |
| CLI-04 | -- --name and a negative positional integer | No option lookup after --; signed numeric parsing is retained. |
| CLI-05 | UTF-8 argument values, invalid bytes, empty arguments | Valid text is copied; malformed text is invalidArgument; empty string values are retained. |
| CLI-06 | --help, missing required field and explicit environment opt-in | Help works without required business inputs; environment is ignored by default. |
| CLI-07 | Completion words containing quotes, backticks, spaces and $() | Output is escaped data and shell tests cannot execute supplied text. |

The following is a real D test/usage fixture to place in the package tests. Runtime assertions become passing only after the specified implementation exists:

```d
import flint.cli : Command, Option, parse;
import flint.arena : Status;
@Command("count", "Count items")
struct Options { @Option("count", 'n', "Item count") int count = 1; }
unittest {
    auto parsed = parse!Options(["--count", "2"]);
    assert(parsed.error.code == Status.ok);
    assert(parsed.options.count == 2);
    assert(parse!Options(["--count", "2147483648"]).error.code == Status.invalidArgument);
}
```

For parser/codec boundaries fuzz every length from 0 through 256, then 1KiB/1MiB boundary seeds; reject overflows before allocation. Run a 60-second ASan smoke on every PR and a 30-minute corpus job nightly. A platform-specific test is required on the platform that owns the native boundary; a Linux compile-only job does not count as a Windows runtime pass.

From the implementation repository root:

```sh
dub test :cli --compiler=dmd
dub test :cli --compiler=ldc2
python3 tools/gates.py --package cli --gate structural
```

Do not mark this package complete until behavioral fixtures, compile-fail safety fixtures, the package budget fixture and all applicable native/WASM jobs pass. A declaration-only typecheck is API verification, not a package acceptance result.

## 7. Primary sources

- https://dlang.org/spec/attribute.html#uda
- https://dlang.org/spec/traits.html
