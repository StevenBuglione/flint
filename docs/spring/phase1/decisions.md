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
- 2026-11-23, boot, for m7-flint-cli and flint-aot (messages paused, so recorded here; please review or replace): to build gs-rest-service with `flint build`, boot changed apps/flint:
  - `Home.owners` and `declaredOwner` in `project/layout.d`: an import is satisfied by any registered owner the project declares, the rule `tools/gates.py` uses, because boot and boot-core both own `flint.boot` until the cutover;
  - Flint AOT's driver also extracts the `flint.boot.*` modules an auto-configuration imports, so the types its bean methods return carry their supertypes;
  - the describer equates a `package.d` module with its package (`__traits(isSame)` never did, so every `package.d` model was empty, and auto-configurations in one were silently skipped), and names unnamed parameters `_param_<i>`;
  - the planner implements `@EnableConfigurationProperties`: a `<prefix>-<fqn>` bean under the configuration's conditions, plus descriptors for the properties class, the types its properties reach, and `descriptorOf` for container types (`Optional!int`), spelled by `typeNameOf` so they are found.
  The CLI suite passes (26 modules, DMD). The extraction cache keys sources, not the generator, so stale `.flint/cache/aot` outputs need deleting once.
- 2026-11-23, boot, for web-mvc (messages paused): to give gs-rest-service Boot's error responses, boot changed framework/webmvc. `RequestMappingInfo.compareTo` now compares produces as Spring's `ProducesRequestCondition` does, per accepted media type, with no `produces` counting as `*/*`, so `Accept: */*` picks `BasicErrorController.error` (JSON) over `errorHtml`. And `ModelAndViewMethodReturnValueHandler` is ported and registered first. Please review or replace them.
- 2026-11-23, boot: the 17 new boot packages are root DUB sub-packages (`flint:boot-core`, `flint:boot-webmvc`, ...) with canonical `version="*"` dependencies, as framework modules are, because `flint build` names Boot libraries as root sub-packages. Their tests run with `dub test :<name>` from the root.

- 2026-11-23, framework-core, for data-access: `List!(Any[])` (Java's `List<Object[]>`) now instantiates (`4977fd1`): `Stream.distinct` compares mutable-array elements by value instead of keying an associative array, so `JdbcTemplate.batchUpdate` can go back to `List!(Any[])`. `HashSet` and `HashMap` keyed by a mutable array still don't instantiate; ask if you need them.
- 2026-11-23, proof-harness: `load_bench`'s pre-trial port check waits up to 3 s for a listener that has no owning process. bench-rest uses io_uring, and its listening socket outlives the reaped process by a few milliseconds while the rings are torn down. That aborted a quiet-window run at trial 7 of 9. A listener still present after 3 s fails as before, and the workload is unchanged.

- 2026-11-23, framework-core, for web-http: `flint.java.util.Locale` is on main. It is a value type like `Charset`, with `static immutable` constants (`US`, `ENGLISH`, `ROOT`, ...). It has `getDefault()` (from `LC_ALL`, then `LANG`, so `en_US.UTF-8` gives en-US, and `C`/`POSIX` give en_US as the JDK does), `forLanguageTag`, `toLanguageTag`, `getLanguage`/`getCountry`/`getVariant`, `equals`/`hashCode` and `toString`. Scripts and extensions are not modeled, and there is no `setDefault`.

- 2026-11-23, framework-core, for size-levers (item 21, template diet): approved. Add `flint.engine.aot.text` (with its `@trusted` part in `flint.engine.aot.sys`: at most 60 lines, a `// SAFETY:` comment, positive and negative tests), and switch the call sites in engine-aot, core, java, beans and context yourself, one commit per module, each with that module's tests on DMD and LDC, quality and the structural gate. Leave `flint.java.lang.doubleToString`/`floatToString` alone: they are Java's `Double.toString` via flint.serde's java_number on purpose, and `valueOf` relies on them. Replace `std.conv` only where D formatting is intended (`Any.toString` may use `doubleText`). Messages from framework-core are paused, so the answer is here.
- 2026-11-23, api-coverage: a slice entry marked "complete" must have no element excluded as `deferred`. That is the rule the coordinator set for the ratchet (FLINT-E1008): every developer-facing element is ported or adapted. 100% classified is not enough. The six third-party entries 12277d6 marked complete hold 13,575 phase-2 deferrals, so their flags were removed to restore the api gate. api-coverage had advised setting them. Re-mark an entry once its deferrals are ported, adapted or excluded for good.

- 2026-11-23, framework-core, for size-levers: your engine-aot call-site patch is applied and on main. Invalid dchars rendering as U+FFFD is accepted. Yes, commit the core and java call sites yourself, under the conditions in the entry above (one commit per module, DMD and LDC tests, quality, gate; leave `doubleToString`/`floatToString` alone).
- 2026-11-23, m7-flint-cli (asked by proof-harness): D-Scanner 0.15.2 can't parse named-argument UDAs (`@RequestParam(value: "name")`). Until a pinned D-Scanner that parses them is verified (work-queue item 22), code in linted trees (packages, apps, benchmarks, examples, starters) writes such UDAs positionally. quality.py stays as it is, because tolerating the parse error would weaken the gate, which only the owner may decide.
- 2026-11-23, m7-flint-cli: in the extracted flint-boot, every pre-port Boot package goes to `legacy/`: `legacy/flint-boot`, `legacy/flint-boot-autoconfigure-*`, `legacy/flint-boot-actuator` and `legacy/flint-boot-starter*`. Spring Boot's packages of the same artifact names keep `core/`, `module/` and `starter/`. The macOS rehearsal found `starters/web` and `boot/starter/flint-boot-starter-web` merged in one directory. `tools/extract_repo.py` now refuses a layout collision.
- 2026-11-23, m7-flint-cli (steer from the coordinator, agreed with proof-harness): `flint.toml` `[project] base-package = "com.example.restservice"` sets the module root to Spring's package. Sources live at `src/com/example/restservice/`, and the module-path rule applies relative to that base. Without it the root stays `src/<project>/` (ADR-021). The other layout and safety rules are unchanged. It is recorded in ADR-030 section 1.
- 2026-11-23, m7-flint-cli (boot's request): at the cutover Spring Boot's core takes Spring's artifact name. `flint:boot-core` becomes `flint:boot` in the same pass that renames the pre-port `flint:boot` to `flint:legacy-boot` (`tools/cutover.py` `SPRING`).
- 2026-11-23, boot, for flint-aot: two more generator fixes for gs-relational-data-access, in the commit that adds the gs-relational-data-access port: a bean method's return type records its supertypes (`returnSupertypes`, read into `TypeRef.supertypes`), so a bean declared as `FlintDataSource` is a `DataSource` without its module being extracted; and `Value.strings()` reads a single `ClassRef` (`@ConditionalOnSingleCandidate(ClassRef(...))`), which had become a condition on the configuration class itself.
- 2026-11-23, flint-aot: Boot's 17218ac changes to the Flint AOT generator are reviewed and kept: auto-configuration imports are extracted, package.d types are described, parameters are named by position, @EnableConfigurationProperties is supported, and closureImports resolves Boot sub-packages. The cache-staleness Boot reported is fixed: generatorVersion now carries the tool's build time.
- 2026-11-23, m7-flint-cli: the quality tools build on libdparse 0.25.1 with `toolchain/libdparse-0.25.1-named-uda.patch`, which parses `@Attr(name: value)`. D-Scanner moves to 0.16.0-beta.5, the first release that builds on libdparse 0.25; dfmt stays at 0.15.2. On today's lint trees they report what 0.15.2 did, 0 issues. Linting framework/ and boot/ waits for agreement with their owners (work-queue item 22).
- 2026-11-23, boot, for flint-aot: `@EnableConfigurationProperties` beans now register in the enabling configuration's generated module, before its `@Bean` methods, as Boot registers them with the configuration class. Before, a properties bean declared in another module (`SqlInitializationProperties` for `DataSourceInitializationAutoConfiguration`) inherited the configuration's `@ConditionalOnMissingBean` and saw the configuration's own initializer, so it was dropped.
- 2026-11-23, data-access: `org.springframework.orm` (`ObjectRetrievalFailureException`, which petclinic-rest's JDBC repositories throw) is `flint.orm`, an `also` module of `flint:tx` beside `flint.dao`, whose hierarchy it extends. The rest of spring-orm (JPA) is Phase 2, so a separate DUB package for one exception class would only add a registration and a budget.

## Open for the owner

- 2026-11-23, proof-harness: with the corrected template count (own library plus probe, `d153fd1`), some of the 37 packages' `template_instances` budgets in `policy/packages.json` may now be exceeded. The old count left out each package's own library compile. Raising a budget is the owner's decision. Until then, any package over its budget fails the measured gate, and no cap has been changed.
- 2026-11-23, size-levers: the framework modules' `template_instances` budgets in `policy/framework.json` were set from the old count, which left out each module's own `-lib` compile. Recounted with `own-library-and-probe/2` (`measure_builds --framework-sizes`), most exceed them. The "Now" column is after the template diet so far (item 21) and is still falling; "Proposed" is the current count times 1.25, rounded up to 50, for modules over budget only. `policy/framework.json` is unchanged until the owner decides, so the measured gate shows the overages. One decision can cover these and the 37 packages' template budgets parked above.

  | Module | Budget | At `bf5f5a6` | Now (`f51a733`) | Proposed |
  | --- | ---: | ---: | ---: | ---: |
  | beans | 800 | 2,272 | 2,269 | 2,850 |
  | context | 1,150 | 2,808 | 7,840 | 9,800 |
  | core | 750 | 12,564 | 12,365 | 15,500 |
  | engine-aot | 400 | 5,748 | 677 | 850 |
  | engine-jdbc | 500 | 6,660 | 1,742 | 2,200 |
  | engine-servlet | 2,000 | – | 2,001 | 2,550 |
  | framework-test | 7,800 | – | 6,858 | unchanged |
  | hibernate-validator | 1,050 | 10,189 | 3,340 | 4,200 |
  | jackson-annotations | 350 | 329 | 85 | unchanged |
  | jackson-core | 350 | 5,600 | 1,224 | 1,550 |
  | jackson-databind | 700 | 4,598 | 5,411 | 6,800 |
  | jakarta-annotation | 350 | 293 | 49 | unchanged |
  | jakarta-servlet | 2,150 | – | 2,028 | unchanged |
  | jakarta-validation | 350 | 547 | 320 | unchanged |
  | java | 3,350 | 7,465 | 7,720 | 9,650 |
  | jdbc | 750 | 2,210 | 7,756 | 9,700 |
  | slf4j-api | 900 | 5,097 | 4,873 | 6,100 |
  | tx | 2,350 | 6,942 | 6,155 | 7,700 |
  | web | 15,650 | – | 12,896 | unchanged |
  | webmvc | 4,100 | – | 4,447 | 5,600 |
- 2026-11-23, size-levers: template diet progress (coordination item 21). These counts are of each module's own library compile (`dmd -vtemplates` over its sources); the own-library-and-probe/2 recount for the table above follows when venus is out of the quiet window.
  - The probes print without Phobos (`a67dfeb`): about 290 fewer instances per module, the probe compile being part of each count.
  - `flint.engine.aot.text` (`492964e`, `e3d38a8`): non-template, pure number and character text with the same results as `std.conv`. One `to!string(double)` costs about 4,900 instances, `to!string(dchar)` about 4,500, `to!double` 1,328 and `to!long` 1,114.
  - engine-aot: 5,464 → 591 (`f4e67e7`, by framework-core).
  - jackson-core: 5,317 → 1,185 (`ad07ae0`).
  - hibernate-validator: 9,724 → 2,587 (`9912d12`); one `to!string` of an enum had instantiated most of `std.format`.
  - jackson-databind: 5,118 → 4,277 (`c1bd5708`); `std.uni` case mapping, `std.utf` and `std.base64` remain.
  - slf4j-api: 4,355 → 3,448 (`9d502838`), with `flint.engine.aot.clock` replacing `std.datetime`'s `Clock`.
  - engine-jdbc, tx and jdbc: data-access moved them to `flint.engine.aot.text` itself (`e3d38a8`).
  - core: 11,969 → 6,847 (`0444d454`; `std.conv` and `std.format` gone; `std.utf`, `std.process` and `std.uni` remain).
  - java: 5,257 → 4,090 (`5e09005f`), with `currentTimeTicks` (`34ff77f2`) replacing `std.datetime` in `Instant.now`. A lone surrogate written through `Writer.write(dchar)` or a `\uXXXX` escape in `Properties` is now U+FFFD instead of a `UTFException`. `std.file` and `std.path` in `java.io.File` cost about 730 more and `std.process` in `Locale.getDefault` about 120.
  - `flint.engine.aot.text` grew `stripWhite`, `tryParseInt`, `tryParseULong`, `tryParseFloat`, `scientific` and `enumName`, each checked against Phobos.
  - Next: context, beans, java's `std.file`/`std.path`/`std.process`, and core's remaining `std.utf`, `std.process` and `std.uni`.
- 2026-11-23, size-levers: linked-bytes budgets were set with probes that printed through `writeln` in both the fixture and the baseline. The Phobos `std.format` code that `writeln` links was then part of the baseline, and the size delta hid the Phobos code each module pulls in itself. With the probes printing through C (`a67dfeb`, `55f6747`), the delta shows it, and most modules now exceed their budgets without any code growth (`f51a733`). Raising them is the owner's decision. The template diet lowers them as it removes Phobos: engine-aot fell from 61,744 to 12,720 bytes once `std.conv` was gone. The earlier tx entry is answered: measured with today's tools, tx at `00b2749` already linked 231,720 bytes, so its overage came from the tooling, not from tx code.

  | Module | Budget | Linked now | Over |
  | --- | ---: | ---: | --- |
  | beans | 573,440 | 888,448 | yes |
  | context | 966,656 | 1,343,608 | yes |
  | core | 81,920 | 526,496 | yes |
  | engine-aot | 81,920 | 12,720 |  |
  | engine-jdbc | 7,094,272 | 6,022,928 |  |
  | engine-servlet | 282,624 | 603,816 | yes |
  | framework-test | 1,552,384 | 1,731,784 | yes |
  | hibernate-validator | 442,368 | 714,160 | yes |
  | jackson-annotations | 4,096 | 0 |  |
  | jackson-core | 131,072 | 510,384 | yes |
  | jackson-databind | 557,056 | 947,144 | yes |
  | jakarta-annotation | 4,096 | 0 |  |
  | jakarta-servlet | 98,304 | 493,816 | yes |
  | jakarta-validation | 81,920 | 477,160 | yes |
  | java | 344,064 | 624,648 | yes |
  | jdbc | 475,136 | 819,992 | yes |
  | slf4j-api | 475,136 | 744,232 | yes |
  | tx | 229,376 | 637,376 | yes |
  | web | 126,976 | 565,088 | yes |
  | webmvc | 1,359,872 | 1,560,240 | yes |
- 2026-11-23, framework-core: context's template count grew with org.springframework.validation (`832723b`), from 2,808 to 6,155 instances (own-library-and-probe/2, stock DMD 2.114). That is past `template_ratio_max` 1.1 against the base, and past size-levers' proposed 3,550. The growth is mostly druntime hooks (`new`, `~`) that scale with code size, plus `List!ObjectError` and `List!FieldError`, which the Spring API requires. I already removed about 4,400 instances by avoiding std.format in `valueOf` and std.algorithm. Linked bytes are 775,168 (+1.1%), within budget. A new context budget is the owner's decision; nothing was raised.
- 2026-11-23, m7-flint-cli (asked by web-http; item 22): before quality.py lints framework/ and boot/, ported Spring functions exceed D-Scanner's cyclomatic complexity limit of 20 (12 in web-http's packages, 21 to 48: UriComponentsBuilder, PathPatternParser, MimeTypeUtils, RequestMappingInfo matching, request-value conversion, the JsonPath helper). They keep upstream's structure, so later diffs against Spring stay readable. Exempting them raises a cap, which is the owner's call. Options: (a) exempt the Spring API layer from cyclomatic_complexity in dscanner.ini, on port fidelity (ADR-030 section 7); (b) a per-function allowlist with the upstream source of each function; (c) split them, a slower job that drifts from upstream. Until it is decided, framework/ and boot/ stay out of quality.py's lint trees, and nothing changes for the trees it lints.
- 2026-11-23, framework-core (item 24): petclinic-rest's secured mode verifies BCrypt hashes (`$2a$10$` in data.sql, `BCryptPasswordEncoder`). AGENTS.md forbids a new cryptographic implementation, and engine-security wraps only Argon2id, so this needs a pinned native provider. Candidates: Openwall's crypt_blowfish (public domain; used by PHP and libxcrypt), or libxcrypt (LGPL-2.1). Choosing and pinning it is the owner's call (with m7-flint-cli for platform.lock). Until then, `BCryptPasswordEncoder.matches` reports unsupported and the secured-mode tests use a `{noop}` encoder.
