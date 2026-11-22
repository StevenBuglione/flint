# flint:test — implementation specification

Status: normative design for agents; contract declarations have been syntax checked. Runtime behavior below is an acceptance requirement, not a claim that a framework implementation already exists. The compiler receipt is [core-contracts.json](../../verification/core-contracts.json).

## 1. Purpose and reference parity

Add readable assertions, compile-time interface mocks and deterministic machine-readable test results to D built-in unittest blocks.

- [ ] AssertJ/testify-style expect(actual).toEqual(expected), boolean assertions and location-rich failures.
- [ ] JUnit XML plus human output, filters, deterministic seed and fail-fast option.
- [ ] Interface mock generation with explicit expectations; no runtime proxy or reflective method invocation.

## 2. Package boundary and exact DUB recipe

Catalog tier: **1**. Direct allowed Flint dependencies: **none**. No transitive import is an excuse to add a direct import without updating the dependency policy. Production code may not depend on flint:test. Recipe path: `packages/test/dub.sdl`, invoked from the monorepo root.

```sdl
name "test"
description "Flint test subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"

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

The root manifest registers the subpackage path. Fully qualified flint:<name> sibling dependencies resolve in the parent package; do not turn these dependencies into independently fetched registry packages. The recipe and [packages policy](../../scaffold/policy/packages.json) are authoritative.

## 3. Public D API and UDA definitions

These are concrete signatures in the contract fixture, not executable implementations. Internal representation may change while preserving signatures and semantics. Source: `contracts/source/flint/test.d`.

```d
/// Public API contract; declarations are not runtime implementations.
module flint.test;

@safe:
struct Expectation(T)
{
    private T actual;
    void toEqual(scope const T expected, string file = __FILE__, size_t line = __LINE__);
    void toBeTrue(string file = __FILE__, size_t line = __LINE__);
    void toBeFalse(string file = __FILE__, size_t line = __LINE__);
}

Expectation!T expect(T)(T actual);
struct MockOptions
{
    bool strict = true;
    uint maxCalls = 256;
}
/// Concrete implementation is generated once per interface at the test boundary.
struct Mock(Contract)
{
    private Contract implementation;
    static Mock create(MockOptions options = MockOptions.init);
    Contract instance();
    void returns(alias method, T)(T result);
    void verify();
}

struct TestOptions
{
    string filter;
    bool failFast = false;
    string junitPath;
    uint seed = 1;
}

int runTests(Modules...)(TestOptions options);
```

## 4. Internal architecture, ownership and safety

Use built-in `unittest` blocks as the authoritative registration source. The test runner builds an explicit module list and uses `__traits(getUnitTests, module)` during compilation; no source-text regex extraction and no runtime scan of loaded modules. Link the runner with -unittest. Native D unittest discovery is permitted through an explicitly configured runtime test runner; an automatic default runner and custom runner must never both execute the same block. BetterC packages use a separate C-main harness that invokes their test functions, keeping this full-D test package out of their production imports.

Expectation captures the value and emits failure details only on a mismatch. Equality is D == with type-specific diagnostics for strings, arrays and scalar values; equality does not call unsafe memcmp on padding. Failure includes expected/actual representation, source file and line. Diagnostic formatting and allocation are permitted in tests; assertions do not become production hot-path dependencies. NaN equality remains false and must be tested deliberately. Never swallow an unexpected exception to make the test pass.

`Mock!Contract` is a facade over an internally generated class that implements every interface method. `create` allocates native test storage, `instance` returns the actual Contract interface, `returns!(Contract.method)(value)` sets a deterministic return expectation, and verify checks recorded counts. The public facade is a struct so its declaration does not pretend that unimplemented interface methods already exist. The implementation validates that Contract is an interface and enumerates its declared/inherited methods exactly once. The initial mock subset supports named non-template methods with value/ref/in parameters and explicit return types; reject variadic C functions, return-by-ref, scope/return lifetime-sensitive borrowed return methods and overloaded methods without an explicit qualified alias. Do not emit an @safe mock that violates the interface's lifetime or @nogc annotations.

Strict mode rejects unexpected calls. maxCalls bounds the preallocated call log; overflow fails the test. For @nogc interface methods, call logging uses only fixed storage and preconfigured values. Expectations must be installed before the handler executes. Every reset clears counts and typed slots; concurrent calls are rejected unless the mock is explicitly owned by one test thread. Test order is deterministic lexicographic module name then declaration order. Seed is printed in every failure, and XML escapes control/markup characters correctly.

**Safety boundary:** The assertion/mock facade is @safe. Test-only adapters may allocate; they do not inherit server @nogc requirements except where an implemented interface requires them. Untrusted test FFI remains in the same approved boundary layout as production.

## 5. Compile-time, size and runtime budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are release gates on the designated reference runner, not observed performance results. Measure the package's fixed feature fixture, with dependencies frozen; cold/incremental definitions and statistical regression rules come from [CI budgets](../../docs/CI_PERFORMANCE_BUDGETS.md).

| Metric | Hard ceiling |
| --- | ---: |
| DMD cold build | 0.80 s |
| DMD incremental build | 0.60 s |
| LDC cold build | 4.80 s |
| LDC incremental build | 2.40 s |
| Marginal stripped linked bytes | 262,144 bytes |
| Compiler peak RSS | 536,870,912 bytes |
| Template instantiations | 2,000 |

The >10% compile/template/RSS regression rule and >5% binary growth rule also apply; passing a hard ceiling does not permit silent drift. Marginal size follows the provider-equivalent definition above; full native-provider and dependency footprints remain in the recorded complete binaries. Package deltas are not summed to estimate an application. Native shared-library bytes and static-dependency bytes must both be reported. BetterC core: **not claimed**.

**Benchmark fixture:** Measure compile-time cost for interfaces with 1/16/64 methods and 64 unittest modules. Runtime mocking speed is a diagnostic only; production size gates ensure flint.test symbols are absent from stripped release apps.

## 6. Required acceptance tests and edge cases

1. Equality diagnostics on scalars/strings/arrays, NaN, file/line correctness and escaped XML.
2. Interface inheritance, repeated method names, unsupported overload diagnostics, missing expectation, too many calls, zero calls and verify after reset.
3. @safe/@nogc interface conformance checked by compile tests; no hand-cast delegate safety attributes.
4. Custom runner executes each unittest exactly once; filter selects no tests returns a distinct nonzero exit unless --allow-empty was explicitly set.
5. Parallel test processes get distinct temp/output paths; runner failure never overwrites another shard report.

Every listed case becomes a named unittest or a compiler-negative fixture, with a deterministic seed for generated schedules/inputs. FFI/kernel lifetime tests run under the platform sanitizer jobs. Add regression fixtures for every corrected failure before closing the slice.

## 7. Agent implementation order and definition of done

1. Add the package modules and public declarations, compile the positive contract usage and the negative misuse fixtures, then implement the smallest deterministic behavior covered by the first acceptance group.
2. Complete ownership/error paths before adding throughput optimization; include bounded-resource exhaustion tests.
3. Add the fixed benchmark fixture, record raw samples and candidate baseline receipts, and complete all acceptance groups before activating this package for integration.

Run from `scaffold/` after implementing this package:

```bash
python3 tools/flint.py test --package test --compiler dmd
python3 tools/gates.py --package test --gate structural
```

The direct test equivalent is `dub test :test --compiler=dmd`. Repeat with `--compiler ldc2` through the orchestrator. A declaration-only contract pass is never a substitute for `dub test` on a runtime implementation. Full Gates 1–6 run for the integrated milestone once its canonical apps and runner baselines exist; absence of a required measurement blocks release rather than fabricating a zero measurement.

## Evidence and rationale

The D capability behind this design is documented at [https://dlang.org/spec/traits.html#getUnitTests](https://dlang.org/spec/traits.html#getUnitTests) (accessed 2026-11-21). Normative limits, failure codes and ownership policies above are Flint design decisions. See [core research evidence](../../research/core-sources.md) for precise capability claims and verification boundaries.
