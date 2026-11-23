# flint:engine-data acceptance traceability

Source: `handoff/specs/tier-3/data.md` section 7 ("Required unit, protocol, fuzz and benchmark acceptance").
PostgreSQL rows run when `FLINT_DATA_PG_TEST_DSN` names a disposable PostgreSQL 18.6 database; they were run
against a local 18.6 instance on both compilers. SQLite rows always run with the native SQL profile.

| Spec item | Covering test(s) | Status |
| --- | --- | --- |
| entity_negative — missing ID, duplicate ID | `fixtures/negative/entity.d` (`FlintDataMissingId`, `FlintDataDuplicateId`), run by `fixtures/negative/verify.py` on DMD and LDC | covered |
| entity_negative — duplicate column | `fixtures/negative/entity.d` (`FlintDataDuplicateColumn`) | covered |
| entity_negative — pointer/class/delegate field | `fixtures/negative/entity.d` (`FlintDataPointer`, `FlintDataClass`, `FlintDataDelegate`) | covered |
| entity_negative — invalid table/column identifier | `fixtures/negative/entity.d` (`FlintDataInvalidTable`, `FlintDataInvalidColumn`); also missing Table, duplicate Version, mismatched key type | covered |
| repository_roundtrip — insert→find→update→delete→exists with Text bytes, booleans, null wrapper, integer boundaries (SQLite) | `tests/contract_tests.d:"SQLite repository roundtrip, schema drift, named query and optimistic lock"` (`long.min`/`long.max`, `Nullable` present-empty vs absent, NUL in bytes, idempotent delete, `ulong.max` key rejected) | covered |
| repository_roundtrip — same on PostgreSQL | `tests/contract_tests.d:"PostgreSQL repository roundtrip, schema drift, named query and optimistic lock"` | covered |
| repository_roundtrip — raw cell mapping, UTF-8 and scalar bounds | `tests/contract_tests.d:"raw mapRow preserves ownership, checks types and rejects null substitutes"`; `tests/boundaries.d:"deterministic codec length, UTF-8 and scalar bounds"` | covered |
| identity_policy — id=0 returns generated nonzero ID; explicit IDs preserved; duplicates conflict | `exercise` in both roundtrip tests (`insert` with `long.max` preserved, second insert → `conflict`, `insert` of id 0 → `invalidArgument`) | covered |
| identity_policy — two generated saves yield distinct nonzero IDs | `tests/contract_tests.d:"query_lexer, ownership, identity_policy and schema_drift (drop column) on SQLite"` and the PostgreSQL twin | added |
| optimistic_lock — one writer wins, stale update returns conflict without overwriting | `optimisticLock` in both roundtrip tests | covered |
| query_lexer — colons in quoted literals, comments, dollar quotes ignored | `Match`/`Projections`/`DollarQuoted` queries in both roundtrip tests | covered |
| query_lexer — colon inside a quoted identifier ignored; repeated `:key` binds one value | `QuotedIdentifierColon` in `"query_lexer, ownership, identity_policy and schema_drift (drop column) on SQLite"` and the PostgreSQL twin | added |
| query_lexer — unknown/unused/duplicate params, positional markers, multiple statements, unterminated literal fail compile | `fixtures/negative/query.d` (6 cases), run by `fixtures/negative/verify.py` | covered |
| schema_drift — rename a mapped column; startup validation fails | `exercise` (`ALTER TABLE ... RENAME COLUMN` then constructor throws) in both roundtrip tests; `AbsentColumn` entity | covered |
| schema_drift — drop a mapped column; startup validation fails | `ALTER TABLE ... DROP COLUMN count` in `"query_lexer, ownership, identity_policy and schema_drift (drop column) ..."` (both drivers) | added |
| ownership — DTO Text handles fail generation checks after arena reset | `optimisticLock` (reset then read → error); `tests/boundaries.d` `checkLength` | covered |
| ownership — a raw struct copy of the DTO cannot outlive the arena (copy's Text/Buffer handles also fail; handles do not resolve against another arena) | `"query_lexer, ownership, identity_policy and schema_drift (drop column) ..."` (both drivers) | added |
| compile_bench — 1/10/100 entity repositories; template counts tracked; 100 within manifest caps | `fixtures/scale/measure.py` (DMD and LDC; checks `template_instances` ≤ 2000 and compiler RSS ≤ 512 MiB from `policy/packages.json`). Observed: DMD 325/469/1909 instances, 129 MB RSS at 100; LDC 311/437/1697, 227 MB | added (runner) |
| Native boundary corpora under ASan / LDC sanitizer configuration | whole D suite (both drivers) under `DFLAGS='-g -O1 -unittest -preview=dip1000 -boundscheck=on -fsanitize=address' dub test :data --compiler=ldc2 --build=plain`, `ASAN_OPTIONS=detect_leaks=0`; data has no C shim of its own (the SQL shim corpus is in `packages/engine-sql/tests/native_asan.py`) | covered (run) |
| Fuzz seeds: truncated input, maximum lengths, empty values | `tests/boundaries.d` (lengths 0..256, 1 KiB±1, 1 MiB±1, truncated/overlong/surrogate UTF-8, tiny arena) | covered |
| Fuzz seeds: cancellation, generation reuse | expired-context `findById` → `timedOut` in `exercise`; stale arena generations in the ownership rows | covered |
| Compile-fail tests assert nonzero exit and stable diagnostic | `fixtures/negative/verify.py` (exit 1 + exact diagnostic, both compilers) | covered |

## Stub review

No always-success paths found. `mapRow` maps one non-null cell and reports `notFound` for an unknown column;
NULL handling is the repository row consumer's job, as documented in `IMPLEMENTATION.md`.

## Commands

```sh
FLINT_DATA_PG_TEST_DSN=... dub test :data --compiler=dmd
FLINT_DATA_PG_TEST_DSN=... dub test :data --compiler=ldc2
python3 packages/engine-data/fixtures/negative/verify.py <log-dir>
python3 packages/engine-data/fixtures/scale/measure.py <output-dir>
```
