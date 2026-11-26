# Per-module definition of done

One command tells a porter whether a module is done and, if it is not, what to fix:

```bash
python3 tools/gates.py --module framework/jdbc --definition-of-done
```

It is the guardrail for autonomous porting in Phase 2 (owner decision 087f28a3). The design is in `coordination/notes/definition-of-done.md`, and the code is in `tools/definition_of_done.py`.

## Steps

Each step reports one of:
- **PASS**;
- **FAIL**: the module's own problem;
- **SKIP**: with its reason, and never counted as a pass;
- **ERROR**: the environment, not the module.

Each failure names what is wrong, where, the rule it breaks, and the command that reruns that step alone (`--step NAME`, repeatable).

| Step | What it runs | Passes when |
|---|---|---|
| `resolve` | `workspace.package_repos()` and the policy entry | the directory is a registered module (FLINT-E0535 otherwise) |
| `structural` | `gates.py --gate structural`, with `--package` for an engine package and `--repo` otherwise | no structural failure names this module. A repo-wide failure elsewhere is an ERROR |
| `api` | `flint api headers <dir>`, then `flint api coverage --repo R`, filtered to the module's Java packages | every ported file has its header, and no upstream element the module owns is unclassified. `--release` also fails `deferred` exclusions |
| `quality` | `quality.py --path <dir> --baseline policy/quality-baseline.json` | no dfmt (`+flint.stack-udas`), D-Scanner or complexity-allowlist finding beyond the baseline, and no baseline entry that is gone (see below) |
| `tests` | `dub test :<name> --build=unittest --temp-build` on DMD and LDC (the host's LDC, never the alpine one), plus the record's `test_packages`; the test binaries build under `.flint/definition-of-done/<name>/`, never in the module directory | both compilers pass |
| `upstream-tests` | `<dir>/upstream-tests.json`, checked against the D files and the fetched upstream | see below |
| `budgets` | `measure_builds.py --framework-sizes --framework <name>` | `incremental_linked_bytes` and `template_instances` are within `policy/framework.json`. Provisional keys are reported, not gated |
| `link-closure` | `jdk_link_closure.py --package <name>` for `flint:java` and `flint:java-*` | public JDK leaf probes keep their declared link closure under O3 and Oz. Existing violations are ratcheted, and `--release` requires a clean closure |
| `apps` | for each Spring app whose dependency closure has the module: `flint test --compiler both --verify` as built and with the static trim (`FLINT_GC_STATIC_VERIFY=0`), as `ci.py` runs it, with a disposable cluster of the pinned PostgreSQL peer for petclinic-rest; then `spring_bench.py accept --impl flint`, and `flint budget` once m7 lands it | allocation budgets hold, the golden suite passes in `exact` mode, and no budget regresses |

### Ownership of Java packages

A module owns the longest Java package prefix that maps to it:
- **Spring ports:** by rule R1 inverted. `flint.web.servlet` (webmvc) owns `org.springframework.web.servlet`; `flint.web` and `flint.http` (web) own the rest of `org.springframework.web` and `org.springframework.http`.
- **Ports of other libraries** (Jackson, Jakarta, SLF4J): by the packages that their mapped elements' `d` symbols come from.
- **Spring Boot ports:** `boot/core/flint-*` and `boot/module/flint-*`, pinned to the `spring-boot` upstream. The `flint.boot_*` libraries are Flint's own, so they own no Java packages and have no upstream tests.

## The quality ratchet

The coordinator decided this on 2026-11-25: `framework/`, `boot/` and `security/` stay out of `quality.py`'s default trees until their findings are fixed. Until then, `policy/quality-baseline.json` records the findings they have today:
- **Keys.** Findings are listed per file, keyed by check and message, with numbers and line positions left out, so an edit elsewhere in a file does not move them.
- **What fails:** any finding not in the baseline, which means new files or new findings in changed files. A recorded finding that is gone also fails, until the baseline is shrunk:

  ```bash
  python3 tools/quality.py --path framework/jdbc --baseline policy/quality-baseline.json --shrink-baseline
  ```

  Shrinking never adds an entry, so the baseline only shrinks, like the budgets. Recording findings (`--record-baseline`) is the integration owner's job, not the porter's.

## The upstream-tests record

**OpenJDK (`openjdk@21.0.13`).** The inventory reads OpenJDK's jtreg and TestNG tests under `test/jdk` (a file with a jtreg `@test` tag or a `@Test` method), keyed by their path below `test/jdk`, and owned by the module that owns the package their directory names.
- **Scope:** only tests of the JDK modules the API manifest pins (`java.base` and `java.sql`) count: the test's package must be a manifest package, or lie below one. Every other JDK module (`java.desktop`'s AWT, Swing, Sound and ImageIO, `java.management`, `jdk.*`) is excluded at module level, because it is outside the JDK port's product scope (owner, `docs/spring/phase2/jdk-port.md`). These tests are not listed row by row.
- **Plain-GPL tests:** many jtreg files are plain GPL-2.0, without the Classpath Exception, so they can never be ported into a `flint:java*` package. Such a class is `excluded` with a `reason` starting `plain-gpl` and `covered_by` naming the original Flint test file(s) covering the same behaviour; until one exists it stays `deferred`.

AGENTS.md requires every ported module to port its upstream tests. `upstream-tests.json` in the module directory records how:

```json
{"schema": "flint.upstream-tests/1", "upstream": "spring-framework@v7.1.0", "module": "jdbc",
 "test_packages": [":jdbc"],
 "classes": {
   "org/springframework/jdbc/support/JdbcUtilsTests.java":
     {"status": "ported", "d": "framework/jdbc/tests/jdbc_utils_tests.d",
      "methods": {"ported": ["commonDatabaseName", "lookupColumnName"]}},
   "org/springframework/jdbc/core/JdbcTemplateTests.java":
     {"status": "partial", "d": "framework/jdbc/tests/jdbc_template.d",
      "methods": {"ported": ["testUpdateCount"],
                  "skipped": {"testBatchUpdateWithSqlParameterSource": "no SqlParameterSource batch yet"}}},
   "org/springframework/jdbc/datasource/init/ScriptUtilsTests.java":
     {"status": "excluded", "reason": "R12: scripts run by Flint Boot's initializer"}}}
```

- **Keys** are paths under the upstream's `src/test/java`.
- **`d`** is the D file that ports the class, or a list of files when its tests are spread over several.
- **`status`** is one of:
  - `ported`;
  - `partial`, which needs `methods.skipped` with reasons;
  - `excluded`, which needs `reason`;
  - `deferred`, which needs `"phase": "2"` or `"3"`. It passes the normal check and fails under `--release`, like a deferred API exclusion.
- **A ported method needs a named unittest in `d`:**
  - `@("Class.method") unittest` in a file that ports several classes;
  - `@("method") unittest` in a file that ports one.

  Unittests whose names are not identifiers are Flint's own tests, and are never counted as ported methods.
- **Every upstream test class the module owns** must appear in the record. The list comes from the sources `flint api fetch --tests` downloads to `FLINT_CACHE` or `~/.flint/cache`. Without that cache, the step is an ERROR, never a pass.
- **`test_packages`** adds other packages whose tests exercise the module. For example, webmvc adds `:framework-test`, where MockMvc lives.

**Drafting the record.** `--write-upstream-tests` drafts the record from the module's `Ported from <project> <tag>, <path>/src/test/java/...Tests.java` headers and its unittest names. It keeps any entries that already exist. Then add the classes it could not see, and give each exclusion and skip its reason.

### Deferrals are a ratchet

The coordinator decided this on 2026-11-26:
- **The record.** `policy/upstream-tests-baseline.json` lists each module's deferred classes.
- **What fails:**
  - a deferred class not in that list, so a recorded class can never be turned back into a deferral;
  - a listed class that is no longer deferred, until the baseline is shrunk.
- **Shrinking.** Port, mark partial or exclude a deferred class, then shrink the baseline:

  ```bash
  python3 tools/gates.py --module framework/context --definition-of-done --step upstream-tests --shrink-upstream-tests
  ```

**Seeding** is the integration owner's job: `--seed-upstream-tests [2|3]` drafts the record and adds every class it still lacks. A class ported in another module of the same upstream is recorded as ported, pointing at that module's file; framework-test ports some web and webmvc tests. Every other class is recorded as deferred and added to the baseline. Seeding never changes a recorded entry.

The 31 Phase 1 modules with pinned test sources were seeded on 2026-11-26, with 4,172 deferred classes. Two kinds of upstream are checked on the module's own record alone, and skip, with the reason, while it has none:
- **No test sources pinned:** Maven `-sources.jar` pins such as Jackson core and annotations, Jakarta and SLF4J.
- **Clean-room upstreams:** a `signatures_only` pin, or `"use": "clean-room"` in `policy/upstream-licences.json`, such as OpenJDK. None of their tests may ever be ported, so the record lists the module's original tests and any Apache Harmony tests it ports.

An explicit test archive in `api/upstream-tests.json` still adds an inventory. Flint's own modules have no upstream tests to record.

## Output

- A summary on stdout, or the full report with `--json`.
- The report is also written to `artifacts/definition-of-done/<name>.json`, with schema `flint.definition-of-done/1`.
- Exit status:
  - **0:** every step passed or was skipped;
  - **1:** a step failed;
  - **2:** an environment error, such as a missing `flint`, `dmd`, `ldc2`, `dub`, `dfmt` or `dscanner`, natives that are not emitted, or no fetched upstream sources.

The whole command runs under one `measure_queue.py hold`, its own Python work included, so a measurement window on venus pauses it. Use `--no-hold` on other machines.
