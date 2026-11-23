# ADR-030: Flint is a port of Spring

Status: accepted by the project owner on 2026-11-23.

## Context

ADR-029 made Spring Boot the reference for Flint's application model, with Flint-specific names wherever D or the performance contract pushed back. The project owner has now asked for more:
- **A port.** Flint becomes a port of the Spring ecosystem. A developer who knows Spring Framework or Spring Boot sees the same annotations, classes, methods, configuration keys and behaviour, and should feel that they are using Spring.
- **Engines.** The engine underneath stays strictly D or C.
- **Mission.** Flint's mission is unchanged: faster cold and edit builds than Go, smaller binaries, and higher throughput with lower p99, RSS and CPU per request. It is proven by measurement.

This ADR records the owner's decisions and the design that holds the mission while the API grows to Spring's size. It is milestone 13 onward in ADR-021, and replaces the remaining starter work of Milestone 10 (ADR-028).

## Decisions

### 1. Names: Spring's, with "Spring" replaced by "Flint"

Every public name is identical to Spring's, with one exception: where an identifier contains the word Spring, Flint replaces that word with Flint. Broadcom's trademark guidelines forbid "Spring" in product names. This rule keeps Flint clear of that while staying a near drop-in.

| Spring | Flint |
| --- | --- |
| `org.springframework.web.bind.annotation.GetMapping` | `flint.web.bind.annotation : GetMapping` |
| `org.springframework.boot.SpringApplication` | `flint.boot : FlintApplication` |
| `@SpringBootApplication` | `@FlintBootApplication` |
| `@SpringBootTest` | `@FlintBootTest` |
| `@WebMvcTest`, `@DataJpaTest`, `MockMvc`, `@MockitoBean` | unchanged |
| `spring.datasource.url`, `spring.jpa.*`, `spring.datasource.hikari.*` | `flint.datasource.url`, `flint.jpa.*`, `flint.datasource.hikari.*`, and the `spring.*` spelling is accepted as an alias |
| `server.servlet.context-path`, `management.*`, `logging.*` | unchanged |
| `spring-boot-starter-web` | `flint-boot-starter-web` (DUB `flint:boot-starter-web`) |

- **Package mapping.** A Java package `org.springframework.X.Y` maps to the D module `flint.X.Y`. Packages from other upstream projects map under their own roots:
  - `jakarta.validation` → `flint.jakarta.validation`;
  - `com.fasterxml.jackson.databind` → `flint.jackson.databind`;
  - `org.slf4j` → `flint.slf4j`;
  - `io.micrometer` → `flint.micrometer`;
  - `reactor.core` → `flint.reactor.core`.
- **Superseded ADR-029 names.** Where ADR-029 chose a different name, the Spring name now wins and the ADR-029 name stays as an alias:
  - `@FlintApplication` stays as an alias of `@FlintBootApplication`;
  - `@FlintTest` stays as an alias of `@FlintBootTest`;
  - `flint.data.*` stays as an alias of `flint.jpa.*`;
  - `pool` stays as an alias of `hikari`.

### 2. The repository family mirrors spring-projects

| Flint repository | Spring counterpart |
| --- | --- |
| `flint` | none: the CLI, the forked compilers, Flint AOT, gates and evidence tools, all written in Flint |
| `flint-framework` | spring-framework |
| `flint-boot` | spring-boot (core, autoconfigure, modules, starters, actuator, test) |
| `flint-security` | spring-security |
| `flint-ai` | spring-ai |
| `flint-batch` | spring-batch |
| `flint-data-commons`, `flint-data-jdbc`, `flint-data-jpa`, `flint-data-redis`, `flint-data-mongodb`, … | the spring-data family |
| `flint-cloud-gateway`, `flint-cloud-config`, `flint-cloud-stream`, `flint-cloud-openfeign`, … | the spring-cloud family |

Shell, Kafka, AMQP, Integration, Session and GraphQL follow in the same pattern.

**The split happens in two steps.** It is first prepared inside this repository: policy gains a `repo` field, and gates and tools learn workspaces. History is then extracted with `git filter-repo`. Dependency edges follow Spring's own:

- **Integrated repositories** (`flint-security`, the `flint-data-*` family, `flint-batch`) sit between boot and framework, because Spring Boot auto-configures them: boot → integrated → framework → flint. They depend on each other only where Spring does (data-jpa → data-commons).
- **Boot-based repositories** (`flint-ai`, the `flint-cloud-*` family, later Shell) ship their own auto-configuration and depend on boot: boot-based → boot.
- **Engines stay in `flint-framework`.** The existing `security` package (hashing, HMAC, secret erasure, the crypto wrappers) is one of them, so `storage` and other engines keep using it. `flint-security` ports the Spring Security API on top of it.

**Versioning.** ADR-023 gains *platform modules*:
- one repository holds many packages under one tag, resolved by platform version, never by MVS;
- `flint` pins the coordinated commits in `platform.lock`;
- a `flint-dependencies` bill of materials gives applications one coordinated set, as `spring-boot-dependencies` does.

Creating the GitHub repositories is an outward step and waits for the owner's go-ahead.

### 3. The closed world, with configuration decided at startup

- **The model.** Flint targets Spring's AOT and native-image model:
  - the classpath (the dependency closure) is fixed at build time;
  - bean definitions are generated as code;
  - proxies are generated ahead of time;
  - nothing reflects at runtime.

  The drop-in claim is therefore precise: an application that runs under Spring AOT runs under Flint.
- **What is decided when.** Only class-presence conditions (`@ConditionalOnClass`, `@ConditionalOnMissingClass`) are decided at build time. Profiles, `@ConditionalOnProperty`, `@ConditionalOnBean` and `@ConditionalOnMissingBean` are decided at startup, from generated branches. So `FLINT_PROFILES_ACTIVE=prod` set at deploy time works as it does in Boot, which Spring native cannot do. The compile-time `import("application.toml")` in `flint.di`'s conditions is replaced.
- **Flint AOT.** This is the build step in `flint build` that does the work. It grows out of `apps/flint/src/flint_tool/engine/scan.d` and runs inside the compile server, using the DMD fork's semantic analysis, so it sees real types.
  - It writes one generated module per user module, plus a thin registry, and never one central import-everything file.
  - Each generated module is plain, non-templated D:
    - bean definitions and lifecycle;
    - condition branches;
    - request-mapping and argument-resolver tables;
    - descriptor tables for message conversion, validation and `@ConfigurationProperties` binding;
    - derived-query SQL;
    - SpEL compiled to D;
    - AOP proxy subclasses for `@Transactional`, `@Cacheable`, `@Async`, `@Retryable`, `@PreAuthorize` and `@Validated`, with Spring's self-invocation behaviour.
  - The cache key is a hash of each module's interface (signatures plus UDAs), so editing a method body regenerates nothing.
  - A runtime SpEL interpreter exists only for expressions that are dynamic.

### 4. Runtime: fibers as virtual threads, memory split by visibility

- **Fibers.** Every handler runs on a reactor fiber, as Spring MVC runs on virtual threads. Blocking-style APIs (`JdbcTemplate`, `RestClient`, `KafkaTemplate`, `JavaMailSender`) suspend on I/O through `TaskWaker` and `yieldUntil` (ADR-017). The single worker thread for ordinary handlers is retired.
  - Fiber stacks reserve 256 KiB with guard pages.
  - Blocking C calls go to a bounded offload pool.
- **Fiber-local state.** `FiberLocal!T` carries what Spring keeps in `ThreadLocal`: transaction synchronization, the security context, request attributes, locale and the logging MDC. Framework packages may not keep mutable module-level thread-local state, and a structural check enforces this.
- **Runtime API added in Phase 0** (`flint.reactor`, extending ADR-017's public API):
  - `shared FiberLocal!T` has `get`, `set` and `remove`, all `@safe nothrow @nogc`. Each task fiber sees its own value and starts at `T.init`. The cells are stamped with the task generation `TaskWaker` uses, so a reused fiber slot never shows the previous task's value, and the cells are cleared when the task ends. Off a task fiber (loop callbacks, offload threads, foreign threads) the value is thread-local. `T` is a class or interface reference or plain data without copy or destruction hooks. Storage is `ReactorOptions.fiberLocalWords` words per fiber (default 32), from a process-wide budget of `maxFiberLocalWords` (128); a local uses one word plus its value.
  - `ReactorOptions.fiberStackBytes` defaults to 256 KiB (was 64 KiB), and `fiberGuardBytes` (default 16 KiB, rounded to pages) is reserved inaccessible below each stack, so an overflow faults in the guard instead of corrupting memory. A single frame larger than the guard can still step over it. Only touched pages are resident: 1,024 idle fibers add 4,096 KiB of RSS with either stack size on Linux x86-64 (`packages/reactor/tests/fiber_stack.d`).
  - `Reactor.offload(work, interrupt)` runs blocking work, such as SQLite or blocking libpq calls, on `ReactorOptions.offloadThreads` threads (default 0, disabled) with at most `offloadQueueCapacity` calls admitted (default 64). Only the calling fiber suspends; callers beyond the capacity wait for room. A finished call wakes its fiber through a per-worker pipe watched like a native descriptor, or by a 1 ms poll where watches are unavailable. The work may borrow the fiber's frame. Cancellation withdraws work that has not started; started work gets `interrupt` once (`sqlite3_interrupt`, `PQcancel`) and the fiber still waits for it to return before reporting `cancelled`. Shutdown waits the same way, so no borrowed storage outlives its use.
  - The structural rule is `module_thread_locals` in `tools/gates.py` and FLINT-E0514 in `flint check`. Existing thread roots, such as the reactor's loop identity, per-thread caches and C callback trampolines active during one call, are listed in `thread_local_allowlist` in `policy/safety-policy.json`. New entries need review, and a stale entry fails.
- **Memory.** Engine memory (parsing, routing, JSON tokens, buffers) stays in the request arena. Everything user code can see (`string`, DTOs, entities, collections) is GC memory, and arena memory is never handed to user code. Entities use `string` fields, which settles ADR-028 section 7.4.
- **GC.** Each binary bakes in its GC configuration through `rt_options`. Phase 1 measures a matrix of collectors and settings on idiomatic application code.
  - **Agreed fallback:** if p99 or RSS loses to Go, Flint builds a D collector with per-thread allocation caches, registered through druntime's GC interface.
- **Exceptions.** User-facing APIs throw Spring's exception types.
  - Framework control-flow exceptions (`ResponseStatusException`, `EmptyResultDataAccessException`, validation failures) skip backtrace capture.
  - Engines return `Result`, and generated dispatch converts to an exception only at the user boundary.
  - The 404 and validation paths have their own p99 tests.

### 5. Size and compile time

- **Classes.**
  - The DMD fork gains an opt-in switch that leaves out `ModuleInfo.localClasses`, so unused classes become garbage for `--gc-sections`. Construction from string names is already banned.
  - LDC is unmodified today. Whether it needs the same patch is an open decision, settled with measurements.
  - Value types (`HttpHeaders`, `MediaType`, `HttpStatus`, `ResponseEntity`) are structs. Classes are used only where Spring users subclass or implement, and are `final` by default.
- **Linking.**
  - Linux glibc outputs link with packed relative relocations (`-z pack-relative-relocs`).
  - A TLS-only OpenSSL build, keeping the benchmark's TLS profile, needs its own ADR.
- **Imports.**
  - Framework modules have no `package.d` aggregators.
  - Annotation modules are leaves that import only UDA structs.
  - Functional parameters use non-template delegate types.
- **Erased core.** Generic public APIs are one-line façades over descriptor-driven, non-template engines, as Java's erased generics are. Factory-heavy generic types such as `ResponseEntity` are erased structs whose templated factories capture `T`'s descriptor. Precompiled libraries cannot reduce template instances, so the erased core is mandatory.
- **Amendment to ADR-016.**
  - **What may be cached.** The pinned platform modules (`flint-framework`, `flint-boot` and the portfolio repositories at the platform version) play the role of Go's standard library. The compile server may hold their semantic analysis, and they may ship as precompiled archives plus `.di` files.
  - **Reproducible.** Archives are built by `flint` from pinned source, and their hashes must equal a local rebuild.
  - **Cache key.** Compiler, flags, platform version and target.
  - **MVS modules.** Third-party modules resolved by MVS always compile from source.
  - **Two published headlines:**
    - the platform cache against Go with a standard-library-primed `GOCACHE`;
    - everything from scratch against `go build -a` with an empty cache.
- **Budgets.** Every framework module carries budgets for added compile time, linked bytes, template instances and generated lines per bean or handler, on top of ADR-019's per-package budgets.

### 6. The API mapping rulebook

[`docs/spring/api-mapping.md`](../spring/api-mapping.md) defines how a Java API element becomes a D one. It has rules R1–R14, each with an ID and an example. Every adapted element cites its rule, and every deviation is listed there with its reason. Elements that cannot exist in D or in a closed world are excluded with a reason category. Examples are JMX, JNDI, JSP, Java serialization, JFR, CRaC, load-time weaving, runtime CGLIB, the jar launcher and the restart classloader.

### 7. Licences, attribution and trademarks

- **Licence.** Every Flint repository is Apache-2.0.
- **NOTICE.** Its `NOTICE` carries Flint's notice, the verbatim NOTICE of each upstream project ported, and the trademark statement: "Spring, Spring Framework and Spring Boot are trademarks of Broadcom Inc. and/or its subsidiaries. Flint is not affiliated with or endorsed by Broadcom."
- **Ported files.** Every ported file starts with:
  - the upstream project, path and pinned tag;
  - "Copyright 2002-present the original author or authors" (or the upstream project's own line);
  - "Licensed under the Apache License, Version 2.0";
  - "Modified by the Flint authors", as Apache-2.0 §4(b) requires.

  Javadoc moves into DDoc under the same terms.
- **The licence matrix.** [`policy/upstream-licences.json`](../../policy/upstream-licences.json) records each upstream project, its licence, the evidence, and how Flint may use it:
  - **Port from source:** Apache-2.0, MIT and BSD.
  - **Port under the BSD option:** dual-licensed projects that offer BSD (Jakarta Persistence).
  - **Separate EPL modules:** EPL-2.0-only projects (Jakarta Servlet, Mail and Transactions) and Logback's EPL-2.0 option are ported into separately licensed EPL-2.0 modules. EPL's copyleft applies per file, so it never reaches applications.
  - **Clean-room:** LGPL, GPL and source-available licences, such as Liquibase's FSL, are implemented from specification and documentation only. No code is copied.

  The `flint api` command family checks every ported file's header against the matrix.

### 8. Proof

- **API coverage.**
  - `flint api extract` turns each pinned upstream source tree into a manifest of every public and protected element.
  - `api/mapping.json` classifies each element as ported, adapted (with a rule ID) or excluded (with a reason).
  - `flint api coverage` fails on any unclassified element.
  - `flint api diff` schedules the work of following a new upstream release.
  - **The parser is a small Java declaration parser written in D** (`apps/flint/src/flint_tool/api/java.d`), not tree-sitter-java:
    - **Closure.** The `flint` closure stays free of native code. It bootstraps from DUB with only the core D packages, and tree-sitter would make it the first CLI dependency to need a native recipe.
    - **Scope.** A manifest needs declarations only. A lexer that understands comments, strings, characters and text blocks, plus bracket balancing over bodies and initializers, recovers them without a full grammar.
    - **Size and speed.** It is about 1,000 lines, and it extracts Spring Framework's 4,789 files in under a second.
    - **Verified.** On the pinned tags it parses every file of both trees. The published Maven Central jars, read with `javap -protected`, give the same set of types and the same member names and arities: 33,111 members for Framework v7.1.0 and 12,611 for Boot v4.2.0. The only differences are classes javac writes but no source declares (bridge methods, public methods inherited from package-private superclasses, and Kotlin and AspectJ types), and the repackaged ASM, CGLIB and Objenesis sources, which the check leaves out on the jar side.

    `flint port-spring` translates method bodies, which a declaration parser cannot read, so it still uses tree-sitter-java.
- **Behaviour.** Each module ports its upstream JUnit tests and publishes counts of ported, passing and excluded tests.
- **Side by side.** Spring Guides applications, spring-petclinic-rest, classic spring-petclinic and the vibe benchmark's Spring Boot references (`benchmarks/vibe/reference/spring`) are ported to Flint. One black-box suite runs against the Java and Flint applications and requires identical status codes, headers, JSON (including Spring's error and `ProblemDetail` bodies) and actuator output.
- **Mechanical translation.** A deterministic translator, `flint port-spring` (tree-sitter-java, MIT), applies only rules with an ID. Its score is the share of Guides files that compile and pass without edits. It tests the rulebook; the hand ports stay the acceptance artifacts.
- **Metrics.**
  - Every application has a Go comparator (stdlib `net/http` + `database/sql`), registered before measurement.
  - `measure_builds`, `load_bench` and the gates must show Flint below Go on every metric on the designated runner.
  - Java Spring Boot (JVM and native) is reported alongside, as context.

### 9. Upstreams pinned

| Upstream | Tag |
| --- | --- |
| Spring Framework | v7.1.0 |
| Spring Boot | v4.2.0 (both GA on 19 Nov) |
| Portfolio projects | matching tags, recorded in `policy/upstream-licences.json` |

Sources are fetched by checksum into a reference cache and never compiled.

## What this supersedes

- **ADR-029:**
  - the name table where it departs from Spring (section 1 above);
  - section 5's "no proxies" (proxies are now generated subclasses with Spring's semantics);
  - section 5's request-arena exposure (user code never sees the arena).
- **ADR-028 section 7.4:** entities use `string`.
- **Milestone 10:** the remaining starter items. Starters are rebuilt in `flint-boot` under Boot's own module layout.
- **AGENTS.md:** it gains the API-layer rules below. Engines keep every existing rule.

## AGENTS.md changes

- **The API layer** (Spring-shaped public types in the framework, Boot and portfolio repositories) follows Spring's shape: classes, interfaces, exceptions, the GC and getters and setters, as the rulebook maps them. It is still `@safe`.
- **Engines** keep `nothrow @nogc` hot paths, the request arena and `Result`.
- **Reflection and generation** are approved in Flint AOT (in `flint`), and in the API layer's internals listed in the rulebook.

## Open decisions

- Whether to patch LDC to leave out `localClasses`, settled with measurements.
- The JPA engine: persistence context, dirty checking, lazy loading, JPQL compiled at build time, Criteria. It is ported from Hibernate ORM (Apache-2.0 since March 2025) and gets its own ADR.
- The TLS-only OpenSSL build, which gets its own ADR.
- The ADR-023 amendment for platform modules, written with the split's preparation.

## Phases

| Phase | Milestone | Content |
| --- | --- | --- |
| 0 | 13 | This ADR, the rulebook, the licence matrix, `flint api`, the runtime and size levers, and the split's preparation. |
| 1 | 13 | **Proof slice.** spring-core subset, beans, context, web, webmvc over a minimal servlet layer, jdbc, tx; Jakarta Validation, Jackson databind subset, SLF4J; Boot core, autoconfigure for web, JSON, JDBC, transactions, validation and SQL init; boot-test with MockMvc. gs-rest-service, gs-relational-data-access and spring-petclinic-rest (JDBC) must give identical output side by side and beat Go on every metric, including the GC matrix. If any metric misses, Flint takes the fallback or redesigns before scaling out. |
| 2 | 14 | Fan-out in parallel, one repository or module per session: Data Commons and JDBC, Security, caching, `@Async`, `@Scheduled`, `RestClient`, Actuator with Micrometer, Thymeleaf with SpEL, the JPA engine and classic PetClinic, and `flint-ai`. Engines without a Spring counterpart take Spring's idiom (cli and tui as Spring Shell; mq as Spring Kafka; storage as `S3Template`). |
| 3 | 15 | The long tail: Kafka, AMQP, Redis and MongoDB on their C clients; Reactor, WebFlux, R2DBC; WebSocket and STOMP; Batch, Integration, Cloud, Session, GraphQL; the remaining Boot modules. |
