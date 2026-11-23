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

## Open for the owner

- 2026-11-23, proof-harness: with the corrected template count (own library plus probe, `d153fd1`), some of the 37 packages' `template_instances` budgets in `policy/packages.json` may now be exceeded. The old count left out each package's own library compile. Raising a budget is the owner's decision. Until then, any package over its budget fails the measured gate, and no cap has been changed.
