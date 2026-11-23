# The Spring side-by-side harness

This harness holds the evidence for Phase 1's two claims (ADR-030 section 8):
- **Flint behaves as Spring does.** One black-box suite per application runs against the Java Spring Boot reference and the Flint port, and both must give identical responses.
- **Flint beats Go.** Every application has an idiomatic Go comparator that passes the same suite. `measure_builds`, `load_bench` and the gates compare Flint against it.

The harness stays in the `flint` repository after the split, because it is evidence tooling.

## Applications

| Application | Kind | Java reference | Go comparator | Database |
| --- | --- | --- | --- | --- |
| `gs-rest-service` | HTTP | spring-guides/gs-rest-service `complete/` | `net/http` | none |
| `gs-relational-data-access` | command | spring-guides/gs-relational-data-access `complete/` | `database/sql` | H2 in memory (Java); SQLite in memory, `modernc.org/sqlite` (Go) |
| `petclinic-rest` | HTTP | spring-petclinic/spring-petclinic-rest, profiles `postgres,jdbc` | `net/http` + `database/sql` | PostgreSQL 18.7, `pgx/v5/stdlib` (Go) |

[`apps.json`](apps.json) pins each reference by commit and archive sha256. Each one runs on Spring Boot 4.2.0 and Spring Framework 7.1.0, under Temurin JDK 21.0.13.1+2 and Maven 3.9.16. The only edit to upstream is the `spring-boot-starter-parent` version, from the one in `boot_parent` to 4.2.0, and `fetch` fails if that edit does not apply exactly once. The licences are Apache-2.0 and are recorded in `policy/upstream-licences.json`.

The references are fetched into `.flint/spring/`, never vendored. Their Maven artifacts are checked against Maven Central's checksums (`--strict-checksums`). The resolved parent pom and BOM are checked against `policy/peer-lock.json`.

The databases:
- **petclinic-rest** uses PostgreSQL for all three implementations. Each run gets a fresh database in a disposable cluster of the pinned peer, which listens on TCP only. The application initialises its schema and data from upstream's `schema.sql` and `data.sql`, as `spring.sql.init.mode=always` does.
- **gs-relational-data-access** uses each ecosystem's embedded database. Go has no H2.

## Layout

- `apps.json`: the registry of applications.
- `suites/springsuite.py`: the comparison rules.
- `suites/<app>.py`: the cases of each application.
- `suites/golden/<app>.json`: the golden observations recorded from the Java reference.
- `suites/test_springsuite.py`: a self-test of the comparison rules.
- `go/<app>/`: the Go comparators.
- `comparators.json`: their registration.
- `gc-matrix.json`: the druntime GC settings Phase 1 measures.
- `flint/<app>/`: where each Flint port lands, with its `flint-spring.json`. It is written by the Phase 1 framework and Boot sessions, not by this harness.
- `tools/spring_bench.py`: the driver.
- `tools/spring_builds.py`: `measure_builds.py --spring`.
- `tools/spring_gc_matrix.py`: the GC matrix.
- `tools/spring_gate.py`: `gates.py --gate spring`.
- `tools/load_bench.py`: schema-2 manifests, with `policy/spring-http-benchmark.json`.

## Prerequisites

Everything is pinned, and nothing is taken from the system:

```bash
python3 tools/install_peers.py --peer jdk --peer maven --peer postgres
python3 tools/install_toolchains.py --compiler go
python3 tools/install_toolchains.py --compiler oha
```

The peers land in `.flint/peers/`, and the harness also looks in the main checkout when it runs from a worktree. Building the references needs network access to GitHub and Maven Central. Building the Go comparators needs `proxy.golang.org`, the first time only. Every module is verified against `go.sum` and the checksum database.

## The suites

```bash
python3 tools/spring_bench.py list
python3 tools/spring_bench.py fetch
python3 tools/spring_bench.py accept --impl java
python3 tools/spring_bench.py accept --impl go
python3 tools/spring_bench.py accept petclinic-rest --impl flint
python3 tools/spring_bench.py accept gs-rest-service --start './my-server' --url http://127.0.0.1:8080
python3 tools/spring_bench.py record
```

- `accept` builds the implementation into `build/spring/`, starts it, runs every case in order and prints each failure. With `--json` it saves the record the gate reads. `--start` scores any implementation, given its start command and origin.
- `record` rewrites the golden files from the Java reference. It runs the reference twice, and the two runs must agree. A value that differs between runs therefore has to be named in the suite (`volatile`, `normalize`); it is never left to chance.

**What is compared.** For HTTP cases:
- the status code;
- every response header except `Date`, as a multiset that keeps the order of repeated names;
- JSON bodies (`application/json`, `*+json`) structurally, which covers Spring's error bodies, `ProblemDetail` and the actuator's `application/vnd.spring-boot.actuator.v3+json`;
- other bodies as text.

The origin is recorded as `{origin}`, because `ProblemDetail.type` and the actuator links embed the request URL. For command cases, the suite compares the exit code and the application's own log events in Spring Boot's console pattern, with the timestamp and PID removed.

**Wire modes:**
- **`exact`** is the default, and the mode Java and Flint must pass. It also compares the reason phrase (Tomcat sends none), the message framing (`Content-Length` or `Transfer-Encoding: chunked`) and compact JSON with Spring's key order.
- **`semantic`** is the mode the Go comparators are registered with. It drops only the reason phrase, the framing headers (`Content-Length`, `Transfer-Encoding`, `Connection`, `Keep-Alive`) and JSON key order. Forcing Go to emit chunked framing would only slow Go down and flatter Flint.

**Every implementation runs in the same environment:**
- the port comes from `SERVER_PORT`;
- petclinic-rest's database comes from `POSTGRES_URL` (JDBC form), `POSTGRES_USER` and `POSTGRES_PASS`, the keys of its `application-postgres.properties`;
- the profiles come from `SPRING_PROFILES_ACTIVE` and `FLINT_PROFILES_ACTIVE`;
- `TZ=UTC` and `LANG=en_US.UTF-8` are set, so `Content-Language` cannot differ by machine.

**Case counts.** gs-rest-service has 18 cases, gs-relational-data-access has 1 (eight log events), and petclinic-rest has 109. The petclinic-rest cases cover:
- every v1 resource, and the v2 paged listings;
- Bean Validation through the application's `ProblemDetail` advice;
- Spring MVC's failures before the handler, which that advice turns into 500 responses;
- `DataIntegrityViolationException` as a 404;
- CORS from `@CrossOrigin`, simple and preflight;
- the Spring Security headers;
- Tomcat's HTML 404 outside the context path;
- the root redirect;
- the actuator links, health and health groups.

**Exclusions:**
- The springdoc endpoints are left out. springdoc is a third-party library outside Phase 1's port list.
- Validation cases use one violation per request. Hibernate Validator reports several violations of one object in no defined order.

**Results today:**
- The Java references pass all their cases in `exact` mode: 18, 1 and 109.
- The gs-rest-service and gs-relational-data-access Go comparators pass in `semantic` mode: 18/18 and 1/1.
- The petclinic-rest Go comparator passes 109/109.

All three Go comparators are registered in `comparators.json`.

Behaviours the suites pin down that a port must reproduce:
- **gs-rest-service** runs its handler before content negotiation, so a 406 still consumes a counter value.
- **petclinic-rest's** catch-all `@ExceptionHandler(Exception.class)` turns unknown paths, type mismatches, unreadable bodies and wrong methods into 500 responses with the exception's simple name as `title`.
- **JDBC deletes cascade.** Deleting a pet type deletes its pets.
- **A 204 from `ResponseEntity` with a body** keeps `Content-Type: application/json` and sends no body.

## The Go comparators

Each comparator is the program a Go developer would write with the standard library, built with the pinned Go 1.27.4: `-trimpath -ldflags=-s -w`, CGO off, `GOTOOLCHAIN=local`. It does the same work as the reference. For example, petclinic-rest reads an owner's pets, types and visits from the database on every request, as the JDBC repositories do. It never caches responses.

**Registration.** A comparator is registered before any Flint measurement:

```bash
git commit benchmarks/spring/go/<app>
git push
python3 tools/spring_bench.py register <app>
python3 tools/spring_bench.py check-registry
```

- **Commit and push first.** `register` refuses uncommitted sources, and the registered commit must survive the rebase onto `main`.
- **`register`** records the comparator's last commit, a digest of its sources, the Go version and its wire mode in `comparators.json`.
- **`check-registry`** is what the measuring tools enforce.

`load_bench` and `measure_builds --spring` refuse a comparator whose sources differ from their registration. Changing a comparator after Flint has been measured against it needs its own reviewed ADR and a remeasurement of both sides (AGENTS.md).

## The Flint ports

A port lives in `benchmarks/spring/flint/<app>/`, next to its `flint-spring.json`:

```json
{
  "schema": "flint.spring-port/1",
  "build": ["flint", "build", "--release"],
  "binary": "build/gs-rest-service",
  "measure": {
    "cached": ["flint", "build"],
    "scratch": ["flint", "build", "--no-platform-cache"],
    "edit_source": "src/app.d",
    "O3": {"command": ["flint", "build", "--profile", "release"], "binary": "build/gs-rest-service"},
    "Oz": {"command": ["flint", "build", "--profile", "size"], "binary": "build/gs-rest-service"}
  }
}
```

**The fields:**
- `build` produces the binary that the suites and `load_bench` run.
- `measure.cached` is the development build with the platform cache, the first headline.
- `measure.scratch` builds every module from source with no platform cache, the second headline.
- `edit_source` is the file that the incremental build appends a declaration to.
- `O3` and `Oz` give the size profiles.

The command names above are placeholders. The port's owner fills in whatever `flint build` offers once Flint AOT and the platform cache land.

**A `flint-spring.json` with `"status": "skeleton"` counts as no port.** It holds sources that do not build yet. **Without a port, every claim about that application fails closed.** `accept --impl flint` exits non-zero. The measuring tools refuse to run unless `--allow-missing-flint` is given, which writes an `incomplete` record. The gate never accepts such a record.

## Measuring

Measure only on the designated runner, when it is otherwise quiet. The production tools refuse a 1-minute load average of 1.0 or more. `--smoke` runs a short harness check that is never evidence.

```bash
python3 tools/measure_builds.py --spring --output artifacts/spring/builds.json
python3 tools/load_bench.py --manifest policy/spring-http-benchmark.json --output artifacts/spring/http.json
python3 tools/spring_bench.py gc-matrix petclinic-rest --output artifacts/spring/gc-matrix-petclinic-rest.json
python3 tools/spring_bench.py gc-matrix gs-rest-service --output artifacts/spring/gc-matrix-gs-rest-service.json
python3 tools/spring_bench.py accept --impl java --json artifacts/spring/acceptance-java.json
python3 tools/spring_bench.py accept --impl go --json artifacts/spring/acceptance-go.json
python3 tools/spring_bench.py accept --impl flint --json artifacts/spring/acceptance-flint.json
python3 tools/gates.py --gate spring --evidence artifacts/spring
```

### Builds

`measure_builds.py --spring` (see `tools/spring_builds.py`) runs nine trials per series, with measure_builds' timing method.

**For Go:**
- a std-primed GOCACHE, cold and incremental;
- a deps-primed GOCACHE, cold;
- `go build -a` with an empty cache;
- the stripped size.

**For Flint**, the port's `cached`, `scratch`, `O3` and `Oz` commands.

**For Java**, `mvn -o package` cold and after a one-line edit. This is context only.

**ADR-030's two headlines**, both with the 0.99 ceiling on the median ratio and its bootstrap 99% upper bound:
- **primary:** Flint with the platform cache against Go with a std-primed `GOCACHE`;
- **secondary:** Flint from scratch against `go build -a`.

The incremental build and the Oz size are verdicts too.

**The deps-primed series is the stricter comparison.** It also primes Go's cache with the comparator's third-party packages (the SQLite or PostgreSQL driver). Those are the analogue of the native C libraries Flint's builds find prepared. It is published next to the headlines and does not gate. On gs-relational-data-access, compiling `modernc.org/sqlite` dominates Go's std-primed cold build (5.4 s, against 0.16 s deps-primed, smoke run on venus), so quoting only the ADR headline would flatter Flint.

### HTTP

`policy/spring-http-benchmark.json` is the Spring-style workload. The 26-byte JSON workload of `policy/http-benchmark.json` stays as it is.

**What runs:**
- `GET /greeting?name=Flint` on gs-rest-service;
- `GET /petclinic/api/owners/1` on petclinic-rest, one owner with its pets, types and visits from PostgreSQL.

**The phases** are the existing ones: a 10 s warmup, a 60 s fixed-rate latency phase and a 60 s capacity phase, over nine trials. The measured targets alternate their order.

**The CPU sets** are disjoint for the server, the load generator and the database.

**Before any trial**, every implementation must pass its suite, and the Go comparator is rebuilt from its registered sources. During load, responses are checked against a regular expression.

**The Java reference runs as context only**, with `-XX:ActiveProcessorCount=2` to match the two server CPUs. It is reported and never compared. A JVM that cannot hold the fixed rate is recorded as unsustained rather than dropped.

**The fixed rates** are 20,000 and 5,000 requests per second. They are initial values, to be confirmed by the first baseline on the designated runner before any Flint measurement. After that, changing them needs an ADR.

### Error paths

ADR-030 section 4 gives the 404 and validation-error paths their own p99 tests. `policy/spring-error-paths-benchmark.json` is a separate manifest, so the Spring-style workload's digest stays unchanged:
- `GET /nope` on gs-rest-service, answered by Boot's JSON 404;
- `POST /petclinic/api/owners` with one invalid field, answered by the application's 400 `ProblemDetail`. Nothing is written, so the request repeats.

`load_bench` runs it like the main workload, with three additions:
- an entry names its application (`app`);
- entries carry the request method, headers and body;
- responses are checked as JSON without key order (`body_json`, with `$regex` for the timestamp and the request URL).

Both bodies verify against the Go comparators and the Java references: 88 bytes (89 from Go) and 426 bytes. The gate requires each path's p99 to be at most 0.99 of Go's (`http-error-paths.json`). The queue entries `error-404-p99` and `error-validation-p99` wait on the Boot error controller and the petclinic-rest port.

### The GC matrix

`spring_bench.py gc-matrix <app>` runs the same Flint binary under each setting of [`gc-matrix.json`](gc-matrix.json), passed as `--DRT-gcopt=<setting> profile:1`. The settings are:
- conservative and precise marking;
- serial and parallel marking;
- `fork:1`;
- larger pools;
- a heap-size factor.

For each setting, the suite must still pass. The Spring workload then measures latency, RSS, CPU and capacity, with the Go comparator interleaved in every trial. druntime's exit profile gives the collections and the maximum pause.

**What happens with the result:**
- The winning setting is baked into the port through `rt_options`.
- If no setting brings p99 or RSS below Go, ADR-030's agreed fallback applies: a D collector with per-thread allocation caches.
- `--binary` measures a stand-in executable, to check the harness before a port exists. Such records are marked `stand-in` and are never evidence.

### Java native image

The Spring Boot native images are context, like the JVM. They are built with `-Pnative native:compile` and GraalVM Community 25.0.5, which is pinned with its checksum in `policy/peer-lock.json` (`install_peers.py --peer graalvm`). Spring Boot 4 requires GraalVM 25 for native images. `native-image` runs with `--parallelism=8`, to leave the runner to other work.

- `spring_bench.py build <app> --impl java-native` builds the image.
- `accept --impl java-native` scores it in `exact` mode.
- The HTTP workload lists `java-native` as a context target.
- `measure_builds.py --spring --native-context` adds one native build per application, with its time and executable size.

The gs-rest-service image builds in 53 s on venus, is 67 MB, and passes 18/18. gs-relational-data-access passes 1/1.

spring-petclinic-rest's image builds, but exits at start-up with `NoClassDefFoundError: Could not initialize class org.slf4j.MarkerFactory`. Its log4j-to-SLF4J bridge fails to initialise in the image. Fixing that would need upstream edits beyond the parent version. The harness therefore records it as a context error, and petclinic-rest's context is the JVM only.

## The measurement queue

Several sessions build on venus at once, so no timing taken at a random moment is evidence. Pending performance runs therefore wait in a queue, and run only in a quiet window. `tools/measure_queue.py` runs the queue; see its docstring.

```bash
python3 tools/measure_queue.py list
python3 tools/measure_queue.py quiet
python3 tools/measure_queue.py prepare <id>
python3 tools/measure_queue.py run <id>
python3 tools/measure_queue.py next
```

- **`quiet`** says whether a run may start now.
- **`prepare`** builds what an entry measures. It may run at any time, because nothing is timed.
- **`run`** checks the window, measures and writes the receipt.
- **`next`** runs every pending entry while the window stays quiet.

**Entries.** Each entry is one file, `benchmarks/spring/queue/<id>.json`, so sessions add entries without editing each other's.
- **Builds.** `builds` names what to build: an app at a commit, built in a detached worktree under `.flint/measure/worktrees/` with that worktree's own native prefix. The shared `.native` is never written.
- **Measurement.** `measure.kind` is one of:
  - `startup`: exec to the first correct response, interleaved;
  - `rest-pair`: `load_bench`'s schema-1 REST workload, with the base build in one slot and the candidate in the other. `load_bench` interleaves them trial by trial, then the regression ratios of `policy/budgets.json` are computed;
  - `command`: steps run in this checkout or in a build's worktree.
- **Status.** `pending` runs with `next`; `blocked` waits on `blocked_on`; `done` has a receipt that counts as evidence.

**The quiet window.** Every measuring step checks it:
- the 1-minute load average is below 1.5;
- no `dmd`, `ldc2`, `ldmd2`, `cargo`, `cmake`, `rustc`, `cc1`, `cc1plus`, `ninja`, `dub`, `mvn`, `gradle` or `native-image` uses CPU anywhere on the host, outside the run's own process tree. A process counts if it uses at least 2 CPU ticks in a 1 s sample. The DMD compile servers keep pre-forked workers asleep between builds, over 2,000 of them on venus, and those idle workers are counted in the receipt but do not block;
- every port is outside 8080–8099, and free. Entries use 18080 and up, and `rest-pair` writes a manifest copy with its ports;
- servers are pinned with `taskset`, and load generators to their CPU sets, as the evidence rules require. The `startup` client runs on CPUs 4–7 and the server on 2–3. `load_bench` and `measure_builds` pin their own processes.

The window is sampled before the measurement, every 10 s during it, and after it. All the samples go into the receipt: load averages, plus each build process with its working directory. A receipt counts as evidence only if every sample was quiet. `--force-busy` and `--smoke` produce receipts that never count, for harness checks only. Receipts and raw outputs stay in `.flint/measure/results/<id>/`; a run that counts appends its receipt to the entry file.

**Queued now:**
- `runtime-levers-rest`: bench-rest at `e16668e` against `966c4b7`, a REST no-regression check of FiberLocal, the 256 KiB guarded stacks and the offload pool. Both commits predate `--app-sizes`, so both are built with bench-rest's README command.
- `relr-startup`: bench-rest at `13d5d62` against `3eef2dc`, built with `measure_builds --app-sizes`. The result goes into `docs/milestones/13-binary-size.md`.
  - The queue's builds reproduce that document's sizes exactly: 6,670,024 and 5,904,144 bytes at O3.
  - Their sha256 values differ from the requester's, and from build to build when the environment differs. The bytes are deterministic, but the binaries are not bit-identical.
- `adr031-startup` and `adr031-rest`: bench-rest before (`440d72d^`, which is `48b8f52`) and after ADR-031's TLS-only OpenSSL (`440d72d`). The first measures start-up, the second is a REST regression check.
  - Each side rebuilds its own native prefix. The build checks OpenSSL Configure's `%disabled` record in `configdata.pm`: after disables `legacy`, `des`, `rc4` and `tls1`, and before disables none of them. `no-legacy` emits no `OPENSSL_NO_LEGACY` macro, so `configuration.h` cannot show it.
  - Sizes: O3 5,904,384 to 5,005,088, and Oz 5,855,232 to 4,955,936. That is 899,296 bytes saved; the base on `main` is 80 bytes larger than the requester's.
- `phase1-spring-apps`: the whole Phase 1 evidence run of the section above. It is blocked on the Flint ports.

Every pending entry is built, and its smoke run passes. They wait for a quiet window.

## Status

**In place:**
- the references, the suites and the golden files;
- the three Go comparators, with their registration;
- the Java native-image context for the two guides;
- the build, HTTP and GC-matrix tooling;
- the gate.

**Smoke runs on venus** exercised every tool. The Go and Java sides were measured, and the GC matrix ran on a stand-in D server: druntime took the settings and reported its profile. Smoke runs are not evidence.

**Missing:**
- **The Flint ports.** Until they land, `gates.py --gate spring` fails with exactly those gaps listed.
- **The production measurements.** They wait for the ports and a quiet runner.
