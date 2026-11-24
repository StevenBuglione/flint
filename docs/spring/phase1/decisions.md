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
