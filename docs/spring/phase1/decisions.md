# Phase 1 decisions log

`coordination.md` rule 4 asks for this log. When a session makes a decision that `AGENTS.md`, ADR-030, the rulebook or the AOT contract does not cover, it adds one dated line here: who decided, what, and why. If a rebase conflicts in this file, keep both lines.

## Decided

- 2026-11-23, coordinator: spring-test (`flint:framework-test`) shares the `flint.test` root by subpackage. web-http owns `flint.test.web.*` and boot owns `flint.test.context.*` (rulebook "Namespaces").
- 2026-11-23, coordinator: the four extracted repos are mirrors until the Phase 1 exit. The cutover requires an empty `policy/unregistered-packages.json`, with `framework/p1-interim` gone, plus rehearsal reports from Windows and macOS.
- 2026-11-23, coordinator: the BOM lives in `flint` next to `platform.lock`. The legacy Boot packages are renamed `flint:legacy-*` at the cutover, and the `flint` home resolves `policy/framework.json` modules as platform modules.
- 2026-11-23, coordinator: Flint's own JDBC driver is `framework/engine-jdbc` (`flint.engine.jdbc`). `TransactionInterceptor` implements `flint.engine.aot.proxy.Advisor` directly.
- 2026-11-23, proof-harness: the Go comparators are scored in a `semantic` wire mode. It ignores only the reason phrase, the framing headers (`Content-Length`, `Transfer-Encoding`, `Connection`, `Keep-Alive`) and JSON key order. Flint and Java are scored `exact`. Forcing Go to emit chunked framing would slow Go and flatter Flint (`benchmarks/spring/README.md`).
- 2026-11-23, proof-harness: `measure_builds --spring` also publishes a "deps-primed" Go series, with the comparator's driver packages primed in `GOCACHE`, next to ADR-030's std-primed headline. It is stricter on Flint and does not gate.
- 2026-11-23, proof-harness: a framework module's provisional timed budgets are replaced by the measured value plus headroom: 1.5x the median seconds, rounded up to 0.01 s, and 1.25x the compiler RSS, rounded up to a MiB (`framework_budgets.py apply`). Budgets already measured are never raised.
- 2026-11-23, proof-harness: template instances count each package's own `-lib` compile as well as its probe, as ADR-019 says (`template_count_method` `own-library-and-probe/2`). The measured gate refuses to compare counts made by different methods.
- 2026-11-23, proof-harness: the quiet window ignores idle DMD compile-server workers. A build process counts only if it uses at least 2 CPU ticks in a 1 s sample.
- 2026-11-23, proof-harness: petclinic-rest runs its JDBC profile on PostgreSQL 18.7 for all three implementations. gs-relational-data-access uses each ecosystem's embedded database: H2 for Java, SQLite for Go and Flint.
- 2026-11-23, boot: api-coverage's classification sweep 1 for the Boot Phase 1 checklists (163 exact ids: 68 `deferred` phase 3 reactive web, 59 `jvm-runtime` ClassLoader APIs, 28 `runtime-reflection` Spring AOT and RuntimeHints, 8 `jvm-platform` JMX and JNDI) is approved as proposed. The `ClassLoader`-free overloads (`LoggingSystem.get()`, `DataSourceBuilder.create()`) stay to be ported, and boot's messages are paused, so the approval is recorded here.
- 2026-11-23, m7-flint-cli: a repo keeps its own trees in the monorepo as `<tree>/<repo>` (`api`, `native`, `examples`, `tests`). The extraction moves them to `<tree>/` (`tools/workspace.py` `REPO_TREES`, `Home.repoLayout`).
- 2026-11-23, m7-flint-cli: the four engine golden examples move to `examples/framework/`. They stay DUB projects, because `flint.toml` has no string imports, extra source directories or wasm target. Extracted, they build against the workspace through `tools/workspace.py build-example`; golden-wasm-app builds through its `build.py` with `FLINT_ROOT`.
- 2026-11-23, m7-flint-cli: `flint add <name>` takes `flint:starter-<name>` while it exists, else Spring Boot's `flint:boot-starter-<name>`. So after the legacy rename, `flint add web` adds `flint:boot-starter-web`.

- 2026-11-23, framework-core: AOT contract 3 (flint-aot's proposal) is accepted as proposed and implemented in the runtime. That covers `flint.engine.aot.expression`, `MethodDescriptor.expressions` (with `expression(annotation, attribute)` added for lookup), `EventListenerSpec.conditionExpression` and `checkContractVersion` 1 to 3. flint:context evaluates compiled `@EventListener` conditions; Spring's conditionMatch and conditionDoesNotMatch are ported. Cache and security evaluation waits for those modules. framework-core's messages are paused, so flint-aot is told here.
- 2026-11-23, framework-core, for web-http: every type `p1-interim` stood in for is on main (1269967, `MethodParameter` 0e4c0c0, MimeType ca39294), so item 1 can delete the package. On `ConversionFailedException`: build it with Java-named `TypeDescriptor`s as planned. `DefaultConversionService` keeps D type names.
- 2026-11-23, framework-core, for m7-flint-cli: main's CLI suite passes on DMD at `b7c1889`+ (`flint test` in apps/flint). The `flint.core.annotation` clash was p1-interim's (and the AOT test fixture's) module against framework/core's package, which follows AGENTS.md (`annotation/package.d`). flint-aot's `e091ac1` routes around it, and retiring p1-interim removes it.
- 2026-11-23, framework-core, for third-party-apis: framework-core owns `flint.java.time` from `77bb70a`. Request changes rather than editing framework/java.
- 2026-11-23, m7-flint-cli: suites move with their code into `tests/<repo>/`: starters and openapi to `tests/boot/`, flint-mcp to `tests/ai/`, graceful shutdown and its fixture to `tests/framework/`. `tools/ci.py` runs each repo's `tests/` with `FLINT_ROOT` and `FLINT_WORKSPACE`, and `tests/flint_testing.py` finds directories by package or repo. test_flint_knowledge stays in flint because it tests the CLI, and so do the DMD-diagnostics misuse tests because they test the toolchain. Both resolve the engines through the workspace.

- 2026-11-23, framework-core, for data-access: `List!(Any[])` (Java's `List<Object[]>`) now instantiates (`4977fd1`): `Stream.distinct` compares mutable-array elements by value instead of keying an associative array, so `JdbcTemplate.batchUpdate` can go back to `List!(Any[])`. `HashSet` and `HashMap` keyed by a mutable array still don't instantiate; ask if you need them.
- 2026-11-23, proof-harness: `load_bench`'s pre-trial port check waits up to 3 s for a listener that has no owning process. bench-rest uses io_uring, and its listening socket outlives the reaped process by a few milliseconds while the rings are torn down. That aborted a quiet-window run at trial 7 of 9. A listener still present after 3 s fails as before, and the workload is unchanged.

- 2026-11-23, framework-core, for web-http: `flint.java.util.Locale` is on main. It is a value type like `Charset`, with `static immutable` constants (`US`, `ENGLISH`, `ROOT`, ...). It has `getDefault()` (from `LC_ALL`, then `LANG`, so `en_US.UTF-8` gives en-US, and `C`/`POSIX` give en_US as the JDK does), `forLanguageTag`, `toLanguageTag`, `getLanguage`/`getCountry`/`getVariant`, `equals`/`hashCode` and `toString`. Scripts and extensions are not modeled, and there is no `setDefault`.

- 2026-11-23, framework-core, for size-levers (item 21, template diet): approved. Add `flint.engine.aot.text` (with its `@trusted` part in `flint.engine.aot.sys`: at most 60 lines, a `// SAFETY:` comment, positive and negative tests), and switch the call sites in engine-aot, core, java, beans and context yourself, one commit per module, each with that module's tests on DMD and LDC, quality and the structural gate. Leave `flint.java.lang.doubleToString`/`floatToString` alone: they are Java's `Double.toString` via flint.serde's java_number on purpose, and `valueOf` relies on them. Replace `std.conv` only where D formatting is intended (`Any.toString` may use `doubleText`). Messages from framework-core are paused, so the answer is here.
- 2026-11-23, api-coverage: a slice entry marked "complete" must have no element excluded as `deferred`. That is the rule the coordinator set for the ratchet (FLINT-E1008): every developer-facing element is ported or adapted. 100% classified is not enough. The six third-party entries 12277d6 marked complete hold 13,575 phase-2 deferrals, so their flags were removed to restore the api gate. api-coverage had advised setting them. Re-mark an entry once its deferrals are ported, adapted or excluded for good.

## Open for the owner

- 2026-11-23, proof-harness: with the corrected template count (own library plus probe, `d153fd1`), some of the 37 packages' `template_instances` budgets in `policy/packages.json` may now be exceeded. The old count left out each package's own library compile. Raising a budget is the owner's decision. Until then, any package over its budget fails the measured gate, and no cap has been changed.
- 2026-11-23, size-levers: the framework modules' `template_instances` budgets in `policy/framework.json` were set from the old count, which left out each module's own `-lib` compile. Recounted with `own-library-and-probe/2` (`measure_builds --framework-sizes` at `bf5f5a64ed`), 13 of 15 exceed them. Proposed for the modules over budget: the recount times 1.25, rounded up to 50, the rule the first budgets used. `policy/framework.json` is unchanged until the owner decides, so the measured gate shows the overages. One decision can cover these and the 37 packages' template budgets parked above.

  | Module | Budget | Recount | Proposed |
  | --- | ---: | ---: | ---: |
  | beans | 800 | 2,272 | 2,850 |
  | context | 1,150 | 2,808 | 3,550 |
  | core | 750 | 12,564 | 15,750 |
  | engine-aot | 400 | 5,748 | 7,200 |
  | engine-jdbc | 500 | 6,660 | 8,350 |
  | hibernate-validator | 1,050 | 10,189 | 12,750 |
  | jackson-annotations | 350 | 329 | unchanged |
  | jackson-core | 350 | 5,600 | 7,000 |
  | jackson-databind | 700 | 4,598 | 5,750 |
  | jakarta-annotation | 350 | 293 | unchanged |
  | jakarta-validation | 350 | 547 | 700 |
  | java | 3,350 | 7,465 | 9,350 |
  | jdbc | 750 | 2,210 | 2,800 |
  | slf4j-api | 900 | 5,097 | 6,400 |
  | tx | 2,350 | 6,942 | 8,700 |
- 2026-11-23, size-levers: `tx` now links 231,800 bytes, over its 229,376 budget. It linked 176,408 when the budget was set on 2026-11-23 (`00b2749`), and data-access has added code since. This is drift caught by the gate, not a measurement change. data-access is told; raising the budget or trimming the module is for the owner and data-access.
- 2026-11-23, framework-core: context's template count grew with org.springframework.validation (`832723b`), from 2,808 to 6,155 instances (own-library-and-probe/2, stock DMD 2.114). That is past `template_ratio_max` 1.1 against the base, and past size-levers' proposed 3,550. The growth is mostly druntime hooks (`new`, `~`) that scale with code size, plus `List!ObjectError` and `List!FieldError`, which the Spring API requires. I already removed about 4,400 instances by avoiding std.format in `valueOf` and std.algorithm. Linked bytes are 775,168 (+1.1%), within budget. A new context budget is the owner's decision; nothing was raised.
