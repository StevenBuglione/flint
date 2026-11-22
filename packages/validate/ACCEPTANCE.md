# flint:validate acceptance traceability

Source: Section 6 of the [validation specification](../../handoff/specs/tier-1/validate.md).
Unit tests run with `dub test :validate` on DMD and LDC. Compile-negative fixtures run with
`python3 packages/validate/negative/check.py <dmd|ldc2>`; each case must fail with its field-local `static assert`
text, and a positive control must compile. The BetterC fixture `tests/betterc.d` runs under `tools/ci.py check --gate
betterc` (native DMD and LDC) and the wasm32 lane of `tools/ci.py platform-run` (`tests/wasm/betterc.mjs`). The
mailbox fuzz uses the fixed xorshift seed `0x5eede3a1`.

| # | Section 6 item | Covering test(s) | Status |
| --- | --- | --- | --- |
| 1a | Empty, ASCII and Unicode whitespace | `tests/behavior.d:UTF-8 whitespace and scalar counts` (every Unicode 17 White_Space scalar; U+200B and NUL are not blank) | covered |
| 1b | Invalid UTF-8 | `tests/behavior.d:UTF-8 whitespace and scalar counts` (truncated, overlong, surrogate, beyond U+10FFFF for NotBlank and Size); `tests/behavior.d:full Thompson matching with ASCII syntax and UTF-8 scalar input` (Pattern) | covered |
| 1c | String scalar versus byte counts | `tests/behavior.d:UTF-8 whitespace and scalar counts` (`string` counts scalars, `ubyte[]` counts bytes); `tests/behavior.d:Size counts scalars in UTF-16 and UTF-32 strings and rejects invalid code units` | covered + fixed |
| 1d | Signed minimum and unsigned maximum | `tests/behavior.d:numeric comparisons avoid sign overflow and rounded long endpoints` (`long.min`, `ulong.max`, negative bound on unsigned); `tests/behavior.d:narrow signed minima, unsigned maxima and nonfinite float and real values` (`int.min`, `short.min`, `ubyte.max`, `uint.max`) | covered + added |
| 1e | NaN and infinity | `tests/behavior.d:numeric comparisons avoid sign overflow and rounded long endpoints` (double); `tests/behavior.d:narrow signed minima, unsigned maxima and nonfinite float and real values` (float and real) | covered + added |
| 2a | Email boundaries | `tests/behavior.d:ASCII addr-spec boundaries and malformed mailboxes` (254 total, 64 local, 63 label, one over each) | covered |
| 2b | Pathological invalid email input | `tests/behavior.d:ASCII addr-spec boundaries and malformed mailboxes` (16 KiB local part, NUL, quotes, non-ASCII, double @); `tests/behavior.d:seeded mailbox fuzz agrees with the addr-spec model and never accepts beyond the bounds` (20,000 seeded structured and byte-noise inputs checked against an independent model) | covered + added |
| 2c | NFA state limit | `tests/behavior.d:256 states and adversarial input stay bounded` (`a{255}` runs, `a{256}` rejected); `tests/behavior.d:nested quantifiers stay within the state budget and linear on adversarial input` (`(a{15}){17}` = 256 states); `negative/check.py: 257 NFA states`, `negative/check.py: nested quantifiers beyond 256 states` | covered + added |
| 2d | Nested quantifiers | `tests/behavior.d:256 states and adversarial input stay bounded` (`(a+)+b` on 16 KiB, 16 KiB + 1 rejected); `tests/behavior.d:nested quantifiers stay within the state budget and linear on adversarial input` (`((a|b)+)*c`, `(a*)*(a|aa)*b` on 16 KiB); static asserts on `(a{16}){16}` and `((a{4}){4}){17}` | covered + added |
| 2e | Rejection of backreferences and look-around | static asserts in `tests/behavior.d` (`(a)\1`, `(?=a)`, `(?<!a)`, `(?:a)`, `\k<name>`, `\p{L}`); `negative/check.py: backreference`, `look-ahead`, `look-behind`, `Unicode property escape` (field-local diagnostics checked) | covered + added |
| 3a | 0 output slots | `tests/behavior.d:violations follow declaration order, annotation order, and nested indexes` (counting-only call) | covered |
| 3b | 1 output slot | `tests/behavior.d:violations follow declaration order, annotation order, and nested indexes`; `tests/behavior.d:one-slot and exactly-sized outputs report written and total separately` (slot beyond the slice untouched) | covered + added |
| 3c | N output slots and more violations than capacity | `tests/behavior.d:violations follow declaration order, annotation order, and nested indexes`; `tests/behavior.d:one-slot and exactly-sized outputs report written and total separately` (capacity equal to total) | covered + added |
| 3d | 4096 violation limit | `tests/behavior.d:the 4097 sentinel leaves output beyond the 4096th violation intact` | covered |
| 3e | Deterministic field ordering | `tests/behavior.d:violations follow declaration order, annotation order, and nested indexes`; `tests/behavior.d:one-slot and exactly-sized outputs report written and total separately` (repeat calls give identical reports and output) | covered + added |
| 4a | Nested DTOs and arrays | `tests/behavior.d:violations follow declaration order, annotation order, and nested indexes`; `tests/behavior.d:default, stale and foreign Text handles inside nested arrays fail without dereference`; BetterC `tests/betterc.d` (`rows[]` index paths) | covered + added |
| 4b | Wrong arena owner and stale Text handle | `tests/behavior.d:Text handles require the current owning arena and use the same UTF-8 rules`; `tests/behavior.d:default, stale and foreign Text handles inside nested arrays fail without dereference` | covered + added |
| 4c | Invalid handles produce a validation failure, never a dereference | `tests/behavior.d:Text handles require the current owning arena and use the same UTF-8 rules` (no arena, foreign, reset); `tests/behavior.d:default, stale and foreign Text handles inside nested arrays fail without dereference` (`Text.init`, foreign and stale in a two-level array; static diagnostic, correct indexes) | covered + added |
| 5a | Compile-fail incompatible UDA/type | `negative/check.py` (NotBlank on integer, Min on struct, Max on string, inverted Min/Max, contradictory duplicate Size, inverted Size, Size on integer, Pattern/Email on bytes, Min without arguments, Valid on a scalar, non-ASCII pattern literal); in-suite `!CanValidate` static asserts in `tests/behavior.d` | covered + added |
| 5b | Compile-fail recursive descriptor cycle | `negative/check.py: direct recursive descriptor`, `negative/check.py: mutual recursive descriptor`, `negative/check.py: nine collection index levels`; static asserts `Recursive`, `TooManyIndexes`, `NestedDepth!64` in `tests/behavior.d` | covered + added |
| 5c | BetterC native object/link checks | `tests/betterc.d` via `tools/ci.py check --gate betterc` (DMD and LDC; now also covers UTF-16 Size) | covered |
| 5d | BetterC wasm32 object/link checks | `tests/betterc.d` built with the `wasm_betterc` command line from `tools/ci.py` and run by `node tests/wasm/betterc.mjs` | covered |

## Fixed

- `Size` on `wstring`/`wchar[]` counted UTF-16 code units instead of Unicode scalars. A one-scalar `"🐈"w` therefore
  failed `@Size(1, 1)`, and unpaired surrogates were accepted. The spec says "Size on strings counts Unicode scalar
  values". `Size` now counts scalars in UTF-16 and UTF-32 strings and fails invalid code units, the same way it
  treats invalid UTF-8 (`source/flint/validate/internal/text.d:wideScalarSize`, `internal/schema.d:checkRule`).
  Regression test: `tests/behavior.d:Size counts scalars in UTF-16 and UTF-32 strings and rejects invalid code units`;
  BetterC `wideBehavior`.

Not run locally: the sanitizer job. It needs `tools/ci.py check --gate sanitizers`, which requires Clang 22.1.8; that
Clang is not installed here. Validate has no FFI or `@trusted` code.

No always-success or stub behaviour was found. `validate` passes an uninitialized `RequestArena`, so every `Text`
constraint reports "invalid or unavailable arena text handle". That is the documented behaviour and is tested.
