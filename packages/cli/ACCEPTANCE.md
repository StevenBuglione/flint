# flint:cli acceptance traceability

Source: `handoff/specs/tier-4/cli.md` section 6. Unit tests run with `dub test :cli` on DMD and LDC.
Compile-negative fixtures run with `python3 packages/cli/fixtures/negative/check.py <dmd|ldc2>`; each case
also compiles a minimally repaired copy as a positive control. Shell fixtures: build
`packages/cli/fixtures/completion`, write `complete.bash`, `complete.zsh`, `complete.ps1` and
`help-completion-fixture.txt` from its `bash`, `zsh`, `powershell` and `help` modes, then run
`fixtures/completion/test_shells.py <dir>`.

| ID | Required item | Covering test(s) | Status |
| --- | --- | --- | --- |
| CLI-01 | `--count 2` and `--count=2` both yield 2 | `tests/contract_tests.d:CLI-01 checked integer and float conversions, enum names and scalar duplication`; `tests/contract_tests.d:CLI-01 bare value option, overflow and trailing data fail with the argument index` | covered |
| CLI-01 | Bare `--count` fails | `tests/contract_tests.d:CLI-01 bare value option, overflow and trailing data fail with the argument index` (code, index and option name; the earlier test checked only the offset) | added |
| CLI-01 | Overflow fails | `tests/contract_tests.d:CLI-01 checked integer ...` (inline forms); `CLI-01 bare value option ...` (separate token `2147483648`, the spec usage fixture) | covered |
| CLI-01 | `2x` fails | both CLI-01 tests above (inline and separate token, value redacted) | covered |
| CLI-02 | `-abc` with three booleans sets all | `tests/contract_tests.d:CLI-02 clustered booleans and one consuming alias, negation, unknown token atomicity` | covered |
| CLI-02 | `-nSteve` with string `n` consumes the rest | same test (`-sSteve`, `-absSteve`) | covered |
| CLI-02 | No ambiguous fallback | `tests/contract_tests.d:CLI-02 a value alias consumes the rest of its cluster even when it spells other aliases` (`-sabc`, `-an5`, `-abs -c`) | added |
| CLI-03 | Duplicate long name rejected with a field-qualified diagnostic | `fixtures/negative/duplicate_long.d` via `fixtures/negative/check.py` (`duplicate-long.second: duplicate long option`); `static assert(!CanParse!DuplicateLong)` in `tests/contract_tests.d` | covered (runner added) |
| CLI-03 | Duplicate short alias rejected | `fixtures/negative/duplicate_short.d` via `check.py` (`duplicate-short.second: duplicate short alias`); `static assert(!CanParse!DuplicateShort)` | covered (runner added) |
| CLI-03 | Duplicate positional index rejected | `fixtures/negative/duplicate_positional.d` via `check.py` (`duplicate-positional.second: duplicate positional index`); `static assert(!CanParse!DuplicatePosition)` | covered (runner added) |
| CLI-04 | No option lookup after `--` | `tests/contract_tests.d:CLI-04 option terminator preserves dash-prefixed text and negative positionals` | covered |
| CLI-04 | Negative positional integer keeps signed parsing | same test (`-7` with and without `--`) | covered |
| CLI-05 | Valid UTF-8 values are copied | `tests/contract_tests.d:CLI-05 returned text owns UTF-8 and preserves empty argument values` (input mutated after parse) | covered |
| CLI-05 | Malformed text is invalidArgument | same test (surrogate, >U+10FFFF, 0xFF after `--`) | covered |
| CLI-05 | Empty string values are retained | same test (`--values=` and `""` positional) | covered |
| CLI-06 | `--help` works without required inputs | `tests/contract_tests.d:CLI-06 precedence, explicit environment opt-in, and actions without required values`; nested `service deploy --help` in `nested command paths select explicit child DTOs ...` | covered |
| CLI-06 | Environment ignored by default | `CLI-06 precedence ...` (`parse!RequiredEnvironment([])` with the variable set fails `required`) | covered |
| CLI-06 | Environment read only on explicit opt-in, CLI wins | `CLI-06 precedence ...` (`ParseOptions(false, true)`, CLI value 8 beats env, invalid env value redacted) | covered |
| CLI-07 | Completion words with quotes, backticks, spaces and `$()` are escaped data | `fixtures/completion/test_shells.py` (bash completes and re-reads the word, marker files never created); `tests/contract_tests.d:CLI-07 completion metadata is emitted only as quoted or encoded data` (bash/zsh single-quoted only, PowerShell base64 only) | added (unit test) |
| CLI-07 | zsh and PowerShell runtime execution | static checks above; `test_shells.py` zsh path and `test_powershell.ps1` | blocked (zsh and pwsh are not installed on this workstation; bash runtime and static zsh/PowerShell checks pass) |
| Fuzz | Lengths 0..256 and 1 KiB/1 MiB seeds | `tests/fuzz/corpus.d:the deterministic parser corpus covers short and boundary input sizes`; `fixtures/fuzz` timed run | covered |

Stub review: no signature-only or always-success paths found. Help, completion and parse each perform the
specified work; errors carry index, option name and a redacted reason.
