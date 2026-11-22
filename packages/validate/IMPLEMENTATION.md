# Flint validation

`flint.validate` applies field annotations to caller-owned DTOs with a
compiler-generated routine per DTO. It writes static diagnostics to a caller
buffer and preserves declaration and annotation order. Nested paths use
`[]` segments and separate indexes. An output slice of length zero counts
failures. A total of 4097 signals more than 4096 failures.

`validate` reads ordinary UTF-8 strings and arrays. Use `validateIn` for arena
`Text`. Each constraint on stale, foreign, or unavailable arena text reports
a failure without exposing the borrowed storage. `Size` counts Unicode
scalars for UTF-8, UTF-16 and UTF-32 text, rejecting invalid encodings, and
elements for other arrays. `NotBlank` uses Unicode
17.0.0 White_Space. Numeric bounds are inclusive. Floating-point NaN and
infinity fail numeric constraints.

`Email` accepts an unquoted ASCII dot-atom local part and letter, digit, or
hyphen domain labels. Mailbox syntax validation has no DNS or delivery
dependency.

## Pattern syntax

`Pattern` compiles a Thompson NFA at compile time and matches the entire
input. The ASCII grammar supports literals, grouping, alternation,
character classes and ranges, anchors, `?`, `*`, `+`, and bounded
repetition. Escapes include ASCII punctuation, ASCII control characters
`\n`, `\r`, `\t`, `\f`, and `\v`, ASCII hexadecimal bytes (`\xHH`),
and the shorthands `\d`, `\s`, `\w` and their uppercase complements.
A dot matches a Unicode scalar other than line feed. Negated classes can
match non-ASCII scalars.

The compiler limits patterns to 256 NFA states, 128 nested groups, and 4096
source bytes. Runtime input is limited to 16,384 UTF-8 bytes. Compile-time
diagnostics identify unsupported constructs and the affected DTO field.
Runtime matching visits each active state at most once per input scalar.

## Verification

Native DMD and LDC unit tests exercise UTF-8, numeric boundaries, email,
pattern syntax, nested diagnostics, overflow and arena ownership. The same
BetterC behavior fixture runs on native DMD, native LDC, and browser WASM.
Linux x86-64 glibc also runs the unit suite under AddressSanitizer, and the
static x86-64 musl suite runs in an empty root.

The feature and direct-dependency control probes in `bench/` exercise
8-, 32-, and 128-field DTO shapes with valid and failing inputs and full
or zero output. The control checks integer bounds and recognizes only the
fixed adversarial pattern's language with a direct scan. Pass `--measure`
for local timing diagnostics on the field workloads and normalized cost
from 1 through 16 KiB of pattern input. Certified results require the
designated-runner evidence process.
