# Phase 1 coordination: how sessions work without waiting

This file lets the Spring port sessions (ADR-030) keep moving when neither the owner nor the coordinating session is available, for example overnight. Read it with `AGENTS.md`, ADR-030 and `docs/spring/api-mapping.md`. It changes no rule in those documents. It says who decides what, and what to do instead of waiting.

## Owners

| Area | Owner session | Session id |
| --- | --- | --- |
| Policy files, gates, `flint` CLI, the repo split and cutover script, platform modules | m7-flint-cli | `local_b3b0e1d4-1ab1-4131-9e4f-9edafa3e0c97` |
| Flint AOT generator, `docs/spring/aot-contract.md` | flint-aot | `local_b0dd4e57-2db1-4296-aecc-1fb59250b014` |
| `framework/java`, `framework/core`, beans, context, `framework/engine-aot` runtime | framework-core | `local_177a74aa-a9f6-4b1f-bf48-23b4f1437bf9` |
| `framework/web`, `webmvc`, `jakarta-servlet`, `framework-test` (`flint.test.web.*`), `engine-web` `FiberRoute`, the servlet adapter, retiring `framework/p1-interim` | web-http | `local_16478490-9a4d-495d-8724-1eb6a895befb` |
| `framework/jdbc`, `tx`, `engine-jdbc`, `aop` (when needed), the SQL engine ABI | data-access | `local_958a603d-3656-43cf-a5cf-f6d0081b0398` |
| Jackson, SLF4J, Jakarta Validation and Annotation | third-party-apis | `local_cc8431bb-4562-4cd2-8239-d8e51c82c6c4` |
| `boot/` (core, modules, starters, `flint.test.context.*`), the legacy Boot packages | boot | `local_9c1d4681-99d8-4e73-bc65-9a7ac1bbf58f` |
| `benchmarks/spring/`, the measurement queue and its quiet-window watcher, framework budgets in the measured gate | proof-harness | `local_06eb8459-e6b9-4e74-83d6-2542ee57b673` |
| `flint api`, the api gate, coverage baselines, header checks, package registration | api-coverage | `local_7afcbe30-d9c8-442e-87e2-713ff2851265` |
| Size levers, framework module budgets and probes, ADR-031 | size-levers | `local_8b7074aa-9040-4e67-963f-9e7fa47c4c84` |
| DMD fork (AArch64, macOS and Windows speed features in the patches) | dmd-arm64 | `local_16d4bbf5-0ef1-4d70-801c-8e67d9f3373a` |
| Native Linux aarch64 lane (VM on pluto) | linux-arm64-vm | `local_11b98e39-0c8b-4c60-ada2-15d7e45b0f06` |
| macOS arm64 lane (pluto) | "Flint on macOS arm64 (pluto)" | Remote Control |
| Windows x86-64 lane (Windows VM) | "Flint on Windows x86-64" | Remote Control |

## Rules for deciding without waiting

1. **The documents decide first.** `AGENTS.md`, ADR-030, ADR-031, the rulebook, `aot-contract.md` and this file. If they answer the question, act on them.
2. **The owner decides inside its area.** Ask the owner directly with `python3 tools/agentctl.py send` (a Claude `SendMessage` may go alongside as a doorbell), not through the coordinator. Every role also writes its hand-off state with `agentctl handoff` at the end of every turn, so an agent in any harness can take the role over (`docs/agents/README.md`).
3. **Never wait more than 30 minutes for a peer.** If the owner hasn't answered and you're blocked, take the smallest reversible step that unblocks you:
   - add new files in the owner's package rather than editing its existing ones;
   - keep the change in a commit of its own;
   - tell the owner what you did and why;
   - the owner may rework it later.
4. **Record decisions.** Any decision the documents didn't cover goes in `decisions.md` beside this file, as one dated line: who, what, why. Rebase conflicts in that file are resolved by keeping both lines.
5. **Things only the owner of the project may decide:**
   - changing the D language;
   - raising a budget or cap, or weakening a gate or test bound;
   - changing a benchmark workload, TLS profile or Go comparator;
   - deleting another session's work;
   - creating or deleting GitHub repositories;
   - the real cutover (`tools/cutover.py --push`);
   - anything in `handoff/`.

   For these, write the question in `decisions.md` under "Open for the owner", and carry on with something else.

## When messaging is paused, and while waiting

The app pauses a session's outgoing messages after about 20 messages without the owner typing in that session. When that happens, or whenever a message isn't urgent, use the shared inbox on venus instead. It lives outside git, so it needs no commits.

- **Inbox location.** `/home/olfa/flint-work/coordination/inbox/<session-name>.md`, one file per session, using the names in the Owners table (`web-http.md`, `boot.md`, `framework-core.md`, …).
- **Writing.** To reach a session, append to its file: a dated line with your name, then the message. Never edit or delete other people's lines.
- **Reading.** At the start of every turn, and before ending one, read your own inbox. Act on new lines, then append `read <time>` so the sender can see you've seen them.
- **Waiting.** Don't end your turn just to wait for an answer. Take other queue work, or arm a Monitor on your inbox file (for example `inotifywait -e modify` or a short polling loop), so an answer wakes you.
- **Remote sessions.** The macOS and Windows sessions can't read venus's files. Keep using `SendMessage` for them.

A session should end its turn only when every queue item it could take is claimed or blocked, and its inbox has nothing new.

## Rules for landing

- **Before every push:**
  1. rebase onto `flint-projects/flint` main;
  2. run the package's tests on DMD and LDC;
  3. run `python3 tools/gates.py --gate structural` and `python3 tools/quality.py`;
  4. after changing a package's dependencies, run `python3 tools/check_locks.py` and relock what it names (`flint lock -C <project>`) in the same commit.
- **Policy edits** regenerate the platform outputs in the same commit (`python3 tools/platform_modules.py --write`, FLINT-E0534).
- **New packages** under `framework/` or `boot/` are registered in `policy/framework.json` or `policy/boot.json` in the commit that adds them (FLINT-E0535). When registering an allowlisted package, delete its line from `policy/unregistered-packages.json` in the same commit.
- **Push each verified step.** Never force-push. Never push to the mirror repos (`flint-framework`, `flint-boot`, `flint-ai`, `flint-data-jdbc`); m7-flint-cli refreshes them with `tools/extract_repo.py --all --push`.
- **Performance findings go into `docs/spring/performance-playbook.md`** in the same commit as the change: the rule, the evidence (numbers, commit and how they were measured) and what enforces it. The playbook is the master list of what every port must do to stay fast, small and quick to build.
- **If you break `main`, fix it first,** before anything else. If someone else broke it and isn't responding within 30 minutes, the smallest fix that restores green is allowed, in a commit of its own, with a note to them.

## Measurement

Timing evidence is taken only by the proof-harness watcher when venus has been quiet for 5 minutes (`tools/measure_queue.py`). While a timed run is in progress, `/home/olfa/flint-work/flint/.claude/worktrees/jolly-mendeleev-ea37ba/.flint/measure/MEASURING` exists. It holds the entry id, start time and pid. Hold compiles while it exists, and build freely when it doesn't: the watcher refuses to start a run while other sessions' builds use CPU. The easiest way is to run heavy builds and test suites through the queue's pause wrapper, from any checkout:

```bash
export FLINT_MEASURE_LOCK=/home/olfa/flint-work/flint/.claude/worktrees/jolly-mendeleev-ea37ba/.flint/measure/MEASURING
python3 tools/measure_queue.py hold -- flint test --compiler both
```

The wrapper stops the command's whole process group (SIGSTOP) while the lock exists and continues it afterwards, so a build that is already running pauses too. A paused build uses no CPU, so the queue ignores it. The watcher claims windows: it takes the lock, waits up to 90 s for wrapped work to pause (three quiet samples 5 s apart), and then measures. If the window does not settle, because some build is not behind `hold`, it releases the lock and tries again 5 minutes later. Queue timing runs with proof-harness rather than measuring yourself. Byte sizes and template counts are deterministic and may be measured any time. On pluto, the macOS, linux-arm64-vm and dmd-arm64 sessions agree quiet windows among themselves.

Queue policy (coordinator, 2026-11-23). A claimed window pauses everyone, so it is spent only on short entries that gate a decision:

- **Claimed windows.** Only entries of about 30 minutes or less that gate a decision claim one. They are gs-builds (per-phase timings and the prelude), gs-rest-multicore-2, the error-path p99s once boot's Date-based error timestamp lands, and the per-application Phase 1 parts under the conditions below. Each entry file says `"window": "claim"` or `"natural"`; without one, an entry estimated at 30 minutes or less claims and anything longer is natural. An entry over 30 minutes claims only when the coordinator names it.
- **Natural quiet.** Long, low-priority entries run only after 5 minutes of natural quiet with no `hold`-wrapped work alive, and never take the lock: they are framework-timings, the GC matrix, java-context and phase1-guides. While one runs, `.flint/measure/MEASURING-NATURAL` exists. `hold` ignores it, so nobody pauses. The moment another session's build or `hold`-wrapped command appears, the run stops and records the attempt as interrupted, not evidence.
- **Order (coordinator, 2026-11-23 19:25Z: runtime is the Phase 1 blocker).** Each entry's `priority` (lower first) comes before its estimate, and natural entries wait while any claimed entry is pending. The gs-builds run pinned at `aa17876b` finishes first, uninterrupted. After it, runtime runs take claimed windows ahead of build runs:
  - **priority 1:** a gs-rest-multicore re-measure. Add one per meaningful batch of allocation cuts on main, not per commit: roughly every 25% drop in allocations per request, by data-access's per-request allocation gate (`policy/request-allocations.json` once it lands). The baseline is gs-rest-multicore-3 at `1141a9bc`, at 31 allocations per request (web-http's `bc808cca`), so the next one is due at about 23 or fewer.
  - **priority 2:** the error-path p99 entries, once boot's Date timestamp lands, and the per-application Phase 1 HTTP parts under their conditions below.
  - **priority 5:** build-time runs (gs-builds, link A/Bs, the Phase 1 builds parts). They take a window only when no runtime run is ready.
  - The GC matrix parts (41 to 61 minutes) stay on natural quiet: they don't gate a decision yet, and the allocation cuts landing now will change the heap's behaviour. The coordinator will name them as claimed exceptions once allocations per request plateau near target, or when D3 has a collector candidate to compare with druntime's (coordinator, 19:35Z).
- **Gap.** Consecutive claimed windows are at least 10 minutes apart (`watch --claim-gap-minutes 10`), so work held during one runs before the next pauses it.
- **Phase 1 parts (coordinator, 16:45Z).** phase1-builds and phase1-http gate the Phase 1 exit, so they may claim windows as named exceptions. They are split per application, with the same trials, durations and comparators, only scheduled separately. Each part certifies on its own, and `spring_bench.py assemble` merges the parts and flags any that were measured at different commits:
  - phase1-builds-gs-rest, phase1-builds-gs-relational and phase1-builds-petclinic, about 17 minutes each;
  - phase1-http-gs-rest and phase1-http-petclinic, about 41 minutes each.

  They claim only when the numbers can move the decision, and until then they run only on natural quiet (`"window": "natural"`, with the condition in `claim_when`):
  - phase1-builds claims after the gs-builds certification (phases and prelude) shows a primary ratio under about 1.5;
  - phase1-http claims after the io_uring steps and the RSS and GC fixes land, since a run that only confirms today's 0.75x throughput isn't worth pausing everyone.

  All five also stay blocked until petclinic-rest scores 109/109 and the parts are pinned to one commit where every port passes exactly.

## Work queue

When your assigned work is done, don't stop.
1. **Claim** the first unclaimed item below that fits your area or skills, by pushing a one-line edit that puts your session name in its "Claimed by" cell.
2. **When it's done,** mark it done with the commit hash.
3. **New tasks:** add them at the bottom when you discover them.

| # | Item | Claimed by | Done |
| --- | --- | --- | --- |
| 1 | Retire `framework/p1-interim`, register `framework/web`, `webmvc`, `jakarta-servlet`, `framework-test` | web-http | `404c77c` (p1-interim retired), registration in the commit that marks this |
| 2 | `FiberRoute` in `engine-web`, the servlet adapter, and a start/stop/port API for Boot | web-http | |
| 3 | Boot on `flint.context`; web-server auto-configuration on the servlet adapter; the gs-rest-service Flint port passing `spring_bench.py accept` | boot | `17218ac` (web server, MVC and error auto-configurations, the port), `2494670` (ServletContextInitializer, graceful shutdown), `d6e3db5` (base-package); 18/18 exact with web-http's `3d49760` (Content-Language), confirmed independently by proof-harness |
| 4 | `engine-jdbc`, `JdbcTemplate`/`JdbcClient`; the gs-relational-data-access Flint port passing its suite | data-access | `94f6762` (driver), `199f62a`, `85df9af` (JdbcTemplate), `8fd18b6` (JdbcClient); Boot app `47ec8e1` (boot) passes 1/1 |
| 5 | Beans and context complete for Phase 1 (`@Configuration`/`@Bean`, `@Value`, profiles, events, lifecycle) with upstream tests ported | framework-core | `0ef8a7b`, `c12b3c3`, `4f280e5` (gaps listed in `framework-core.md`: listener replies, FactoryBean, `@Priority`) |
| 6 | jackson-databind subset byte-equal with Jackson, SLF4J, Jakarta Validation with Hibernate Validator messages | third-party-apis | `01947a2` (java.time), `daa0b85`, `d13b99b` (arrays, Optional, enums, records, `@JsonNaming`), `51756be`, `6e870d2` (validation); goldens and gaps in `third-party.md`; against spring-petclinic-rest: `08235db` (`\p{L}` in `@Pattern`), `b3e0272` (custom constraints, violation builder), `c3aa2b8` (`@JsonAnyGetter`; the suite's 14 recorded DTO bodies byte-equal). Every `defaultMessage` the suite records is Hibernate's; the end-to-end suite runs with item 10 |
| 7 | AOT contract 2 emission; mapping and descriptor tables for the three Phase 1 apps | flint-aot | `63b6caf5` (contract 2), `7d7f06d8` (gs-rest-service against the real annotations), `ed9f8708` (contract 3 and petclinic-rest's shapes); gs-relational-data-access runs on the generated tables with boot's `47ec8e1`. Contract 3 since; later fixes in `aot-contract.md` section 12 |
| 8 | Framework module budgets and probes for every `framework.json` module | size-levers | `01d5802`..`2e021fd` (timings provisional until proof-harness's quiet-window run) |
| 9 | Cutover decisions 1–7 in `tools/cutover.py` and the CLI | m7-flint-cli | `ce402cc`..`f228c76`. Linux and macOS rehearsals pass, except the known items 19 (golden-wasm-app) and 14 (gs-rest-service, in progress). The Windows rehearsal is green at `dee89bda`: 27 of 27, cutover commit 2303324e, on the Windows 11 VM, 9.3 min |
| 10 | spring-petclinic-rest (JDBC) Flint port passing its suite | data-access (`local_958a603d`) | |
| 11 | Classification sweeps: lower the coverage baselines by classifying excluded and adapted elements in the Phase 1 checklists, with the module owners' agreement | api-coverage (`local_7afcbe30`) | |
| 12 | SpEL subset compiled to D for `@Value("#{…}")`, `@Cacheable(key=…)` and `@PreAuthorize` | flint-aot | b3ac47b, ed9f870, e171856 |
| 13 | Port the upstream JUnit tests for spring-web and spring-webmvc classes already ported | macOS session (from size-levers) | `8087167`..`1d117caa`: 43 upstream classes, 747 tests ported; unported features and likely bugs behind named version gates, reported to web-http |
| 14 | Spring-style REST benchmark app (Flint) for `load_bench`'s Spring workload. Scope (proof-harness): the workload measures the side-by-side ports themselves, so this is the gs-rest-service and petclinic-rest Flint apps under `benchmarks/spring/flint/<app>/` with their `flint-spring.json` (build, cached, scratch, O3 and Oz commands), written against the framework as items 2, 3, 4 and 10 land; the framework and auto-configuration stay with their owners | proof-harness | |
| 15 | Windows platform lane receipt (Gate 6) | Windows session | receipt at `3988927` (exit 0, 455 s, LDC; 37 of 37 packages, the negative fixtures and the betterC runs; `verified_receipt` passes against that commit) |
| 16 | macOS platform lane receipt in a quiet window | macOS session | receipt at `10ae6c3` (exit 0, 454 s, forked DMD and LDC) |
| 17 | linux-aarch64 platform lane receipt | linux-arm64-vm | |
| 18 | DMD arm64 stage 2 (Flint on DMD arm64) | dmd-arm64 | macOS: 37/37 plus engine-desktop in the GUI, lane receipt `10ae6c3` on the fork; Linux arm64: `f3419a15` (the fork builds there), `c21e0c90`, lane `b758925` (`556fbc08`) with the fork and LDC, every bound asserted |
| 19 | `examples/framework/golden-wasm-app` compiles again: `flint_demo/sys/exports.d` assigns `CommandBuffer` and `SignalGraph`, whose `opAssign` engine-wasm-bridge and engine-ui-signals now `@disable` (found by m7-flint-cli; `build.py` itself is fixed) | third-party-apis | `ea21b76` (Oz and O3 link; Node smoke run of the four exports) |
| 20 | Toolchain PGO training after the cutover: `install_toolchains.py` `PGO_APPS` trains on `examples/framework/golden-rest-service` and `benchmarks/bench-rest`, which are engine applications that leave the flint repo. Train through the fetched framework platform module, or choose flint-repo apps (found by m7-flint-cli) | | |
| 21 | **Priority.** Template diet for the framework modules before any budget is raised: find where each module's instances come from (druntime hooks, Phobos, `flint.java` generics), cut them by the erased-core rule (ADR-030 section 5): non-template engines, no Phobos in the API layer, and generic façades that are one-liners. Report per module before and after in `decisions.md`, so the owner decides budgets on the reduced counts | size-levers | |
| 22 | Pin a D-Scanner that parses named-argument UDAs (Flint's annotation idiom, R2), then lint framework/ and boot/ with quality.py too | m7-flint-cli | Part 1 done in `8642a068`: dfmt 0.15.2 and D-Scanner 0.16.0-beta.5 build on libdparse 0.25.1 plus `toolchain/libdparse-0.25.1-named-uda.patch`, so named-argument UDAs parse, and the lint trees still report 0 issues. Part 2 is open: lint framework/ and boot/. That shows 318 D-Scanner findings and 9 dfmt diffs (web 145, webmvc 78, framework-test 52, boot 14, jakarta-servlet 13, others under 5), which need fixes or dscanner.ini module filters agreed with web-http and boot |
| 23 | Platform cache (ADR-030 section 5): `flint build` compiles the pinned platform modules (flint-framework, flint-boot) into reproducible archives plus `.di` files, keyed by compiler, flags, platform version and target, or keeps their semantic analysis in the compile server. `--no-platform-cache` builds them from source, for the secondary headline. Proof-harness's `measure.cached`/`measure.scratch` commands wait on it (found by m7-flint-cli) | m7-flint-cli (archive half), dmd-arm64 (compile-server half) || archive half done: `flint build` links cached, reproducible archives (decisions.md). Next: the compile-server half with dmd-arm64, and proof-harness re-measures |
| 24 | Spring Security subset for spring-petclinic-rest, staged under `security/` (repo `security`): core (Authentication, SecurityContextHolder on FiberLocal, UserDetails, ProviderManager, DaoAuthenticationProvider), JDBC users, `@PreAuthorize`/`@EnableMethodSecurity` as an advisor over flint-aot's compiled SpEL, the web filter chain (headers, HTTP Basic, authorization, exception translation) over web-http's servlet adapter, and the `HttpSecurity` DSL. petclinic-rest passes with `petclinic.security.enable` false and true. Needs boot (`SecurityAutoConfiguration`), web-http (filters), proof-harness (secured-mode goldens) and a BCrypt verifier (open for the owner) | framework-core | |
| 25 | Port the upstream JUnit tests for the spring-core (util, convert, env, annotation), spring-beans, spring-context, spring-jdbc and spring-tx classes already ported, the way item 13 did for web. Every gap and difference goes behind a named version gate that is checked to fail when enabled, and findings go to the owners' inboxes. Coordinate with framework-core and data-access | macOS session | `97c155dc`..`d15da338`: 46 upstream classes (spring-jdbc, spring-tx, spring-core, spring-beans, spring-context), about 840 tests ported; gaps and likely bugs behind named version gates, relayed to data-access and framework-core |
| 26 | Port the upstream JUnit tests for the Spring Boot classes already ported (core: `Binder`/relaxed binding, `SpringApplication`→`FlintApplication`, config data and profiles; autoconfigure for web, Jackson, JDBC, transactions, validation, SQL init and security) and for jackson-databind and Hibernate Validator, the way items 13 and 25 did. Gated gaps; findings go to the coordinator for boot's and third-party-apis' inboxes | macOS session | `80836da7`..`1f06c273`: Boot JDBC, transaction and security autoconfigure; Binder, config data and profiles; FlintApplication, failure analyzers, origins and availability (boot-core 623 tests); web server, WebMVC, Jackson, validation and message source autoconfigure; Hibernate Validator; 15 jackson-databind classes. Gaps and likely bugs behind named version gates, relayed to boot and third-party-apis |
| 27 | Fix the highest-impact gated bugs that the owners haven't reached, under the 30-minute rule (owners idle): one commit per fix, the fix ungates its test, and a line in the owner's inbox. In order: (1) the servlet engine and Boot serve on all CPUs by default, not 1 reactor thread; (2) Jackson rejects invalid number strings, omits null `Nullable` under NON_NULL, and fails on self-references instead of segfaulting; (3) Boot disallows bean overriding and circular references by default, and OncePerRequestFilters cover ERROR dispatch; (4) Hibernate Validator reports non-numeric strings as invalid instead of HV000030; (5) the `cleanupTransactionInfo` leak, if data-access hasn't fixed it; (6) the TypeDescriptor nested-element segfault. Leave design-level items (annotation inheritance, @AliasFor runtime merging) to their owners | macOS session | `55a5e264`..`176085c9`, one commit per fix: (1) `server.flint.threads`, default every CPU up to 16 (ADR-030 section 4); (2a-c) Jackson `NumberInput.parseDouble`, Nullable inclusion, direct self-references; (3a-b) Boot overriding and circular references off, OncePerRequestFilters on every dispatcher type; (4) BigDecimal syntax for numeric Strings; (5) TransactionInfo cleanup in a finally; (6) nested TypeDescriptors. Each ungates its tests; owners' inbox lines sent to the coordinator. Linux reruns and petclinic-rest (PostgreSQL) are venus's |
| 28 | Per-request allocation budget gate (owner decision, decisions.md 2026-11-23). Each Phase 1 app (gs-rest-service, gs-relational-data-access, petclinic-rest) gets a test that serves each endpoint the black-box suite covers (the 2xx paths plus the 404 and validation-error paths) through the real servlet path, after warm-up. It counts GC allocations and bytes per request on the serving thread, and fails above a checked-in budget in `policy/request-allocations.json`. Budgets start from the measured count ×1.25, rounded up, and only go down: the structural gate refuses raises, as it does for template budgets. The test names the top call sites on failure. It runs in `dub test`/CI on DMD and LDC, is deterministic (no timing), and its counts are recorded beside gc.md's allocation table | data-access (with proof-harness for the app fixtures) | |
