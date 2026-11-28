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
- 2026-11-23, data-access: spring-data-commons' `org.springframework.data.domain` (Sort, Pageable, PageRequest, Page, PageImpl, for petclinic-rest's v2 paging) is `flint:data-commons` in `framework/data-commons` (the structural gate's place for a framework.json module), module `flint.data.domain`, registered in policy/framework.json with `"repo": "data-commons"` (policy/repos.json's integrated repo), since no policy file registers integrated packages yet; platform.lock now sources data-commons from the monorepo, as data-jdbc (its GitHub repo held only a README). m7-flint-cli was asked where it belongs and had not answered within 30 minutes; the directory and policy file can move without touching the module name.

- 2026-11-23, framework-core (item 24): the Spring Security modules are staged as `framework/security-{crypto,core,web,config}` with `"repo": "security"` in `policy/framework.json`, not under a top-level `security/`. The structural gate accepts framework.json modules only under `framework/`; m7-flint-cli has not answered in 30 minutes. This is the smallest reversible step: a `git mv` and a policy edit once integrated repos have their own registration.

- 2026-11-23, coordinator: proof-harness's smoke run (one trial, busy venus, not evidence) shows gs-rest-service behind Go on every metric. Cold build 9.0 s vs 0.16 s (std-primed) / 3.4 s (`go build -a`); Oz binary 11.7 vs 6.6 MB; throughput 65k vs 155k req/s; p99 1.02 vs 0.29 ms; RSS 18.5 vs 13.1 MB. Performance is now the top priority. m7-flint-cli takes the platform cache (item 23), size-levers the binary breakdown, and third-party-apis leads the request-path profile, sending hotspots to their owners. Phase 1 apps continue. Phase 2 does not start until quiet-window numbers meet Go (ADR-030's stop rule). If confirmed gaps don't close, the fallback-or-redesign choice goes to the owner.
- 2026-11-23, m7-flint-cli (item 23): the platform cache's archive half is in `flint build` (flint-cli.md, "The platform cache"). It is on by default on Linux, with `--no-platform-cache` and `FLINT_PLATFORM_CACHE=0` for the from-scratch headline. Archives only, no `.di` files: DMD 2.114's `-H` output fails compile-time evaluation, and its `-inline` output loses imports behind UDA sequences, so the source stays the interface and the compile server holds the analysis. Two related fixes: `flint build` now writes `dub.selections.json` even when it is empty, because DUB rebuilt and relinked every project without it; and the Linux dev link is ld.bfd unless the DMD install chose mold (`install_toolchains.py --dmd-linker mold`, ADR-021). On gs-rest-service locally (not evidence): the no-op `flint build` drops from 4.0 s to 1.1 s. A one-line edit's DUB step is 2.5 s with cached archives and ld.bfd, or 0.9 s with mold, where `flint build` took 3.7 s in all before. flint adds about 0.9 s, mostly SHA-256 in the unoptimized dev-profile flint; a release-built flint does the no-op in 0.27 s.

- 2026-11-23, framework-core (item 24): the Spring Security modules moved to `security/security-{crypto,core,web,config}` once m7-flint-cli registered integrated repos (29820bc3); `"repo": "security"` is unchanged.
- 2026-11-23, m7-flint-cli (item 23, with the compile-performance session): mold is pinned (2.40.4, `policy/toolchains.json`), and on Linux x86-64 `install_toolchains.py --compiler dmd` configures DMD to link with it by default. The Milestone 6 numbers that beat Go assumed mold, and ADR-021 makes it the dev linker, but it was opt-in. gs-rest-service's link takes 0.3 s with it and 2.0 s with ld.bfd. `--dmd-linker system` opts out, and `flint doctor` warns (FLINT-E0823) when DMD links with the default.
- 2026-11-23, m7-flint-cli (item 23): flint writes the compile server's platform prelude in the format dmd-arm64 proposed. `.flint/generated/platform/dmd-server-prelude.txt` lists the `-I` paths, version identifiers and DFLAGS of the platform modules the project depends on, then their module names. Project builds pass the file as `FLINT_DMD_SERVER_PRELUDE`. The server should preload those modules, key itself by the file's digest, and compile in-process when a request's semantic switches differ. Until it reads the variable, the variable does nothing.

- 2026-11-23, coordinator: the compile-server half of the platform cache (item 23), the platform prelude in `flintserver.d`, is assigned to dmd-arm64 under the 30-minute rule. The base DMD patch's owning session hasn't answered in two hours. dmd-arm64 offered, and m7-flint-cli wires `FLINT_DMD_SERVER_PRELUDE` on flint's side. Uncertified gs-builds trials (11:44Z) put gs-rest-service at cached cold 1.54 s vs Go 0.159 s, incremental 0.98 s vs 0.154 s, and from scratch 4.51 s vs `go build -a` 3.24 s. Both sessions are asked for a breakdown of where the time goes.
- 2026-11-23, proof-harness: Flint's cold build measurements (`measure_builds --spring`) run with their own `FLINT_CACHE`, primed by one recorded build. The platform archives stay primed, as ADR-030's platform cache allows. flint's digest log (`digests.log`, cc2f98e2) is cleared before every cold and scratch trial: its entries are keyed by stat data, and a port measured in place keeps its files' stat data between trials, which Go's fresh source copies do not.
  - **Revised 17:00Z (proof-harness, at m7-flint-cli's request).** Cached cold trials now keep the digest log. It holds stat-keyed sha256 of the toolchain executables, flint and the platform sources, never the port's own sources: project sources are hashed in full and the artifact is always new in a cold trial. So it is platform and toolchain state, like Go's std-primed `GOCACHE`, and it lives in the platform cache that the primary headline allows. dmd-arm64's trace put about 130 ms of each cold build into re-hashing it.

    The reasons for clearing it were the in-place port's unchanged stat data and Go's fresh source copies. Two guards keep those reasons covered:
    - any entry under the port's directory is pruned before every trial, whatever flint records, and the receipt counts them in `port_entries_pruned`;
    - scratch trials still clear the log.

    The old method stays published, not gating, as `flint_cached_cold_digests_cleared_seconds` ("context: primary with the digest log cleared"), so the effect of this change is visible in every run. The coordinator or the owner can restore the old gating method by swapping the two series.
  - **Confirmed by the coordinator, on conditions (16:57Z, `5221ad67`, and their message to proof-harness; this supersedes `f35a12b3`'s "keep wiping digests.log").** The log already lives in `FLINT_CACHE`, and one that holds only digests of the toolchain, flint and the platform sources is platform cache state. ADR-030 section 5 defines the primary as the platform cache against a std-primed `GOCACHE`, so keeping it is within the definition, not a workload change. Conditions before the primary gates:
    1. Every project-keyed entry is pruned, and the run fails on a project-keyed hit. Met in `bf57dc9f`, below.
    2. m7-flint-cli's staleness test: an edited platform or toolchain file is re-hashed despite an unchanged size and a restored mtime (ctime and inode in the stat key). This is m7's to deliver.
    3. The context verdict "primary with the digest log cleared" is in every run. Met in `bf57dc9f`.
  - **Platform-only cold trials (proof-harness, 17:30Z; the coordinator's condition 1 of 16:57Z).** The primed cache keeps the project's own AOT models, their annotation sets and generated output (since `7907be4e`), which flint-aot moved under `projects/<root hash>/` in `64b85d08`. Cold trials reused them: the `2018e5e5` logs say "0 extracted, 23 from the shared cache". Go's cold trials never reuse the app's own work.

    Now `measure_builds --spring` builds a platform-only cache once, after the prime: a hard-link copy without `projects/`, with the digest log pruned of the port's entries and copied, not linked. Each cold trial (cached, static, scratch, context) then gets a fresh hard-link clone of it, deleted after the trial; the trial's edit build runs in the same clone. The run fails in three cases:
    - the platform-only cache still names the port's path in any text file;
    - a cold trial's AOT step extracted nothing, so it reused project-keyed state;
    - any platform entry changed in place through a hard link.

    The receipt records each cold trial's AOT counts (`aot_extracted_and_shared_per_cold_trial`) and the pruned digest entries. Every gs-builds primary since `7907be4e` (including 2.52 at `2018e5e5`) is optimistic for this reason; the incremental, edit-build and size results are unaffected.
  - **Update, 17:18–17:21Z (certified, `gs-builds` at `36c29248`, no foreign build in 12 samples).** This is the first fair cold result: platform-only cold trials (`bf57dc9f`), m7-flint-cli's cold-path steps (`804c2b6c`, `dc711c95`), ctime and inode in the digest stat key (`87c13a93`, condition 2) and nothing from FLINT_CACHE in the log (`36c29248`). It is still built with today's flags, with debug info (owner decision `4b27d207` comes with m7's next batch). Every cold trial extracted the project's own model (1) and took 22 platform models from the cache. Median ratios (99% interval):
    - primary: 3.07 (2.76–3.36), 0.535 s against 0.174 s;
    - context, primary with the digest log cleared: 3.62 (3.25–3.97);
    - secondary: 1.10 (1.06–1.12), 3.734 s against 3.381 s;
    - edit build, dev profile as built (shared objects): **0.447 (0.404–0.487), which passes**: 0.078 s against 0.175 s;
    - edit build, fully static: 1.87 (1.78–2.04), 0.326 s;
    - Oz: 0.615, which passes.

    Per-phase medians in ms:

    | Series | total | flint | aot | plan | compile | link |
    | --- | --- | --- | --- | --- | --- | --- |
    | edit, shared objects | 63 | 21 | 0 | 0 | 25 | 18 |
    | edit, static | 312 | 92 | 0 | 22 | 20 | 177 |
    | cached cold | 520 | 377 | 91 | 0 | 29 | 19 |
    | cached cold, digest log cleared | 615 | 474 | 89 | 0 | 31 | 21 |
    | static cold | 460 | 149 | 91 | 22 | 20 | 179 |
    | scratch | 3,714 | 129 | 88 | 3,265 | – | 230 |

    flint's own phase is 377 ms in the shared-object cold build against 149 ms in the static one, and the project's AOT extraction is about 90 ms. A FLINT_LOG diagnosis (17:25Z, under hold, not evidence) found why: the priming build links the shared platform object before the AOT library exists, so every later build keys it differently (`--whole-archive` gains `libflint-aot-library.a`). Each fresh cold clone therefore relinks it (`dmd -shared`, about 160 ms) and still runs the platform `dub describe` (about 50 ms). That is flint's behaviour as built, so the result stands; m7-flint-cli has the log. Evidence: `benchmarks/spring/evidence/gs-builds/20261123T171818Z/`.
  - **Update, 19:28–19:31Z (certified, `gs-builds` at `aa17876b`, no foreign build in 15 samples).** This is the first run under owner decision `4b27d207`: the gating commands carry `--no-debug`, matching Go's `-s -w`, and the with-debug series is non-gating context. It also has m7-flint-cli's `2d8a16dc`: no shared-object relink and no platform describe per cold trial, and static builds replay DUB's commands. Every cold trial extracted the project's model (1) and took 22 platform models from the cache. Median ratios (99% interval):
    - **primary: 1.255 (1.17–1.28)**, 0.198 s against 0.158 s (3.07 at `36c29248`);
    - **secondary: 0.985 (0.953–1.009)**, 3.251 s against 3.302 s. The median is under 1, but the upper bound misses the 0.99 ceiling;
    - **edit build, dev profile (shared objects): 0.398 (0.386–0.415), which passes**: 65 ms against 162 ms;
    - edit build, fully static: 1.27 (1.24–1.33), 0.206 s;
    - Oz: 0.617, which passes.
    - Context, not gating: primary with the digest log cleared 1.86; with debug information, primary 1.27, secondary 1.10, shared edit 0.407 and static edit 1.49.

    Per-phase medians in ms (no-debug):

    | Series | total | flint | aot | plan | compile | link |
    | --- | --- | --- | --- | --- | --- | --- |
    | cached cold | 195 | 78 | 74 | 0 | 24 | 19 |
    | edit, shared | 60 | 20 | 0 | 0 | 23 | 17 |
    | static cold | 356 | 82 | 74 | 23 | 20 | 158 |
    | edit, static | 200 | 22 | 0 | 0 | 24 | 155 |
    | scratch | 3,247 | 61 | 73 | 2,909 | – | 203 |

    The cold gap to Go (about 40 ms) is mostly the project's AOT extraction (74 ms) and flint's own 78 ms. The primary is now under the coordinator's 1.5 threshold for the Phase 1 builds parts. Evidence: `benchmarks/spring/evidence/gs-builds/20261123T192758Z/`.
  - **Update, 20:55–20:58Z (certified, `phase1-builds-gs-rest` at `6ab588f8`, the Phase 1 builds part).** This part includes m7-flint-cli's `6ab588f8` (the platform description record no longer goes stale, so cold trials skip `dub describe`) and `943466fa` (8 link threads by default). Java, Go and Flint pass 18/18. Median ratios (99% interval):
    - **primary: 0.933 (0.886–0.986), which passes**: 0.146 s against 0.157 s. This is the first time Flint's primary beats Go. The stricter deps-primed comparison is 0.914;
    - secondary: 1.009 (0.983–1.029), 3.335 s against 3.303 s. It narrowly fails;
    - **edit build, dev profile (shared objects): 0.427, which passes**;
    - edit build, fully static: 1.115 (1.089–1.146), with a link of 127 ms at 8 threads. It fails;
    - **Oz: 0.619, which passes**.
    - Context, not gating: digest log cleared 1.53; with debug information, primary 0.908, secondary 1.11 and static edit 1.22.

    Phases of the cached cold build: total 141 ms, flint 21, aot 74, compile 26 and link 21. The project's AOT extraction is now the largest part. Evidence: `benchmarks/spring/evidence/phase1-builds-gs-rest/`. size-levers reported a foreign `cc` compile in the first ~14 s of the claimed window. It ended before the claim settled at 20:55:17Z, the first timed trial began after 20:55:26Z, and all 16 samples during the measurement were clean, so no scored trial overlapped (`overlap-check.json` beside the evidence).
  - **gs-relational-data-access, same commit (certified, `phase1-builds-gs-relational`, 20:40–20:45Z).** Java, Go and Flint pass 1/1. Median ratios (99% interval):
    - **primary 0.037 (0.036–0.039); against a deps-primed GOCACHE, 1.295 (1.222–1.378).** Go's std-primed cold build compiles its 12 third-party packages (the pure-Go `modernc.org/sqlite` and its libc) from source, about 5.3 s, while Flint links its native SQLite and platform archives prebuilt. The deps-primed ratio is therefore the like-for-like comparison, and on it Flint is 30% slower;
    - **secondary 0.361 (0.360–0.364).** No deps-primed equivalent exists: `go build -a` recompiles every package, the driver included, while Flint's `--no-platform-cache` rebuilds the D modules but links the native C libraries prebuilt;
    - edit build, dev profile (shared objects): 0.788, which passes;
    - edit build, fully static: 1.41, which fails (compile 90 ms, link 113 ms);
    - Oz: **1.249, which fails**: 8,359,904 against 6,695,800 bytes, both stripped. size-levers is breaking it down.

    From now on `measure_builds --spring` and the Spring gate print the deps-primed ratio and this note next to the primary whenever the comparator has third-party packages. That is context only; the gating definitions are unchanged. Evidence: `benchmarks/spring/evidence/phase1-builds-gs-relational/`.
  - **petclinic-rest, same commit (certified, `phase1-builds-petclinic`, 21:08–21:14Z).** This is the independent check: Java, Go and Flint pass 109/109. Median ratios (99% interval):
    - **primary 0.620 (0.607–0.676); against a deps-primed GOCACHE, 4.18 (4.00–4.47).** Go's std-primed cold build compiles its 31 third-party packages (pgx and its dependencies) from source, about 1.8 s. With them cached, Go builds in 0.307 s against Flint's 1.282 s, so like for like Flint is about four times slower. Flint's cold build is AOT 760 ms (the project's extraction and generation for about 20 modules) plus compile 454 ms;
    - **secondary 0.334, not a valid scratch build.** petclinic-rest's `measure.scratch` lacks `--no-platform-cache`, so it ran as a cached cold build (1.39 s, plan 0) against `go build -a`. data-access owns the port and was asked to add the flag at 19:12Z. Until then this verdict says nothing about the secondary headline. A real scratch build would also have no deps-primed equivalent;
    - **edit build, dev profile (shared objects): 2.08 (2.01–2.26), which fails**: 0.644 s against 0.309 s. Compile is 454 ms: the edited controller module recompiles with its large imports;
    - edit build, fully static: not measured, because the port declares no `measure.cached_static` (requested from data-access);
    - **Oz: 1.070, which fails**: 12,173,112 against 11,380,728 bytes, both stripped.

    So with all three parts at `6ab588f8`, gs-rest-service passes its primary (0.933), edit build and Oz, and misses its secondary and static edit build narrowly. gs-relational-data-access and petclinic-rest pass their std-primed primaries only because Go compiles their drivers. Like for like they are 1.30 and 4.18, their edit builds and Oz fail or pass as listed, and petclinic-rest's secondary and static edit build still need port changes. Evidence: `benchmarks/spring/evidence/phase1-builds-petclinic/`.

- 2026-11-23, data-access: `@EnableTransactionManagement` stays in `flint.transaction.annotation` (R1), but `ProxyTransactionManagementConfiguration`, `AbstractTransactionManagementConfiguration` and `TransactionManagementConfigurer` live in the child module `flint.transaction.annotation.configuration`. They build the `TransactionInterceptor`, which reads `@Transactional` from the annotation module, and one module would import itself (circular imports are rejected). The annotation imports the configuration by its qualified name. flint:tx now depends on flint:beans and flint:context, as spring-tx does on spring-context for these classes. Size: flint:tx goes from 5,983 to 6,360 templates and 584,240 to 584,528 bytes; it was already over its budget (2,350 templates, 229,376 bytes), so I raised nothing and reported it to size-levers.
- 2026-11-23, third-party-apis (item 26's regex finding): Jakarta `@Pattern` needs `java.util.regex` semantics, and `flint.validate`'s automaton is not that engine: 256 NFA states (`[0-9]{1,160}` fails), ASCII literals, `\p{L}` only, no look-around, back-references, reluctant or possessive quantifiers, inline flags or `Pattern.Flag`s. Since `fbe899d5`, such a pattern fails loudly (HV000032, "Flint's run-time pattern engine does not support this java.util.regex pattern yet") instead of rejecting every value. The plan:
  - **Where.** `flint.java.util.regex` (`Pattern`, `Matcher`, `PatternSyntaxException`, R1) in `framework/java`, framework-core's module (asked in its inbox); Hibernate's `PatternValidator` compiles through it. `flint.validate` keeps the compile-time `@Pattern` contract of `handoff/specs/tier-1/validate.md`. No `std.regex` (AGENTS.md).
  - **Source.** OpenJDK is GPL-2.0 with the Classpath Exception and is not in `policy/upstream-licences.json`, so the engine is clean-room from the `java.util.regex.Pattern` Javadoc. Its tests are a corpus of (pattern, flags, input) cases with the expected result and `PatternSyntaxException` text recorded from JDK 21 by a generator kept beside the golden file, as `GoldenValidation.java` does.
  - **Engine.** A compiled program run by a backtracking matcher over code points, which is what look-around and back-references require. Steps are bounded per match: the budget is a documented deviation, since Java has none, and an exhausted budget throws instead of hanging a request thread (ReDoS). Look-behind needs a bounded maximum length, as Java requires.
  - **Landed** as `flint.hibernate.validator.internal.regex` (until framework-core says where `flint.java.util.regex` goes): the first group below, with JDK 21 parity on 367 recorded cases.
  - **Order.** First Hibernate's needs: the syntax subset with groups, classes (with intersection), quantifiers (greedy, reluctant, possessive, counted), anchors and `\b`, look-around, back-references, `\Q...\E`, inline flags and `Pattern.Flag`'s `CASE_INSENSITIVE`, `MULTILINE`, `DOTALL`, `UNIX_LINES` and `COMMENTS`. Then the Unicode general categories, generated from JDK 21's `Character.getType` as `letters.d` is. `UNICODE_CASE`, `CANON_EQ`, `\X` and Unicode scripts and blocks come last.
- 2026-11-23, size-levers (owner decision 5): BCrypt's provider is Openwall's crypt_blowfish 1.3, pinned as `crypt-blowfish` (`352af765`), consumer engine-security. The lock pins the release archive by SHA-256, Openwall having no repository. Its signature names RSA key 72B97DB1295029F1, which is in none of Openwall's published key files, so it was not verified; the pin rests on the digest, as every lock entry does. Only `crypt_blowfish.c` is built, with `policy/native-c.toml`'s hardening set: `wrapper.c` would define the C library's `crypt`, `crypt_r` and `crypt_gensalt`. `tools/provider_checks/crypt_blowfish_vectors.c` passes against the hardened build and an address,undefined build on linux-x86_64-glibc. For the owner: the lock's `research/licenses/<name>.txt` notice files live in `handoff/`, so crypt-blowfish has none; the licence text and its source digest are in the lock entry.
- 2026-11-23, size-levers (owner decision 3): the gate side is on main (`e849cb88`). `tools/template_budget_ratchet.py` refuses any `template_instances` budget raised after the anchor in `policy/budgets.json` (`template_budget_ratchet.after`), commit by commit and in the working tree, so lowering and raising back fails too. CI's structural-gate checkouts fetch the full history; a shallow one fails. `measure_builds --package-templates` counts the 37 packages' templates without timed builds. The anchor and the reset land together once the current diet round does (java and core std.file, std.path and std.process); until then the rule is off.
- 2026-11-23, size-levers (owner decision 3): **template budgets reset.** Each `template_instances` budget is now the corrected count (own library plus probe, `measure_builds --framework-sizes` and `--package-templates`) times 1.25, rounded up to 50. The counts were taken at `9db7fcd5`, after the diet round: java and core without std.process, std.file and std.path (`ab46223d`), and context without std.datetime (`9db7fcd5`). `policy/budgets.json`'s `template_budget_ratchet.after` is `e00b7bd0`, the reset commit's parent, so the structural gate now refuses any raise.
  - Framework modules, count → budget (old budget): core 6,829 → 8,550 (750); engine-aot 847 → 1,100 (400); engine-jdbc 2,188 → 2,750 (500); jackson-annotations 85 → 150 (150); jackson-core 467 → 600 (350); jackson-databind 3,860 → 4,850 (700); jakarta-annotation 49 → 100 (100); java 5,861 → 7,350 (3,350); jdbc 8,915 → 11,150 (750); slf4j-api 4,033 → 5,050 (900); tx 6,518 → 8,150 (2,350); data-commons 4,547 → 5,700 (5,750); beans 2,387 → 3,000 (800); context 7,460 → 9,350 (1,150); jakarta-validation 1,120 → 1,400 (350); hibernate-validator 4,209 → 5,300 (1,050); jakarta-servlet 2,240 → 2,800 (2,150); web 13,334 → 16,700 (15,650); webmvc 5,037 → 6,300 (4,100); framework-test 9,940 → 12,450 (7,800); engine-servlet 2,485 → 3,150 (2,000); security-crypto 1,163 → 1,500 (1,200); security-core 2,241 → 2,850 (2,600); security-web 1,576 → 2,000 (1,800); security-config 2,808 → 3,550 (3,300). In total 60,000 → 125,850: the old budgets left out each module's own `-lib` compile.
  - Packages (each was 2,000): engine-reactor 1,496 → 1,900; arena 535 → 700; conc 1,163 → 1,500; engine-di 1,774 → 2,250; config 1,664 → 2,100; serde 1,550 → 1,950; validate 1,065 → 1,350; log 850 → 1,100; test 1,350 → 1,700; engine-web 1,356 → 1,700; engine-http 725 → 950; engine-security 760 → 950; engine-actuator 1,945 → 2,450; engine-schedule 626 → 800; engine-rpc 779 → 1,000; engine-sql 470 → 600; engine-data 729 → 950; engine-migrate 1,093 → 1,400; engine-cache 945 → 1,200; cli 1,312 → 1,650; term 283 → 400; engine-tui 529 → 700; engine-style 294 → 400; engine-widgets 402 → 550; os 1,847 → 2,350; engine-wasm-bridge 132 → 200; engine-ui-signals 222 → 300; engine-wasi 402 → 550; engine-mq 673 → 850; engine-storage 1,547 → 1,950; engine-mail 783 → 1,000; engine-ai 1,176 → 1,500; engine-mcp 1,394 → 1,750; engine-template 1,102 → 1,400; engine-codec 253 → 350; engine-desktop 377 → 500. In total 74,000 → 44,950. arena was measured at `c88cf777`, after the Flint collector (`9bfdd441`, 173 → 535); nothing outside arena and Boot imports it, so the other counts stand.
  - engine-prompt keeps 2,000: its probe does not build. `packages/engine-prompt/bench/dub.sdl` and its baseline name `widgets/bench/harness/fake_display.d`, which `1720dea7` moved to `engine-widgets/`. Its budget resets when the probe is fixed; until then the ratchet holds it at 2,000.
  - engine-prompt's probe fixed (`7260b873`, asked by the coordinator): both manifests now name `engine-widgets/bench/harness/fake_display.d`, and the fixture and baseline build and run. Count 681 → budget 900 (was 2,000), by the same rule; packages now total 43,850.
  - framework-core's `ea038af1` (String.format over one non-template Formatter engine) adds 112 instances to java (5,749 → 5,861 at its parent and at the commit) and no linked bytes (162,024 both); java's new budget includes it.
  - The diet steps that preceded the reset, linked bytes before → after: java 624,744 → 162,024 and core 477,496 → 477,536 (`ab46223d`); context 1,233,712 → 1,233,712 (`9db7fcd5`; 8,069 → 7,460 instances, the probe links std.datetime through other paths). beans has no Phobos instances left: its 2,387 are druntime lowerings and java/core generics, so it had nothing to cut.

- 2026-11-23, size-levers (coordinator's L1, Boot side proposed to boot): **SQL drivers are linked by composition.** The engine-sql core reaches PostgreSQL and SQLite only through `enablePostgres()`/`enableSqlite()`. Applications declare the driver as Spring apps declare the driver jar: `flint:postgresql` (`flint.postgresql.Driver`, PgJDBC's `org.postgresql.Driver`) or `flint:sqlite-jdbc` (`flint.sqlite.JDBC`, sqlite-jdbc's `org.sqlite.JDBC`). boot-jdbc's `PostgresJdbcDriverAutoConfiguration`/`SqliteJdbcDriverAutoConfiguration` (Flint additions, `@ConditionalOnClass` on those classes) enable it, `DataSourceAutoConfiguration.dataSource` takes their `Driver` beans so they exist first, and boot's check (`fbcc04ef`: `determineDriverClassName` with `DatabaseDriver`, Hikari's `setDriverClassName`) fails at startup with "Cannot load driver class: flint.postgresql.Driver (add the flint:postgresql dependency)" when the URL's driver is undeclared, since engine-jdbc's `FlintDriver` accepts only the URLs of enabled drivers. gs-relational-data-access declares sqlite-jdbc (H2's place), petclinic-rest postgresql. Oz stripped: gs-relational 8,359,904 → 4,400,528 (1.249 → 0.657 of Go), petclinic-rest 12,173,112 → 10,776,280 (1.070 → 0.947), gs-rest-service 4,107,880 → 4,112,152 (unchanged; main drift). Acceptance 1/1, 109/109, 18/18. Playbook S-1a.
- 2026-11-23, size-levers (boot's choice, flint-aot's `30cebc6a`): the L1 fallback is gone. Flint AOT static-imports each `META-INF/services` provider, so `flint.postgresql`/`flint.sqlite` link and register themselves, and boot-jdbc's `PostgresJdbcDriverAutoConfiguration`/`SqliteJdbcDriverAutoConfiguration` and `dataSource`'s `Driver[]` parameter are removed. D-JDBC-1 now records only that a program without Boot (no Flint AOT) enables its driver itself.

- 2026-11-23, web-http (coordinator's call, windows-port's report): the delayed-echo test in engine-web's `http1_socket_behavior` proves waiting handlers are woken by completions, not polled, by counting task fiber resumptions (`Reactor.taskResumptions`, unittest and debug builds only): at most 2 per echo, asserted on every platform and compiler. Its 30 ms CPU bound keeps asserting on Linux and macOS and is reported on every Windows lane (ADR-026 known gaps). There GetProcessTimes charges CPU in 15.625 ms scheduler ticks, so 30 ms is under two ticks and a reading is quantized luck, not a measurement (LDC failed once at 31.25 ms, two ticks). The resumption count, verified on IOCP with DMD and LDC, is the proof there.

## Owner decisions, 2026-11-23

Decided by the project owner on 2026-11-23, answering the items parked below. The parked entries stay for their evidence.

1. **Build stop rule.** Phase 1 continues. The cause is known: the generated code instantiates heavy templates; one generated Jackson auto-configuration module compiles to a 17 MB object. The fix is to make generated code non-templated, as ADR-030 section 3 already requires, route it through the erased core, and split the largest generated modules across compile jobs. Phase 2 stays paused until certified build numbers beat Go.
2. **Shared-object dev linking: yes.** The dev profile links the platform cache as shared objects, so an edit relinks only the app. Release and size profiles stay static. Edit-build evidence reports two numbers, as cold builds do (ADR-030 section 5): the dev profile as built (shared objects) as the primary headline, and fully static as the secondary.
3. **Template budgets.** Each framework and package budget resets from the corrected count (own library plus probe) after the template diet, times 1.25, rounded up to 50, the rule the first budgets used. From then on budgets may only go down. The gate refuses a raise. This corrects a measurement, not a cap.
4. **Complexity limit.** Ported Spring functions that exceed D-Scanner's cyclomatic complexity limit are exempt only by name, through a per-function allowlist in which every entry cites its upstream source file and method. New Flint code stays under the limit, and framework/ and boot/ join quality.py's lint trees.
5. **BCrypt.** Pin Openwall's crypt_blowfish (public domain) as a native provider for `BCryptPasswordEncoder`, with its licence-matrix entry. No new cryptographic code is written.
- 2026-11-23, m7-flint-cli (owner decision 4): `policy/complexity-allowlist.json` lists the ported functions that may exceed D-Scanner's cyclomatic complexity limit. tools/quality.py drops a complexity finding only when the function it points at is listed, and only if the entry names an upstream project of policy/upstream-licences.json plus the upstream file and method. An entry whose function falls back within the limit is reported as stale. The first 9 entries are ports their module documentation names: HttpHeaders, UriComponentsBuilder, HierarchicalUriComponents, PathPattern, InternalPathPatternParser, AbstractMessageConverterMethodProcessor, ControllerAdviceBean, RequestMappingInfoHandlerMapping and jackson-core's NumberInput. quality.py skips the pre-port Boot directories, which retire at the cutover. framework/, boot/ and security/ join its default trees once their remaining findings are fixed: 8 functions over the limit that are not ports (helpers and test tables), 6 dfmt differences and a few lint findings, sent to their owners.

- 2026-11-23, coordinator: **ADR-030 section 4's agreed GC fallback is triggered.** The certified gs-rest-multicore run (gs-rest-service, Spring workload, 9 trials, 15:59Z) loses to Go on every runtime metric: capacity 187k vs 251k req/s (0.75), CPU per request 11.4 vs 8.3 µs (1.38), p50 at 20k req/s 0.111 vs 0.060 ms (1.84), p99 0.632 vs 0.258 ms (2.45), peak RSS 25.1 vs 13.8 MB (1.82). ADR-030 pre-agreed that if p99 or RSS loses, Flint builds a D collector with per-thread allocation caches, registered through druntime's GC interface. data-access owns it, together with the RSS investigation (per-reactor preallocation, fiber stacks, GC reserve). web-http owns request-path CPU and latency, and third-party-apis JSON cost. Phase 2 stays paused until certified runtime beats Go.
- 2026-11-23, m7-flint-cli: the Windows cutover rehearsal passes, so the coordinator's precondition of a Windows rehearsal report is met. It ran at source `dee89bda` (cutover commit 2303324e) on the Windows 11 VM, with `--check-timeout 14400`, and passed 27 of 27 in 9.3 min. The report is in the Windows session's shared notes (cutover-windows-dee89bd-green). The fixes that got it there:
  - Windows path separators in repoLayout, packagePath, diagnostics and the AOT generator;
  - CRLF in locks, sources and test output;
  - a project-local DUB home past MAX_PATH;
  - the joined recipe's test-only flint packages;
  - DUB's absolute-sourcePaths assert;
  - user32 for OpenSSL;
  - `core.thread.osthread` imports;
  - a Python suite ported to Windows, with its skips listed in ADR-026.
- 2026-11-23, m7-flint-cli (the coordinator's condition 2 for the cached-cold primary to gate): `<FLINT_CACHE>/digests.log` reuses a digest only while the file keeps its whole stat identity: size, modification time, change time (ctime), inode and device. ctime can't be set back, so an edit that keeps the size and restores the mtime is still re-hashed. Files whose mtime or ctime is under two seconds old are not recorded, because the kernel stamps ctime from a coarse clock. A unit test in support/files.d proves it. Remove ctime from the key and the test fails at "the change time catches the restored mtime". The log holds only toolchain, flint, home and platform files, never the project's, and proof-harness keeps it across cached cold trials (1235dc4b), pruning any port entry.

## Open for the owner

- 2026-11-23, proof-harness: **The first certified Flint-versus-Go runtime numbers miss every metric.** Queue entry `gs-rest-multicore` (web-http's), 15:18–15:59Z, a claimed window with no foreign build in 218 samples. gs-rest-service at `c473ea7b6f93` (multi-core servlet default; the port passes 18/18 exact) against the registered Go comparator, on the Spring REST workload with 9 interleaved trials. Flint/Go median ratios with 99% intervals (targets: throughput at least 1.01, the others at most 0.99):
  - throughput 0.746 (0.738–0.751): 187k against 251k req/s;
  - p50 1.84 (1.76–1.88): 0.111 against 0.060 ms;
  - p99 2.45 (2.17–2.63): 0.632 against 0.258 ms;
  - peak RSS 1.82 (1.80–1.84): 25.1 against 13.8 MB;
  - CPU per request 1.38 (1.34–1.40).

  ADR-030's agreed fallback applies to p99 and RSS: a D collector with per-thread allocation caches. Throughput and CPU per request need the request-path work (third-party-apis is profiling it; web-http measured 76.1k instructions per request). The evidence is in `benchmarks/spring/evidence/gs-rest-multicore/`.
  - **Update, 17:34–18:14Z (certified, `gs-rest-multicore-2`, web-http's, at `1af77aed`: io_uring steps 1–2 plus data-access's `8815f2d2`).** A claimed window with no foreign build in 218 samples, and the port passes 18/18 exact. Flint/Go median ratios (99% interval), with the first run's in brackets:
    - throughput 0.759 (0.753–0.770) [0.746]: 190k against 250k req/s;
    - p50 1.96 (1.88–2.45) [1.84]: 0.118 against 0.060 ms;
    - p99 2.45 (2.31–2.87) [2.45]: 0.644 against 0.263 ms;
    - peak RSS **1.61 (1.59–1.63)** [1.82]: 22.2 against 13.8 MB;
    - CPU per request 1.52 (1.40–1.78) [1.38]: 12.6 against 8.3 µs.

    RSS improved by about 3 MB; throughput is about the same. CPU per request and p50 are slightly worse, but their intervals overlap the first run's. Every metric still misses. Evidence: `benchmarks/spring/evidence/gs-rest-multicore-2/`.
  - **Update, 18:27–19:07Z (certified, `gs-rest-multicore-3` at `1141a9bc`).** This build has io_uring steps 1–3 plus the allocation cuts: `bc808cca` (servlet path, 37 to 31 allocations), `08b19d2f` (Accept parsing) and `b7c8891d` (writeValueAsBytes). The coordinator asked that this attribution be kept. The collector is druntime's default. A claimed window with no foreign build in 218 samples, and the port passes 18/18 exact. Flint/Go median ratios (99% interval), with multicore-2's in brackets:
    - throughput **0.801 (0.796–0.808)** [0.759]: 200k against 249k req/s;
    - p50 1.83 (1.69–1.97) [1.96]: 0.111 against 0.061 ms;
    - p99 **2.27 (2.01–2.50)** [2.45]: 0.595 against 0.262 ms;
    - peak RSS 1.66 (1.65–1.68) [1.61]: 23.0 against 13.8 MB;
    - CPU per request 1.46 (1.33–1.58) [1.52]: 12.0 against 8.2 µs.

    Throughput rose about 5% and p99 fell. RSS and CPU per request are within noise of multicore-2. Every metric still misses. Evidence: `benchmarks/spring/evidence/gs-rest-multicore-3/`.
  - **Update, 19:44–20:24Z (certified, `gs-rest-multicore-4` at `27e8d10b`).** This is the allocation-cut run, at 19 per request: web-http's `27e8d10b` takes /greeting from 31 to 19 GC allocations, and the build also has `6a48c768` (lookup path) and `852b8a8e` (Jackson writes). The collector is druntime's default with no gcopt, on the same workload as multicore-3. A claimed window with no foreign build in 217 samples, and the port passes 18/18 exact. Flint/Go median ratios (99% interval), with multicore-3's in brackets:
    - throughput **0.885 (0.877–0.892)** [0.801]: 218k against 247k req/s;
    - p50 **1.48 (1.44–1.52)** [1.83]: 0.090 against 0.061 ms;
    - p99 **1.93 (1.82–2.05)** [2.27]: 0.522 against 0.271 ms;
    - peak RSS 1.62 (1.60–1.64) [1.66]: 22.2 against 13.8 MB;
    - CPU per request **1.17 (1.14–1.19)** [1.46]: 9.7 against 8.3 µs.

    Cutting allocations by 39% moved throughput, latency and CPU by 10–20% each, while RSS is flat. Every metric still misses. Evidence: `benchmarks/spring/evidence/gs-rest-multicore-4/`.
  - **Update, 22:57–23:37Z (certified, `gs-rest-multicore-5` at `b520e07a`).** This batch has:
    - `73d9ecbf` (/greeting at 16 allocations per request);
    - `7938d402` (servlet handler limit 200, 100 fibers per reactor);
    - `46d21e28` (inline Any);
    - flint-aot's `30cebc6a`;
    - the rebuilt shared toolchain (DMD `0aae4c32`; multicore-4 ran on `1a894e5e`).

    The collector is druntime's default with no gcopt, on the same workload. A claimed window with no foreign build in 217 samples, and the port passes 18/18 exact. (The 21:25Z attempt was voided by a foreign compile.) Flint/Go median ratios (99% interval), with multicore-4's in brackets:
    - throughput **0.916 (0.910–0.922)** [0.885]: 227k against 248k req/s;
    - p50 1.69 (1.54–1.78) [1.48]: 0.102 against 0.061 ms. **Worse**;
    - p99 **1.57 (1.38–1.68)** [1.93]: 0.405 against 0.258 ms;
    - peak RSS **1.44 (1.42–1.47)** [1.62]: 19.9 against 13.8 MB;
    - CPU per request 1.33 (1.22–1.39) [1.17 (1.14–1.19)]: 11.0 against 8.3 µs. **Worse beyond the intervals.**

    RSS fell about 2.3 MB (the handler limit), and p99 and throughput improved. CPU per request rose about 13% and p50 rose. The batch can't attribute that rise to one change. The handler limit (fewer fibers per reactor, with queueing past the limit) is a candidate, as is the toolchain change for anything DMD-built; the release build itself is LDC. Every metric still misses. Evidence: `benchmarks/spring/evidence/gs-rest-multicore-5/`.

- 2026-11-23, proof-harness: **The Phase 0 runtime levers regress bench-rest's peak RSS by 6.2%.** This is certified: queue entry `runtime-levers-rest`, 14:14–14:54Z, load 0.78 at the start, no foreign build in any of 220 samples. bench-rest at `e16668e` (base) against `966c4b7` (FiberLocal, 256 KiB guarded fiber stacks, the offload pool), both built with bench-rest's README release command, on the production REST workload with 9 interleaved trials. Median ratios with 99% intervals against `policy/budgets.json`'s regression ceilings:
  - peak RSS 1.062 (1.045–1.090; 13.66 MB against 12.87 MB): over the 1.05 ceiling;
  - p50 1.017 (0.989–1.037), CPU per request 1.006 (0.987–1.015), throughput 0.997: within;
  - p99 0.993 (0.856–1.345): too wide to call.

  ADR-030 section 4 expected only touched pages to count, so that larger stacks would be RSS-neutral (`packages/reactor/tests/fiber_stack.d` measures idle fibers). Under load the regression ratio is exceeded. Either the levers change, or the owner accepts the cost. The evidence is in `benchmarks/spring/evidence/runtime-levers-rest/20261123T141406Z/`.

- 2026-11-23, proof-harness: **ADR-030's Phase 1 stop rule is met on builds.** These are the first certified Flint-versus-Go numbers: gs-rest-service builds, queue entry `gs-builds` at 7ddf0354, 12:30–12:33Z. The window was quiet: load 0.32, and no foreign build process in any of 14 samples. Nine trials each, with the release-built flint, DMD linking with the pinned mold, the platform cache primed and the digest log cleared before every cold trial. Flint misses every gated build metric (Flint/Go median ratio, 99% interval; the target is at most 0.99):
  - primary, the platform cache against a std-primed `GOCACHE`: 6.72 (6.34–6.87), 1.066 s against 0.159 s;
  - secondary, `--no-platform-cache` against `go build -a`: 1.30 (1.29–1.32), 4.192 s against 3.232 s;
  - incremental: 3.99 (3.84–4.17), 0.632 s against 0.158 s;
  - Oz binary size: 1.245, 8,259,192 bytes against 6,634,456, both stripped. The run recorded 1.775 because flint's artifact was unstripped; corrected in `correction.json` beside the evidence.

  ADR-030 says to take the fallback or redesign before Phase 2. The agreed fallback (a D collector) addresses p99 and RSS, not builds or size, so for these metrics only a redesign or an amended target remains, and that decision is the owner's.
  - **Levers that remain** (m7-flint-cli, 2026-11-23): flint-aot's template diet for the generated Jackson auto-configuration module, the 448 ms critical-path compile; splitting that module across compile jobs; and the dev link, through shared-object dev builds, which is the owner's call. The binary size is with size-levers. The compile-server preload of the platform modules is ruled out: dmd-arm64's prototype gained 13 ms once correct (9f1a1d8b).
  - **Evidence:** `benchmarks/spring/evidence/gs-builds/20261123T123014Z/`.
  - **Update, 15:06–15:09Z (certified, `gs-builds` at `6a7baf8f`, no foreign build in 12 samples):** after the template diet, the cached AOT library (ff31b6d2) and size-levers' work, the median ratios (99% interval) are:
    - primary: 4.01 (3.84–4.11), 0.628 s against 0.157 s;
    - secondary: 1.09 (1.07–1.11), 3.588 s against 3.291 s;
    - incremental, dev profile as built: 2.89 (2.82–3.01);
    - Oz size: **0.594, which passes**, 3,943,248 bytes against 6,634,456, both stripped.

    The fully static incremental build waits for `flint build --static` (owner decision 2). Evidence: `benchmarks/spring/evidence/gs-builds/20261123T150624Z/`.
  - **Update, 16:07–16:12Z (certified, `gs-builds` at `dee89bda`, no foreign build in 12 samples):** this run has shared-object dev linking (592d4b37) and the static secondary. Median ratios (99% interval):
    - primary: 3.46 (3.40–3.57), 0.547 s against 0.158 s;
    - secondary: 1.11 (1.10–1.12);
    - edit build, dev profile as built (shared objects): 1.53 (1.46–1.60), 0.240 s against 0.158 s;
    - edit build, fully static: 2.97 (2.86–3.04), 0.468 s;
    - Oz: 0.609, which passes.

    Evidence: `benchmarks/spring/evidence/gs-builds/20261123T160701Z/`.
  - **Update, 16:48–16:51Z (certified, `gs-builds` at `2018e5e5`, no foreign build during the run).** This run has the DMD fork with dmd-arm64's compile-server prelude, built from the checkout's own patch (PGO). It also has m7-flint-cli's cached platform description (`c2ae7990`, `2018e5e5`) and flint-aot's `2cd5ce4d`. Median ratios (99% interval):
    - primary: 2.52 (2.38–2.65), 0.402 s against 0.160 s;
    - secondary: 1.06 (1.01–1.08), 3.519 s against 3.313 s;
    - edit build, dev profile as built (shared objects): **0.758 (0.704–0.799), which passes**: 0.123 s against Go's 0.162 s;
    - edit build, fully static: 2.15 (2.04–2.25), 0.348 s;
    - Oz: 0.612, which passes.

    Per-phase medians in ms, against the edit-build budget of 100 total, 20 flint, 60 compile and 20 link:

    | Series | total | flint | aot | plan | compile | link |
    | --- | --- | --- | --- | --- | --- | --- |
    | edit, shared objects | 118 | 22 | 0 | 20 | 57 | 18 |
    | edit, static | 340 | 89 | 0 | 21 | 58 | 170 |
    | cached cold | 391 | 276 | 18 | 22 | 59 | 17 |
    | scratch | 3,512 | 127 | 17 | 3,111 | – | 242 |

    In the shared-object edit build, compile and link are within budget. The 118 ms total is over the 100 ms budget by DUB's plan (20 ms, which m7 is taking off the dev path) and flint's 2 ms. In the cold build, flint's own 276 ms is the description run again, because cold trials clear `.flint`. In the static edit build, the 170 ms link dominates. Evidence: `benchmarks/spring/evidence/gs-builds/20261123T164458Z/`.
  - **Not yet certified:** the runtime metrics. A smoke run gave Flint about 0.26–0.4x Go's throughput. `phase1-guides` measures them in the next window.

- 2026-11-23, coordinator: the edit-build floor. After m7-flint-cli's cut (`19390bd1`: 0.98 s → 0.69 s), gs-rest-service's edit build is link 0.2 s, compile 0.13 s and flint's own overhead about 0.3 s. Even with every planned lever (the compile-server prelude, flint overhead cuts), m7 estimates a floor near 0.35 s against Go's 0.154 s. Closing it likely needs dev builds that link the platform cache as shared objects, so an edit relinks only the app; release and size builds stay static. That changes what the edit-build gate compares (a dynamically linked dev binary against Go's static one), so it's the owner's call. m7 is prototyping and measuring it, plus split debug info (which needs no decision), and won't make shared-object dev builds the default without a yes.

- 2026-11-23, proof-harness: with the corrected template count (own library plus probe, `d153fd1`), some of the 37 packages' `template_instances` budgets in `policy/packages.json` may now be exceeded. The old count left out each package's own library compile. Raising a budget is the owner's decision. Until then, any package over its budget fails the measured gate, and no cap has been changed.
- 2026-11-23, size-levers: the framework modules' `template_instances` budgets in `policy/framework.json` were set from the old count, which left out each module's own `-lib` compile. Recounted with `own-library-and-probe/2` (`measure_builds --framework-sizes`), most exceed them. The "Now" column is after the template diet so far (item 21; re-measured at `61b21965`, after the core and java cuts) and is still falling; "Proposed" is the current count times 1.25, rounded up to 50, for modules over budget only. `policy/framework.json` is unchanged until the owner decides, so the measured gate shows the overages. One decision can cover these and the 37 packages' template budgets parked above.

  | Module | Budget | At `bf5f5a6` | Now (`61b21965`) | Proposed |
  | --- | ---: | ---: | ---: | ---: |
  | beans | 800 | 2,272 | 2,210 | 2,800 |
  | context | 1,150 | 2,808 | 7,771 | 9,750 |
  | core | 750 | 12,564 | 7,111 | 8,900 |
  | engine-aot | 400 | 5,748 | 685 | 900 |
  | engine-jdbc | 500 | 6,660 | 2,088 | 2,650 |
  | engine-servlet | 2,000 | – | 2,003 | 2,550 |
  | framework-test | 7,800 | – | 6,866 | unchanged |
  | hibernate-validator | 1,050 | 10,189 | 3,516 | 4,400 |
  | jackson-annotations | 150 | 329 | 85 | unchanged |
  | jackson-core | 350 | 5,600 | 1,224 | 1,550 |
  | jackson-databind | 700 | 4,598 | 4,904 | 6,150 |
  | jakarta-annotation | 100 | 293 | 49 | unchanged |
  | jakarta-servlet | 2,150 | – | 2,054 | unchanged |
  | jakarta-validation | 350 | 547 | 906 | 1,150 |
  | java | 3,350 | 7,465 | 6,444 | 8,100 |
  | jdbc | 750 | 2,210 | 8,524 | 10,700 |
  | slf4j-api | 900 | 5,097 | 4,873 | 6,100 |
  | tx | 2,350 | 6,942 | 5,983 | 7,500 |
  | web | 15,650 | – | 13,291 | unchanged |
  | webmvc | 4,100 | – | 4,643 | 5,850 |
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
  - Re-measured at `61b21965` (table above, both columns): core 12,365 → 7,111 and java 7,720 → 6,444 in the official count. Growth from new features since `f51a733`: jakarta-validation 320 → 906, jdbc 7,756 → 8,524 and engine-jdbc 1,742 → 2,088 (`967ea89e`, `7f8365c6`), hibernate-validator 3,340 → 3,516 (`b3e0272c`), webmvc 4,447 → 4,643 (`8d147762`).
  - core, second cut: 6,715 → 6,364 (`fc75c912`), with `decodeUtf8`, `isValidUtf8`, `utf8Length` and `codePointCount` (`edf2df15`, parity-tested against `std.utf`) replacing `std.utf`, and `stripWhite` replacing `std.string.strip`. String to Character now reports malformed UTF-8 as `IllegalArgumentException`, not `UTFException`.
  - jackson-core, second cut (`6e27825f`, asked by third-party-apis): its last Phobos imports, `std.conv` in the location, pointer and unexpected-character text, the throwing `std.utf.decode` under ESCAPE_NON_ASCII and `std.string.strip` in value coercion, go to `decimal`, `decodeUtf8` and `stripWhite`; jackson-core now depends on engine-aot. Official count (own-library-and-probe/2, `measure_builds --framework-sizes`) against `a0fc0954`: 1,226 → 438 template instances (budget 350), and linked bytes 514,480 → 52,144 (budget 131,072): the throwing decode had linked `UTFException` and the `std.format` behind its message. `tests/text_test.d` checks the replaced paths, malformed UTF-8 included; its cases print identically on the old code.
  - The six `HashMap!(FeatureEnum, bool)` instances of the size breakdown are boot's generated `JacksonProperties` maps, Spring Boot's public `Map<Feature, Boolean>`, not jackson code; left to boot (inbox), about 35 KB.
  - `std.uni` stays in core, java and jackson-databind: about 620 instances, for Java's Unicode case rules. A non-template wrapper in engine-aot would pay it once instead of in each module, but would take engine-aot (budget 400, now 685) past its budget, so that is for the owner to decide with the budgets.
  - java and core, third cut (`ab46223d`, approved by framework-core): `flint.engine.aot.host`, a `@safe` `package(flint)` facade with its `@trusted` calls in `flint.engine.aot.sys.environment` and `sys.files`, replaces `std.process` (`Locale.getDefault`, `classPathRoots`, `getSystemEnvironment`, `suppressGetenvAccess`), `std.file` (`File`, `FileInputStream`) and `std.path` (`getAbsolutePath`). Official count (own-library-and-probe/2, `measure_builds --framework-sizes`), before at `81adeabb`, after at `ab46223d`: java 6,590 → 5,749 template instances and 624,744 → 162,024 linked bytes (`std.file` had linked `std.datetime`); core 6,926 → 6,829 (477,496 → 477,536 bytes); engine-aot 778 → 847 (12,720 → 12,872 bytes), the facade's cost. Behaviour kept from Phobos except three points, each closer to Java: `getSystemEnvironment` is in the environment's order instead of hash order; an unreadable file gives `FileNotFoundException` "(Permission denied)" instead of D's `FileException`; `getAbsolutePath` returns the path as given when the current directory cannot be read (`std.path` threw).
  - security-crypto after `cea4e861` (BCrypt through engine-security, asked by framework-core): 1,163 template instances (budget 1,200) and 37,576 linked bytes (budget 622,592), so no split is needed.
  - Next: context and beans (mostly instances of core and java templates); then the budget reset of owner decision 3.
- 2026-11-23, size-levers: linked-bytes budgets were set with probes that printed through `writeln` in both the fixture and the baseline. The Phobos `std.format` code that `writeln` links was then part of the baseline, and the size delta hid the Phobos code each module pulls in itself. With the probes printing through C (`a67dfeb`, `55f6747`), the delta shows it, and most modules now exceed their budgets without any code growth (`f51a733`). Raising them is the owner's decision. The template diet lowers them as it removes Phobos: engine-aot fell from 61,744 to 12,720 bytes once `std.conv` was gone. The earlier tx entry is answered: measured with today's tools, tx at `00b2749` already linked 231,720 bytes, so its overage came from the tooling, not from tx code.

  | Module | Budget | Linked now (`61b21965`) | Over |
  | --- | ---: | ---: | --- |
  | beans | 573,440 | 814,832 | yes |
  | context | 966,656 | 1,269,960 | yes |
  | core | 81,920 | 477,456 | yes |
  | engine-aot | 81,920 | 12,720 |  |
  | engine-jdbc | 7,094,272 | 6,048,568 |  |
  | engine-servlet | 282,624 | 612,296 | yes |
  | framework-test | 1,552,384 | 1,865,288 | yes |
  | hibernate-validator | 442,368 | 738,224 | yes |
  | jackson-annotations | 4,096 | 0 |  |
  | jackson-core | 131,072 | 510,384 | yes |
  | jackson-databind | 557,056 | 939,280 | yes |
  | jakarta-annotation | 4,096 | 0 |  |
  | jakarta-servlet | 98,304 | 493,928 | yes |
  | jakarta-validation | 81,920 | 473,120 | yes |
  | java | 344,064 | 624,704 | yes |
  | jdbc | 475,136 | 771,136 | yes |
  | slf4j-api | 475,136 | 744,232 | yes |
  | tx | 229,376 | 584,240 | yes |
  | web | 126,976 | 565,200 | yes |
  | webmvc | 1,359,872 | 1,694,400 | yes |
- 2026-11-23, size-levers (asked by the coordinator): where gs-rest-service's Oz binary goes, against Go's about 6.6 MB. Built at `0d50d1fc` with `flint build --profile size` (LDC, `-Oz`, thin LTO, `-fno-moduleinfo-localclasses`; flint passes the profile through `DFLAGS`, so every library gets it, and LDC links with `--gc-sections`). Attributed with the new `tools/binary_breakdown.py` (symbol sizes by D package and by the static C library defining them; `.eh_frame` by the function each entry covers).
  - **Measurement: 3.49 MB.** The executable is 11,730,840 bytes as built and 8,237,064 after `strip --strip-all`: `.symtab` and `.strtab` hold 3.49 MB. Go's comparator is built with `-ldflags=-s -w`, but `spring_builds.measure_flint` records the unstripped file, though its docstring promises the stripped one. Stripped, the ratio is about 1.25, not 1.78. Sent to proof-harness, who owns the file; fixed in 682f7cd0, which strips both sides with the same GNU strip (certified Oz ratio 1.245).
  - **OpenSSL, 3.27 MB with its unwind tables, in a plain-HTTP app.** libcrypto has 2,680,531 bytes of symbols and libssl 280,724, plus 305,372 of `.eh_frame`. The ADR-031 TLS-only build is in use. They link because engine-web's server decides at run time whether to create the TLS transport (`runtime.d:514`, `hasTls(options)`), so the linker keeps `TlsDriver`, the `flint_tls_*` shim and everything OpenSSL reaches from it. `transport.d`'s template-class trick can't drop it while that branch exists. A link-time choice (the server's TLS factory registered only by apps that compose TLS, Spring Boot's `server.ssl.*` included) would put the binary at about 4.9 MB, below Go, whose net/http always links crypto/tls. That is web-http's and boot's design call. nghttp2 (125,581 bytes plus 17,672 of unwind tables) is the same case for HTTP/2.
  - **Inside OpenSSL:** `ossl_aes_gcm_{en,de}crypt_avx512` are 675,280 bytes and `ecp_nistz256_precomputed` 151,552. Dropping the AVX-512 VAES GCM path keeps the TLS profile but changes AES-GCM throughput on AVX-512 machines. It is an ADR-031 option that needs a TLS timing run, so it is not taken.
  - **Unwind tables for C code: about 340 KB** (`.eh_frame` libcrypto 265,968, libssl 39,404, nghttp2 17,672, and the rest). D code needs its 435,480 for exceptions. The C providers could be built with `-fno-asynchronous-unwind-tables`, which leaves OpenSSL's perlasm CFI in place. No D exception crosses a C frame, since engine callbacks are `nothrow`, but a crash backtrace through C frames would get shorter. native_build is m7-flint-cli's call.
  - **D, 3,068,588 bytes.** The rows overlap: the code rows include their own vtables and ClassInfos, and the last row totals them across packages.

    | Area | Bytes | Owner, lever |
    | --- | ---: | --- |
    | `flint.java.util` collections | 502,437 | framework-core: 250 per-type copies (HashMap 14, HashSet 21, AbstractCollection 28 instantiations, ...). Sharing one implementation for class element types and making `stream()` lazy (data-access counts 828 `_d_newclassT` instances from `java/util` alone) |
    | druntime per-type helpers (`core.internal`) | 493,863 | follows the type count: `_d_arraycatnTX` 67 instances, associative arrays (`newaa`) about 120 KB, `_d_isbaseof2` 109 |
    | `std.format` and `std.conv` | 210,831 | the app's own `format(template_, name)` (flint:java has no `String.format` yet: framework-core, then proof-harness's port); about 30 boot functions (yaml, property binding, logging, uptime); web's `SimpleConversion`, `parseJavaDouble`/`parseJavaLong`, `Cookie.getMaxAge`/`setMaxAge`, `HandlerExecutionChain.toString`; jackson-core's `TokenStreamLocation.offsetDescription` and `UTF8StreamJsonParser.unexpected`. All of them must go before `std.format` drops out |
    | TypeInfo, vtables, ClassInfo | 541,880 | 901 ClassInfos, mostly the collection copies. `-fno-moduleinfo-localclasses` works: unreferenced classes are gone |

  - **Whole modules that link but go unused** are small: boot actuator and validation together are 25,645 bytes. The AOT tables (`flint_aot`) are 51,772.
  - Sent to owners: proof-harness (stripping), web-http and boot (TLS and HTTP/2 at link time; their `std.format`/`std.conv` callers), framework-core (collections; `String.format`), third-party-apis (jackson-core's two callers; six `HashMap!(FeatureEnum, bool)` at 5.8 KB each, where an `EnumSet` or bit set would do), m7-flint-cli (unwind tables for C providers).
- 2026-11-23, framework-core: context's template count grew with org.springframework.validation (`832723b`), from 2,808 to 6,155 instances (own-library-and-probe/2, stock DMD 2.114). That is past `template_ratio_max` 1.1 against the base, and past size-levers' proposed 3,550. The growth is mostly druntime hooks (`new`, `~`) that scale with code size, plus `List!ObjectError` and `List!FieldError`, which the Spring API requires. I already removed about 4,400 instances by avoiding std.format in `valueOf` and std.algorithm. Linked bytes are 775,168 (+1.1%), within budget. A new context budget is the owner's decision; nothing was raised.
- 2026-11-23, m7-flint-cli (asked by web-http; item 22): before quality.py lints framework/ and boot/, ported Spring functions exceed D-Scanner's cyclomatic complexity limit of 20 (12 in web-http's packages, 21 to 48: UriComponentsBuilder, PathPatternParser, MimeTypeUtils, RequestMappingInfo matching, request-value conversion, the JsonPath helper). They keep upstream's structure, so later diffs against Spring stay readable. Exempting them raises a cap, which is the owner's call. Options: (a) exempt the Spring API layer from cyclomatic_complexity in dscanner.ini, on port fidelity (ADR-030 section 7); (b) a per-function allowlist with the upstream source of each function; (c) split them, a slower job that drifts from upstream. Until it is decided, framework/ and boot/ stay out of quality.py's lint trees, and nothing changes for the trees it lints.
- 2026-11-23, framework-core (item 24): petclinic-rest's secured mode verifies BCrypt hashes (`$2a$10$` in data.sql, `BCryptPasswordEncoder`). AGENTS.md forbids a new cryptographic implementation, and engine-security wraps only Argon2id, so this needs a pinned native provider. Candidates: Openwall's crypt_blowfish (public domain; used by PHP and libxcrypt), or libxcrypt (LGPL-2.1). Choosing and pinning it is the owner's call (with m7-flint-cli for platform.lock). Until then, `BCryptPasswordEncoder.matches` reports unsupported and the secured-mode tests use a `{noop}` encoder.
- 2026-11-23, third-party-apis (runtime investigation, gs-rest-service; profile on busy venus, LDC release, server on CPUs 2-3, oha 4 threads / 64 connections on 4-7; indicative, not evidence; re-measure through the queue):
  - **The servlet engine serves on one reactor thread.** `ServletEngineOptions.cores` defaults to 1 and Boot never sets it, so the server used 1.00 core of the 2 it was given. With `cores = 2` (a local experiment, not committed): 113-144k req/s against 69-75k, p50 0.42-0.46 ms against 0.82-0.88 ms, with the same ~14 µs of CPU per request. Go would be at 9-11 µs per request with both cores busy (155-226k req/s), so the remaining gap is CPU per request. The default and its property (Tomcat's thread pool spans the CPUs) belong to web-http (engine-servlet) and boot (web-server auto-configuration).
  - **Where the CPU goes** (user-space cycles, Jackson fix applied): GC 39% (allocation and collection), D code 45%, libc 14%. By innermost framework layer: servlet adapter 29% (19 points GC), fibers and scheduling 22%, message converters and content negotiation 21% (10 GC), dispatch 14% (6 GC), Jackson 7% (1 GC), HTTP engine 4%, argument resolution 1%. Exceptions: none on this path.
  - **Allocation sites** (share of user CPU spent in GC under each): `ServletEngineRequest.setAttribute` 4.8% (an associative array per request); `PathContainer.parsePath` 4.4% and `splitSegments` 4.2%; `Matched!` 3.4%; Accept and media-type parsing about 9% (`parseMediaTypes`, `MimeTypeUtils.tokenizeList`, `parseMimeTypes`, `resolveMediaTypes`, `MimeType.appendTo`, `determineCompatibleMediaTypes`, and a `ContentNegotiationManager` built per request); `getHeaders` 2.2%; `ServletEngine.capture` 2.6%; response `fields` 1.0%. Engine memory is meant to stay in the arena (ADR-030 section 4); these are framework allocations per request.
  - **Syscalls per request** (strace, 20,000 requests): one `recvfrom`, one `sendto`, two `epoll_ctl` (re-arming; Go's edge-triggered epoll needs none), plus about one `mmap`/`mprotect`/`madvise` per 17 requests (fiber stacks).
  - **Fixed here, Jackson** (`9aacecc`): the generator's zeroed 8000-byte buffer, a builder and a sink closure per write, and a simple-name computation per property. Jackson went from 14.5% to 6.8% of user CPU (GC 8.2 to 0.8 points); 63.7k to 70.2k req/s in one paired run. Then `JacksonJsonHttpMessageConverter.writeInternal` copied the JSON twice (`writeValueAsString`, then a cast to bytes). web-http's `b7c8891d` writes `writeValueAsBytes`'s buffer itself, without a copy: 78.5k to 77.1k instructions per request.
  - Sent with numbers to web-http, boot, framework-core and flint-aot.
  - **Later, Jackson per write** (LDC release, Greeting `{"id":1,"content":"Hello, World!"}`, `ObjectMapper.writeValueAsBytes`, busy venus, indicative): `dfb2996d` cut GC bytes from 736 to 576 per write (the first buffer fits its size class; the generator back in the 128-byte class) and about 265 to 252 ns (short pieces copied inline instead of `_d_array_slice_copy`). The two write contexts (96 bytes each) remain. `cab192b6` removed the monitor `MapperConfig.bean()` took on every lookup, which every reactor thread contended on (web-http's finding); Hibernate's `PatternCache` likewise. **Zero per write (2026-11-23):** `JsonFactory` recycles generators (buffer and context chain included) through a 16-slot compare-and-swap pool, as Jackson's `BoundedPool` recycles `BufferRecycler`s; the factory owns it because framework packages keep no thread-local state. A recycled generator clears its contexts' values, so it holds no request object. Greeting through `ObjectMapper.writeValue(OutputSink, Any)`: 576 GC bytes in 4 allocations → 0. `writeValueAsBytes` allocates only its result (48 bytes). The converter's switch to `writeValue(&outputMessage.writeBody, value)` is web-http's `27e8d10b`. **Reads (2026-11-23):** parsers are recycled the same way, property names are interned in a factory-owned 1024-slot table (Jackson's symbol canonicalizer; a name that finds no slot within eight probes is copied instead, so hostile names cannot grow it), escaped text decodes in a reused scratch buffer, and `readStructured` no longer creates a bean it then discards. petclinic-rest's `@RequestBody` DTOs, GC bytes per read: OwnerFieldsDto 1,152 → 176 (the DTO and its five strings, nothing else), PetFieldsDto 1,216 → 272, VisitFieldsDto 768 → 144. What remains of the engine's is engine-aot's `Any` box for `LocalDate`/`Nullable!int` and the date text java.time parses (framework-core: inline small structs; slice overloads of the parsers). **After both (2026-11-23):** dates parse from the body (`1ee6ac1d`, `c0aafbbf`: Pet 256, Visit 128) and `Any` holds small structs inline (`46d21e28`), so PetFieldsDto reads in 128 bytes and VisitFieldsDto in 64 (LDC release, local). Each read allocates only what it hands to user code: the DTOs and their strings. The write-only factory went from 8,520 to 336 bytes when the name table moved to the first read (`5ca4c5bc`).
- 2026-11-23, dmd-arm64 (assigned by the coordinator; the base DMD patch's owner, compile performance, had not answered for 2 hours, so the 30-minute rule applies): item 23's compile-server half, the platform prelude in `flintserver.d` behind `FLINT_DMD_SERVER_PRELUDE=<file>`, is built by dmd-arm64 in the base patch. m7-flint-cli wires the flint side. Its own commits; the owner may rework it.
- 2026-11-23, dmd-arm64 (item 23, compile-server half): the platform prelude was prototyped and is **not landed**, because it does not pay. gs-rest-service's cached cold build on venus at `7a10718c` is 0.93 s:
  - `flint` before DUB about 0.2 s, of which AOT generation 90 ms; DUB's plan 12 ms;
  - compile 448 ms on the critical path, the generated `flint_aot.flint.boot.jackson.autoconfigure` (the next job takes 215 ms);
  - link 150 ms (mold).
  - That compile, in-process: 523 ms, of which code generation 233 ms for a **17 MB object from a 438-line generated module** (9.6 MB without `-g`; `-g` costs 31 ms, `-allinst` 60 ms). Semantic analysis is 300 ms, mostly semantic3 of template instances.
  - Served from a prelude of the 259 platform modules it is 217 ms, but the link fails. The platform archives lack instances that only the app's generated code needs, such as `Stream!(JsonReadFeature).ofArray`, which `libflint_boot-jackson.a` references 64 times but never defines. The preloaded instances belong to non-root modules, so the served compile skips them.
  - Moving those instances into the root module, as an `-allinst` import does, makes the compile correct but 510 ms, a 13 ms gain, and the object still differs from the in-process one by 14 symbols.
  - The existing toolchain-only server has the same flaw on a smaller scale: its objects lack 9 druntime instances, which link only because druntime provides them.
  - The levers are the template instances the AOT-generated code pulls in (flint-aot, item 21's template diet), splitting the largest generated module across compile jobs, and the link. The prototype is on the work repo's `prelude-experiment` branch. `FLINT_DMD_SERVER_PRELUDE` stays harmless: the fork ignores it.
- 2026-11-23, dmd-arm64 (item 23; the coordinator approved it on conditions after 2670d5be): the compile server's platform prelude **lands for dev edit builds**. This reverses 9f1a1d8b's "not landed" for edit builds. That finding measured the cold critical path, an `-allinst` generated platform module, which the prelude cannot help. On the edit build, the one project compile is mostly semantic analysis of the platform.
  - **gs-rest-service at e422e636 on venus, load about 1, PGO fork:** edit build 0.44 s → 0.36 s (3 trials each); cold 0.98 → 0.95 s. The project compile alone takes 178 ms in-process, 125 ms with the toolchain-only server and 63 ms with the platform prelude.
  - **Edit-build breakdown with the prelude (0.37 s):** flint before DUB 13 ms, `dub describe` 41 ms, DUB planning 22 ms, compile 60 ms, link 131 ms (mold 127 ms), flint after DUB about 87 ms.
  - **Cold-build breakdown (0.96 s):** flint before DUB about 200 ms, of which AOT extraction is 57 ms and `dub describe` 40 ms. The compile critical path is 454 ms: the generated platform library's `flint_aot.flint.boot.jackson.autoconfigure`, rebuilt because a cold trial clears `.flint`. Link 144 ms; flint after DUB about 115 ms.
  - **Conditions:**
    - Dev profile only: m7-flint-cli's 4bd8c690 passes `FLINT_DMD_SERVER_PRELUDE` to dev-profile, non-test builds that link the platform cache. Release and size use LDC, and `--no-platform-cache` builds get no prelude.
    - Correctness: gs-rest-service (18 of 18), gs-relational-data-access (1 of 1) and petclinic-rest (109 of 109, PostgreSQL) pass the same acceptance cases from an in-process build, a served cold build and a served edit build. Every edit build's project compile was served (`FLINT_DMD_SERVER_TRACE`: 1 compiled, 0 refused). The 36 boot and framework packages pass `dub test --force` with the fork.
    - Run through the pause wrapper.
  - **Missing instances fail loudly.** A served compile leaves an instance out of its object only when DMD assumes another object emits it. The reference is then a strong undefined symbol, which the link rejects with an undefined-symbol error (FLINT-E0701). It cannot resolve to anything else: the mangled name fixes the template and its arguments, and a dev build compiles every module with the same flags.
  - **The two rules that keep a served compile's objects as an in-process compile's:**
    - `-allinst` compiles keep the toolchain-only server.
    - `needsCodegen` ignores instantiations by preloaded modules the request does not import.
    - The regression test for the second rule links a served object on its own. Without the rule, that link fails with `undefined symbol: …twice!int`.
  - **Not covered yet:** Windows' worker pool does not read the prelude. macOS builds it (type-checked), but it has not been measured on pluto. Packages DUB splits into chunks compile with `-allinst`, so a large project package gains nothing until `-allinst` is supported.
- 2026-11-23, coordinator (build benchmark, cold trials): cold trials keep wiping all of `.flint`, including `digests.log`. What a trial wipes is part of the workload, which only the owner can change. Platform and toolchain state moves into `FLINT_CACHE` instead, which cold trials already keep, as Go keeps a primed `GOCACHE`:
  - Entries in `FLINT_CACHE` are content-addressed and are trusted by name, not re-hashed. A missing or altered entry is a miss or a loud failure, never used.
  - Toolchain and `flint` binaries are keyed by the toolchain receipt's digest plus each file's stat identity (device, inode, size, mtime and ctime).
  - Project files are always hashed on a cold build.
  - The build benchmark's description records this.
  - Context: gs-builds at `2018e5e5` (`65d17a19`) has the shared-object edit build at 0.758 of Go, primary 2.52 and secondary 1.06. m7-flint-cli's cold-path steps, all approved: the platform description in `FLINT_CACHE`, then no app-side `dub describe`; `bf7b7b97` already took the edit build's plan step to 0. flint-aot is asked to serve the app's AOT extraction from the platform prelude (about 65 ms on cold builds).
- 2026-11-23, coordinator (supersedes the cold-trial entry at `f35a12b3`): proof-harness's `1235dc4b` is confirmed. Cached cold trials keep `digests.log` in `FLINT_CACHE`, with the port's entries pruned.
  - **Why it holds:** the log already lives in `FLINT_CACHE`, and its retained entries cover only the toolchain, `flint` and the platform sources. That is platform cache state, inside ADR-030 section 5's definition ("platform cache vs std-primed GOCACHE"), so it is not a workload change.
  - **Conditions before the primary gates:**
    1. Every project-keyed entry is pruned or excluded for each cold trial, not only the log's port entries: AOT models and generated output (kept by project root since `7907be4e`), objects, and anything else the port owns. The harness fails a cold trial that gets a project-keyed hit. The `2018e5e5` primary (2.52) reused the port's AOT output ("23 from the shared cache, 0 extracted") and is optimistic. Its incremental and edit series are unaffected.
    2. m7-flint-cli adds a test: an edited platform or toolchain file is re-hashed despite an unchanged size and a restored mtime (ctime and inode in the stat key).
    3. Every run keeps publishing the non-gating "primary with the digest log cleared".
- 2026-11-23, owner (via the coordinator; answers gc.md option D's two owner questions): **the Flint collector is approved as proposed.** data-access builds it now, in parallel with the allocation cuts. It does not wait for them.
  - **Home:** `flint.arena.sys.gc`, an allowlisted low-level `sys/` directory of the existing `flint:arena` package. No new package; the 37-package surface is unchanged.
    - The collector's `@system` code stays inside that directory.
    - Any `@trusted` entry point follows AGENTS.md: an adjacent `// SAFETY:` comment, at most 60 lines, and positive, negative and sanitizer or fuzz coverage.
  - **Sources:** druntime's collector, under Boost-1.0, and bdwgc's soft-dirty tracking (`SOFT_VDB`), under its MIT-style licence.
    - Both get entries in `policy/upstream-licences.json` before any ported code lands.
    - Ported files carry the upstream path, tag and copyright, with "Modified by the Flint authors".
    - NOTICE gains both attributions.
  - **Gating:** each step (D1 per-thread caches with page release, then D3 if the pause still loses) is measured through proof-harness's queue against druntime's collector on the same binary, before any claim.
    - Correctness evidence: druntime's GC tests, a stress fuzzer with a shadow reachability check, ASan and TSan.
    - It is switchable back to the conservative collector through `rt_options`.
- 2026-11-23, owner (via the coordinator; m7-flint-cli's static edit-build breakdown): **measured Flint builds match the registered Go comparator's flags.**
  - Go is built with `-ldflags=-s -w` (no symbol table, no DWARF). The Flint builds that gate against it are therefore built without debug information, and their link drops the symbol table as `-s` does. This covers the cached cold build, the incremental build, the static edit build and scratch. The platform archives they link are the no-debug variant, with the debug setting in the platform cache key.
  - The same series with debug information (today's dev default) is published in every run as non-gating context, as the cleared-digest-log series already is.
  - Developers' own `flint build` default is unchanged. The measured command selects the profile explicitly and says so in `flint-spring.json`'s `measure` block and in the benchmark description.
  - Measurements up to now carried debug information. They stay as recorded and are not rewritten.
- 2026-11-23, owner (via the coordinator): **per-request allocations get a budget gate, like template budgets.** Ported Java idioms that allocate on every request are the main cause of the p99 and RSS gap. Examples are media types parsed per request, an attribute map per request, and path parsing (gc.md: about 40 allocations and 4.8 KB per /greeting). The HTTP engine itself already beats Go.
  - **What is measured:** each Phase 1 app's endpoints (2xx, 404 and validation-error paths) are served through the real servlet path after warm-up. GC allocations and bytes are counted per request.
  - **Budgets:** stored in `policy/request-allocations.json`. Each starts at the measured count ×1.25, rounded up, and only goes down; the structural gate refuses raises.
  - **Failure output:** the gate names the top call sites.
  - **Where it runs:** deterministic, in `dub test` and CI on DMD and LDC.
  - **Owner:** data-access, with proof-harness for the app fixtures. Work-queue item 28 in coordination.md.
- 2026-11-23, proof-harness: **FLINT_LINK_THREADS=8 beats the default 4 for gs-rest-service's static dev edit build** (queue entry `link-threads-ab`, m7-flint-cli's A/B approved by the coordinator, 19:17Z, a claimed window with no foreign build). Setup: gs-rest-service at `36c29248` with mold, 15 edit builds per arm, the arms alternating within each trial (`tools/spring_link_ab.py`). The difference of medians (8 minus 4), with a bootstrap 99% interval:
  - static edit build, link phase: 174 → 136 ms, −38 ms (−42 to −30), which excludes zero;
  - static edit build, total (phases_ms.total): 312 → 274 ms, −38 ms (−46 to −26), which excludes zero;
  - shared-object edit build, link: 16 → 14 ms, −2 ms (−4 to +3), and total 60 → 60 ms, 0 (−4 to +3); neither excludes zero.

  By m7's rule (change the default only if the interval excludes zero), 8 qualifies for static dev links. The shared-object dev build is indifferent. Evidence: `benchmarks/spring/evidence/link-threads-ab/`.
- 2026-11-23, owner (via the coordinator): **Phase 2 waits for the Phase 1 exit.** The plan's stop rule stands. No Phase 2 module starts, not even ones off the request path, until Phase 1's runtime metrics beat Go or the agreed fallback is in place.
  - The runtime fix (allocation cuts, the allocation gate, the collector) is foundational, and every module that serves requests would inherit it.
  - Coordinator assignment, same day: framework-core takes the media-type and path parsing in the web and webmvc packages, formerly web-mvc's area; web-mvc is stopped (out of context). web-http keeps the servlet adapter.
- 2026-11-23, coordinator: **runtime first.** The runtime metrics are the only thing between Phase 1 and its exit (gs-rest-multicore-3: throughput 0.801, p50 1.83, p99 2.27, RSS 1.66, CPU per request 1.46 against Go).
  - **Target:** on gs-rest-service's /greeting, only user code allocates on the GC heap (the Greeting and its string). Engine and framework memory goes to the request arena or reused buffers (ADR-030 §4). Flint's own HTTP engine already beats Go (1.68× throughput); the gap is the Spring layer's allocations and the GC pauses they cause.
  - **Owners:**
    - data-access leads, with the allocation gate (item 28) and per-site targets in gc.md;
    - web-http: servlet adapter;
    - framework-core: media types and path parsing;
    - flint-aot: generated dispatch and argument resolution;
    - third-party-apis: Jackson reads and writes.
  - **Collector:** D3 (mostly-concurrent marking) is prototyped now, in parallel, because p99 is the metric least likely to fall to allocation cuts alone.
  - **Measurement:** runtime runs claim windows ahead of build-time runs once the current gs-builds finishes. A gs-rest-multicore re-measure follows each roughly 25% drop in allocations per request.
- 2026-11-23, owner (via the coordinator; data-access's RSS breakdown, gc.md §1.4): **measure a static release build before deciding how the measured apps link.**
  - **Background:** the Go comparator is a fully static binary (CGO off). Flint's release apps link libc and other libraries dynamically, and their shared text is about 1.75 MB of resident memory.
  - **The comparison run:** proof-harness runs a non-gating, side-by-side comparison of gs-rest-service's release build, static against dynamic. It measures peak RSS, throughput, p99 and CPU per request in one claimed window, plus stripped O3 and Oz sizes against Go.
  - **The decision rule:** switch the measured release profile to static only if the Oz size still passes against Go and no runtime metric gets worse beyond its interval. Size and runtime then use the same static release build, and the dynamic series stays published as context, as with `--no-debug` (`4b27d207`). Earlier results stay as recorded.
- 2026-11-23, fast-path spike (coordinator's task): **a per-endpoint, build-time-specialised request path is prototyped and recommended, staged** (`docs/spring/phase1/fast-path.md`, branch `spring/fast-path-proto`, not on main).
  - **How it works.** Flint AOT emits `fast_<id>` for simple mappings behind the prototype switch `FLINT_AOT_FAST_PATH=1`, which is part of the AOT output key. `FastPathTable` proves each route against the configured strategies at startup. The servlet container offers requests before it builds servlet objects.
  - **Allocations.** gs-rest-service `/greeting` drops from 16 to 1 GC allocation per request at `eaa27d1d`: the user's `String.format` result only. 18/18 exact with the fast path on and off.
  - **CPU.** 71.1k → 43.2k instructions per request.
  - **Local load.** Throughput about 1.4× and CPU per request about 0.73× against main, with RSS unchanged.
  - **Pay-for-use (the coordinator's merge condition).** Two beans Flint AOT generates only when an endpoint qualifies bring in the table (a `WebMvcConfigurer`) and the container's offer (a `WebServerFactoryCustomizer` calling `FlintServletWebServerFactory.setFastOffer`, boot's agreed Flint addition). Stripped gs-rest-service: on is +22,664 B. Off keeps about 1.1 KB of interface residue (type info and cast helpers), +744 B net against main at `e77bc654`.
  - **Reviews.** web-http (after its return-value-handler fix), flint-aot and framework-core approved. boot agreed `setFastOffer`. The A/B is fast-path-ab in proof-harness's queue (9fbbcb07).
  - **Landed default-on** (owner decision `7206d97d`): every build emits it for qualifying endpoints, and `FLINT_AOT_FAST_PATH=0` opts out. Next: petclinic-rest's shapes (fast-path.md §9.1) with web-http, boot and framework-core.
  - **petclinic-rest.** At the spike's measurement its request cost 1,655 allocations, almost all data path (about +2–5% from the fast path). After data-access's cuts it costs 360 (`0017b3f3`), so the skippable framework layer is about 19%. Estimate after shapes S1–S4: capacity +8–15% (fast-path.md §9.1).
- 2026-11-23, owner (via the coordinator): **the two top priorities are the per-endpoint fast-path spike and petclinic-rest's cold build.**
  - Together they decide most of the mission risk.
    - The fast path is the main lever for gs-rest-service's throughput, CPU, p99 and RSS against Go.
    - petclinic's cold build is the largest build gap: 4.18× Go with Go's dependencies primed (e96671ce); AOT 760 ms plus compile 454 ms, 77% of it petclinic's own code.
  - **Fast path.** fast-path-spike reaches a go/no-go quickly. Owners whose files it touches review within 30 minutes: flint-aot, web-http, third-party-apis, framework-core. proof-harness gives its A/B the first measurement window once it's ready. On go, extend it to petclinic-rest's endpoints.
  - **petclinic cold build.**
    - flint-aot lands the describer memoization first.
    - m7-flint-cli puts petclinic's cold compile and edit build ahead of the musl work: per-module compile, parallel jobs, serving the project's dependencies from the prelude.
    - framework-core and size-levers cut what petclinic's code instantiates, in its templated user-facing APIs and the generated modules.
    - size-levers' L1 shrinks the link.
  - Other work continues behind these two.
- 2026-11-23, owner (via the coordinator): **compiler-fork features that serve the mission are approved.** That covers the DMD fork (and, if needed, the LDC fork) gaining tooling and code-generation capabilities.
  - **Approved now:**
    - a native AOT extraction mode, -flint-aot-extract, served over the platform prelude (design 3A);
    - compile-server changes for per-module compilation, including the -allinst/prelude fix if the experiment shows it's needed (design 3B);
    - runtime-library build flags such as -fno-moduleinfo-localclasses.
  - **The boundary:** these features must not change the D language. That means no new syntax, no changed semantics of valid D programs, and no compiler-inserted write barriers. Changing the language stays owner-only (coordination.md, rule 5).
  - **The evidence standard:** every such feature must produce output identical to the existing path (playbook B-7). A served or native result must match the in-process or CTFE result byte for byte, and missing instances fail loudly (FLINT-E0701). It keeps the unforked fallback, and has regression tests in the fork.
- 2026-11-23, proof-harness: **The per-endpoint AOT fast path passes its gate. With it on, gs-rest-service beats Go on throughput and p99** (queue entry `fast-path-ab`, fast-path-spike's A/B, owner priority `74a746d1`, 22:17–22:44Z, a claimed window with no foreign build in 144 samples).
  - **Setup:** branch `spring/fast-path-proto` at `139e4fc4`, with the tree's own flint and `flint build --profile release --no-debug`. Arm off is as built. Arm on adds `FLINT_AOT_FAST_PATH=1`, and its generated module contains `fast_com_example_restservice_GreetingController_greeting` (checked). Both arms pass 18/18 exact.
  - **Workload:** the Spring workload unchanged, with Go interleaved (Go, off, on / on, off, Go), 4 trials per arm (`tools/spring_binary_ab.py`).
  - Ratios of medians, with bootstrap 99% intervals; they are wide at 4 trials:

    | | throughput | p50 | p99 | p999 | peak RSS | CPU per request |
    | --- | --- | --- | --- | --- | --- | --- |
    | on / off | **1.394 (1.379–1.401)** | 0.639 (0.574–0.865) | **0.507 (0.366–0.672)** | 0.608 | 0.999 (0.986–1.014) | **0.659 (0.603–0.868)** |
    | off / Go | 0.927 | 1.589 | 1.437 | 1.802 | 1.451 | 1.278 |
    | on / Go | **1.293 (1.285–1.299)** | 1.016 (0.961–1.329) | **0.729 (0.548–0.934)** | 1.095 | 1.450 | 0.843 (0.783–1.061) |

    Medians: on 319k req/s and p99 0.198 ms; off 229k and 0.390 ms; Go 247k and 0.272 ms. Peak RSS: 19.9 MB both, against Go's 13.7 MB.
  - **Decision rule (fast-path.md section 9):** on beats off on throughput, CPU per request and p99 beyond the intervals, no metric is worse, and both arms pass 18/18. So the mechanism lands opt-in, then default on. Against Go, the on arm wins throughput and p99 beyond their intervals. p50 is at parity and CPU per request is ahead at the median, though its interval reaches 1.06. Peak RSS (1.45) remains the gap.
  - Evidence: `benchmarks/spring/evidence/fast-path-ab/`.
- 2026-11-23, owner (via the coordinator): **the AOT fast path is the default way Flint runs, for everything.** This follows the certified fast-path-ab (6b7125e2): on against off, throughput 1.394, p99 0.507, CPU 0.659; on against Go, throughput 1.293 and p99 0.729.
  - **Default on.** Every endpoint that qualifies gets a generated direct handler by default, with no flag. The generic Spring path is the fallback for whatever doesn't qualify.
  - **The rules don't change:** responses stay byte-identical to Spring's, the fall-back rules in fast-path.md §3–4 apply, and it stays pay-for-use. An opt-out setting stays available for diagnosis.
  - **"For everything" is the direction for every module.**
    - Phase 1 extends the qualifying shapes so petclinic-rest's endpoints use it: path variables, ResponseEntity, @CrossOrigin, static security headers.
    - Later modules (Security, Data repositories, JPA, Thymeleaf and others) design a build-time, generated direct path from the start, with the Spring-shaped objects materialised only when asked for. This becomes a performance-playbook rule.
  - Certified measurements use the default, so the fast path is part of every Flint/Go result from now on.
- 2026-11-24, proof-harness: **gc-pools-ab, druntime collector settings on gs-rest-service** (data-access's A/B, the coordinator's three-arm design of 22:10Z). Queue entry `gc-pools-ab`, 23:48–00:15Z, a claimed window with no foreign build in 143 samples.
  - **Setup:** `b520e07a`, the same binary under three `--DRT-gcopt` settings, no Go (`--no-go`, mode "ab"), 4 trials per arm on the Spring workload. Every arm passes 18/18.
  - **Results:** ratios of medians against conservative (druntime's default), with bootstrap 99% intervals. They are wide at 4 trials (`ratios-vs-conservative.json` beside the evidence).

    | arm | throughput | p50 | p99 | peak RSS | CPU per request | median max pause |
    | --- | --- | --- | --- | --- | --- | --- |
    | conservative | 228.5k req/s | 0.103 ms | 0.390 ms | 19.7 MB | 11.2 µs | 13.5 ms |
    | `parallel:1` | 1.005 (0.993–1.015) | 0.904 | 0.809 (0.726–1.068) | 0.993 (0.982–1.007) | 0.896 (0.799–1.164) | 4.0 ms |
    | `parallel:1 minPoolSize:4 incPoolSize:0` | **0.979 (0.970–0.993)** | 0.866 | 0.823 (0.710–1.052) | **0.775 (0.764–0.788)** | 0.855 (0.766–1.052) | 3.5 ms |

  - **The rule** (lowest p99 and RSS with no throughput or CPU loss beyond its interval) **picks `parallel:1`.** It loses nothing beyond an interval, and its median max pause falls from 13.5 to 4 ms; its p99 and RSS changes are within their intervals.
  - **`minPoolSize:4 incPoolSize:0` cuts peak RSS by 22% (about 4.4 MB, beyond its interval)** but costs 2.1% of throughput beyond its interval, so the rule excludes it. Accepting that trade is the coordinator's call.
  - Evidence: `benchmarks/spring/evidence/gc-pools-ab/`.
- 2026-11-23, owner (via the coordinator): **docs/spring/phase1/resume-plan.md is approved as written (82601fed), and work resumes on it.**
  - **The order:** integrate; one same-commit baseline B; then one build bottleneck and one runtime bottleneck at a time.
  - **Active team:** dmd-arm64, flint-aot, boot, data-access and proof-harness, plus framework-core for the Any trim only. Every other role stays parked until named for a slice.
  - **Decisions carried with the approval:**
    - small GC pools are deferred until fast-path-pools-ab on the default fast path;
    - static edit builds stay gating;
    - the Spring gate is strengthened so that p50 (at 0.99) and receipt provenance (exact SHA, trial counts and coverage across build, HTTP, error and GC parts) fail closed, with p99.9 reported;
    - runtime metrics apply to the two HTTP apps, with gs-relational-data-access measured on builds, size and acceptance;
    - third-party-apis' next item is chosen from the baseline.
- 2026-11-24, proof-harness: **phase1-builds-petclinic certified at B** (`ca5fbd4a46ed`, the resume plan's baseline, claimed window 02:30–02:37Z). Java, Go and Flint pass 109/109. The build ran in B's private fork tree (DMD `1d521b26`, native extractor present; shared toolchain `7145bb79`), and all 69 extracting builds used the native extractor. Median ratios (99% interval), production, 9 trials:
    - **primary 0.261 (0.244–0.276), which passes**: 512 ms against Go's std-primed 1,963 ms. Against a deps-primed GOCACHE (context) it is 1.72 (1.66–1.77), down from 4.18 at `6ab588f8`. Phases: flint 36, AOT 216, compile 222, link 34 ms;
    - **secondary 1.417 (1.409–1.448), which fails**: 5,744 ms against `go build -a`'s 4,053 ms. This is the first valid scratch build, and 4,953 ms of it is the platform build from source;
    - **edit build, dev profile: 0.645 (0.620–0.656), which passes**: 192 ms against 298 ms (2.08 at `6ab588f8`). Compile 116, link 32 ms;
    - **edit build, fully static: 2.53 (2.48–2.58), which fails**: 755 ms; compile 395, link 313 ms;
    - **Oz: 0.948, which passes**: 10,788,160 against 11,380,728 bytes, stripped (1.070 at `6ab588f8`).
    - Context: digests cleared 622 ms; with debug information, primary 523 ms, static edit 811 ms, scratch 6,346 ms.

    Evidence: `benchmarks/spring/evidence/phase1-builds-petclinic/20261124T023031Z/`.
- 2026-11-23, coordinator: the throughput plan and busy-wait audit by GPT-6.2-Astra High (docs/spring/phase1/throughput-plan-astra.md) is adopted for the runtime slice.
  - **Order:** the first five changes are (1) data-access lands the engine-sql wait fix; (2) proof-harness builds an owner-1 diagnostic separating lease wait, lease hold, SQL drive, row mapping, dispatch and response; (3) web-http builds the internal cross-thread reactor wake; (4) data-access wires ticket-specific lease handoff once (2) confirms the convoy; (5) web-http does gs-rest's single-pass query and header binding.
  - **Reactor ownership:** web-http owns engine-reactor for the wake work.
  - **Design rule (playbook):** a cross-thread wake must not be an ordinary mailbox post, because the mailbox stops being drained when every fiber slot is occupied. It uses reserved per-slot records, a ready bitmap and the owner's eventfd, with a wait-generation handle.
  - **Targets:** throughput lower 99% bound at least 1.30x Go, and CPU per request, p50, p99 and RSS upper bounds at most 0.99x, on each HTTP app.
- 2026-11-24, proof-harness: **phase1-http-gs-rest certified at B** (`ca5fbd4a46ed`, claimed window 02:47–03:27Z, no foreign activity). The Spring workload, production, 9 interleaved trials, against the registered Go comparator; the default fast path, release `--no-debug`, binary `4675a607` (receipt artifact and measured identity agree). Median ratios, Flint / Go (99% interval):
    - **throughput 1.280 (1.272–1.293), which passes** the 1.01 floor (319,300 against 249,500 req/s). It misses the throughput plan's 1.30 lower bound;
    - **p99 0.826 (0.746–0.868), which passes**;
    - **p50 1.140 (1.100–1.261), which fails** (69 against 61 µs). p50 is scored since owner decision 4;
    - **peak RSS 1.418 (1.393–1.453), which fails** (19.6 against 13.9 MB);
    - **CPU per request 0.951 (0.932–1.029), which fails** on its upper bound (7,850 against 8,250 ns);
    - p99.9 0.956 (0.718–1.089), reported only.

    RSS still decides, so fast-path-pools-ab (resume plan order 9) is pending. Evidence: `benchmarks/spring/evidence/phase1-http-gs-rest/20261124T024702Z/`.
- 2026-11-24, owner and coordinator: **execution model kept; two experiments queued after the lease fix.** The owner asked for a "silver bullet". Two independent GPT-6.2-Astra High reviews (`execution-model-astra.md`, `specialization-astra.md`) found none: keep stackful fibers as the general model, widen the default fast path (single-pass binding, shared JSON writers, `ResponseEntity`, errors, security, JDBC row plans), and fix the PostgreSQL CPU gap (Flint about 104 µs per request against Go's 14 µs, a 19.2k req/s cap on its own) together with the lease wake. Owner decision: queue both experiments below. Both run **after** data-access's lease handoff lands (throughput plan change 4), and both are diagnostics, never evidence.
  - **Floor reference (proof-harness; reference handlers from web-http for `/greeting` and data-access for owner 1):** hand-written minimal paths for `/greeting` (atomic counter, query decode, escaping, identical bytes) and for `GET /owners/1` (same pinned libpq, pool of 10, read-only transaction, three queries, identical JSON), run beside the default apps at the same affinity, concurrency and rates. Record application and PostgreSQL CPU separately, lease hold, instructions, syscalls and fixed-rate wake latency. Purpose: how far each app is from an achievable floor.
  - **Direct handler (web-http):** a hand-specialized `/greeting` that runs on the owner loop without a fiber, compared with today's dispatch and with owner-local fiber dispatch, at the same admission limit, response bytes, slow readers and concurrent ordinary handlers. It needs a real task context so `FiberLocal` doesn't fall back to thread-local storage. Count handoffs, runnable delay, touched stack pages and loop lag. Compiler support follows only if it shows a repeatable fixed-rate p50 gain with no p99 starvation; shipping it would need an owner amendment to ADR-030's every-handler-on-a-fiber rule.
  - **Deferred:** general stackless lowering, Loom-style stack copying, batching across requests (it would change the workload) and user-visible request regions.
- 2026-11-24, owner: **every comparator sends the Spring reference's SQL, per request, or the benchmark is invalid.** The Go petclinic comparator's own header promises "the same SQL work per request", but its reads (for example `GET /owners/{id}`, `api.go:105`) run on the plain handle with no transaction, while spring-petclinic-rest's `ClinicServiceImpl` read methods are `@Transactional(readOnly = true)` and Flint follows them. Owner: "it should be the same queries being sent; if they're not, our benchmarks mean nothing."
  - **Ground truth is the Java reference, not either port.** proof-harness runs a statement census (PostgreSQL statement log or `pg_stat_statements`: transaction commands, parse/bind/execute, statement text, rows, connections opened) for every endpoint in the registered workloads, against Java Spring Boot, Flint and Go. Each port must match Java's sequence per request: the same statements, the same transaction boundaries, the same number of round trips where the wire protocol makes them observable. (pgjdbc sends `BEGIN` in the same message as the first query; record what Java actually puts on the wire.)
  - **Fix whichever side diverges.** Where Go differs from Java, the comparator is corrected. Where Flint differs (extra statements, re-prepares, validation queries), Flint is corrected. Neither side is allowed to drop work Java does.
  - **AGENTS.md integrity rule:** a comparator change needs its own ADR and a remeasurement of both sides. proof-harness drafts the ADR with the census as evidence, and the change lands only with it. No certified result changes: phase1-http-petclinic has never been certified (it's blocked), gs-rest-service has no database, and gs-relational-data-access is measured on builds and size only.
  - The same census applies to every future comparator before its first measurement.
- 2026-11-24, proof-harness: **error-404-p99 certified at B** (`ca5fbd4a46ed`, claimed window 03:37–04:37Z, no foreign activity; the error-path workload with the Java context, 9 trials). gs-rest-service GET /nope (404 ProblemDetail), Flint / Go median (99% interval):
    - **p99 5.74 (5.26–6.35), which fails** (684 against 119 µs). The Java context's p99 is 574 µs, so Flint's 404 path is slower than Spring Boot on the JVM;
    - p50 5.57, throughput 0.335 (82,400 against 246,000 req/s), CPU per request 3.56 (32.6 against 9.1 µs), peak RSS 1.45; p99.9 5.08, reported.

    The 404 path costs about 4x the CPU of the /greeting fast path (7.9 µs per request): it goes through the full servlet dispatch, error attributes and problem rendering. Evidence: `benchmarks/spring/evidence/error-404-p99/20261124T033719Z/`.
- 2026-11-24, owner: **ADR-032 accepted, with no exemptions.** The owner asked why the first-insert metadata lookups should be exempt. The coordinator's answer was that there's no strong reason: exempting them saves only a few lines of Go, while an exemption-free rule can't be argued with and stays fair if startup or first-request latency is ever measured. Owner: "Yes." So:
  - **SimpleJdbcInsert's first-insert metadata lookups are matched.** The Go comparator issues the same two catalog queries on its first insert into each table.
  - **Actuator health is matched too.** Each implementation validates its pool the way the reference does (HikariCP's validation on the health check); Flint's missing validation is data-access's.
  - **No exemptions remain** in ADR-032 section 3 or in the check-registry rule. proof-harness sets ADR-032 to accepted, makes the Go change (the reference's read-only transactions, the read/write split for the six writes, the first-insert lookups, the health validation, and nothing beyond Java), re-registers the comparator with a fresh census, and remeasures every petclinic part at one commit, per section 5.
- 2026-11-24, owner: **Java JVM AOT and native-image petclinic join the benchmark as context.** Owner: add "the actual JVM AOT petclinic and the AOT native image of petclinic", to show whether Flint beats the Spring version it ports, not just Go. Go stays the gate; these are context targets reported beside every Phase 1 result: build time, executable or deployable size, start-up to first correct response, throughput, p50, p99, peak RSS and CPU per request.
  - **`java-aot` (new), for all three apps:** Spring AOT processing (`process-aot`, run with `-Dspring.aot.enabled=true`) plus the JDK's ahead-of-time cache (JEP 483/514/515: a training run that writes `-XX:AOTCacheOutput`, then production runs with `-XX:AOTCache`). This needs JDK 25, which Spring Boot 4 supports; use the JDK inside the pinned GraalVM Community 25.0.5, or pin a Temurin 25 JDK in `policy/peer-lock.json` with its checksum. The training run is the benchmark's own warm-up requests, never the measured workload, and its cost is reported as part of build time.
  - **`java-native` for petclinic-rest:** today the image builds but exits at start-up (`NoClassDefFoundError: org.slf4j.MarkerFactory`, the log4j-to-SLF4J bridge). Fix it with build configuration only: native-image arguments such as `--initialize-at-run-time` or `--initialize-at-build-time`, reachability metadata, or a dependency exclusion in the build. Never edit application source. Each change is listed in the README, and the image must pass the black-box suite (109/109) in exact mode before it's measured.
  - **Fairness:** the same CPU pinning, pool size (10), PostgreSQL, workload and warm-up as Go and Flint. The JVM targets get the warm-up the workload already gives them, plus the AOT training run above; no JIT-specific extra warm-up beyond what the manifest defines. `--parallelism=8` for native-image as today. Builds use `measure_queue.py hold` so they never overlap a measuring window.
  - **SQL:** ADR-032's census covers them like any implementation (they run the reference's code, so they should match Java exactly).
- 2026-11-24, owner: **the Java context is captured once, saved, and fair.** Owner: "Those details should just be captured once and saved for our results. Also make sure it's a fair comparison." This refines 096c82ba:
  - **Capture once.** Each Java target (JVM, JVM AOT, native) is measured in one claimed capture per app on the designated runner and saved as a pinned reference record (`benchmarks/spring/evidence/java-context/<app>/<stamp>/`, with raw samples and a receipt). It isn't re-run with every Flint measurement. It's re-captured only when something it depends on changes: the Java app's commit, the JDK, GraalVM, Spring Boot or the Maven dependency lock, the workload manifest, the TLS profile, or the runner's hardware or kernel. The record lists each of these, and the report refuses a stale record.
  - **Fair across time: ratios against an interleaved Go.** Because the capture and later Flint runs happen at different times, the capture interleaves the registered Go comparator in every trial, exactly as Flint's runs do, and stores Java ÷ Go per metric with 99% intervals. Flint ÷ Java is then reported as (Flint ÷ Go) ÷ (Java ÷ Go), each from same-trial measurements, so drift on the runner cancels. The absolute numbers are reported too, with their capture dates.
  - **Fair conditions, all equal to Go and Flint:** the same server CPUs (`taskset`, 2 CPUs; the JVM also gets `-XX:ActiveProcessorCount=2` so its JIT and GC threads size themselves to what it actually has, with all their CPU counted), the same load generator and pinning, the same pool size (10), the same PostgreSQL, TLS profile, workload, warm-up and duration, and the reference's own application settings. JVM flags are only what the reference or Spring Boot ships by default: no heap or GC tuning that Go or Flint don't get, and no extra JIT warm-up beyond the manifest's. The AOT training run uses only the warm-up requests, and its time is part of build time. The native image is GraalVM Community, so no PGO (an Oracle GraalVM feature); that's stated in the record.
  - **Builds:** Java builds run from a pre-populated, offline Maven repository, the analogue of Go's primed GOCACHE, and that's stated. Build time, artifact size (the jar plus the JDK it needs, and the native executable) and start-up to first correct response are reported for each target.
  - **Correctness and SQL:** each Java target passes the black-box suite in exact mode and the ADR-032 census before its capture counts.
- 2026-11-24, coordinator: **scratch build and gs-rest RSS plan** (GPT-6.2-Astra High, `scratch-rss-astra.md`, under the owner's standing permission to consult Astra when stuck).
  - **Scratch (1.417x):** the 4,953 ms isn't measured platform compilation. It's DUB's residual on the *recursive, serial* path. `flint:term` (a pre-build `sh native/build.sh` invoking `cc`) and `flint:os` (a `.c` source, `interrupt_latch.c`) make the forked DUB's `canUseParallelPipeline` reject petclinic's whole 57-package graph. **m7** (with dmd-arm64 for the DUB patch) makes those two inputs schedulable so the graph builds in parallel. The first decision point is DUB planning, compile and archives at 2.65 s or less, against a 3.75 s total target.
  - **Scratch integrity:** B's scratch trials cloned the platform-only `FLINT_CACHE` and got 42 AOT model hits (171 ms AOT against 473 ms unprimed). A strict "everything from source" claim must start from empty derived AOT state and assert zero hits. **proof-harness** fixes the scratch mode and records each side's effective CPUs (both currently inherit venus's 32). B stays recorded as measured. The native-toolchain boundary (prebuilt libpq, OpenSSL and the D runtime libraries against `go build -a` rebuilding Go's runtime, std and pgx) goes to the owner.
  - **RSS (1.418x):** Flint is *below* Go after warm-up (11.57 against 13.80 MB) and rises about 8 MB during the 60 s fixed-rate phase. Even 16 bytes per request is 19 MB of cumulative allocation per scored minute, so the pools grow while the live set stays at 440 KB. **proof-harness** runs `fast-path-pools-ab` with an added 1 MiB arm and per-pool residency, collections and `smaps` snapshots at readiness, after warm-up and during the rise, for Flint and Go. The budget is 13.0 MB (GC pools 5.8, mappings 5.1, stacks and buffers 1.55, rings 0.55). `release-static-ab` (musl) and the fiber-stack and arena census follow only if that census shows the bytes.
- 2026-11-24, owner: **comparator baselines are captured once; routine runs measure Flint only.** Owner: "We should only need to run the bench for Flint once we capture the other apps' baseline; this is to save time in CI." This extends b442b9f9 from Java to Go:
  - **One capture per comparator.** Go (and each Java target) is measured once per app on the designated runner, with the same nine trials, workload, pinning and receipts as today, and saved as a pinned baseline record with raw samples. Routine queue entries and CI then run **Flint only** and score against that record. This roughly halves each window.
  - **Re-capture triggers** (the report refuses a stale record): the comparator's digest or toolchain (Go version, JDK, GraalVM, Maven lock), the workload manifest, the TLS profile, the PostgreSQL version, the runner's hardware, kernel or CPU governor, or ADR-032's census.
  - **Drift guard, so a stored baseline stays fair:** every Flint-only run starts with a short runner calibration. It's a fixed probe recorded alongside the baseline capture: one short Go trial at the scored rate, plus a fixed CPU and memory micro-probe. If the runner differs from the capture beyond its recorded noise (the capture's own 99% band), the run is marked not-evidence and Go is re-captured. Raw calibration samples go in every receipt.
  - **AGENTS.md compatibility:** the baseline is still an observed result on the designated runner, the candidate never replaces its own baseline, and runner metadata and raw samples are retained.
- 2026-11-24, owner: **two measurement questions settled as the coordinator recommended** (owner: "Recommend answers").
  1. **The Phase 1 exit claim gets one interleaved confirmation run.** Routine runs and CI stay Flint-only against stored baselines (c015f307). The final evidence run at the claimed commit measures Flint with the Go comparator interleaved trial by trial, as B did, so the headline result never rests on stored comparator numbers. The same applies to any release-gate claim.
  2. **The scratch-build boundary:** pinned upstream C libraries (libpq, OpenSSL, liburing, libyaml and the rest of `policy/native-lock.json`) and the installed D runtime libraries (druntime and Phobos from the pinned toolchain) count as the installed toolchain, the way `go build -a` doesn't rebuild the Go compiler. Everything else rebuilds from source on the clock: every D package, Flint's own C shims and wrappers, the AOT models and generated code, starting from empty derived state with zero cache hits asserted. The boundary is written into the scratch receipt and the published result, listing what's prebuilt on each side (Go: compiler and linker; Flint: the compilers, the runtime libraries and the pinned C libraries). The primary cold build (platform cache against Go's stdlib-primed GOCACHE) remains the headline build comparison.
- 2026-11-24, proof-harness: **error-validation-p99 certified at B** (`ca5fbd4a46ed`, claimed window 04:47–05:47Z, no foreign activity; the error-path workload with the Java context, 9 trials). petclinic-rest POST /petclinic/api/owners failing one constraint (400 ProblemDetail, no database work), Flint / Go median (99% interval):
    - **p99 6.07 (5.75–6.42), which fails** (753 against 124 µs);
    - p50 7.23, throughput 0.120 (19,000 against 158,000 req/s), **CPU per request 6.65** (106 against 16 µs), peak RSS 0.939 (passes); p99.9 5.16, reported.

    The request does no SQL, so the 106 µs is binding, validation and problem rendering on the servlet path: the third-party-apis (validation) and boot (error attributes) items the resume plan names for a missing error path. Evidence: `benchmarks/spring/evidence/error-validation-p99/20261124T044658Z/`.
- 2026-11-24, proof-harness: **phase1-builds-gs-relational certified at B** (`ca5fbd4a46ed`, claimed window 06:11–06:16Z; a first attempt at 05:57Z was voided by an unwrapped ldc2 compile from dmd-arm64's checkout). Java, Go and Flint pass 1/1. Median ratios (99% interval), production, 9 trials:
    - **primary 0.042 (0.041–0.044), which passes** (228 ms against Go's std-primed 5,428 ms, which compiles the pure-Go SQLite); against a deps-primed GOCACHE (context) 1.46 (1.39–1.55), against 1.295 at `6ab588f8` (Go's deps-primed build is now 156 ms). Phases: flint 20, AOT 103, compile 83, link 18 ms;
    - **secondary 0.369, which passes** (B's scratch mode, which still cloned the platform AOT models; the strict scratch of owner decision c25ae2b3 applies from the next certification);
    - **edit build, dev profile: 0.765, which passes** (125 against 163 ms);
    - **edit build, fully static: 1.387 (1.355–1.466), which fails** (226 ms: compile 91, link 109);
    - **Oz: 0.662, which passes** (4,430,936 against 6,695,800 bytes; 1.249 at `6ab588f8`): the L1 size win certifies.

    Evidence: `benchmarks/spring/evidence/phase1-builds-gs-relational/20261124T061138Z/`.
- 2026-11-24, proof-harness: **phase1-builds-gs-rest certified at B** (`ca5fbd4a46ed`, claimed window 06:26–06:29Z, no foreign activity). Java, Go and Flint pass 18/18. Median ratios (99% interval), production, 9 trials:
    - **primary 1.063 (0.962–1.103), which fails** (170 against 160 ms), against 0.933 at `6ab588f8`. Phases: flint 21, **AOT 100**, compile 20, link 20 ms; the AOT step (extraction and the fast path's generated code) is now most of the cold build, against 74 ms at the last gs-builds certification;
    - **secondary 0.985 (0.973–1.039), which fails** on its upper bound (3,289 against 3,340 ms; B's scratch mode);
    - **edit build, dev profile: 0.387, which passes** (64 against 166 ms);
    - **edit build, fully static: 1.093 (1.067–1.297), which fails** (176 ms; link 128);
    - **Oz: 0.625, which passes** (4,147,432 against 6,634,456 bytes).

    Evidence: `benchmarks/spring/evidence/phase1-builds-gs-rest/20261124T062614Z/`.
- 2026-11-24, proof-harness: **release-static-ab certified at B** (`ca5fbd4a46ed`, claimed window 06:39–07:07Z, no foreign activity; non-gating, owner rule 6ecd8933). gs-rest-service release, dynamic glibc (as built) against fully static musl (`flint package --target linux-x86_64-musl`, prepared at B with the watcher stopped), both 18/18 exact, 6 interleaved runs per arm. Static / dynamic, median (99% interval):
    - throughput **0.924 (0.915–0.931), worse beyond its interval** (298,200 against 322,800 req/s);
    - p50 **1.109 (1.043–1.147), worse**; p99 1.139 (0.885–1.542) and CPU per request 1.087 (0.978–1.198), inside their intervals;
    - peak RSS **0.918 (0.909–0.944), better** (17.9 against 19.5 MB);
    - stripped size: O3 5,407,920 against 4,745,176 bytes, Oz 4,904,368 against 4,147,432 (Oz 0.739 of Go's 6,634,456, a pass, but larger than the dynamic Oz).

    **Verdict under 6ecd8933: the measured release profile stays dynamic glibc.** The rule switches only if no runtime metric gets worse beyond its interval, and throughput and p50 do (musl's mallocng and libc replace glibc's, as playbook M-5 recorded). The 8% RSS saving is real; it goes to the RSS work as a lead, not a profile switch. Evidence: `benchmarks/spring/evidence/release-static-ab/20261124T063926Z/`.
- 2026-11-24, proof-harness: **fast-path-pools-ab certified** (main `5d7890bd`, claimed window 07:23–07:50Z, 3 interleaved runs, Go interleaved, `gc-matrix --smaps`; diagnostic A/B, owner decision 2 and Astra's RSS review 41053ce3). gs-rest-service on the default fast path, all arms 18/18. Against Go, median (99% interval):

    | arm | peak RSS | throughput | p99 | p50 | CPU/request | collections/s | max pause |
    |---|---|---|---|---|---|---|---|
    | `parallel:1` | 1.417 (1.398–1.458) | 1.319 | 0.917 | 1.294 | 1.029 | 8.4 | 0 ms |
    | `+ minPoolSize:4 incPoolSize:0` | 1.110 (1.083–1.131) | 1.318 | 0.813 | 1.127 | 0.949 | 17 | 0 ms |
    | `+ minPoolSize:1 incPoolSize:0` | **0.939 (0.929–0.961)** | 1.300 | 0.846 | 1.248 | 1.021 | 38 | 1–3 ms |

    **What grows (smaps census):** with the default pools, one new anonymous mapping of 7 MiB (druntime's grown second GC pool) appears during the fixed-rate phase and becomes fully resident: total RSS goes 11.3 MB after warm-up → 19.3 MB by 30 s and stays there. Fixed 4 MiB pools fill during warm-up and never grow; fixed 1 MiB pools stay at 12.6–12.9 MB (Go: 13.0 MB, flat). The rest is steady on both sides: about 198 mappings of 256 KiB (about 1.2 MB resident, fiber stacks) and 4.1 MB of Flint binary text against Go's 5.8 MB. So the RSS gap is the collector's pool growth policy, not live data: 1 MiB fixed pools meet the 13.0 MB budget for 1.4% throughput (1.319 → 1.300 of Go), 4.5 times the collections and pauses up to 3 ms. Evidence: `benchmarks/spring/evidence/fast-path-pools-ab/20261124T071647Z/`.
- 2026-11-24, coordinator, **provisional pending the owner** (asked at about 2:55 AM EST, no answer yet; reversible): **Boot's default GC setting becomes fixed 1 MiB pools** for B2, as recommended. fast-path-pools-ab (8c7d2302) showed the RSS gap is druntime growing a 7 MiB pool during the fixed-rate phase. Fixed 1 MiB pools gave RSS 0.939 of Go (12.6–12.9 MB, inside the 13.0 MB budget), throughput 1.300, p99 0.846, CPU 1.021, 38 collections per second and a 1–3 ms maximum pause. That run predates the RELRO root trim (33969576) and the pools[] move (f4808d67), which cut each collection's root scan by 43% and then 25%. B2 shows whether CPU per request also passes. If B2's CPU fails, the next arm is 2 MiB. The owner can override at any time; it's one rt_options line.
- 2026-11-24, proof-harness: **Go baseline of gs-rest-service captured** (owner decision c015f307; claimed window 08:27–09:10Z, harness `57d49362`, the registered comparator `d33e8488`): 18/18, then nine production trials of the HTTP workload and nine of the 404 path, five calibration trials and the nine-sample probe. Medians: HTTP 250,710 req/s, p50 61 µs, p99 261 µs, RSS 13.9 MB, CPU 8,208 ns per request (B's interleaved Go: 249,500 req/s, p99 260 µs); 404 path 245,310 req/s, p99 114 µs. Calibration bands are tight (coefficient of variation 0.4–0.9%). Record: `benchmarks/spring/baselines/go/gs-rest-service/20261124T082805Z/`; Flint-only runs (`--baseline`) measure against it while its fingerprint holds.
- 2026-11-24, coordinator: **B2 = `0f01d6edd0a416a709e828cd7a7e94d7c531c563`**, the second same-commit baseline. It contains:
  - the engine-sql wait fix and the FIFO lease handoff on RemoteWaker (57d49362);
  - the RELRO root trim and the pools[] move;
  - the census SQL fixes and health validation;
  - the fast-path binding;
  - the 404 and validation-error work (third-party-apis, web-http, framework-core, boot);
  - m7's static link dedup, per-module static replay and the DUB parallel pipeline on shared toolchain v4.1 (DMD e7757432);
  - the provisional fixed 1 MiB GC pools (0f01d6ed);
  - ADR-032's corrected Go comparator.

  The batch runs under c015f307 (Go baselines captured once, Flint-only parts against them). Builds use strict scratch and served compiles, with 0 refused asserted. Priority order:
  1. the Go baseline capture for petclinic-rest;
  2. phase1-http-petclinic, its first measurement;
  3. phase1-builds for all three apps;
  4. phase1-http-gs-rest;
  5. error-404-p99 and error-validation-p99 (Go baselines for the error paths captured as needed);
  6. the GC-matrix parts on natural quiet.

  B's results stay as history. The exit claim still needs its one interleaved confirmation run (c25ae2b3).
- 2026-11-24, proof-harness: **Go baseline of petclinic-rest captured** (c015f307; claimed window 09:20–10:02Z, harness `57d49362`, the ADR-032 comparator `c2791378`, census 0/109): 109/109, then nine production trials of the HTTP workload and nine of the validation-error path, calibration and probe. Medians: owner 1 at 20,990 req/s, p50 235 µs, p99 556 µs, RSS 26.5 MB, CPU 63.0 µs per request (before ADR-032 Go served about 28,300 req/s without the reference's transactions); validation path 157,220 req/s, p99 118 µs. Calibration coefficient of variation 0.3–0.7% (p99 5.7%). Record: `benchmarks/spring/baselines/go/petclinic-rest/20261124T092019Z/`. Known gap in both records' fingerprints: the PostgreSQL peer is recorded as null (it is pinned by libpq's version in native-lock.json, not peer-lock.json); it is left as is through B2, so B2's runs and assembly stay consistent, and fixed with the next re-capture.
- 2026-11-24, proof-harness: **phase1-builds-petclinic certified at B2** (`0f01d6edd0a4`, claimed window 10:44–10:49Z, no foreign activity; a private copy of shared v4.1, mold, strict scratch, served compiles reported). Java, Go and Flint pass 109/109, and so do the served dev and static binaries built in the tree afterwards (exact mode). Compile server: 2,335 requests compiled, 44 refused, one in each of the 44 scored cold builds (named in the receipt; B2's toolchain predates 4ac873d8). Median ratios (99% interval), 9 trials. **Every gated build metric passes:**
    - primary 0.257 (0.253–0.279): 519 against 2,018 ms; deps-primed context 1.66;
    - **secondary 0.457 (0.442–0.479)**, strict scratch from an empty cache (owner c25ae2b3): 1,829 against 4,003 ms, against 1.417 at B (m7's parallel DUB pipeline and per-module archives);
    - edit, dev profile: 0.602 (194 against 322 ms);
    - **edit, fully static: 0.785 (0.759–0.822)**: 253 ms, link 81 ms, against 2.53 at B (the per-module archive layout, c17ea1ba);
    - Oz 0.949 (10,874,920 against 11,462,648 bytes).

    Evidence: `benchmarks/spring/evidence/phase1-builds-petclinic/20261124T104354Z/`.
- 2026-11-24, proof-harness: **phase1-builds-gs-relational certified at B2** (`0f01d6edd0a4`, 10:59–11:03Z, no foreign activity). Java, Go and Flint pass 1/1, and so do the served dev and static binaries. Compile server: 961 compiled, 44 refused (one per scored cold build). Median ratios (99% interval), 9 trials:
    - primary 0.044 (232 against 5,284 ms); deps-primed context 1.53;
    - **secondary 0.121 (0.120–0.124)**, strict scratch (846 against 6,986 ms; 0.369 at B);
    - edit, dev profile: 0.815;
    - **edit, fully static: 1.053 (1.004–1.095), which fails** narrowly: 161 against 153 ms (compile 81, link 54; 1.387 at B);
    - Oz 0.669.

    Evidence: `benchmarks/spring/evidence/phase1-builds-gs-relational/20261124T105854Z/`.
- 2026-11-24, proof-harness: **phase1-builds-gs-rest certified at B2** (`0f01d6edd0a4`, 11:13–11:15Z, no foreign activity). Java, Go and Flint pass 18/18, and so do the served dev and static binaries. Compile server: 1,031 compiled, 44 refused (one per scored cold build). Median ratios (99% interval), 9 trials:
    - **primary 1.083 (1.055–1.154), which fails**: 165 against 152 ms; phases flint 23, **AOT 101**, compile 20, link 18 ms (1.063 at B): the AOT step remains the build bottleneck for gs-rest (flint-aot);
    - **secondary 0.289 (0.283–0.298)**, strict scratch (925 against 3,200 ms; 0.985 at B);
    - edit, dev profile: 0.399;
    - **edit, fully static: 0.660 (0.615–0.691)**: 104 ms, link 56 (1.093 at B);
    - Oz 0.628.

    Evidence: `benchmarks/spring/evidence/phase1-builds-gs-rest/20261124T111251Z/`.
- 2026-11-24, proof-harness: **phase1-http-gs-rest certified at B2** (`0f01d6edd0a4`, 11:25–11:47Z, no foreign activity): the first Flint-only part (owner c015f307), against the Go baseline `benchmarks/spring/baselines/go/gs-rest-service/20261124T082805Z`. **The drift guard stayed in band** before and after (Go calibration 253,500 and 251,600 req/s, p99 262 and 261 µs; both probes in band), so the 6% drift seen on petclinic is not machine-wide. Flint / Go, median (99% interval), 9 trials:
    - **throughput 1.323 (1.318–1.330), which passes**, and its lower bound clears the throughput plan's 1.30;
    - **p99 0.851, which passes**;
    - **peak RSS 0.944 (0.927–0.962), which passes**: 13.2 against 13.9 MB (1.418 at B; B2 has fixed 1 MiB pools by default);
    - **p50 1.297 (1.131–1.356), which fails** (79 against 61 µs);
    - **CPU per request 1.053 (0.984–1.087), which fails** on its upper bound (8,641 against 8,208 ns);
    - p99.9 1.131, reported.

    Evidence: `benchmarks/spring/evidence/phase1-http-gs-rest/20261124T112529Z/`.
- 2026-11-24, proof-harness: **phase1-http-petclinic certified at B2** (`0f01d6edd0a4`, 13:00–13:40Z, no foreign activity), interleaved with Go trial by trial (the coordinator's fallback while the guard's bands are set from cross-session calibrations; a first interleaved attempt at 12:10Z was voided by one tick of an idle scratchpad PostgreSQL, the stray check's threshold since fixed). The first certified petclinic runtime result; the 5,000 req/s warm-up held in every trial. Flint / Go, median (99% interval), 9 trials:
    - throughput **0.933 (0.922–0.952), which fails** (18,710 against 20,060 req/s; at B Flint held about 1,600);
    - p50 **2.008, which fails** (0.480 against 0.239 ms); p99 **1.858, which fails** (1.09 against 0.587 ms);
    - **peak RSS 0.818 (0.809–0.835), which passes** (21.5 against 26.3 MB);
    - CPU per request **1.578, which fails** (99.9 against 63.3 µs);
    - p99.9 2.71, reported.

    The remaining gap is CPU per request: the next runtime candidate for data-access (the per-row locks, bind arrays and monitors of the throughput plan) and the S1–S4 fast-path shapes. Evidence: `benchmarks/spring/evidence/phase1-http-petclinic/20261124T125955Z/`.
- 2026-11-24, coordinator: **petclinic CPU plan adopted** (GPT-6.2-Astra High, `petclinic-cpu-astra.md`). At B2, Go uses 63.3 µs per request at the scored rate and 55.5 µs at capacity; Flint uses 99.9 and 104.0. The CPU gate needs about 62.7 µs (before the confidence interval), the 1.30 throughput target 76.7 µs per two-CPU tier, and closing p50 needs about 243 µs of elapsed time, so wake and dispatch delay matter as well as CPU. Plan for 55–65 µs on a Spring-faithful path.
  - **Allocation target:** 100 per owner-1 request first, then 60–80 (235 at 6200b84b).
  - **Order:**
    1. The floor diagnostic, three arms at one revision: ordinary Flint, a minimal handler with identical bytes, and that handler with the real mapping, DTOs and Jackson restored (proof-harness with data-access).
    2. Direct mapping of the six pet-type rows through a metadata-validated ordinal plan (data-access with flint-aot), widened only if it pays end to end.
    3. S1–S4 (flint-aot), measured alone and combined.
    4. A 2 MiB pool arm for petclinic (boot, via --DRT-gcopt) and web-http's wake bisect.
    5. Re-profile before spending on maps, Jackson or transaction glue.
  - **Not budgeted:** a 30–40 µs win from a JDBC executor alone. An arena entity graph copied at the boundary is rejected (two representations, lifetime hazards).
- 2026-11-24, owner: **fixed 1 MiB GC pools confirmed as Boot's default** (owner: "1 MiB pools"). The provisional decision 236459b6, implemented in 0f01d6ed, is now final. A per-app arm for petclinic (2 or 4 MiB through `--DRT-gcopt`) stays an experiment in the petclinic CPU plan. Changing the default for any app comes back to the owner with its measurements.
- 2026-11-24, proof-harness: **error-404-p99 certified at B2** (`0f01d6edd0a4`, 15:10–15:50Z, interleaved with Go, no foreign activity). Two earlier attempts measured nothing: at 13:50Z the drift guard (Go p99 outside the capture's band) switched the entry to interleaved, and at 14:20Z data-access's valgrind server, outside its held group, voided the window. framework-core's idle scratchpad PostgreSQL (15:09–15:29Z) overlapped this window but never used 2 ticks in a sampling second, so under the stray rule it does not count. gs-rest GET /nope, Flint / Go, median (99% interval):
    - **p99 6.04 (5.32–6.80), which fails** (681 against 113 µs); unchanged from B (5.74);
    - p50 6.93, throughput 0.377 (93,000 against 247,000 req/s), CPU per request 3.85 (35.2 against 9.1 µs), RSS 1.02; p99.9 6.84, reported.

    Evidence: `benchmarks/spring/evidence/error-404-p99/20261124T151028Z/`.
- 2026-11-24, proof-harness: **error-validation-p99 certified at B2** (`0f01d6edd0a4`, 16:00–16:40Z, interleaved with Go, no foreign activity; the first window that froze a stray instead of losing to it: a gs-rest server from worktree elastic-lamport, frozen at the claim and continued at the end, recorded in the receipt). petclinic POST /owners failing one constraint, Flint / Go, median (99% interval):
    - **p99 3.995 (3.632–4.254), which fails** (491 against 123 µs), against 6.07 at B;
    - p50 4.01, throughput 0.188 (29,570 against 157,700 req/s), CPU per request 3.81 (60.8 against 16.0 µs; 106 µs at B), RSS 0.764; p99.9 2.53, reported.

    Evidence: `benchmarks/spring/evidence/error-validation-p99/20261124T160020Z/`.
- 2026-11-24, proof-harness: **gc-pools-petclinic** (diagnostic A/B, the petclinic CPU plan 3df9a1c5; main `f4e81ead`, 16:50–17:14Z, 3 interleaved runs, no Go, smaps census, nothing frozen). petclinic-rest with fixed collector pools; each arm overrides only `minPoolSize` and `incPoolSize`, so the mark threads keep Boot's affinity default. All arms 109/109. Medians:

    | pools | throughput | p99 | peak RSS | CPU/request | collections / 1,000 requests | mark time | max pause |
    |---|---|---|---|---|---|---|---|
    | 1 MiB (the default) | 18,926 req/s | 1.134 ms | 21.6 MB | 100.1 µs | 4.9 | 2.6 s | 2 ms |
    | 2 MiB | 0.978× | 1.073× | 1.062× | 1.000× | 4.7 | 2.9 s | 4 ms |
    | 4 MiB | **1.037×** | 1.032× | 1.162× (25.1 MB) | 1.001× | 3.3 | 2.1 s | 4 ms |

    CPU per request does not move, so the collector is not petclinic's CPU gap. 4 MiB pools buy 3.7% throughput through a third fewer collections, for 3.5 MB of RSS that still stays under Go's 26.3-26.5 MB (about 0.95x). The smaps census shows the heap filling in warm-up and flat through the fixed-rate phase for every arm. Whether a per-app setting is worth it is boot's and data-access's call; gs-rest stays at 1 MiB. Allocations per request come from data-access's request-allocation gate (pool size does not change them). Evidence: `benchmarks/spring/evidence/gc-pools-petclinic/20261124T164958Z/`.
- 2026-11-24, proof-harness: **floor-reference, the three-arm floor diagnostic** (the petclinic CPU plan 3df9a1c5; main `271fb314` with data-access's arms 0460ca01; 17:24–17:31Z, no foreign activity, nothing frozen; diagnostic, never evidence). GET /petclinic/api/owners/1, one server per step, the manifest's CPU sets, data-access's lease counters, 20 s per step:

    | arm | capacity (64 conn.) | app CPU/request | PostgreSQL CPU/request | lease wait at capacity | lease hold at 5,000 req/s | p50 / p99 at 5,000 req/s |
    |---|---|---|---|---|---|---|
    | ordinary Flint petclinic-rest | 20,008 req/s | 98.0 µs | 56–57 µs | 2.54 ms | 305 µs | 0.462 / 1.083 ms |
    | floor, minimal (rows to the response) | 23,327 | 65.4 | 59–61 | 2.18 ms | 215 | 0.289 / 0.581 |
    | floor, mapped (+ entities, OwnerDto, Jackson) | 22,782 | 69.2 | 59–60 | 2.23 ms | 220 | 0.309 / 0.638 |

    - **Where the CPU is:** petclinic's mapping, DTOs and Jackson cost about 4 µs per request; the other 29 µs between the mapped floor and ordinary Flint is the servlet and MVC layer (dispatch, filters, argument and return handling). Ordinary Flint also holds its lease about 85 µs longer.
    - **What limits capacity:** in every arm the pool of 10 is saturated (lease waits of 2.2–2.5 ms), so capacity is about the pool size over the lease hold; PostgreSQL spends 56–61 µs of CPU per request, about as much as the floor's own CPU.
    - **Syscalls per response** (untimed strace census, 2,000 requests at 8 connections): 5 `sendto` in every arm, the five statements (BEGIN, three SELECTs, COMMIT); the HTTP response goes through io_uring (about 2.6 `io_uring_enter` per response), so its writes are not visible as syscalls. About 17.6 `recvfrom` per response in every arm (3.5 per statement), 22–29% of them returning EAGAIN across the whole logs: libpq's non-blocking reads.

    Evidence: `benchmarks/spring/evidence/floor-reference/` (the strace logs, 170–200 MB each, stay in .flint/measure/results).
- 2026-11-24, coordinator: **B3 = `d6d15b0073dda669dacf790dea443f033f4dbb55`**, the third same-commit baseline. Beyond B2 it adds:
  - **builds:** flint-aot's served AOT extraction (6200b84b), shared toolchain v4.2 (served compiles all-or-none, 4ac873d8), m7's gs-relational static-edit fixes (d8854571, 01d15212), the D-JDBC-2 glue resolver;
  - **runtime:** web-http's write-behind response path (45e8b765) and gs-rest allocation fix (1b73f250); data-access's direct row mapping (f83eabd9, bf353ba4), libpq read driving (da10da45) and engine-jdbc and engine-sql cuts; third-party-apis' Jackson property writers and the validator fixes (8f1a7ef7 included); framework-core's transaction interceptor, HashMap and emptyList fixes;
  - **size:** framework-core's collections erasure (14ebc0c8, af1573af; petclinic Oz −415 KB);
  - **fast path:** S1–S3, not yet active for petclinic until S4.

  The batch runs Flint-only against the captured Go baselines and falls back to interleaved, since the cross-session guard bands land about 4 AM EST tomorrow. Builds assert 0 refused compiles again. Order:
  1. phase1-builds for gs-rest, gs-relational and petclinic;
  2. phase1-http-petclinic;
  3. phase1-http-gs-rest;
  4. error-404-p99 and error-validation-p99.

  The GC matrix waits for natural quiet. B2's results stay as history.
- 2026-11-24, proof-harness: **phase1-builds-gs-rest certified at B3** (`d6d15b0073dd`, 19:11–19:13Z, no foreign activity; a private copy of shared v4.2, strict served compiles, strict scratch). Java, Go and Flint 18/18, and the served dev and static binaries 18/18. Served: 1,093 compiles client-served, 18 client-local (all c-source, allowed), 0 refused by the server. **Every gated build metric passes**, median (99% interval), 9 trials:
    - **primary 0.554 (0.519–0.594)**: 86 against 156 ms, AOT 26 ms (101 at B2: flint-aot's 6200b84b serves the extraction);
    - secondary 0.280 (strict scratch, 900 against 3,208 ms); edit 0.355; static edit 0.596; Oz 0.618.

    Evidence: `benchmarks/spring/evidence/phase1-builds-gs-rest/20261124T191046Z/`.
- 2026-11-24, proof-harness: **phase1-builds-gs-relational certified at B3** (`d6d15b0073dd`, 19:23–19:27Z, no foreign activity). 1/1 everywhere, served binaries included. Served: 1,023 client-served, 18 c-source, 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials: primary 0.020; **deps-primed context 0.688 (0.650–0.721)**, against 1.53 at B2: Flint now builds faster even than Go with its third-party packages cached; secondary 0.121 (strict scratch); edit 0.541; **static edit 0.803 (0.772–0.828)**, 125 against 155 ms (1.053 at B2); Oz 0.662. Evidence: `benchmarks/spring/evidence/phase1-builds-gs-relational/20261124T192301Z/`.
- 2026-11-24, proof-harness: **phase1-builds-petclinic certified at B3** (`d6d15b0073dd`, 19:37–19:43Z, no foreign activity; one stray callgrind frozen and continued). 109/109 everywhere, served dev and static binaries included. Served: 2,463 client-served, 18 c-source, 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials: primary 0.207 (404 against 1,953 ms; AOT 110 ms); secondary 0.473 (strict scratch); edit 0.584; static edit 0.774; Oz 0.925. Context: deps-primed 1.27. **With this part, all 15 gated build metrics of the three Phase 1 applications pass at B3.** Evidence: `benchmarks/spring/evidence/phase1-builds-petclinic/20261124T193649Z/`.
- 2026-11-24, proof-harness: **phase1-http-petclinic certified at B3** (`d6d15b0073dd`, 19:53–20:33Z, interleaved with Go, no foreign activity; one stray callgrind frozen and continued). **Flint's throughput passes on petclinic for the first time.** Flint / Go, median (99% interval), 9 trials:
    - **throughput 1.132 (1.090–1.143), which passes**: 22,800 against 20,140 req/s (0.933 at B2). No dip: Flint's trials ran 21,930–23,040 req/s;
    - **peak RSS 0.793, which passes** (20.8 against 26.3 MB);
    - p50 **1.478, which fails** (0.351 against 0.238 ms; 2.008 at B2); p99 **1.445, which fails** (0.839 against 0.581 ms; 1.858 at B2; every trial 0.82–0.90 ms, no outlier);
    - CPU per request **1.331, which fails** (84.2 against 63.2 µs; 1.578 at B2);
    - p99.9 1.96, reported.

    Evidence: `benchmarks/spring/evidence/phase1-http-petclinic/20261124T195306Z/`.
- 2026-11-24, owner: **HTTP parity for the gated error paths, as recommended** (owner: "Yes, your recommendation"). Astra's review (`error-paths-astra.md`) found that Tomcat, and so the Java reference and Flint, close the connection after every validation 400, while the Go comparator reuses it, and that Go sends both error bodies with `Content-Length` where Java sends them chunked. The registered `semantic` wire mode permitted both.
  - **Rule:** on every gated path, each comparator matches the Java golden's framing (chunked or `Content-Length`), connection lifetime (`Connection: close` and the actual close, or reuse) and reason phrase, plus everything `semantic` already checks. How a server produces the bytes stays free: write coalescing, internal dispatch, caching.
  - **Go change, and only that:** the 404 and the validation 400 become chunked, the 400 closes its connection as Tomcat does, and the reason phrases are empty as Java's are. Nothing beyond Java.
  - **Process (AGENTS.md):** proof-harness writes ADR-033 (HTTP parity), measures the transport cost first (raw responses, a second request on each socket, accepts per request), makes the change, adds a check-registry rule so `exact` framing and connection lifetime are enforced on gated paths, re-registers the comparator, re-captures the affected Go baselines (gs-rest's error path and petclinic's validation path), and remeasures both sides at one commit. B2's and B3's error-path results stay as history against the old comparator.
- 2026-11-24, proof-harness: **phase1-http-gs-rest certified at B3** (`d6d15b0073dd`, 21:06–21:46Z, interleaved with Go, no foreign activity; one stray callgrind frozen and continued). Flint / Go, median (99% interval), 9 trials:
    - **throughput 1.488 (1.475–1.507), which passes** and clears the plan's 1.30: 372,200 against 250,200 req/s (1.323 at B2); every Flint trial ran 367,500–375,800 req/s;
    - **p99 0.842 (0.783–0.935), which passes** (0.215 against 0.256 ms; 0.851 at B2);
    - **peak RSS 0.772 (0.751–0.779), which passes** (10.6 against 13.8 MB; 0.944 at B2);
    - p50 **1.319 (1.190–1.516), which fails** (79 against 60 µs; 1.297 at B2);
    - CPU per request **1.006 (0.953–1.086), which fails** (8.30 against 8.25 µs; 1.053 at B2);
    - p99.9 1.13, reported.

    Evidence: `benchmarks/spring/evidence/phase1-http-gs-rest/20261124T210603Z/`.
- 2026-11-24, owner: **HTTP parity extends to every gated path** (owner: "Yes, all gated paths"). ADR-033's rule (each comparator matches the Java golden's framing, connection lifetime and reason phrase; production of the bytes stays free) now covers every request a gated workload or the black-box suite scores, not just the error paths. That includes petclinic's `GET /owners/{id}`, which Java sends chunked and Go currently sends with `Content-Length`, and gs-rest's `/greeting` if its golden differs. proof-harness amends ADR-033's scope, extends the Go change and the parity record to every gated path (nothing beyond Java), re-registers, then runs the held Go re-captures (go-baseline-*-2) once against the final comparator. All phase1-http and error-path parts are remeasured against the new records at B4. Earlier results stay as history against the old comparator.
- 2026-11-24, proof-harness: **error-404-p99 certified at B3** (`d6d15b0073dd`, 22:08–22:48Z, interleaved with Go, no foreign activity; one stray callgrind frozen and continued; the 21:56Z claim failed on a session server and the freezer now sweeps during the claim, 86ca5aba). Against the pre-ADR-033 comparator (Content-Length framing), so it is history once parity lands. Flint / Go, median (99% interval), 9 trials:
    - **p99 2.98 (2.32–3.34), which fails**: 340 against 114 µs (6.04 at B2: 681 µs; web-http's write-behind halved it);
    - context: p50 2.34 (93 against 40 µs); CPU per request 1.96 (17.8 against 9.1 µs; 3.87 at B2); capacity 0.579 (142,900 against 246,700 req/s); RSS 0.84; p99.9 3.56.

    Evidence: `benchmarks/spring/evidence/error-404-p99/20261124T220806Z/`.
- 2026-11-25, proof-harness: **error-validation-p99 certified at B3** (`d6d15b0073dd`, 23:21Z–00:00Z on 11-24/25, interleaved with Go, no foreign activity; a stray callgrind and a session's scratchpad PostgreSQL cluster frozen and continued). Against the pre-ADR-033 comparator, which kept every connection where Flint, like Tomcat, closes after the 400; so it is history once parity lands. Flint / Go, median (99% interval), 9 trials:
    - **p99 3.23 (3.10–3.31), which fails**: 383 against 119 µs (3.995 at B2: 491 µs);
    - context: p50 2.66 (109 against 41 µs); CPU per request 2.98 (47.2 against 15.8 µs); capacity 0.227 (35,800 against 157,900 req/s, Flint reconnecting after every 400); RSS 0.69; p99.9 2.21.

    Evidence: `benchmarks/spring/evidence/error-validation-p99/20261124T232105Z/`.
- 2026-11-25, proof-harness: **transport-pricing measured** (ADR-033's price, diagnostic, never evidence; B3's tree with the pre-parity comparators, 00:10–01:07Z, claimed, no foreign activity; 7 interleaved trials per Go arm). Go variant / Go as it was:
    - **chunked framing costs almost nothing**: the 404's p99 is 1.03 (not significant) and CPU 1.01; the owner GET's p99 is 0.91 and CPU 1.01; the 400's CPU is 1.04 and capacity 0.92;
    - **close-after-400 is the price**: p99 1.74 (121 to 210 µs), p50 2.42, CPU 1.98 (15.9 to 31.4 µs), capacity 0.331, 1.0 accepts per request (against 0.0004).

    Java and Flint send identical transport on all three paths (no reason phrase, chunked, the 400 closed). At these levels Flint's validation p99 against the parity comparator would be about 1.85, against 3.23 at B3.

    New question for the owner: Tomcat's default `maxKeepAliveRequests` of 100 closes Java's kept connections about once per 100 requests (0.0101 accepts per request). Neither Flint nor Go does this, and the golden cannot record it.

    Evidence: `benchmarks/spring/evidence/transport-pricing/20261125T001045Z/`, with ADR-033's price section.
- 2026-11-25, owner: **match Tomcat's keep-alive request limit** (owner: "Yes, match Tomcat"). Spring Boot's embedded Tomcat closes a persistent connection after `server.tomcat.max-keep-alive-requests` (default 100) requests, so the Java reference reconnects about once per 100 requests (0.0101 accepts per request in proof-harness's transport pricing, 406cc215).
  - **Flint (fidelity):** Flint Boot binds `server.tomcat.max-keep-alive-requests` with Spring's default of 100 (−1 means unlimited, as in Boot), and engine-web closes a connection with `Connection: close` on the Nth response, exactly as Tomcat does. Owners: boot (property and autoconfiguration), web-http (engine-web).
  - **Go (parity, ADR-033 amendment):** the comparator applies the same 100-request limit with the same close behaviour, and nothing beyond Java.
  - **Sequencing:** the Go baseline captures in flight against the parity comparator finish as they are, and stay valid while neither side has the limit. The Flint change and the Go change land together. Then the comparator is re-registered, its parity record retaken (including a test of the 100th-response close), and the Go baselines re-captured once.
- 2026-11-25, owner: **work faster: five process changes** (owner approved the coordinator's list).
  1. **The dev loop doesn't need windows.** Sessions judge their own changes with deterministic per-request instruction and allocation counts (callgrind plus the allocation counter), run under `measure_queue.py hold`, never with timed load. m7 builds a shared tool (`tools/spring_instr.py <app> <request>`: instructions, allocations and bytes per request, by layer) so every session measures the same way. Windows are for certification only.
  2. **Certify only at baselines.** No one-off A/B windows. Every certified number comes from a named baseline batch (B4, B5, …). Exception: a diagnostic the coordinator names explicitly.
  3. **Flint-only runs** against the captured Go baselines once the cross-session guard bands are set (about 09:00Z), with interleaved runs only as the guard's fallback.
  4. **Critical path only.** Active: web-http (web stack, reactor), data-access (SQL and JDBC), flint-aot (fast path), proof-harness (measurement), m7 (dev-loop tool, size), and boot until the keep-alive property lands. Parked until named: framework-core, third-party-apis, web-mvc, and the platform and starter sessions.
  5. **Reviews don't block.** A cross-owner change that keeps acceptance exact and every gate green may land if its reviewer hasn't answered within 30 minutes. The reviewer can still raise issues afterwards, which are fixed forward. Owner-only decisions (coordination.md rule 5) are unchanged.
  - **Second runner:** 10.10.10.13 is pluto (Apple M1, macOS, arm64), already the macOS and arm64 lane. Its numbers aren't comparable with venus (x86-64 Linux, io_uring), so it can't share Phase 1 certification. A second x86-64 Linux runner would double certification capacity; the owner is asked whether one exists.
- 2026-11-25, coordinator: **posidon is the timed-diagnostics runner** (owner provided olfa@10.10.10.12). It's an i7-11700K (8 cores, 16 threads), 31 GB RAM, Ubuntu 24.04, kernel 6.8, the same pinned DMD v4.2, LDC, Go, oha, PostgreSQL 18.7 and liburing as venus. Acceptance passes there (18/18, 109/109, 1/1, Go in parity mode), and `load_bench --smoke` passes. `~/flint-work/bench-mode.sh on|off|status` is on: performance governor, docker, snapd, apt and other timers stopped, the network untouched.
  - **Use:** timed before/after (A/B) diagnostics that a session needs beyond deterministic counts. Its numbers are NEVER certification evidence and never mixed with venus (different CPU and kernel; its PostgreSQL CPUs 8–9 are hyperthread siblings of cores 0–1). venus does certification only.
  - **Rules:** one timed run at a time, under `tools/measure_queue.py hold` on posidon. Stop every server you start. Push your commit to posidon's bare repo (`git push olfa@10.10.10.12:flint-work/flint.git <commit>:refs/heads/<your-role>`, key `~/.ssh/full-access-ssh-key`) rather than copying trees. Re-emit native blocks after a pull. Never delete the owner's files there; the disk has 18 GB free.
- 2026-11-25, coordinator: **B4 = `fb4c73d1adc7550f728b76b3e53258f0708cb4d3`**, named now rather than at 09:00Z, so it doesn't sit idle for 3 hours. Beyond B3 it adds:
  - **responses:** sent on handler return (83973b57) and io_uring poll waits (e03f50f4);
  - **petclinic:** BEGIN pipelined with the first query (2719028d), libpq read driving (da10da45), the fast-path S1–S4 (S4 18c696a6: owner 1 at −18.9% instructions), the JDBC allocation slices (owner 1 at about 107 allocations, from 164) and the pgjdbc catalog port (census 0 of 109);
  - **404:** the shortcut's engine and Boot halves (not active until flint-aot's bean lands);
  - **builds:** the AOT digest fix;
  - **fidelity:** Tomcat's keep-alive limit on Flint and Go.

  Runtime parts run Flint-only against the `-3` Go records (8d29301a comparators), and the guard's fallback switches any part that fails it to interleaved; the cross-session bands land after 08:30Z and apply from B5. Order:
  1. builds for the three apps (strict, 0 refused);
  2. phase1-http-petclinic;
  3. phase1-http-gs-rest;
  4. error-validation-p99 and error-404-p99.

  The calibration sessions keep their slots.
- 2026-11-25, proof-harness: **phase1-builds-gs-rest certified at B4** (`fb4c73d1adc7`, 05:54–05:59Z, no foreign activity; a private copy of shared v4.2, strict served compiles, strict scratch). Java, Go (parity wire mode, ADR-033) and Flint 18/18; the served dev and static binaries 18/18. Served: 1,093 compiles client-served, 18 client-local (all c-source, allowed), 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials:
    - primary 0.530 (0.497–0.568): 87 against 165 ms;
    - secondary 0.277 (strict scratch, 906 against 3,272 ms); edit 0.368; static edit 0.600; Oz 0.624.

    Evidence: `benchmarks/spring/evidence/phase1-builds-gs-rest/20261125T055404Z/`.
- 2026-11-25, proof-harness: **phase1-builds-gs-relational certified at B4** (`fb4c73d1adc7`, 06:09–06:13Z, no foreign activity). 1/1 everywhere (Go in the parity wire mode), served binaries included. Served: 1,023 client-served, 18 c-source, 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials: primary 0.020; deps-primed context 0.682 (0.643–0.813); secondary 0.120 (strict scratch); edit 0.526; static edit 0.773 (0.751–0.810), 126 against 163 ms; Oz 0.668. Evidence: `benchmarks/spring/evidence/phase1-builds-gs-relational/20261125T060905Z/`.
- 2026-11-25, proof-harness: **phase1-builds-petclinic certified at B4** (`fb4c73d1adc7`, 06:23–06:29Z, no foreign activity). 109/109 everywhere (Go in the parity wire mode), served dev and static binaries included. Served: 2,463 client-served, 18 c-source, 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials: primary 0.214 (412 against 1,927 ms); secondary 0.490 (strict scratch); edit 0.578; static edit 0.770; Oz 0.935. Context: deps-primed 1.27. **All 15 gated build metrics of the three applications pass at B4.** Evidence: `benchmarks/spring/evidence/phase1-builds-petclinic/20261125T062255Z/`.
- 2026-11-25, coordinator: **petclinic CPU work goes to the Spring framework path, not transport or mapping.** This is diagnostic evidence from posidon, never certification: `benchmarks/spring/evidence/floor-reference/posidon-20261125T065217Z/` and `posidon-20261125T070834Z/`, the second clean under the host-wide lock (e1b85c5d) and freeze-strays. App CPU per request at 5,000/s on one machine:
  - Go: 95.1 µs;
  - floor-minimal (same HTTP stack and libpq, identical bytes): 63.2;
  - floor-mapped (plus the real mapping, DTOs and Jackson): about 75.3;
  - ordinary Flint: 116.0.

  PostgreSQL CPU and I/O syscalls are equal across the arms. The roughly 41 µs between floor-mapped and ordinary Flint is servlet, MVC and security filters, the tx interceptor, and NamedParameterJdbcTemplate/BeanPropertyRowMapper over JDBC. It is the only share above Go. Ordinary Flint also has about 0.45 more fiber parks and 0.4 more futex calls per request, with identical I/O. Use the deltas between arms, not posidon's ratios: posidon is Intel, venus is AMD.

  Owners:
  - flint-aot: the next fast-path layers;
  - data-access: JDBC and tx, plus the extra parks and futex calls;
  - web-http: the extra park if it is in the engine.

  Mapping work (direct row mapping) is deprioritized, since about 11 µs is the whole mapping-plus-Jackson cost.
- 2026-11-25, proof-harness: **phase1-http-petclinic certified at B4** (`fb4c73d1adc7`, 07:33–08:13Z, interleaved with Go after the Flint-only run's closing drift guard missed by 0.6% on Go calibration CPU; no foreign activity; a stray callgrind frozen and continued). Go is the ADR-033 comparator with Tomcat's keep-alive limit (`8d29301a`), accepted 109/109 in the parity wire mode. Flint / Go, median (99% interval), 9 trials:
    - **throughput 1.416 (1.407–1.423), which passes**: 27,610 against 19,500 req/s (1.132 at B3); Flint's trials ran 27,020–27,760 req/s;
    - **peak RSS 0.754, which passes** (20.2 against 26.8 MB);
    - p50 **1.048 (1.030–1.057), which fails** (250 against 238 µs; 1.478 at B3);
    - p99 **1.133 (1.078–1.188), which fails** (668 against 590 µs; 1.445 at B3);
    - CPU per request **1.044 (1.033–1.054), which fails** (68.2 against 65.3 µs; 1.331 at B3);
    - p99.9 1.42, reported.

    Evidence: `benchmarks/spring/evidence/phase1-http-petclinic/20261125T073334Z/`.
- 2026-11-25, proof-harness: **phase1-http-gs-rest certified at B4** (`fb4c73d1adc7`, 09:17–09:57Z, interleaved with Go after the Flint-only run's guards missed by 0.5–1.5%; no foreign activity). Go is the ADR-033 comparator with Tomcat's keep-alive limit (`8d29301a`), accepted 18/18 in the parity wire mode. **Every gated runtime metric passes, for the first time on gs-rest.** Flint / Go, median (99% interval), 9 trials:
    - **throughput 1.451 (1.437–1.469)**: 342,190 against 235,810 req/s (1.488 at B3, against the comparator without the keep-alive limit);
    - **p50 0.809 (0.799–0.820)**: 51 against 63 µs (1.319 at B3);
    - **p99 0.481 (0.450–0.508)**: 136 against 283 µs (0.842 at B3);
    - **peak RSS 0.736 (0.726–0.746)**: 10.3 against 14.0 MB;
    - **CPU per request 0.718 (0.709–0.725)**: 6.20 against 8.63 µs (1.006 at B3);
    - p99.9 0.69, reported.

    Evidence: `benchmarks/spring/evidence/phase1-http-gs-rest/20261125T091722Z/`.
- 2026-11-25, coordinator: **Release and size builds were ThinLTO-codegenned at O0. Fixing it is a bug fix, not a policy change.** web-http found it (diagnostic A/B on posidon at 6590fac7, spring_instr, same tree).
  - Cause: `policy/profiles.toml` gives `-O3 --flto=thin` (release) and `-Oz --flto=thin` (size) as DFLAGS. DUB's LDC link step forwards `--flto` but not `-O`, so ldc2 passes `-Wl,-plugin-opt=O0` to the ThinLTO plugin. All Flint bitcode (framework and app) was optimised at O0 at link; only the prebuilt druntime was optimised.
  - Effect of `-plugin-opt=O3` at the link: petclinic owner 1 360,928 → 273,344 instructions (−24.3%); validation 400 292,788 → 200,940 (−31.4%); allocations unchanged; stripped release 15.90 → 14.34 MB.
  - Decision: the flint CLI passes each profile's optimisation level to every LDC LTO link path, with a regression test (m7). This restores what the profiles already state, so no budget, gate, workload or comparator changes. DMD builds have no LTO and are unaffected.
  - Consequence: every certified Flint CPU, latency, size and release link-time number up to B4 was measured with unoptimised Flint code. B5 is named only after the fix lands, and re-measures all parts (builds, sizes, runtime).
- 2026-11-25, proof-harness: **error-validation-p99 certified at B4** (`fb4c73d1adc7`, 10:07–10:47Z, interleaved from the start (coordinator, 2fe4a4f6); no foreign activity; a stray callgrind frozen and continued). Go is the ADR-033 comparator with Tomcat's keep-alive limit (`8d29301a`): it closes after the 400, as Java and Flint do, and passes 109/109 in the parity wire mode. Flint / Go, median (99% interval), 9 trials:
    - **p99 1.81 (1.72–1.92), which fails**: 389 against 215 µs. At B3 it was 3.23 against the comparator that kept connections; transport-pricing predicted about 1.85 under parity;
    - context: p50 1.095 (111 against 102 µs); CPU per request 1.41 (46.4 against 32.8 µs); capacity 0.797 (42,060 against 52,750 req/s; 0.227 at B3); RSS 0.72; p99.9 1.45.

    Evidence: `benchmarks/spring/evidence/error-validation-p99/20261125T100737Z/`.
- 2026-11-25, proof-harness: **error-404-p99 certified at B4** (`fb4c73d1adc7`, 10:59–11:39Z, interleaved from the start; no foreign activity). Go is the ADR-033 comparator with Tomcat's keep-alive limit (`8d29301a`): a chunked 404 with no reason phrase, 18/18 in the parity wire mode. Flint / Go, median (99% interval), 9 trials:
    - **p99 1.80 (1.55–1.87), which fails**: 236 against 131 µs (2.98 at B3: 340 against 114 µs, against the Content-Length comparator);
    - context: p50 1.43 (61 against 43 µs); CPU per request 1.55 (15.3 against 9.9 µs; 1.96 at B3); capacity 0.587; RSS 0.81; p99.9 3.70.

    Evidence: `benchmarks/spring/evidence/error-404-p99/20261125T105931Z/`.
- 2026-11-25, coordinator: **B5 = `8ed3de37dc5713907b163f778b629c09a1317d8e`**, named by proof-harness when scoreboard-B4 landed (pinned at c103021b).
  - **Contents:** the ThinLTO level fix (a8dc0aea, 8ba53b8f; decision dd774a24), so B5 is the first baseline whose release and size builds are optimised at link. It also includes the morning's landed slices: data-access R-61, R-63..R-65, R-76 and R-77; flint-aot S4, the error-page shortcut and 817b5d73, 3bd9d852, 43567442, d531a1ba, 40cfddfa, 34a9836e and d3e2e6c1 (S5, inert until web-http's POST hook); web-http R-67 and R-69; m7's std.format cuts and build-cache race fixes.
  - **Measurement:** every gated part is re-measured, builds ×3 then the four runtime parts. All run interleaved from the start, pending the owner's choice between interleaved and Flint-only. Comparators are unchanged since B4.
  - **GC parts:** B4's GC-matrix parts are superseded (O0 code) and re-pinned to B5, after the gated parts.
  - **B4 for the record:** scoreboard-B4 (8ed3de37) passes all 15 build metrics and every gs-rest runtime metric. Petclinic fails p50 1.048, p99 1.133 and CPU 1.044. Validation fails at p99 1.81 and the 404 at p99 1.80.
- 2026-11-25, proof-harness: **phase1-builds-gs-rest certified at B5** (`8ed3de37dc57`, 11:55–12:00Z, no foreign activity; strict served compiles, strict scratch). Java, Go (parity) and Flint 18/18, served binaries included. Served: 1,111 client-served, 18 c-source, 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials: primary 0.522 (84 against 161 ms); secondary 0.277; edit 0.326; static edit 0.588; **Oz 0.549** (0.624 at B4: the ThinLTO O3 fix, dd774a24). Evidence: `benchmarks/spring/evidence/phase1-builds-gs-rest/20261125T115517Z/`.
- 2026-11-25, proof-harness: **phase1-builds-gs-relational certified at B5** (`8ed3de37dc57`, 12:10–12:15Z, no foreign activity). 1/1 everywhere (Go in parity mode), served binaries included. Served: 1,023 client-served, 18 c-source, 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials: primary 0.019; deps-primed context 0.653; secondary 0.114; edit 0.549; static edit 0.782 (0.755–0.817); **Oz 0.627** (0.668 at B4, the O3 fix). Evidence: `benchmarks/spring/evidence/phase1-builds-gs-relational/20261125T121045Z/`.
- 2026-11-25, proof-harness: **phase1-builds-petclinic certified at B5** (`8ed3de37dc57`, 12:25–12:31Z, no foreign activity). 109/109 everywhere (Go in parity mode), served binaries included. Served: 2,445 client-served, 18 c-source, 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials: primary 0.198 (394 against 1,989 ms); secondary 0.493; edit 0.543; static edit 0.709; **Oz 0.889** (0.935 at B4, the O3 fix). Context: deps-primed 1.21. **All 15 gated build metrics pass at B5.** Evidence: `benchmarks/spring/evidence/phase1-builds-petclinic/20261125T122452Z/`.
- 2026-11-25, owner: **Boot's default GC heap growth factor becomes 3** (`heapSizeFactor:3`), keeping the fixed 1 MiB pools (`minPoolSize:1 incPoolSize:0`, bad399f3).
  - Evidence: posidon diagnostic sweep at B4, `benchmarks/spring/evidence/gc-heap-size-factor/posidon-20261125T082533Z/` (1aa899c8).
    - Factor 3 against druntime's default 2: petclinic owner p99 −7% at 0.88× Go peak RSS; gs-rest /nope p99 −9% at 0.83× Go; app CPU unchanged or slightly lower.
    - Factor 8 failed the RSS gate.
  - The setting is baked in by `packages/arena/source/flint/arena/sys/gc/fixed_pools.d`, which Boot imports. An application's `rt_options` and an operator's `--DRT-gcopt` still override it, as in Spring Boot, where JVM heap flags override defaults.
  - B5 (8ed3de37) measures factor 2. The change lands after it and is certified from B6.
- 2026-11-25, proof-harness: **phase1-http-petclinic certified at B5** (`8ed3de37dc57`, 12:41–13:21Z, interleaved from the start; no foreign activity). Go is the ADR-033 comparator with Tomcat's keep-alive limit (`8d29301a`), 109/109 in the parity wire mode. **Every gated runtime metric passes, for the first time on petclinic.** Flint / Go, median (99% interval), 9 trials:
    - **throughput 1.613 (1.608–1.621)**: 31,620 against 19,600 req/s (1.416 at B4);
    - **p50 0.830 (0.820–0.840)**: 198 against 238 µs (1.048 at B4);
    - **p99 0.899 (0.854–0.949)**: 525 against 584 µs (1.133 at B4);
    - **peak RSS 0.700 (0.654–0.707)**: 18.6 against 26.6 MB;
    - **CPU per request 0.824 (0.817–0.839)**: 53.6 against 65.1 µs (1.044 at B4);
    - p99.9 1.04, reported.

    B4's trees were ThinLTO-codegenned at O0; B5 has the O3 fix (dd774a24) and the fast path S5. Evidence: `benchmarks/spring/evidence/phase1-http-petclinic/20261125T124138Z/`.
- 2026-11-25, proof-harness: **phase1-http-gs-rest certified at B5** (`8ed3de37dc57`, 13:31–14:12Z, interleaved from the start; no foreign activity). Go 18/18 in the parity wire mode (`8d29301a`). **Every gated runtime metric passes.** Flint / Go, median (99% interval), 9 trials:
    - **throughput 1.861 (1.851–1.875)**: 439,600 against 236,170 req/s (1.451 at B4);
    - **p50 0.679 (0.668–0.689)**: 43 against 63 µs;
    - **p99 0.397 (0.382–0.409)**: 114 against 288 µs;
    - **peak RSS 0.673 (0.661–0.689)**: 9.5 against 14.1 MB;
    - **CPU per request 0.564 (0.557–0.568)**: 4.90 against 8.69 µs (0.718 at B4);
    - p99.9 0.81, reported.

    Evidence: `benchmarks/spring/evidence/phase1-http-gs-rest/20261125T133134Z/`.
- 2026-11-25, owner: **On the error-path workloads, the load-generator saturation check applies only to the gated fixed-rate phase.**
  - Background: B5 error-validation-p99 was refused at 14:24Z (008cc880). Flint's capacity phase reached 55,769 req/s; with a new connection per 400 (ADR-033), that saturated oha's four load CPUs.
  - Rule: when oha saturates in the capacity phase, it is recorded as "client-limited, context". The gated metric (p99 at the fixed rate) and its own saturation check are unchanged. No workload, CPU set or comparator changes, and Go's records stay valid.
  - Applies to error-validation-p99 and error-404-p99. proof-harness implements it and re-queues validation at B5.
- 2026-11-25, owner: **Per-exchange storage is pooled; a request or response retained past its exchange throws `IllegalStateException` (option (a))**, as Tomcat does with `RECYCLE_FACADES=true`. Servlet 6.0 §3.13 makes request objects valid only within `service`/`doFilter` and lets containers recycle them.
  - Design: `coordination/notes/exchange-pool.md` (web-http). It is the top error-path lever in `docs/spring/phase1/gc-tail-astra.md`: about 3.4 KB of /nope's 5.2 KB per request.
  - Never acceptable: a retained façade seeing another exchange's data.
  - m7's required changes, before slice 1:
    - R1: a seqlock generation check, bumped at return and at checkout;
    - R2: the check covers every object reaching pooled storage (streams, writers, header, attribute and parameter views, cookies, parts);
    - R3: body readers are covered too;
    - R4: storage returns only after the final write completes, and is never handed to the reactor by reference;
    - R5: the pool holds only free states, and a return is idempotent per generation;
    - R6: each state is its own GC block.
  - Retained RSS is capped. m7 reviews every slice before it lands; the 30-minute rule does not apply.
- 2026-11-25, proof-harness: **error-404-p99 at B5 voided** (results `20261125T143428Z`, coordinator 15:12Z). An unheld `dub build :tx --compiler=dmd` (data-access, taskset CPUs 0–3, about 14:59:30–15:00:50Z) overlapped Flint trial 5's fixed-rate phase (14:59:14–15:00:14Z) and capacity phase. The receipt counted the run as evidence with 0 foreign samples: freeze-strays never freezes compilers, and the 10 s busy sampler did not see the build. The run is marked `VOID.json` (`spring_bench.certified_results` skips it), is not re-run at B5, and is deferred to B6 with validation.
- 2026-11-25, coordinator: **B6 = `be86e77f76512c680a004f9389889d6023e3ecab`**, named by proof-harness when scoreboard-B5 landed (pinned at fc5f127c).
  - **Contents beyond B5:**
    - Boot's heapSizeFactor:3 (05397ca6);
    - S5 live (dcee361d), lean S6 (f028e7c0) and the hand-back lookup cut (9b5b9c0b);
    - data-access R-79 and R-84..R-87, R-92;
    - web-http R-80, R-83, R-90, R-93;
    - third-party-apis rounds 1–2;
    - m7's registry flattening (R-91);
    - the error-path client-limit rule (44d970c1; decision ae7858f8).
  - **Measurement:** every gated part, all interleaved from the start. The GC-matrix parts follow on natural quiet.
  - **scoreboard-B5 for the record:** every gated build and HTTP runtime metric of both apps passes. Both error paths are deferred to B6: validation by the harness rule, and the 404 voided as contaminated by an unheld build.
- 2026-11-25, proof-harness: **phase1-builds-gs-rest certified at B6** (`be86e77f7651`, 15:24–15:30Z, no foreign activity; strict served, strict scratch). 18/18 everywhere (Go in parity mode), served binaries included. Served: 1,111 client-served, 18 c-source, 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials: primary 0.499 (82 against 165 ms); secondary 0.278; edit 0.337; static edit 0.591; Oz 0.549. Evidence: `benchmarks/spring/evidence/phase1-builds-gs-rest/20261125T152433Z/`.
- 2026-11-25, proof-harness: **phase1-builds-gs-relational certified at B6** (`be86e77f7651`, 16:19–16:23Z, no foreign activity; the soak window of the freezer safeguards, 87b68463, with compiler freezing in log-only mode: 0 would-freeze entries and 0 foreign samples across the run's own served builds). The 15:40Z run is void (the freezer race froze its own Go compile). 1/1 everywhere (Go in parity mode), served binaries included. Served: 1,023 client-served, 18 c-source, 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials: primary 0.019; secondary 0.116; edit 0.519; static edit 0.749 (0.725–0.792); Oz 0.626. Evidence: `benchmarks/spring/evidence/phase1-builds-gs-relational/20261125T161939Z/`.
- 2026-11-25, proof-harness: **phase1-builds-petclinic certified at B6** (`be86e77f7651`, 16:33–16:40Z, no foreign activity; the first window with compiler freezing in normal mode: nothing frozen). 109/109 everywhere (Go in parity mode), served binaries included. Served: 2,445 client-served, 18 c-source, 0 refused. **Every gated build metric passes**, median (99% interval), 9 trials: primary 0.193 (389 against 2,008 ms); secondary 0.475 (0.470–0.801); edit 0.540; static edit 0.700; Oz 0.889. **All 15 gated build metrics pass at B6.** Evidence: `benchmarks/spring/evidence/phase1-builds-petclinic/20261125T163316Z/`.
- 2026-11-25, proof-harness: **phase1-http-petclinic certified at B6** (`be86e77f7651`, 16:50–17:30Z, interleaved; no foreign activity, nothing frozen). Go 109/109 in the parity wire mode (`8d29301a`). **Every gated runtime metric passes.** Flint / Go, median (99% interval), 9 trials:
    - **throughput 1.649 (1.635–1.659)**: 32,360 against 19,620 req/s (1.613 at B5);
    - **p50 0.823 (0.816–0.829)**: 197 against 239 µs;
    - **p99 0.828 (0.815–0.897)**: 489 against 590 µs (0.899 at B5; B6 is the first tree with heapSizeFactor:3);
    - **peak RSS 0.740 (0.736–0.764)**: 19.8 against 26.8 MB (0.700 at B5, the heap factor's cost);
    - **CPU per request 0.809 (0.806–0.817)**: 52.6 against 65.1 µs;
    - p99.9 0.99, reported.

    Evidence: `benchmarks/spring/evidence/phase1-http-petclinic/20261125T165002Z/`.
- 2026-11-25, proof-harness: **phase1-http-gs-rest certified at B6** (`be86e77f7651`, 17:40–18:20Z, interleaved; no foreign activity, nothing frozen). Go 18/18 in the parity wire mode. **Every gated runtime metric passes.** Flint / Go, median (99% interval), 9 trials: **throughput 1.846 (1.833–1.855)**, 437,590 against 237,010 req/s; **p50 0.683 (0.679–0.696)**; **p99 0.384 (0.380–0.404)**, 110 against 286 µs; **peak RSS 0.758 (0.741–0.769)**, 10.6 against 14.0 MB (0.673 at B5, heapSizeFactor:3); **CPU per request 0.568 (0.564–0.573)**, 4.91 against 8.64 µs; p99.9 0.77, reported. Evidence: `benchmarks/spring/evidence/phase1-http-gs-rest/20261125T173958Z/`.
- 2026-11-25, proof-harness: **error-validation-p99 certified at B6** (`be86e77f7651`, 18:30–19:10Z, interleaved; no foreign activity, nothing frozen). Go is the parity comparator (`8d29301a`), 109/109. **The gated p99 passes for the first time.** Flint / Go, median (99% interval), 9 trials:
    - **p99 0.896 (0.862–0.932), which passes**: 190 against 213 µs (1.81 at B4);
    - context: p50 0.722 (73 against 101 µs); CPU per request 0.768 (25.1 against 32.6 µs; 1.41 at B4); RSS 0.73; p99.9 1.11;
    - capacity 1.488, a lower bound: Flint's capacity phase was client-limited in all 9 trials (oha saturated at a connection per request) and is recorded as context under owner decision ae7858f8; Go's was not.

    Evidence: `benchmarks/spring/evidence/error-validation-p99/20261125T183025Z/`.
- 2026-11-25, owner: **Rule: a class's metadata object (`typeid(X)`, `X.classinfo`, any `TypeInfo`) never owns a GC-allocated monitor.** No `new Mutex(<TypeInfo/ClassInfo>)` and no `setSameMutex` that gives one a GC mutex. `synchronized(typeid(X))` stays allowed (C-heap monitor).
  - Purpose: the collector stops scanning class metadata and other provably pointer-free static data on every collection (m7's static-data census). That is about 25 µs of the 404's ~123 µs pause and about 48 µs of petclinic's. No metadata is removed or changed: only what the GC reads.
  - The owner requires certainty that nothing breaks and the development experience is unaffected. So the rule is enforced three ways:
    1. A semantic build-time gate (typed, not textual): any `Mutex` construction or `setSameMutex` whose argument is a TypeInfo/ClassInfo, in app, framework or dependency code. It fails with file:line and the fix.
    2. A verify mode, on by default in debug and test profiles and in every app's `flint test`: each collection also checks every ClassInfo monitor word, and aborts with the class name if one points into the GC heap.
    3. Release: a startup validation of the build-time `.data` map, with a fallback to whole-range scanning if it's missing or mismatched. `FLINT_GC_STATIC_TRIM=0` turns trimming off.
  - Acceptance:
    - full framework and app suites pass in verify mode on DMD and LDC;
    - 109/109, 18/18 and 1/1;
    - negative tests prove that both the gate and the verifier catch a violation;
    - dev, edit and static-edit build times are unchanged within noise.
- 2026-11-25, coordinator: **B7 = `43db0cae5fbc57f5f6035ab97f3d6d6caf3ac5f6`**, named when flint-aot's template 404 landed (R-100), pinned at 83e811d7. The owner chose to skip B6's 404 and go straight to B7 (20:15Z).
  - **Contents beyond B6:**
    - the exchange pool, slices 1–2 (R-94, R-97);
    - full S6 and the template 404: /nope at O3 is 17,850 instructions with 0 allocations and 0 bytes per request (B4: 67,752 / 27 / 5,216);
    - the validation cuts (R-99 and third-party-apis);
    - R-96, R-95;
    - the sampler/freezer fixes (7ad165cc, 87b68463, 45095ca7).
  - **Order:** the deciding part first: 404, validation, petclinic, gs-rest, builds ×3, all interleaved. GC-matrix last.
- 2026-11-25, proof-harness: **error-404-p99 certified at B7** (`43db0cae5fbc`, 20:11–20:55Z, interleaved; no foreign activity, nothing frozen, under the tightened sampler and freezer). B7 carries flint-aot's template 404 (43db0cae). Go is the parity comparator (`8d29301a`): a chunked 404 with no reason phrase, 18/18. **The gated p99 passes for the first time.** Flint / Go, median (99% interval), 9 trials:
    - **p99 0.558 (0.495–0.623), which passes**: 77 against 139 µs (1.80 at B4, 2.98 at B3);
    - context: p50 0.679 (29 against 43 µs); CPU per request 0.527 (5.27 against 10.0 µs; 1.55 at B4); throughput 2.046; RSS 0.64; p99.9 2.01, reported.

    With this part, **every gated runtime target of Phase 1 has passed at least once.** Evidence: `benchmarks/spring/evidence/error-404-p99/20261125T201109Z/`.
- 2026-11-25, owner: **Phase 1 closes on performance at B7, and Phase 2 porting moves to an autonomous agent (gpt-6.2-sol) behind CI guardrails.** Plan (a):
  1. **Finish B7's gated parts** (validation, petclinic, gs-rest, builds ×3). If all pass, Phase 1's performance claim is certified at one commit: every gated metric beats Go, with byte-identical output against Java.
  2. **Defer the rest of the exit ledger, without blocking anything:** the GC-matrix parts, framework timings, Java context, platform-lane receipts and `docs/milestones/13.md`. They run in natural quiet or later, and are no longer on the critical path.
  3. **Build CI guardrails first (about a day), so an autonomous porter is steered by failing checks rather than by review:**
     - `flint budget`: per-endpoint instruction, allocation and byte budgets from deterministic counts, failing CI on regression;
     - a per-module definition of done: API-coverage, structural, allocation and acceptance gates, upstream tests ported, and budgets set for each new request shape;
     - the performance playbook's rules and today's lessons as agent instructions: bytes per request decide GC tails; no per-request locks or allocations in caches; proved fast paths with fallback; the ClassInfo-monitor rule (e170ffd0); exchange-storage lifetime (8cb4beb8).
  4. **Then gpt-6.2-sol ports Phase 2 module by module,** each in its own worktree. Existing sessions review anything touching the shared engines (reactor, HTTP, GC, AOT); venus certifies at baselines.
- 2026-11-25, proof-harness: **error-validation-p99 certified at B7** (`43db0cae5fbc`, 21:55–22:36Z, interleaved; no foreign activity). The freezer stopped one stray at the claim, another session's callgrind, and thawed it at window end. The first attempt (21:05–21:45Z) is not evidence: an unheld python3 from another session ran 0.44 s of CPU inside the window. Go is the parity comparator (`8d29301a`), 109/109. Flint / Go, median (99% interval), 9 trials:
    - **p99 0.810 (0.780–0.835), which passes**: 173 against 213 µs (0.896 at B6, 1.81 at B4);
    - context: p50 0.703 (71 against 100 µs); CPU per request 0.728 (23.5 against 32.3 µs; 0.768 at B6); RSS 0.75; p99.9 1.045, reported;
    - capacity 1.612 is a lower bound: as at B6, Flint's capacity phase was client-limited in all 9 trials and is recorded as context (owner decision ae7858f8); Go's was not.

    Evidence: `benchmarks/spring/evidence/error-validation-p99/20261125T215555Z/`.
- 2026-11-25, proof-harness: **phase1-http-petclinic certified at B7** (`43db0cae5fbc`, 22:46–23:25Z, interleaved; no foreign activity, nothing frozen). Go 109/109 in the parity wire mode (`8d29301a`). **Every gated runtime metric passes again.** Flint / Go, median (99% interval), 9 trials:
    - **throughput 1.662 (1.653–1.666)**: 32,550 against 19,580 req/s (1.649 at B6);
    - **p50 0.820 (0.809–0.838)**: 195 against 238 µs;
    - **p99 0.812 (0.790–0.856)**: 467 against 575 µs (0.828 at B6);
    - **peak RSS 0.758 (0.752–0.772)**: 20.3 against 26.7 MB;
    - **CPU per request 0.810 (0.800–0.821)**: 52.6 against 64.9 µs;
    - p99.9 1.115 (0.917–1.646), reported.

    Neither side's capacity phase was client-limited. Evidence: `benchmarks/spring/evidence/phase1-http-petclinic/20261125T224601Z/`.
- 2026-11-25 23:50Z, owner: **Phase 1 closes now; Phase 2 starts at once.** In the owner's words: "we are good … we can fix stuff later after we complete all the original library work since ci and benching is the thing that takes the longest." This amends 087f28a3:
  - **B7's remaining parts no longer gate the close.**
    - phase1-http-gs-rest was already measuring; it is recorded here if it certifies clean.
    - builds ×3 and the GC matrix are cancelled.
    - The close-out cites B6 (`be86e77f`) for gs-rest runtime and all 15 build metrics, where every one passed, and B7 (`43db0cae`) for the 404, validation and petclinic runtime.
    - **The performance claim is therefore "every gated metric passed at a certified baseline (B6 or B7)", not "at one commit".** [closeout.md](closeout.md) states this plainly.
  - **venus certification stops blocking development.** It runs only on request, or overnight in natural quiet. MEASURING is released after gs-rest, so held builds are no longer paused.
  - **Guardrails:**
    - **`flint budget` no longer gates the start.** Phase 2 starts behind the definition of done, the allocation gates (now with the forced static trim) and the playbook.
    - m7 lands `flint budget` as soon as it is seeded; from then on every lane must pass it.
  - **Phase 2 runs on gpt-6.2-sol** in three parallel lanes: data, security, context and client ([../phase2/launch-plan.md](../phase2/launch-plan.md)). The existing Claude sessions review shared-engine changes.
- 2026-11-26, proof-harness: **B7 closed partial; Phase 1 closes on performance** (owner decision relayed by the coordinator, 2026-11-25 23:48Z).
    - **Certified at B7:** error-404-p99, error-validation-p99 and phase1-http-petclinic, all passing.
    - **Not evidence:** phase1-http-gs-rest (23:35–00:15Z) was busy, from an unheld `python3` from worktree eloquent-yalow-66198e at 23:50:25Z (1 CPU tick). The coordinator's self-reported `agentctl roles` at 23:46Z does not appear in the samples. Per the decision it is not retried.
    - **Cancelled and blocked in the queue:** phase1-builds ×3 and the six GC-matrix parts.
    - **Close-out:** [closeout.md](closeout.md) (coordinator) cites B6 for builds and gs-rest's runtime and B7 for the rest; every gated metric passes at a certified baseline.
    - **From now on:** venus claims no windows. MEASURING is released, and certification runs only on request or in natural quiet.
- 2026-11-26 00:25Z, owner: **launch Phase 2's wave 2 now**, not after wave 1 lands a module. The new lanes are sol-observability, sol-template, sol-jpa and sol-ai, for seven lanes in all.
  - **Reason:** the git history shows the Phase 1 port went from 0 to 6,923 classified elements (about 6.4 MB of D) between 04:00 and 10:00Z on 2026-11-23, with about ten sessions. Parallelism, not difficulty, sets the pace.
  - **sol-jpa:** its ADR still goes to the owner before any engine code lands.
- 2026-11-26 00:45Z, coordinator: **the upstream-tests step of the definition of done gets a `deferred` status, a seed command and a ratchet.**
  - **Why:** no Phase 1 module has an `upstream-tests.json`; context alone has 184 unrecorded upstream test classes. The step therefore fails every Phase 2 lane that touches a Phase 1 module, for debt that predates it.
  - **The rule mirrors the API gate's existing one:**
    - `deferred`, with its phase, passes the normal check and fails under `--release`;
    - the seed records missing classes as `deferred` and never overwrites a recorded entry;
    - a module's deferred count may only shrink, like the quality baseline.
  - **No bar is lowered:** no module passed this step before. proof-harness implements the change and seeds the Phase 1 modules.
- 2026-11-26 00:50Z, coordinator: **partial slices.**
  - **Every landed slice** must pass the normal definition of done.
  - **`--release` is the "module complete" check.** What a lane hasn't ported yet is recorded as `deferred` with its phase, in both api mappings and upstream-tests, as api/framework already does. It is never left unclassified.
  - **Deferred counts only shrink.**
  - **api-coverage seeds the newly pinned upstreams:** spring-ai, Thymeleaf and Jakarta Persistence.
  - The porting guide, step 5, now says this.
- 2026-11-26 00:55Z, owner: **ADR-034 (JPA engine) is approved as proposed.** It ports Hibernate ORM 7.1.0 (02eb1ac3), with build-time mappings, accessors, proxies and JPQL.
  - **Limits:** a JPA petclinic-rest variant runs within 1.05× of the `JdbcTemplate` version's instructions and p99, keeps at least 0.95× its throughput, and adds no GC allocation for engine bookkeeping.
  - **Scope:** PostgreSQL first.
  - **Landing:** engine code lands after data-access and flint-aot agree the JDBC, transaction and AOT contracts. sol-jpa marks the ADR Accepted.
  - **Still open:** classic PetClinic's Go comparator needs its own owner decision later.
- 2026-11-26 00:55Z, owner: **context's linked-bytes cap rises to 1,196,032 B,** from 966,656 B, which is the measured 1,086,712 B at b29e4cba plus 10%, rounded up to 4 KiB.
  - **Why:** context was 12% over its 2026-11-23 cap before any Phase 2 code, so every sol-context slice failed the budgets step.
  - **The cap only goes down from here.** framework-core looks for recoverable growth, and lowers the cap to match what it recovers.
  - **The commit that raises the cap** carries `Budget-Raise-Approved: <this entry's commit>`.
- 2026-11-26 01:00Z, owner: **standing approval for Phase 2 lanes' approval requests.** In the owner's words: "any time sol looks for an approval review it and if it good approve it."
  - **Who decides:** the coordinator reviews each request that would otherwise wait for the owner (ADRs, budget raises with evidence, rulebook deviations, design and policy questions), and approves it on its merits.
  - **Recording:** each approval is recorded here as "coordinator, under the owner's standing approval".
  - **Still asked of the owner first:**
    - creating or deleting repositories, and other outward-facing or irreversible actions;
    - deleting another session's work;
    - D language or shared-toolchain changes;
    - changes to a certified workload, the TLS profile or a Go comparator.
- 2026-11-26 01:00Z, coordinator, under the owner's standing approval: **D-MICROMETER-1 is approved** (sol-observability, ad531599).
  - **The change:** Micrometer's `Tags`, a Java `final class`, becomes an abstract class with a module-private constructor and private final implementations.
  - **Why it's equivalent:** users can neither subclass nor construct it, and the static API is unchanged.
  - **What it buys:** an allocation-free canonical empty set (R-109).
  - **Null overloads** use typed null under D-7.
- 2026-11-26 01:05Z, coordinator, under the owner's standing approval: **sol-template's upstream-tests baseline for the expression module is approved.** It records 49 classes:
  - LiteralTests, partial;
  - 44 deferred to phase 2;
  - 1 abstract fixture, excluded;
  - 3 SpelCompiler classes, excluded because they test JVM bytecode generation.

  **Condition:** their behavioural cases (compiled result equals interpreted result) must be ported against Flint AOT's SpEL compilation when it lands.
- 2026-11-26 01:07Z, coordinator, under the owner's standing approval: **seeding a module's upstream-tests baseline is pre-approved,** for new modules and for newly owned classes, on three conditions:
  - every class not yet ported is `deferred` with its phase;
  - every `excluded` class has a concrete reason;
  - nothing recorded as ported or partial is downgraded.

  **Still needs the coordinator's approval:** a downgrade, or an exclusion without a concrete reason. **First use:** micrometer-core (sol-observability).
- 2026-11-26 01:15Z, coordinator, under the owner's standing approval:
  - **D-DATA-2 (sol-data): approved.** Data Commons' initial scroll positions compare by value and are created by factories, where Java caches the instances.
  - **D-DATA-3 (sol-data): approved.** Typed property paths and the typed sort use D getter aliases where Java uses method references, with no runtime proxies.
  - **sol-ai: approved.** A narrow `-flint.ai.chat.messages.part` entry in `dscanner.ini`'s `object_const_check`, consistent with the existing Spring-namespace exemptions. Engines stay checked.
- 2026-11-26 01:20Z, coordinator: **context's cap raise (0168bca6) is not applied.** framework-core traced the overage to a Phobos link cascade rather than module growth, so the caps stay as they are.
  - **The cascade:** an LTO link resolves a template instance from the first Phobos archive member that defines it. That member drags in about 300-450 KB: std.net.curl, std.socket, regex, zip and more.
  - **The two triggers:** `flint.util`'s use of std.uni, and engine-reactor's `Thread.sleep(25.msecs)`.
  - **With both fixed:** context is 583 KB, beans 243 KB and core 11 KB, all well under their existing caps.
  - **Owner's decision kept:** "only goes down" is respected; this simply removes the need to go up.

- 2026-11-26 00:56Z, sol-observability: D-MICROMETER-1's empty-tag rule is now R-113. SpEL keeps R-109 after the parallel landings assigned the same number.
- 2026-11-26 01:10Z, coordinator: **re-verification after a rebase.**
  - **Why:** main moves every few minutes with seven lanes, and a full app gate takes several, so lanes kept re-running full gates after each rebase.
  - **The rule:** a slice whose full definition of done passed before the rebase re-runs only the cheap steps when the incoming commits touch nothing in its dependency closure or its apps. The cheap steps are resolve, structural, quality, api, upstream-tests and its own DMD/LDC tests. If the incoming commits touch either, the full definition of done runs again.
  - **Recording:** the lane says which path it took.
- 2026-11-26 01:20Z, coordinator, under the owner's standing approval: **`incremental_linked_bytes` measures loadable section bytes, not the stripped file size.**
  - **Why:** file deltas are quantised to 4 KiB pages. framework-core showed ai-model's probe reading 56 → 4,152 B while its real loadable bytes went 264 → 272.
  - **The caps are unchanged.** This corrects a measurement artefact; it does not loosen any cap. m7 implements it.
- 2026-11-26 01:20Z, coordinator: **the 1.19× and 0.889 size gaps get a lever.** framework-core removes the remaining triggers of the Phobos link cascade (std.socket, std.uni, std.net.curl) from gs-rest and petclinic, one trigger per commit, measuring app Oz before and after.
  - **Starting point:** cf17a00b's case tables currently add 16 KB to gs-rest and 8 KB to petclinic, duplicating std.uni. They will be halved.
- 2026-11-26 01:25Z, coordinator, under the owner's standing approval: **D-JPA-2 (sol-jpa) is approved.** `LockModeType` is a D enum with Java's values and NONE as the `@NamedQuery` default, so the annotation remains compile-time metadata.
  - **Why it deviates:** Java's enum also implements `FindOption` and `RefreshOption`, which a D enum cannot.
  - **How calls stay Java-shaped:** `EntityManager`'s option overloads accept the built-in enum values at that boundary.
- 2026-11-26 01:35Z, owner: **port the Java SE standard library parts that Spring and its applications use,** as a one-time tax, optimised so that an application links only what it uses ([../phase2/jdk-port.md](../phase2/jdk-port.md)).
  - **Lanes:** four gpt-6.2-sol lanes: sol-jdk-core, sol-jdk-time-text, sol-jdk-math-regex and sol-jdk-concurrent-io.
  - **Licence:** OpenJDK is GPL-2.0 with the Classpath Exception, so the implementation is clean-room from the specification, and only API signatures are extracted. Apache Harmony (Apache-2.0) may be ported.
  - **Excluded:** UI libraries and JVM-only facilities (reflection, class loading, serialization, RMI, JMX and the like).
  - **Enforcement:** a link-closure gate, built first, checks every JDK leaf's linker map against its declared closure and the banned Phobos families.
- 2026-11-26 01:32Z, coordinator: **apps landing slot.** A change that touches gs-rest's or petclinic's dependency closure lands only while its role holds `agentctl claim apps-landing` (40-minute lease). The holder rebases, runs the full definition of done and pushes, then releases the slot.
  - **Why:** sol-observability's Actuator slice passed five full candidates, and each push raced another closure change.
  - **Changes outside the closure** land under the cheap-rebase rule, without the slot.
- 2026-11-26 01:38Z, coordinator, under the owner's standing approval: **D-SPEL-1 (sol-template) is approved.** SpEL's `TypedValue` becomes a value struct, so evaluation steps allocate nothing.
  - **Calls:** `new TypedValue(v)` becomes `TypedValue(v)`.
  - **BooleanTypedValue** becomes a factory returning `TypedValue`.
  - **Unchanged:** `TypedValue.NULL`, `equals` and `toString` keep Java's semantics.
- 2026-11-26 01:40Z, coordinator: **D-SPEL-2 (sol-template) is not approved.** It would have required `nothrow @nogc` on `EvaluationContext` methods, restricting user implementations.
  - **Instead:** porting-guide rule 7. The evaluator takes a `@nogc` fast path for Flint's own final contexts and a generic GC-allowed path for any other implementation, with parity tests.
  - **No deviation is needed.**
- 2026-11-26 01:42Z, coordinator, under the owner's standing approval: **D-DATA-4 (sol-data) is approved.**
  - **The clash:** only on `Window!int`. Java tells `positionAt(int index)` from `positionAt(Integer item)` by boxing, which R5 erases.
  - **The resolution:** `positionAt(index)` keeps Java's index meaning, and element lookup is `positionAt!int(item)`.
  - **Tests (R7):** they assert Java's choice for both calls.
- 2026-11-26 01:45Z, coordinator, under the owner's standing approval: **budgets for the Java standard library packages (`jdk-leaf-rule`).**
  - **Per leaf:** each JDK leaf has its own loadable-byte and template budget for its single-leaf probe, set at the measured value plus 10%. After that it only shrinks.
  - **Per package:** a package's budget is the sum of its leaves' budgets. Adding a leaf may raise it by exactly that leaf's budget, with the trailer `Budget-Raise-Approved: jdk-leaf-rule`.
  - **Anything else:** any other growth needs a raise request with evidence.
- 2026-11-26 01:50Z, coordinator, under the owner's standing approval: **D-DATA-5 (sol-data) is approved.** `Range.unbounded()` and `Bound.unbounded()` return value-equal instances rather than one shared object.
  - **A general rulebook rule follows:** shared singleton instances of generic classes with fields become value-equal per instantiation, and reference identity is not preserved. api-coverage adds it.
- 2026-11-26 01:52Z, coordinator, under the owner's standing approval: **empty arrays.** A zero-length D array or slice, null or not, means Java's empty array; for example, `BigInteger` with a zero-length magnitude throws Java's `NumberFormatException`.
  - **Java's NullPointerException for a null required array** is dropped, as R5 already does for strings.
  - **Where Java gives null its own meaning,** such as an optional array parameter, `Nullable!(T[])` is used.
  - api-coverage records this as an R5 clarification.
- 2026-11-26 01:52Z, coordinator: **until m7 lands the loadable-section metric,** JDK leaf budgets (`jdk-leaf-rule`) are set in the definition of done's current stripped-byte metric, at the measured value plus 10%. Every JDK leaf is re-baselined in loadable bytes in one commit when the switch lands.
- 2026-11-26 01:55Z, coordinator, under the owner's standing approval:
  - **`java.net.URL.equals` and `hashCode` never resolve DNS.** They compare normalised components only.
    - **Why:** Java's DNS-based equality blocks on network I/O inside `equals`, which is incompatible with fibers, and makes hashing nondeterministic.
    - **Recorded as** a deviation by sol-jdk-concurrent-io. `URI` keeps Java's semantics.
  - **R5 now covers nullable value types** (for example `Persistable!long.getId()` returns `Nullable!long`). `Optional!T` stays reserved for `java.util.Optional`.
- 2026-11-26 01:58Z, coordinator, under the owner's standing approval:
  - **Pre-approved:** narrow `object_const_check` exclusions in `dscanner.ini` for Spring, Jakarta and Java API namespaces, each in its own commit with a reason.
    - **Why:** Java's `toString`, `equals` and `hashCode` on Object references cannot be `const` in D.
    - **Never excluded:** engines (`flint.engine.*`, arena, conc, `packages/*`).
  - **JDK lanes don't hold slices for module-ref retention** that comes only from today's aggregate `flint.java.lang` import. It is baselined in the closure gate's ratchet, and sol-jdk-core's split removes it.
- 2026-11-26 02:00Z, coordinator, under the owner's standing approval: **`new-module-rule`.**
  - **First caps:** a new module's first caps are its measured linked bytes and templates plus 10%, cited by receipt, with the trailer `Budget-Raise-Approved: new-module-rule`.
  - **After that:** caps only shrink.
  - **First use:** engine-jpa, at 4,840 B and 1,305 templates.
- 2026-11-26 02:03Z, coordinator, under the owner's standing approval: **`api-growth-rule`.**
  - **What it allows:** an API module (not an engine) whose cap is reached only by newly ported public API may raise the cap by that slice's measured delta plus 10%.
  - **Conditions:** the commit proves the delta comes from the new declarations (probe with and without them, nothing existing grew), and carries the trailer `Budget-Raise-Approved: api-growth-rule` with the numbers.
  - **Not covered:** growth of existing code, or an avoidable implementation cost, still needs a request.
  - **First use:** sol-ai's RateLimit, +51 templates, so ai-model's template cap goes from 1,200 to 1,260.
- 2026-11-26 02:12Z, owner: **keep the three pre-approved budget-raise rules** (`new-module-rule`, `api-growth-rule`, `jdk-leaf-rule`).
  - **This amends owner decision 3** (2026-11-23, "template budgets only go down"). A raise is allowed only in a commit carrying `Budget-Raise-Approved: <id>`, naming one of these rules (`policy/budget-raise-rules.json`) or a recorded decision. `tools/template_budget_ratchet.py` enforces it (30a78ed3).
  - **Every other raise** still needs a reviewed request with evidence.
- 2026-11-26 02:33Z, coordinator, under the owner's standing approval: **page-boundary crossings before the loadable-section metric lands.**
  - **The rule:** when a slice's stripped-byte probe jumps by a 4 KiB page, but its measured loadable-section growth is small and comes only from newly ported API, the stripped cap may rise to the new stripped value plus 10%. The commit cites both numbers, with the trailer `Budget-Raise-Approved: <this entry's commit>`.
  - **Expiry:** every such cap is re-baselined in loadable bytes when m7's metric switch lands (planned around 06:00Z), and this rule expires then.
  - **First case:** sol-jdk-math-regex's BigInteger float and double conversions: stripped 19,288 → 23,440, loadable +1,256 B at O3 and +1,200 B at Oz, no template growth.
- 2026-11-26 02:40Z, coordinator: **no compiler flags in package recipes.** DUB propagates a package's flags to every consumer, so they silently change how applications compile. Compiler-flag policy lives in the release profiles (`profiles.toml`), measured on both apps.
  - **First case:** sol-jdk-concurrent-io's `--linkonce-templates` was refused. Its cross-leaf `RTInfoImpl` finding is baselined in the closure ratchet instead.
  - **Next:** m7 evaluates `--linkonce-templates` as a profile-wide LDC setting, measuring size, build time and closure-gate violations.
- 2026-11-26 02:47Z, coordinator: **the loadable-section metric is live** (520f8f11).
  - **Expired:** the interim page-crossing rule (94badfcf).
  - **JDK leaves:** byte caps are re-baselined in loadable bytes at measured plus 10%, one commit per package, under `jdk-leaf-rule`.
- 2026-11-26 02:55Z, owner: **use every machine, and add lanes.**
  - **posidon** (olfa@10.10.10.12, i7-11700K): it becomes the landing machine. Its m7-GC reservation is lifted. proof-harness's merge train runs the combined apps verification and `flint budget` there, and pushes to GitHub from venus.
  - **venus** stays the development machine.
  - **Four new gpt-6.2-sol lanes, for 15 in all:**
    - sol-framework: spring-core, spring-beans and spring-context remainders; framework-core reviews;
    - sol-boot: Boot core and auto-configuration; boot reviews;
    - sol-jackson: Jackson's tree model and features; third-party-apis reviews;
    - sol-web: spring-web and webmvc remainders; web-http reviews.
- 2026-11-26 03:05Z, coordinator: **`flint budget` lands now.** gs-rest's 18 endpoints are seeded as measured. petclinic's 13 endpoints that rose 0.50–1.23% since the 83ed6a19 seed are seeded at their current values and marked "under attribution", so main stays green and further growth is caught. After m7's bisect, they return to 83ed6a19 values unless the cause was a deliberate trade.
- 2026-11-26 03:05Z, owner: **integration across all five machines** ([../phase2/integration.md](../phase2/integration.md)). venus develops. posidon, the owner's desktop (10.10.10.122) and 10.10.10.116 become merge-train verifiers, run speculatively in parallel with strict landing order. posidon alone runs `flint budget`, and pluto keeps the macOS lane.
- 2026-11-26 03:30Z, coordinator, under the owner's standing approval: **`metric-rebaseline`.**
  - **What it allows:** a byte cap set in the old stripped-file metric during Phase 2 may be re-baselined once in loadable bytes, at the measured value plus 10%. The same executables are measured in both metrics, and the commit carries the trailer `Budget-Raise-Approved: metric-rebaseline`.
  - **Not covered:** caps that predate Phase 2.
- 2026-11-26 03:33Z, coordinator, under the owner's standing approval: **modules over their cap on main only because of the known Phobos cascade** (S-9: web, and any other module whose probe shows the std.socket, curl, regex or zip cascade) **use a base-relative ratchet until the cascade is gone.**
  - **The test:** a slice passes the budgets step if its candidate's loadable bytes and templates are at most main's base plus the slice's own growth under the existing rules (`api-growth-rule` and the like), measured on the same machine and recorded in the commit message.
  - **The caps are unchanged.**
  - **Expiry:** the exception ends for a module when its probe no longer links the cascade, after which the module must fit its cap.
  - **Why:** web's 126,976 B cap was set when the probe baseline also linked Phobos I/O. Probes switching to C output (55f6747c) exposed about 420 KB of cascade that the S-9 owners (boot, framework-core, data-access, web-http) are removing now.
- 2026-11-26 03:55Z, coordinator, under the owner's standing approval: **throughput changes.**
  - **Bigger slices:** 30–100 elements each.
  - **No local apps step** for slices going to the merge train; the train runs the apps on the verifiers.
  - **Batched train submissions.**
  - **For the train (proof-harness):** union merge for append-only docs, and an `agentctl id next` allocator for playbook and deviation IDs.
  - **Three more lanes, 18 in all:**
    - sol-translator: a deterministic Java-to-D translator for mechanical element kinds (plan section 8.4);
    - sol-test: spring-test and boot-test;
    - sol-aop: spring-aop with AOT proxies.
  - **Machines:** neptune's winbuild VM was force-stopped (owner) so neptune can serve as verifier C.
- 2026-11-26 04:05Z, coordinator, under the owner's standing approval: **R15 (enums with fields) is adopted** from the web-mvc proposal, minus its interface clause, which R18 now covers.
  - **The rule:** such an enum becomes a struct with `static immutable` constants and Java's enum methods.
  - **The enum rules are now complete:** constant-only enums stay D enums (R15), enums with methods are covered by R20, enums with interfaces by R18, and enums with fields by R15.
- 2026-11-26 04:08Z, coordinator, under the owner's standing approval: **D-AOT-MEMBER, the one shared deviation for Java reflection members.**
  - **The mapping:** `AccessibleObject` and `Member` map to engine-aot's `MemberDescriptorRef`, with the declaring descriptor, the kind, a safe pointer for method, constructor or property, and `.init` when absent.
  - **Scope:** only metadata that Flint AOT generates is exposed. Missing categories throw `UnsupportedOperationException` until the generator adds them; no reflection is used.
  - **Ownership:** framework-core owns the type, and every lane cites this deviation.
- 2026-11-26 04:20Z, owner: **GitHub Actions are never run remotely,** and no self-hosted runner is registered. Workflows are run locally with `act` when wanted. Required checks are enforced on Flint's own machines: the module definition of done on venus, and the merge train, with the apps verification and `flint budget`, on posidon, the desktop and neptune.
- 2026-11-26 04:22Z, owner: **EPL-2.0 code may be ported from source,** because it costs nothing and anyone may use and modify the result. It goes into its own EPL-2.0 module (licence matrix use `epl-module`, as for Jakarta Servlet), with each file's EPL header kept and the module's own LICENSE and NOTICE.
  - **First use:** AspectJ 1.9.27's `org.aspectj.lang.annotation` (sol-aop). This replaces the clean-room instruction of 04:18Z.
- 2026-11-26 04:25Z, owner: **the licensing rule for everything.** A licence is acceptable if the code is free of cost, legally modifiable, usable by anyone, and creates no legal issues for Flint or its users. Applied:
  - **Port from source, freely:** permissive licences (Apache-2.0, MIT, BSD, ISC, zlib, Boost, Unicode).
  - **Port from source, in a module of its own** that keeps the upstream licence, headers, LICENSE and NOTICE:
    - file-level copyleft (EPL-2.0, MPL-2.0);
    - **GPL-2.0 with the Classpath Exception (OpenJDK), approved by the owner.** The exception is kept, so applications that link the module are not GPL.
    - **No mixing:** GPL-2.0+CE files never share a package with Apache-2.0-derived files (Apache-2.0 and GPL-2.0-only cannot be combined into one work). Packages depend on each other freely, which is what the exception allows.
  - **Not without a coordinator review** (default clean-room): LGPL, because D links statically and the relinking obligations could burden users.
  - **Never:** strong copyleft without a linking exception (GPL or AGPL, which would force users' applications to be GPL), and source-available, non-commercial or paid licences (FSL, BSL, SSPL, commercial).
- 2026-11-26 04:30Z, owner: **flint.java is ported from OpenJDK.** This amends 04:25Z: there are no separate `-openjdk` packages.
  - **Licence:** every `flint:java*` package is GPL-2.0-only WITH Classpath-exception-2.0, like OpenJDK. Flint's own code in those packages is contributed under the same terms.
  - **Spring and other Apache-2.0 code** depends on `flint:java*` freely. The Classpath Exception means applications and Flint's other repositories are not affected.
  - **Apache Harmony is no longer used.** The few Harmony-derived files (BigInteger tests and code in `flint:java-math`) are replaced by OpenJDK ports, or by original code, so no `flint:java*` package mixes Apache-2.0 and GPL-2.0 files.
  - **The repo licence stays Apache-2.0.** Each `flint:java*` package states its own licence in `dub.sdl` and carries its own LICENSE file (with the Classpath Exception text) and NOTICE.
- 2026-11-26 04:32Z, coordinator, under the owner's standing approval: **LDC `--linkonce-templates` is adopted in the release profiles** (sol-jdk-core, m7 reviewing). Diagnostic A/B on the owner's desktop, 3 alternating pairs each way:
  - **Edit builds:** gs-rest −22%, petclinic −29%.
  - **Cold builds:** petclinic −18%; gs-rest +3%, within noise.
  - **JDK closure violations:** 664 → 36, with 0 new.
  - **App sizes:** matched.
  - **Next:** a certified venus build run in tonight's overnight window confirms the gated build metrics. This was a profile-wide change, never a per-package flag (36c5384c).
- 2026-11-26 04:48Z, owner: **every difference between Flint's public API and the Java original is kept in one running, user-facing log,** so none of it is knowledge that people are expected to just know.
  - **The log:** `docs/spring/java-differences.md` is GENERATED from `api/*/mapping.json`. It lists every adapted element with its rule or deviation and its Java-to-Flint form, every excluded element with its reason, and deferred elements as counts.
  - **A front section** explains R1–R22 and the common deviations in plain language, with examples.
  - **A gate** keeps it in sync on every landing, and every adapted entry must cite a rule or deviation that exists in `api-mapping.md`.
  - **Owner of the work:** api-coverage.
- 2026-11-26 04:55Z, coordinator, under the owner's standing approval: **an ABI-preserving pilot for the per-element-type cost of `List!T`** (sol-jdk-core).
  - **Kept:** `List!T` stays nominal, along with `Collection`/`Iterable`, `ArrayList` subclassing, null and `Object` casts, and the AOT descriptor path.
  - **Erased:** equals, hash, toAnyArray, element type, storage modes, bounds and cursor state move into one non-template list and cursor, driven by a per-element descriptor. Each `T` gets one thin typed adapter.
  - **Acceptance:**
    - marginal loadable bytes per new element type, on O3 and Oz, DMD and LDC, against matched controls (1→2 class, interface and string types, plus Jackson `JsonNode` and Micrometer `Meter`);
    - zero-allocation reads and foreach;
    - unchanged parity for factories, subList and views, CME, descriptors and Binder subclasses.
  - **If the per-T interface table keeps the floor above about 2 KiB,** an erased marker interface with non-virtual typed methods comes back for review before coding, with an R10 note.
  - **Deferred:** the DUB namespace move.
- 2026-11-26 04:55Z, coordinator, under the owner's standing approval: **Boot autoconfigure gains direct dependencies on `flint:beans` and `flint:core`** (sol-boot). They follow the tier direction and are already in the link closure. Each edge lands with the first import that needs it, followed by `tools/check_locks.py` over every project. Deferred contracts (`AnnotatedTypeMetadata`, `Condition`, `ConditionContext`) are not imported until they land.
- 2026-11-26 05:05Z, coordinator, under the owner's standing approval: **module size probes link with the flags that apps ship with (`probe-flags-rebaseline`).**
  - **Finding** (sol-boot S-36): `measure_builds --framework-sizes` links each module probe without the release profile's LDC `-fno-moduleinfo-localclasses` and `--gc-sections`.
    - Without those flags, ModuleInfo class lists keep every class of every imported module alive.
    - Importing two beans interfaces cost +181,600 B in the probe but +11,824 B with the release flags.
    - gs-rest-service's O3 binary changed by −16 B.
  - **Decision:** module probes use the release profile's link flags. proof-harness makes the change.
  - **Re-baseline:** every module's linked-byte cap is re-baselined once, on the same machine, at the new measurement plus 10%, and never above its old cap. The commit carries `Budget-Raise-Approved: probe-flags-rebaseline` and a before/after table for every module. Template caps are unchanged, because templates don't depend on link flags.
  - **Until it lands:** slices whose probe growth comes from ModuleInfo retention wait, unless their release-flag growth fits the existing rules. sol-boot's report slice waits.
- 2026-11-26 05:10Z, coordinator, under the owner's standing approval: **Java package cycles that D cannot express** (sol-observability: Micrometer `Timer` → `HistogramSupport` → `Meter`).
  - **The pattern:** declarations may live in an internal leaf module. The canonical module re-exports them with selective `public import leaf : Name, ...` of exactly those symbols. There are no wildcard re-exports and no `package.d` aggregators.
  - **Why no deviation is needed:** R1 governs the import path a developer writes, and that path is unchanged.
  - **Records:** `mapping.json` records the canonical path, and an import test compiles code that uses only the Java-shaped imports. flint-aot confirms that descriptors and diagnostics show the canonical name.
  - **Rulebook:** api-coverage adds the pattern to R1.
- 2026-11-26 05:12Z, coordinator, under the owner's standing approval: **SpEL string indexing on supplementary characters** (sol-template). Indexing either UTF-16 half of a supplementary character returns `"�"`. Indices and length stay Java's (R14), and BMP characters are unchanged. A valid UTF-8 string cannot hold Java's lone surrogate. This is a D-SPEL deviation row in api-mapping.md.
- 2026-11-26 05:12Z, coordinator, under the owner's standing approval: **R23: Java `Object`-typed values map to `flint.engine.aot.Any`**, the erased-core design of ADR-030 section 2.
  - **Coverage:** inline zero and scalar values, a null reference as `Any`'s null, and identity kept for references.
  - **Where it applies:** new mapping entries cite R23 rather than per-module deviations (first user: sol-data's `IdentifierAccessor`).
  - **Who:** api-coverage adds the rule.
- 2026-11-26 05:15Z, coordinator, under the owner's standing approval: **`List!T` per-type cost, second design** (sol-jdk-core).
  - **Pilot result:** the first pilot cut LDC marginal bytes per element type by about 30%: class from 17.3 to 12.0 KB, JsonNode from 17.0 to 11.8 KB, Meter unchanged. In a lean probe, the per-T typed interface thunks, vtables and ClassInfo still cost about 3.5 KB.
  - **Approved for measurement:**
    - nominal `List!T` becomes an erased marker over one non-template `RawList` virtual contract;
    - typed `get`, `add` and iteration methods become non-virtual;
    - each `T` gets one final internal view adapter;
    - `ArrayList!T` and `AbstractList!T` stay public and subclassable, as compatibility adapters.
  - **Before the full conversion:** measured numbers for factories and one internal mutable-result entry point (Jackson, Meter), with a target of about 2–3 KiB per `T` on LDC O3 and Oz and no DMD regression. Cross-implementation `List.equals` and `hashCode` stay exact. Reads and foreach stay allocation-free.
  - **A deviation:** classes that implement `List!T` directly need the legacy adapter. This gets a D-id with an R10 mapping note.
- 2026-11-26 05:15Z, coordinator: **the Deviations table in api-mapping.md becomes generated** from one file per deviation (`api/deviations/`), owned by api-coverage, because parallel submissions kept conflicting on its rows. Union merge is unsafe for that file's prose.
- 2026-11-26 05:15Z, coordinator: **adopting `--linkonce-templates` (04:32Z) is suspended until the runtime cost is measured.** The train's first `flint budget` failure (petclinic-rest +3–10% instructions per request) came from a tree that contained the profile change. The adoption evidence covered build time and size, not instructions per request. sol-jdk-core withdrew the profile commit, and its source changes land on the stock profiles. proof-harness runs `flint budget` on main plus the profile change alone. Adoption resumes only if per-endpoint instructions stay within budget, or narrowly (for example edit builds only) with a decision.
- 2026-11-26 05:20Z, coordinator, under the owner's standing approval: **interim, until `probe-flags-rebaseline` lands.** A slice whose standard module probe is over budget only because of ModuleInfo class-list retention may pass the budgets step on two pieces of evidence:
  - the release-flag probe (`-fno-moduleinfo-localclasses`, `--gc-sections`);
  - a matched canonical release application showing no meaningful shipped growth.

  Both are recorded in the commit body with receipts. No cap is changed. First use: sol-boot's ConditionEvaluationReport startup slice. The standard probe showed +181,600 B, the release-flag probe +11,824 B, and the canonical app +8 B with no report symbols.
- 2026-11-26 05:30Z, coordinator: **`probe-flags-rebaseline` (05:05Z, b386f7a3) and the 05:20Z interim (d295724b) are WITHDRAWN.** Their premise was wrong. proof-harness checked that `measure_builds`' module probe already compiles with the release dflags, including `-fno-moduleinfo-localclasses`, and LDC drops dead sections. sol-boot confirmed that the +181,600 B and +11,824 B figures came from its own standalone `ldc2 -i` probes, not from the gate's probe. No cap changes, and the rule is removed from `policy/budget-raise-rules.json`. Slices pass the budgets step on the gate's own probe as before. sol-boot's ConditionEvaluationReport slice needs that probe's result (the canonical app moved by +8 B).
- 2026-11-26 05:50Z, coordinator: **`--linkonce-templates` is not adopted for the release profiles.** This settles the 05:15Z suspension.
  - **Isolated `flint budget` on posidon,** all on base d8f4e413 (proof-harness, `coordination/notes/budget-isolation-0538Z/`):
    - linkonce alone causes 31 petclinic-rest problems: delete paths +9 to +9.7% instructions per request, and owner errors and updates +4 to +8.5%;
    - gs-rest stays within budget (median 0.987).
  - **sol-jdk-concurrent-io's rename is cleared** (median 1.000). The 05:07Z train blamed it wrongly.
  - **Open:** the RTInfo closure problem that linkonce hid (a shared GC-bitmap definition drags in unrelated archive members) needs a remedy that costs nothing at runtime. Candidates are per-module separate compilation or a dedicated bitmap member, decided on measured build times (sol-jdk-core).
  - **Narrower use:** linkonce for dev or edit builds only would need its own decision, with numbers.
- 2026-11-26 05:55Z, coordinator, under the owner's standing approval: **borderline `flint budget` misses are re-measured, not tolerated.** The 1% per-endpoint tolerance is at the noise floor on some petclinic-rest endpoints: main alone missed by +1.17%, and flint-aot by +1.11%.
  - **The method:** an endpoint missing by less than twice its tolerance is re-measured (about 5 runs), and the median is judged. The report lists all samples. m7 implements this in `flint budget`; until it lands, the train re-runs a borderline miss once before bouncing a lane.
  - **No budget or tolerance changes.** Widening an endpoint's tolerance needs its measured spread and a separate decision.
- 2026-11-26 06:22Z, coordinator: **standing delegation of upstream-test seeding.** A lane may run `--seed-upstream-tests` itself, and commit the result, when both hold:
  - it registers a new module or namespace in its own slice;
  - the seed adds only that module's or namespace's upstream test classes as deferred.

  The commit body lists the exact class paths. Seeding never changes a recorded entry, and the upstream-tests step must PASS. Anything wider still goes to the coordinator. Budget-raise trailers stay with the coordinator (the lanes' own AGENTS rule).
- 2026-11-26 07:22Z, coordinator, under the owner's standing approval: **main is within its `flint budget`** (proof-harness, posidon, `--repeat 5` on 962c64a8).
  - **'update owner pet':** median 561,003 against a budget of 562,146, with a spread under 0.1%. The +1.3% misses seen on train candidates are therefore real and come from a submission. The train's median re-measure (962c64a8) bisects them to their submission. No re-baseline is needed.
  - **'create owner: telephone with letters':** bimodal on main, with runs of 103.2k and 104.4k, about 1.2% apart. That explains main's earlier +1.17%.
  - **Tolerance for that one endpoint:** m7 may set it from its measured spread (`--update --repeat 5`, 3× the spread), in a commit with the samples. This is the separate decision the 05:55Z rule asked for. All other endpoints keep 1%. The source of the bimodality (likely GC timing) is worth finding later.
- 2026-11-26 07:36Z, coordinator, under the owner's standing approval: **runtime `Class` checks (R4).**
  - **Annotations and compile-time uses:** Java `Class<?>` stays `ClassRef` via `classOf!T`, name only, so the AOT annotation ABI is unchanged.
  - **Runtime values needing `isInstance` or `isAssignableFrom`:** a separate `RuntimeClassRef` via `runtimeClassOf!T` (`flint.java.runtimeclassref`, sol-jdk-core, flint-aot reviewing). It holds the class's `ClassInfo` and uses druntime's `@safe nothrow @nogc` `TypeInfo_Class.isBaseOf`. It converts to `ClassRef` by name.
  - **Null:** `RuntimeClassRef.init` is Java's null `Class`, and operations on it throw `NullPointerException`, as in Java. This is not an R5 drop.
  - **Scope:** reference types first; arrays and primitives come later.
  - **First user:** `ApplicationObjectSupport.requiredContextClass` (sol-web).
- 2026-11-26 07:36Z, coordinator: **`fillSecureRandom` moves to a dependency-free `flint:conc` leaf** (sol-jdk-math-regex), with a `public import` kept from `flint.conc`. `UUID.randomUUID` was linking conc's arena static-root machinery, about 10 KB per app (sol-ai's `Document` trace).
- 2026-11-26 07:40Z, coordinator, under the owner's standing approval: **calibrating `flint budget` tolerances to measured noise, if the median re-measure isn't enough.** Two trains (05:50–06:44 and 06:44–07:33) landed nothing, mostly because of borderline misses at the 0.5% (gs-rest) and 1% (petclinic) tolerances. Each costs a 10-minute bisect step on posidon.
  - **Trigger:** if the first train with the median-of-5 re-measure (started 07:33) still bounces a lane on a miss under 2× tolerance.
  - **Calibration (m7 with proof-harness):**
    - run `flint budget --repeat 5` for both apps on main, on posidon;
    - set each endpoint's tolerance to max(current tolerance, 3× its measured spread), capped at 2%;
    - one commit carries every endpoint's samples and cites this decision.
  - **Unchanged:** the budgets (instruction counts) themselves, the certified workloads, and the rule that real regressions bisect to their submission. Endpoints above the 2% cap need their own decision, with the cause of the noise.
- 2026-11-26 08:30Z, coordinator, under the owner's standing approval: **faster merge-train attribution** (proof-harness). The train's bounces since 05:49Z are real 1–3% petclinic-rest instruction regressions on shared request paths, not noise. For example, 'list vets' is 407,208 on main (spread 0.03%) and +1.26% on a candidate prefix. The cost is the bisect, at 10–30 minutes per posidon step. Approved, in order:
  - **(a) Budget-only bisect steps:** once a candidate has failed only `flint budget`, bisect steps run only `flint budget` for the failing app.
  - **(b) No median re-measure for tight endpoints:** endpoints whose recorded spread is under 0.2% skip the re-measure.
  - **(c) Per-submission budget pre-screen:** posidon measures main plus each submission alone, in parallel with the stacked candidates. A submission that regresses alone bounces at once, with its per-endpoint numbers.

  Budgets and tolerances are unchanged. The 07:40Z calibration stays for genuinely noisy endpoints only.
- 2026-11-26 08:50Z, coordinator: **main is over its gs-rest-service `flint budget` on two endpoints** (proof-harness, posidon, median of 5 on a1e841e8).
  - **The misses:** 'name with spaces and plus' +0.58% against a 0.50% tolerance, and 'unknown parameter is ignored' +0.70% against 0.63%.
  - **When it landed:** between d8f4e413 (which passed) and a1e841e8.
  - **No re-baseline:** raising a per-endpoint budget is an owner decision (087f28a3).
  - **The plan:**
    1. proof-harness bisects main's gs-rest budget over d8f4e413..a1e841e8 with budget-only steps, and the culprit's lane fixes it forward;
    2. until then, the train judges only those two endpoints against main's measured median, so a candidate fails them only by regressing further. This is a temporary list that the fix commit deletes. All other endpoints stay on their absolute budgets.

    Main's miss stays an open release blocker.
- 2026-11-26 10:40Z, coordinator: **the gs-rest-service `flint budget` miss is measurement drift, not code** (proof-harness, `coordination/notes/gs-rest-bisect/summary.md`). This supersedes 476a03c3's 'regression' framing.
  - **The evidence:** the seed commit 1b23b27a itself now measures +0.42% median over its own budgets (+80 to +180 instructions per request) on posidon. The shift appeared between 05:38Z and about 07:33Z. Petclinic did not shift, and the measurement code is unchanged.
  - **The cause:** instruction counts are deterministic, so some input to the measured binary changed. Candidates are the native install, the toolchain, or posidon's system libraries or kernel. proof-harness is identifying which.
  - **Interim:** the train judges gs-rest only relative to main's measured median on every endpoint. A candidate fails gs-rest only by being worse than main. Petclinic stays absolute. This is a temporary list, removed when the cause is reverted or the owner re-baselines.
  - **Budgets unchanged:** a gs-rest re-baseline is the owner's decision.
- 2026-11-26 12:25Z, coordinator: **merge-train budget order is stack-first** (proof-harness; amends 08:30Z (c)). posidon, the only `flint budget` runner, measures the whole stacked candidate in parallel with the acceptance verifiers.
  - **Green stack:** everything lands on one posidon run, about 10 minutes instead of about 95 for screening every submission first.
  - **Red stack:** the closure-touching submissions are then screened one by one, so the regressing lane is named directly. Budget-only bisect steps (a) and the tight-spread rule (b) stay.
- 2026-11-26 14:35Z, coordinator: **region time zones drop `pure nothrow @nogc`** (sol-jdk-time-text's region-provider seam c1ceab147, reviewed by sol-jdk-core). `ZoneId.offset`, `ZoneId.normalized` and `ZonedDateTime.of(LocalDateTime, ZoneId)` lose those effects, because Java's region path consults a rules provider and can throw `ZoneRulesException`.
  - Fixed-offset paths keep exactly their existing effects. `ZonedDateTime.of(LocalDateTime, ZoneOffset)` and `ZoneOffset.toZoneId` stay `pure nothrow` without `@nogc`, because a non-UTC offset allocates its ID text. `LocalDateTime.atOffset` stays `pure nothrow @nogc` and is the migration for `@nogc` callers that need only an offset date-time. (Corrected at 14:40Z; the 14:35Z text wrongly said the fixed paths had `@nogc`.)
  - No engine or hot-path caller loses `@nogc`. On main, the only outside caller is `LocalDateTime.atZone`, which is already unattributed.
  - The effect change goes into the mapping and the generated java-differences page, with a migration note.
  - The prototype stays private until the apps' closure passes the train's budgets.
- 2026-11-26 14:46Z, coordinator: **aop may depend directly on java-regex** (sol-aop, for Spring's ~30 regexp pointcut elements; the MemberDescriptorRef boundary was approved by flint-aot). aop isn't in the apps' closure, and java-regex already is through hibernate-validator, so no app gains a package. There's no cycle.
  - The policy and DUB edges land in one commit, followed by `tools/check_locks.py` over every project.
  - Spring's full-match semantics (`matcher.matches()`) are kept, with pinned full-match versus `find()` cases.
  - The pattern is compiled once during configuration, and the matching path is allocation-asserted.
  - Any cap change follows the normal rules with measured numbers.
- 2026-11-26 14:50Z, coordinator (corrected 14:58Z): **the opt-in java-time zone module keeps IANA tzdata 2026e** (sol-jdk-time-text). At 14:50Z I approved 2026f to match the Ubuntu Java 21.0.13.1 on venus. The project's pinned oracle, Temurin 21.0.13+9 in `api/upstreams.json`, bundles 2026e and has the same 604 IDs. It matches IANA 2026e on all 350,826 wall-clock and local-resolution rows, so the data pin, the OpenJDK source tag and the oracle agree. Moving to 2026f goes with the upstream Java pin, as its own reviewed change.
  - The archive is checked against IANA's `.asc` signature and its SHA-256.
  - The licence-matrix row (public domain) and the `api:false` upstream entry land with the package.
  - The 13 Java SystemV IDs and the alias differences are listed explicitly.
- 2026-11-26 15:02Z, coordinator: **an attribute-only closure change may land through main-push** (framework-core's "Permit scoped reads through Any accessors" in engine-aot `any.d`, which sol-context needs). It's an exception to the train rule for a change that adds DIP1000 attributes and no code paths. It needs:
  - the engine-aot DoD on both compilers, plus structural;
  - compile-only builds of all three apps on DMD and LDC, because `return scope` can break a caller that lets the result escape;
  - unchanged codegen: identical engine-aot release bytes and template count before and after.

  If any of these fails, the change goes through the train.
- 2026-11-26 14:55Z, coordinator: the sol-jdk-math-regex and sol-translator launchers had been SIGSTOPped since about 06:00Z with no FROZEN record and no MEASURING lock. I resumed both by pid, and proof-harness is looking for the leak.
- 2026-11-26 15:08Z, coordinator: **rule R24, Java `final` instance fields** (sol-framework's `InstanceFilter`, which framework-core approved). A `public` or `protected` `final` field becomes a same-name, same-visibility, `final`, non-`ref` accessor over a private field assigned once in the constructor. Reads look the same as Java's, and assignment doesn't compile. It's a general rule rather than a narrow deviation, because Spring has many such fields, `protected final Log logger` among them.
- 2026-11-26 15:25Z, coordinator: **no throw-only typed-`null` overloads** (api-coverage). When Java null-checks a parameter only to throw, and the D type is a value type that can't hold `null` (an enum, a struct or record, a primitive), the port doesn't add `f(typeof(null)) { throw ...; }`. Passing `null` fails to compile, and a test pins that. Ported upstream null-check tests count as ported through that assertion. Typed-`null` overloads remain only for D-7's real overload ambiguity. This amends R20's earlier typed-`null` bullet (R5 and R20 updated). Existing throw-only overloads (the actuator `Access.cap` hand port, sol-ai's pending `ToolResultPart.of(typeof(null))`) are removed as their owners touch them.
- 2026-11-26 15:30Z, coordinator: **enums with private per-constant fields stay D enums** (third-party-apis, reviewing sol-jackson's `MapperFeature`, `SerializationFeature` and `DeserializationFeature`). Private fields that only constructor arguments set, and only methods read, don't trigger R15's struct form. The enum keeps Java's constants in order, and its methods are ported now as R20-style UFCS free functions computed from the constant, rather than deferred. R18's overloads apply too when the enum implements an interface. R15 updated.
- 2026-11-26 16:10Z, coordinator: **static-only Java types may be D structs of static members and stay `ported`** (api-coverage's kind audit of `ported` type rows; R1 updated). The 14 static-only utility classes and constants-only interfaces in the audit keep `ported`. The 11 real kind changes become `adapted` with a rule or deviation, and their owners fix them; `BasicAuthenticationConverter` must become a class that implements `AuthenticationConverter`. api-coverage adds a Java-kind versus D-kind check to `api_differences --check`, with a shrink-only baseline.
- 2026-11-26 16:15Z, coordinator: **R19 covers `$`, and R25 covers interfaces only the library implements** (api-coverage's kind audit). A `$` in a Java identifier becomes `_` (`BCryptVersion.$2A` is `_2A`), `adapted` R19. A Java interface whose only implementations are inside the upstream library, and whose instances users only obtain from its factories, may be a `final` class (`MergedAnnotations`, `HibernateValidatorConfiguration`), `adapted` R25. The test is no public outside implementation in the pinned source, no documentation inviting one, and no ported upstream test implementing it.
- 2026-11-26 16:20Z, owner via coordinator: **JDK first.** The owner asked to put all effort on completing the OpenJDK port before the other libraries, because every later port reuses it. All 18 gpt-6.2-sol lanes move to `java.*` packages, one owner per package, as the lane table in docs/spring/phase2/jdk-port.md lists. Each lane first lands only its in-flight work (queued train entries, verified main-push slices, red-main fixes) and parks other Spring work on private branches. Claude roles finish in-flight work and then review. api-coverage reconciles the OpenJDK manifest with existing `flint.java` code, which today's 2.3% coverage figure undercounts.
- 2026-11-26 16:58Z, coordinator: **R26, `null` arrays** (sol-jpa's `java.util.zip` boundary). D can't tell `null` from an empty array, so array parameters stay plain arrays and a `null` argument counts as empty. Java's `NullPointerException` for a `null` array becomes a no-op, recorded once per type citing R26. Returns where Java's `null` means "absent" become `Nullable!(T[])` under R5. This applies to every JDK lane.
- 2026-11-26 17:03Z, coordinator: **temporary link-closure allowance for LDC first-object placement, starting with StringJoiner → HexFormat** (sol-aop; reviewed by sol-jdk-core, which owns the closure gate). LDC places a package's shared template instances in its first object, so the stock StringJoiner probe pulls `hexformat.o` only to resolve StringJoiner's own `RTInfoImpl` symbol. The allowance lists exactly what that object may contribute: `RTInfoImpl`, HexFormat's `ModuleInfo` and module ref, druntime `core.checkedint.mulu`, `__arrayAlloc!char` and their `.eh_frame`, at 159 mapped bytes per profile. It fails on any other symbol, and on any symbol from `flint.java.util.hexformat` itself. It generalises 523bd5bd, and it's removed when the compile-scope fix (proof-harness's three-scope A/B) lands. Later edges of the same kind are added only as exact symbol lists with a size total, reviewed by sol-jdk-core.
- 2026-11-26 17:48Z, coordinator: **`NullPointerException` is explicit (R8)** (api-coverage; lanes kept hitting it, most recently sol-template's `DateFormat`). D crashes with SIGSEGV on a `null` class reference where Java throws `NullPointerException`. Flint checks explicitly and throws `flint.java.lang.NullPointerException` at the point Java does, through one shared cold helper per package. A crash is never accepted, and rows without the check stay deferred.
- 2026-11-26 17:58Z, coordinator: **formulaic new leaf caps need no coordinator approval.** For the JDK-first work, a lane may land a new leaf row in leaf-budgets.json without asking me when four things hold: its caps are exactly ceil(measured x 1.10) for both bytes and templates (new-module-rule); the package's existing caps stay unchanged and the probe passes them; the leaf is 2 KB or less; and the commit message gives the measurement. It carries no Budget-Raise-Approved trailer, since it isn't a raise. Any package cap raise (jdk-leaf-rule), any leaf over 2 KB, and any brand-new package still come to me, and I author the trailer where one is needed.
- 2026-11-26 18:16Z, coordinator: **package caps follow the combined measurement when it's tighter than the leaf sum** (from sol-jackson's java-nio exceptions). jdk-leaf-rule lets a package cap rise by a new leaf's cap. Exception leaves each count the shared java.lang closure (about 436 templates), so summing them overstated java-nio's templates fourfold (1,922 against 449 measured). From now on, a package cap change takes, for each metric, the lower of the leaf sum and the combined package measurement plus 10%. Caps may always shrink to that.
- 2026-11-26 19:27Z, coordinator: **the merge train restacks after naming a culprit** (proof-harness). A returned lane that resubmitted went back to the head of the queue, so when it failed again at position 1 the whole train landed nothing (17:45 to 19:19Z). From now on, once the train names a culprit it restacks the submissions behind it and verifies them once more in the same train. If that restacked set fails, it bisects. No lane loses its turn, and one repeat failure can't cost a whole train.
- 2026-11-26 19:35Z, coordinator: **`Optional.of` and `Optional.ofNullable` keep slice values present (R26)** (sol-jdk-core, reviewed by framework-core). Java keeps `""` and `new byte[0]` present, but the D factories rejected the default empty string and empty byte arrays, because D can't tell them from `null`. Under R26 a slice is never absent: both factories now treat any slice argument as a present value, and absence is `Nullable!T` or `Optional.empty()`. Class references keep Java's `null` semantics. Java's `ofNullable((String) null)` returning empty is the one observable difference, recorded once on `Optional` citing R26. sol-jdk-core changes both factories together, with its caller checks (Stream findFirst/reduce, the DataAccessUtils result-count paths, the AOT optional bean lookup) on DMD and LDC.
- 2026-11-26 19:57Z, coordinator: **hashing through an erased reference swallows a throwing `hashCode` (R11)** (sol-aop's `Formatter` `%h`, reviewed by framework-core). D's `toHash` is `nothrow`, so `mixin JavaObject;` hashes a throwing `hashCode` to 0, and erased consumers (associative arrays, `%h`) inherit that. It's recorded once under R11, and the affected elements cite R11; no per-element deviation ID and no per-call-site callback table. Typed `hashCode()` calls still propagate.
- 2026-11-26 20:25Z, coordinator: **leaf budgets are enforced by the link-closure step** (sol-jdk-core, b885b8fe7). Before this, the step checked only symbol closure, so a leaf could pass while over its leaf-budgets.json cap (sol-ai's BitSet, 14,876 against 14,850). Each leaf is now measured by its exact probe, against the row's named control (default: the minimal main control). Templates come from one DMD invocation for the leaf and its probe, except rows whose cap commit shows they were cut with separate invocations. An overrun fails the step. The audit of all 38 rows found two overruns, both measurement-method differences with no growth since their caps were set: Object (1,184 to 1,244, 8c12429a4) and ByteBuffer (24,460 to 24,524, b8e8ed771). A row that fails from now on is real growth: shrink it, or ask for a cap.
- 2026-11-26 20:45Z, coordinator: **`ArrayList` of a class or D interface uses fully erased storage** (sol-jdk-core's 18db93dd6; framework-core owns flint:java and recommended it). Lists of interface types instantiated the whole AbstractList/ArrayList/sort family per interface. Erasing them saves gs-rest about 20 KB and petclinic about 40 KB of linked size. Keeping `ArrayList!E <: AbstractList!E` saved only about 600 B on the probe while adding 3 KB, so that arm was dropped. Deviation, registered once and cited from the ArrayList/AbstractList rows: no `AbstractList!E` upcast, and inherited bulk paths use indexed operations without a custom iterator (explicit `iterator()` still dispatches). Class elements already behaved this way. Conditions: allocation gates on both apps and compilers, `flint budget` on posidon (typed reads now do a dynamic interface cast), a compile-time guard on the upcast if expressible, and the app-size receipt in the commit.
- 2026-11-26 21:27Z, coordinator: **a red merge-train stack is bisected with flint budget, and a re-measure covers only the app that missed** (proof-harness, 2026-11-26 21:45Z). Screening each closure-touching submission alone, one after another on posidon at about 30 minutes each, could hold a red train for four hours.
  - **Red stack:** posidon checks main's budget first, because a bisect against an unverified base misled us before (gs-rest read +0.43% with no code change). It then bisects the stack in budget-only steps for the apps that missed: 3 steps for 8. A red main blames nobody.
  - **No per-lane screens:** a bisect always names the first submission whose prefix misses, including one that misses only on top of the lanes before it, so there is no separate combination case that a screen would decide.
  - **Re-measure:** the median-of-5 re-measure of a borderline miss already covers only the apps that missed, so it is unchanged and verification is not weakened.
  - **The 19:27Z restack, now implemented:** once a culprit is named, the lanes behind it are restacked on the green prefix and verified once more in the same train. If that fails, the train bisects without a second restack.
- 2026-11-27 00:17Z, coordinator: **the merge train judges gs-rest-service and petclinic-rest against main's measured medians while posidon's drift is open** (proof-harness). This extends the 2026-11-26 08:45Z and 10:40Z entries, and the absolute budgets in benchmarks/spring/flint/*/budgets.json stay untouched: this is not a budget raise, only how the train compares while the cause is open.
  - **The drift:** posidon's instruction counts shifted again with no code change. Main 3cb7b83a read +0.78% over the gs-rest list's 10:35Z medians (about +190 instructions on every small endpoint), and the 10:35Z reference commit 4f581e3a, re-measured the same way, read +0.774%. Evidence: coordination/notes/main-red-2357Z/.
  - **The list:** benchmarks/spring/train-budget-relative.json now holds main 3cb7b83a's median of 5 for all 18 gs-rest and all 109 petclinic endpoints. A candidate fails an endpoint only if it regresses past main by more than that endpoint's tolerance.
  - **Ruled out:** an LD_PRELOAD clock-shift test made no difference. The monotonic clock read as 45, 37 or 19 h of uptime gave identical counts, and the wall clock moved back 14 or 20 h stayed within run noise. Counts are bit-exact within a session and shift between sessions; the cause is still open.
  - **The owner** decides, with this evidence, on the budget re-baseline. Remove the list when the cause is fixed or the owner re-baselines.
- 2026-11-27 02:26Z, coordinator: **the merge train lands a green prefix as soon as it's known** (proof-harness). When acceptance fails in a later group, the groups before it are already acceptance-green, but they used to wait for the bisect behind them (about an hour).
  - **When it lands:** a prefix lands only as exactly the tree that was verified, main plus those lanes and acceptance-green.
  - **Its budget:** the whole stack's green flint budget doesn't count for the prefix (a later lane could have lowered the counts), so posidon budget-checks the prefix's own tree first, beside the bisect.
  - **The push:** it is confirmed with `-> main` and an ancestry check, and re-verified after a rebase if main moved under build-relevant paths. The prefix is settled at once, mail included.
  - **The rest:** the bisect and any restack land on top of the pushed tip.
- 2026-11-27 03:20Z, coordinator: **Sol lanes may run on agy (Antigravity) or the GitHub Copilot CLI** (owner, 2026-11-27, after the OpenAI usage limit stopped all 18 Codex lanes until 2026-12-03). `agentctl launch` now accepts `--harness agy` (default model gemini-4-neon-high) and `--harness copilot` (default model auto), with `--profile` naming the model. Each tick is a fresh headless session started from the role's brief and hand-off state, because several lanes share venus and "continue the most recent conversation" could pick up another lane's. The trial runs sol-jackson on agy and sol-jdk-core on Copilot before the rest move. The rules don't change with the harness: hold builds while measuring, push only through main-push or the train, never edit caps.
- 2026-11-27 07:25Z, coordinator: **Flint libraries compile per source module (the "all-Flint" DUB scope) by default** (proof-harness's compile-scope A/B, coordination/notes/compile-scope-ab/; sol-jdk-core's plan). Against DUB's batch scheduling, two runs agreeing within 1% showed LDC release cold builds 27% faster for gs-rest (21.3 to 15.5 s) and 12% for petclinic (68 to 59 s), and scratch builds the same. Edit builds were unchanged, and DMD dev cold builds were 0.1 to 0.3 s slower. Linked binaries are 48 KB (gs-rest) and 41 KB (petclinic) smaller at O3, and all 454 batch-placement closure violations disappear. Both runs were flagged non-quiet only because of the merge train's own regeneration step; option (a), accepted for a build-system decision. Release claims still need certified timing. It lands as one change through the train: the scope default, unique template counting (sol-jdk-core, so a shared instance counts once), and the removal-only closure-ratchet re-baseline.
- 2026-11-27 08:21Z, coordinator: **an interleaved flint budget A/B is the tie-breaker before the merge train returns a lane that failed only flint budget** (proof-harness). Instruction counts include the reactor's idle polling between requests, about a third of each request on gs-rest, and that part shifts from session to session. Stored numbers can therefore fail a lane, or main itself, for the session alone: flint-aot's 05:43Z return, and main reading +1.1% over the list at 08:1xZ.
  - **The method:** tools/budget_ab.py alternates the prefix's and the candidate's release binaries in one posidon session with flint budget's own measurement, median of 5 each, and judges each endpoint against its tolerance. That's the method that cleared flint-aot, whose 18 gs-rest endpoints were all within ±0.21% of main (coordination/notes/flint-aot-interleaved-ab/).
  - **In the train:** when a bisect names a culprit by flint budget alone, the train runs the A/B before returning it. If the culprit is within tolerance, it rides on, and the rest of its acceptance-green group is judged the same way against it, once. A real regression stays returned.
  - **For the owner:** excluding idle polling from the budget window, which would make counts deterministic, is a measurement-definition change and needs a re-baseline.
- 2026-11-27 09:52Z, coordinator: **a red merge-train stack is judged interleaved against main, with no stored-number main check; main's absolute flint budget is posted every 24 h** (proof-harness).
  - **The red stack:** the interleaved stack-against-main A/B (tools/budget_ab.py, one posidon session) measures main as the verified base that the 2026-11-26 21:27Z rule asked for. It replaces that rule's stored-number main check, which session drift kept failing on unchanged main, and saves about 40 minutes of posidon per red stack. A red stack is bisected the same way.
  - **The daily run:** every 24 hours, between trains while apps-landing is free and not paused, the scheduler runs main's absolute flint budget on posidon. It writes the log to coordination/notes/main-budget-daily/ and mails the misses to the coordinator, so slow cumulative drift in main itself stays visible to the owner.
- 2026-11-27 10:55Z, coordinator: **an interleaved budget A/B that could not run is an infrastructure failure, not a verdict** (proof-harness).
  - **The rule:** when the merge train's A/B (a lane's tie-breaker, or the whole stack against main) could not run, nobody is returned. The lanes stay queued at the head and are retried next train; what is green before them lands. The coordinator is paged, with the logs (coordination/train/interleaved-*.log). Commit ca6e46ff5.
  - **The cause that prompted it:** flint-aot's b7b949bfe was based on a main older than tools/budget_ab.py, so its tie-breaker had no tool to run (10:40Z). The A/B script now runs the scheduler's own copy of the tool (56b36c9ed). flint-aot's entry was put back without a resubmission and lands on the 08:21Z interleaved verdict (coordination/notes/flint-aot-interleaved-ab/).
- 2026-11-27 16:14Z, coordinator: **the owner approved the v4.3 toolchain cutover that makes per-source compile scope the default** ("Yes, cut over"). This carries out the 07:25Z decision. The DUB patch changes, and so does `dub_patch_sha256`, so the change, the shared `.tools` swap and the verifier receipts all move together.
  - **The plan:** coordination/notes/compile-scope-ab/cutover-plan.md, run by proof-harness from step 2, with sol-jdk-core's template-counting and closure re-baseline commits (1875c0ce6 on 7fa83718c) stacked on proof-harness/scope-cutover.
  - **The freeze:** from 16:15Z until proof-harness broadcasts the v4.3 hashes (estimated 3-4 h).
    - No build-relevant direct main-push; docs and coordination changes are fine.
    - apps-landing pauses after the train in flight.
    - Lanes keep working on private branches.
    - After the swap, every lane rebases and rebuilds its platform modules once.
  - **Rollback:** step 7. `.tools` and verifiers.json go back to v4.2, and the commit is reverted through main-push.
  - **Independent of the interleaved budget A/B**, whose fix (7fa83718c) builds each side with its own flint CLI.
- 2026-11-27 17:35Z, coordinator: **porting becomes mechanical first: the porter, its correctness gate and a performance lint** (owner: "reduce the manual work required down to a science so that we can complete this work significantly faster and reducing the amount of AI credits … and then we would have some sort of verifiable gate that proves that our porter is actually correct with the performance gates also"). Plan: docs/spring/phase2/porter-plan.md.
  - **The case:** about 62% of the 48,406 deferred Phase 2 Spring and third-party elements are mechanical shapes: getters, setters, type declarations, trivial constructors, fields and R11 methods. The current translator handles only a few shapes, so lanes hand-write all of them.
  - **The gate** (`gates.py --gate porter`, required, shrink-only baseline):
    - determinism;
    - reproduction of the hand-ported corpus, API-identical, with the hand port's tests run against the generated module on DMD and LDC;
    - a Temurin differential oracle for every generated body;
    - no edits to generated regions;
    - generated output no larger than the hand port and within its caps, the allocation and closure gates, and `flint check --perf` lint rules taken from the playbook.
  - **The lanes:** once a shape is supported and its gates are green, lanes run the porter first for it. Hand-porting a supported shape needs a written reason.
  - **Owners:**
    - sol-translator: the porter, port plans and gates (a)–(e);
    - m7-flint-cli: `flint check --perf`;
    - framework-core with proof-harness: the first lint rules;
    - api-coverage: provenance in the mappings;
    - proof-harness: daily metrics (generated share, reproduction rate, elements per lane-hour as the credit proxy).
  - **sol-translator's JDK exception drafts** fold into milestone 2/3 (exception families), not a separate track.
- 2026-11-27 18:50Z, coordinator: **the v4.3 per-source compile-scope cutover was rolled back** (proof-harness, step 7 of the cutover plan; owner approval of 16:14Z). posidon's verification of the cutover commit f181fb558 on v4.3 passed the api gate, acceptance and allocation in both trim modes, but flint budget was red far past session drift: petclinic's delete endpoints +9.8% to +10.7% (`delete pet` 261,013 -> 287,479), `create user: missing roles` +4.4%, gs-rest-service +2.3% to +2.7% on most endpoints. The commits change no runtime code, so compiling the Flint libraries one module per compiler job itself costs instructions per request, most likely through lost cross-module inlining. The compile-scope A/B (07:25Z entry) measured build time and closure, not runtime.
  - **Nothing shared had changed:** the commit was not pushed, `.tools` is still v4.2, and verifiers.json is untouched. The freeze was lifted at 18:52Z, and the merge train resumed on v4.2 with every lane in place.
  - **Next, for the owner:** proof-harness runs an interleaved diagnosis on venus, batch vs per-source release builds. If it confirms, it also measures per-source plus LDC thin/full LTO for release, and per-source for dev/edit builds only. Raising flint budgets is not an option on the table.
  - **The 07:25Z decision stays recorded but unadopted** until that evidence and an owner decision.
- 2026-11-27 23:30Z, coordinator: **every Sol lane runs on opencode with deepseek/deepseek-v4.1-flash-1017 through OpenRouter for the rest of the port** (owner). Claude's weekly limit stopped the 15 Opus lanes and the Claude app sessions until 2026-12-02 01:00Z, and agy's weekly quota runs until about 2026-12-04.
  - **How it runs:** `agentctl launch --harness opencode` (7056c0444, 90a2c5729) runs `opencode run --model openrouter/deepseek/deepseek-v4.1-flash-1017 --auto --dir <worktree>` each tick from the role's brief file, as agy and Copilot did.
  - **The key:** the OpenRouter key lives in ~/.config/flint-lanes/deepseek.env (chmod 600, never committed or printed) and reaches only the opencode child's environment.
  - **In-flight work** merges through the merge train as usual (owner: "Through the train"). Nothing is force-merged, and lanes continue from their fp branches and hand-off notes.
  - **The rules don't change with the harness:** hold builds while measuring, land only through the main-push slot or the train, caps and trailers from the coordinator, IDs from `agentctl id next`.
- 2026-11-27 23:40Z, coordinator: **during the harness migration, a resubmission keeps its old apps-landing queue-member label** (sol-aop, sol-jpa and sol-boot, after the move to opencode). The label (`sol-aop-opus`, `sol-jpa-opus`, …) is only the train's ordering key, and `merge_train` orders submissions by that queue member. Resubmitting under a new label (`-opencode`) would silently send the lane to the back of a 19-deep queue. Lanes keep the old label until the queue is empty and the labels can be migrated as one deliberate step. This changes no role name or mail address.
- 2026-11-27 23:40Z, coordinator: **the serde first-object review moves from m7-flint-cli to sol-jdk-core while m7 is stopped** (sol-observability's `fp sol-observability-serde-copytext`, 4926f2a04/d90a24fb3). m7-flint-cli is a Claude app session and is stopped until 2026-12-02 01:00Z, so waiting on it blocks the fix for the rest of the limit. sol-jdk-core owns the link-closure and first-object rules, which is what the change touches; the coordinator approves the serde and cap side. The shrink re-cut to 13,104 B citing 5a09c016c stands. m7's `flint check --perf` framework stays with m7.
- 2026-11-27 23:40Z, coordinator: **api-coverage may land the ServletException metadata fix itself** (type row ported, `getRootCause()` ported, all four constructors deferred with the checked-exception cause lifecycle reason, as `IOException` was before 74f5b9d48). It is metadata-only and reversible, so the 30-minute rule applies; web-http still owns the real merged-constructor split, and api-coverage tells sol-web and web-http what changed.
- 2026-11-28, sol-translator: **the port plan records `BasicAuthenticationEntryPoint`'s accessor attributes, as sol-security verified.** The pinned spring-security 7.2.0 source declares the realm field and getter `@Nullable`, so R5 derives `Nullable!string` for both accessors; sol-security's `65628e6ce` makes the hand port follow that. Adding `"accessors": {"getter": ["const","pure","nothrow","@nogc"], "setter": ["pure","nothrow","@nogc"]}` to `api/port-plan/spring-security-7.2.0.json` makes `getRealmName()` and `setRealmName(String)` reproduce on DMD and LDC against that commit (2 of 2). On `fp/main` the hand port still keeps a plain `string`, so the type stays one of the six full-gate divergences until that commit lands; the plan entry changes no count by itself and its rows are unchanged. `accessors.py --compare --only` and the nine `test_accessors.py` tests pass; `structural`, `quality` and `--gate porter --digests-only` (46 regions) pass.
- 2026-11-28, sol-jpa: **approve two brand-new JDK packages for the ZIP/JAR port; both are verified and held private.** The coordinator lease is lapsed, so this is the 17:58Z/1365 sign-off request (a new package and a >2 KB leaf both need it; there is no Budget-Raise-Approved trailer on either, because each carries its first caps under new-module-rule, not a raise).
  - **`framework/java-util-jar` (`flint.java.util.jar`)**, `fp/sol-jpa-jar-manifest` @ `d5c7c0a9f` (rebased onto `fp/main` `5d9283318` on 2026-11-28; it was `222c3cb59` on `8c2df5944`): `Manifest`, `Attributes`, `Attributes.Name` (3 of 8 types, 56 of 93 members). Module DoD green at that tree: resolve/structural/api/quality/tests/upstream-tests/budgets/link-closure pass, apps skip (evidence `.flint/sol-jpa/current/jar-manifest-dod-rebased2.json`; the amended commit has the identical tree `354a968f8`). Measured on venus under v4.2: package probe 50,468 O3 bytes / 763 DMD templates -> caps 55,515 / 840; leaf `flint.java.util.jar` 49,936 O3 bytes / 589 templates. The later jar types need `java.util.zip` (`JarEntry` -> `ZipEntry`, `JarFile`/streams -> `ZipFile`/`ZipInputStream`).
  - **`framework/java-zip-exception` (`flint.java.util.zip.zipexception`)**, `fp/sol-jpa-java-zip-exception` @ `d4b482490`: `ZipException`. Module DoD green: all eight steps pass, apps skip (evidence `.flint/sol-jpa/current/zip-exception-dod.json`). Measured on venus under v4.2: package probe 3,260 O3 bytes / 436 DMD templates -> caps 3,586 / 480; leaf `flint.java.util.zip.zipexception` 3,396 O3 / 2,220 Oz bytes / 220 templates -> caps 3,736 / 242. It is separate because `ZipException extends java.io.IOException`, which adds 193 DMD templates to the `java-zip` batch probe (63 -> 256 against cap 63) and shifts LDC's first-object placement (S-159). The failed in-package attempt (`sol-jpa-zip-zipexception` @ `9cc1b6400`) is superseded and must not be submitted.
  - **On approval:** rebase each onto current `fp/main`, re-run its DoD, and submit one at a time after the checksum entry (`14ff03f3e94e`, train slot 10) lands, under the role's existing `sol-jpa-opus` label (23:40Z rule). If refused, both stay private with the reason recorded here.
- 2026-11-28 02:20Z, sol-jackson: **The `java.nio.charset` coding-exception tail needs a `framework/java-nio-charset` byte-cap raise (open for the owner).** S-182, `fp/sol-jackson-charset-tail-r1` @ `b10bcb9c8` (code `8cd2b38f1`, on the fc-io-cause replay `8c0693731`), ports `CharacterCodingException`, `MalformedInputException`, `UnmappableCharacterException`, `CoderResult.throwException` and the convenience `CharsetDecoder.decode(ByteBuffer)`/`CharsetEncoder.encode(CharBuffer)`. Measured on venus under v4.2 and hold, the fixture's loadable sections are 395,033 B without the tail and 395,273 B with it: **+240 B and no templates**. All of the growth is registration of the new public modules: `.data +208` (ModuleInfo for `flint.java.io` and the three exception modules), `__minfo +32`, `.relr.dyn +8`, `.eh_frame -8`; `.text` is unchanged because the probe calls none of the new functions, so nothing existing grew. The package probe is 59,768 O3 incremental linked bytes against the 59,719 cap (49 B over) and 685 DMD templates against 692. By api-growth-rule the cap becomes 59,719 + 240 = 59,959; templates stay 692. All other DoD steps pass (resolve/structural/api/quality/tests on DMD and LDC/upstream-tests/link-closure). The slice is also blocked on fc-io-cause `4906d9b23` (train #5), whose IOException cause lifecycle its exceptions and tests use. Needs the owner/coordinator's `Budget-Raise-Approved: api-growth-rule` trailer.
  - **State at 2026-11-28 02:3xZ:** the jar package is already rebased and green (above). The zip-exception package cannot be verified or landed on its own yet: `fp/main` has no `java-zip` module, so it must be rebased after the checksum entry lands (it is branched on `14ff03f3e94e`; once that lands its six checksum commits drop out, leaving the one `ZipException` commit). Both remain held private.
  - **Correction at 2026-11-28 02:45Z:** the zip-exception package *is* verifiable on its own, independent of `java-zip`. Its `dub.sdl` depends only on `flint:java`, and `ZipException` imports only `flint.java.io : IOException` (both on `fp/main`). A clean cherry-pick of the `ZipException` commit onto `fp/main` `1006e8990`, dropping only the `java-zip` subpackage/dependency/policy blocks and the `DataFormatException` mapping rows carried from the shared checksum base, is now `fp/sol-jpa-java-zip-exception-main` @ `369b111c0` (private). Full module DoD is green at that tree: resolve/structural/api/quality/tests/upstream-tests/budgets/link-closure pass, apps skip (evidence `.flint/sol-jpa/current/zip-exception-standalone-dod.json`); measured package probe 3,260 O3 B / 436 templates (caps 3,586/480) and leaf 3,396 O3 / 2,220 Oz B (caps 3,736/242), unchanged from the earlier measurement. It still needs the 1365 sign-off and still lands after the checksum entry by the on-approval/23:40Z rule, but its rebase no longer waits for `java-zip`.
- 2026-11-28 02:15Z, sol-template: **the public `DecimalFormat` bridge needs a ~325 B `framework/java-text` byte-cap raise, or a directed public-API reduction (open for the owner).** Local branch `sol-template-decimal-public-bridge` @ `937a75fac`, on the decimal-stack rehearsal `2019e53d7` (unpushed; the extraction/follow-ups `ba775772f` is train slot #13 and not yet on `fp/main`). The bridge adds Java's public `java.text.DecimalFormat` and `java.text.DecimalFormatSymbols` over the private renderers: `getInstance`, the constructors, `applyPattern`/`toPattern`, the grouping and integer/fraction digit accessors and setters, `format(long)`/`format(double)`, and copy-independent symbols. The `StringBuffer`/`FieldPosition` overloads, `java.util.Currency` and `getCurrencyInstance` stay deferred. `dub test :java-text` is green on DMD and LDC (21 modules); the rest of the module DoD passes except `budgets`.
  - **Measured** (`tools/measure_builds.py --framework-sizes --framework java-text`): base `2019e53d7` 56,944 B / 708 templates; bridge `937a75fac` 57,464 B / 721 templates; caps 57,139 B / 726. Templates are now under the cap; bytes are **+325 B over**. The +520 B growth is the two public classes' method bodies plus their vtable/TypeInfo, which the package probe links as one batch (B-93/S-19); it is not Phobos and not a per-pattern template expansion. The mapping rows for these members are still `excluded`/`deferred`, so the bridge claims no coverage yet.
  - **Levers already spent:** the erased-core call-site pass (one `allocate`/`seal`, one throw helper per module, one symbols factory) took templates 732 -> 721 and left bytes unchanged; the instrumented log showed 11 fewer instances. Removing `format(double)` alone measured 57,392 B (-72 B, still +253 B).
  - **Remaining options:** an owner-approved raise; or a deliberate public-API reduction (for example, defer the `format(double)`/`format(long)` string overloads until the `StringBuffer`/`FieldPosition` bridge lands) and re-measure; or move the two classes to their own registered package, which needs the new-package sign-off and its own probe. No local cap change; the branch stays private.
- 2026-11-28, sol-translator: **the `java.net.URL` dependency gap is circular, so the requested `:java` dependency cannot be added; a skeleton leaves an unreachable member type pending instead.** `framework/java-net-url` depends on `:java` (for `flint.java.lang.javaobject`), so `:java` cannot depend on `java-net-url`; the same holds for `:slf4j-api` only if its URL users are hand rows. A skeleton that declares a member whose mapped type lives in a module the destination package cannot import now records that member as `// port:pending` (as it does for an unmapped type) instead of importing it and failing the whole type's compile. On the branch `sol-translator-unreachable-pending` this takes `java.sql.PreparedStatement` from 20 to its listed 3 divergences, `java.sql.ResultSet` from 42 to its listed 2, and `org.slf4j.LoggerFactory` from 2 to 0, and raises the skeleton reproduced count from 927 to 1130 (floor 981). It is **held, not landed**, because it also drops 19 types below their listed divergence counts (the shrink-only list then needs `--write-baseline`) while eight types still exceed theirs: `io.micrometer...NoopHistogram` 2 vs 0 (attributes), `ServletRequest` 30 vs 29 and `ServletResponse` 15 vs 14 (web-http's hand ports lack the Java 6.1 `setCharacterEncoding(Charset)` default), `AbstractResourceBasedMessageSource` 6 vs 0 (framework-core's hand port), `core.io.Resource` 11 vs 10 (`:core` needs direct `java-nio-channels`/`java-nio-file` dependencies), `SimpleJdbcInsert` 11 vs 3 and `SimpleJdbcInsertOperations` 9 vs 3 (the held array/varargs element-id issue), and `BasicAuthenticationEntryPoint` 3 vs 0 (sol-security's `65628e6ce` plus the plan entry). Once those are fixed, the branch's change and one `--write-baseline` recut land together. The real long-term fix for JDBC's `URL` members is a separate `java-sql` package that depends on both `:java` and `java-net-url`; that is a new-package decision for framework-core and the owner. Test: `test_skeletons.test_a_member_type_the_package_cannot_import_is_pending`.
- 2026-11-28, sol-jpa: **`java.util.zip`'s narrow `IllegalArgumentException` leaf is `flint.java.lang.runtimeexception`.** sol-framework's `c05ddb2f8544` (train #4) defines `IllegalArgumentException` and `IllegalStateException` inside `flint.java.lang.runtimeexception`, because `RuntimeException.initCause` throws them and a separate `illegalargumentexception.d` would be a circular import; none is planned. So `java.util.zip`'s `Deflater` imports `flint.java.lang.runtimeexception : IllegalArgumentException` and its internal exception helper imports `flint.java.lang.nullpointerexception : NullPointerException`, once #4 lands. No new leaf, and no new approval beyond the ZIP package approvals already open under 1365.
