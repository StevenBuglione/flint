# ADR-021: Flint as a platform — one CLI, one project model, one way

Status: **accepted** by the project owner on 2026-11-22, with the decisions recorded at the end. It expands [ADR-018](ADR-018-flint-cli.md), whose decisions stand, from a build tool into the single entry point for everything Flint. Nothing here is implemented yet.

## Goal

Flint should feel like Spring Boot for D with native performance. A developer or an LLM should be able to:

- create a project;
- add a capability;
- configure it in `application.toml`;
- build it faster than Go;
- test it with its real peers;
- ship it as a static binary or container.

All of that goes through one tool and one documented way, on any operating system. Code should be fast and easy for humans to review, and the build should block the usual D and C foot-guns before they reach a binary.

Five principles decide the details:

1. **One way.** There is one manifest, one layout, one config format, one dependency resolver and one formatter. When D allows several ways, the Flint project codifies one. Alternatives exist only as explicit, visible escape hatches.
2. **Machine-first, human-readable.** Every command has stable `--json` output and every diagnostic has a stable code, so LLMs and tools never scrape prose. The same information prints as clear, coloured text for people.
3. **Reproducible by construction.** Builds use pinned toolchains, pinned and hashed dependencies (D and native), and write a receipt for every artifact (ADR-018).
4. **Safe by default.** The checks Flint already runs in CI (the `@safe` policy, `@trusted` rationale, DIP1000, sanitizers, native hardening) become part of the build. A project can't opt out silently.
5. **Fast by default.** The Milestone 6 toolchain is the default, with no tuning needed. Every flag stays overridable per profile, and overrides are recorded.

## 1. The `flint` command

The `flint` command is written in D on Flint's own libraries (ADR-018) and is the only tool a Flint user needs.

| Area | Commands |
| --- | --- |
| Project | `flint new <name> [--starter web,data,...]`, `flint add <starter\|package>`, `flint remove`, `flint generate <controller\|service\|repository\|entity\|migration\|config> <Name>` |
| Build loop | `flint build`, `flint run`, `flint test`, `flint check`, `flint fmt`, `flint watch` |
| Dependencies | `flint deps tree\|why\|update\|vendor\|audit`, `flint lock` |
| Shipping | `flint package [--target T] [--container] [--sbom]`, `flint release` (signs via Sigstore, ADR-017) |
| Toolchain | `flint toolchain install\|verify\|info`, `flint doctor`, `flint daemon start\|stop\|status` (the compile server) |
| Knowledge | `flint docs <query>`, `flint explain <FLINT-Ennnn>`, `flint examples <topic>`, `flint mcp` |
| Measurement | `flint bench`, `flint measure`, `flint gate` (taking over the Python tools as ADR-018 describes) |

Rules every command follows:

- `--json` emits one documented schema per command, versioned like an API.
- Exit codes are stable:
  - 0 ok;
  - 1 the user's code failed (build, test or check);
  - 2 the environment or toolchain is wrong;
  - 3 dependency resolution failed;
  - 4 usage error.
- No command prompts unless `--interactive` is passed, so agents never hang.
- Every command that changes files can print the exact diff first (`--plan`) and is deterministic: the same inputs give byte-identical outputs.

## 2. The Flint project model

### Layout

`flint new shop --starter web,data` creates the layout below, and `flint check` enforces it.

```text
shop/
  flint.toml                 # the only manifest
  flint.lock                 # exact D and native dependency graph, hashes, toolchain identity
  config/
    application.toml         # base configuration
    application-dev.toml     # profile overrides (FLINT_PROFILE / --flint.profile)
    application-prod.toml
  src/shop/
    app.d                    # module shop.app: the application root
    order/                   # package-by-feature: one folder per business capability
      order.d                # entity (@Table)
      repository.d           # repository (CrudRepository)
      service.d              # @Service
      controller.d           # @RestController
  test/shop/order/           # tests mirror src/; integration tests declare their peers
  resources/                 # migrations/, templates/, static/
  native/                    # optional embedded C, built under the native rules (section 5)
  Dockerfile                 # generated; static musl binary on an empty base image
  AGENTS.md                  # generated "Flint way" rules for coding agents
  .flint/                    # caches and receipts (git-ignored)
```

Rules:

- **Module paths must match file paths** under `src/`, and the first segment is the project name. This is checked.
- **Package-by-feature**, not package-by-layer. A feature folder holds its entity, repository, service and controller.
- **Generated code lives only in `.flint/generated/`**, is never committed, and is rebuilt from its inputs (migrations, schemas, routes). Today's checked-in `generated/` folders, such as the golden REST example's, move there.
- `native/` exists only when a project embeds C, and section 5's rules apply to it.

### `flint.toml`

```toml
[project]
name = "shop"
version = "0.1.0"
flint = "1.0"                      # platform version: pins toolchain, libraries and rules together

[starters]
web = {}
data = { driver = "postgres" }

[dependencies]                     # Flint-registry D packages beyond what starters bring
"github.com/acme/flint-stripe" = "1.4.2"

[profile.release]                  # overrides on top of the canonical profile; recorded in receipts
dflags = ["-mcpu=native"]

[targets]
default = ["linux-x86_64-musl"]
```

- `flint = "1.0"` is the single version knob, like a Spring Boot BOM. It fixes which toolchain, which Flint library versions and which rule set a project uses, so a project never mixes incompatible versions. `flint upgrade` moves it and shows what changes.
- DUB becomes an internal backend. `flint` drives the forked DUB pipeline from `flint.toml`. `dub.sdl` is generated only for publishing to code.dlang.org (`flint publish --dub`), so Flint libraries stay usable from plain D projects.

### Configuration

Configuration has exactly one shape: `config/application.yaml` plus `application-<profile>.yaml` (ADR-029), bound to typed `@ConfigurationProperties` structs through `flint.config`.

- The precedence and profile rules are the existing `flint.config` specification: base file, then profile file, then `.env`, then environment, then `--set`.
- **Superseded by [ADR-029](ADR-029-spring-boot-is-the-reference.md) section 6:** Flint projects use `config/application.yaml` with Spring Boot's keys, in a strict YAML 1.2 subset bound to typed fields, which removes the implicit-typing ambiguity that first ruled YAML out. TOML stays readable, and the library still reads JSON for non-project users.
- `flint config` prints every resolved key with its source, its type and the struct that binds it. This is the equivalent of Spring Boot's `/actuator/configprops`, available at build time.
- Unknown keys are errors with a "did you mean" suggestion.

## 3. Starters: `flint-starter-<domain>`

A starter is a Flint package with three parts:

- it depends on the right core packages;
- it ships **auto-configuration**: beans registered only when their configuration section or a dependency is present;
- it ships its configuration schema, documentation and example.

`flint add data` adds `flint-starter-data`. Its pool, migrations and repositories are then wired from the `[database]` section, with no registration code.

The first starters map directly onto the core packages:
- `web`, `data`, `security`;
- `cache`, `messaging` (mq) and `mail`;
- `storage`, `ai` and `mcp`;
- `cli`, `tui` and `desktop`;
- `observability` (actuator and log).

The DI package needs one addition for this, recorded through ADR-017's public API process:

- compile-time conditional registration (`@ConditionalOnConfig("database")`, `@ConditionalOnMissingBean`);
- an `@AutoConfiguration` discovery list that each starter exports.

All of it resolves at compile time, so it has no reflection and no start-up cost. That keeps Spring Boot's ergonomics without its runtime classpath scanning.

## 4. Dependencies

### D packages

D packages follow the Go model, which is fast, simple and needs no central server:

- **Identity:** a package is identified by its repository path (`github.com/acme/flint-stripe`) and a semantic version tag.
- **Resolution:** dependencies resolve with **minimal version selection**. It is deterministic, needs no SAT solver, and gives the same result on every machine.
- **Lock file:** `flint.lock` records each package's content hash, and a checksum mismatch is an error.
- **Proxy:** an optional caching proxy (`FLINT_PROXY`) serves teams and offline builds.
- **The Flint core libraries** resolve as one versioned set from the `flint = "x.y"` platform version.

### Native (C and C++) dependencies

Native dependencies are resolved by Flint's resolver, which uses **Conan 2 internally as its engine**. Conan is an implementation detail: users and library authors work only in `flint.toml`, `flint.lock` and `flint` commands. No Conan file, profile, remote or command is ever visible, and no Conan knowledge is needed.

- **Declaring them:** a D library declares its native needs in its own `flint.toml` (`[native] openssl = "3.4.1"`, with `linkage` and options), and applications inherit them transitively. The library's embedded C sources are declared there too (`[native.c] sources`, `include_dirs`, `standard`).
- **Flint owns the engine:**
  - `flint toolchain install` installs a pinned, self-contained Conan build, with its own interpreter, in Flint's toolchain directory, never in the user's Python;
  - `flint` generates every Conan input on the fly: the conanfile from `flint.toml`, the host and build profiles from the Flint target and profile, and the configuration and remotes;
  - `flint` consumes Conan's output (include and library directories, definitions, system libraries) and passes it to the D link.

  Conan's own home, cache and settings live under `.flint/` and the toolchain directory, isolated from any Conan the user may have installed.
- **Flint owns the recipes:**
  - Conan resolves only against **Flint's own recipe remote**. Recipes are vetted and mirrored from ConanCenter or written by the Flint project, and each passes the Flint recipe policy: pinned source hashes, the mandatory hardening flags, licence metadata and sanitizer variants;
  - ConanCenter is never queried directly at build time;
  - today's 19 providers in `policy/native-lock.json` become the first recipes on that remote, so the evidence chain built in Milestones 3–6 carries over.
- **Locking:** `flint.lock` records, for every native package:
  - the recipe revision;
  - the package ID;
  - the source hash and the binary hash.

  It is generated from Conan's lockfile and verified on every build, so the same `flint.lock` gives the same native binaries on every machine.
- **Targets:** each Flint target (`linux-x86_64-musl`, `linux-aarch64-glibc`, and later `macos-arm64` and `windows-x86_64`) maps to a generated Conan host profile, and the toolchain maps to a build profile. That profile pair is part of the cache key. The OS, architecture, libc and minimum version, compiler, C++ standard library and options are all recorded.
- **Binary cache:** prebuilt binaries for tier-1 targets are published to the Flint remote and Sigstore-signed. Anything else builds from source with the pinned toolchain, or in the dev container, so a missing binary never means a broken build.
- **Conflicts:** when two packages need incompatible versions of one native library, the build fails and names both requesters and both constraints, in Flint's own words. A raw Conan error never reaches the user. Flint never silently picks one version.
- **System libraries:** `system = true` uses the host's library only when written explicitly, and the receipt marks the build non-portable. Silently linking whatever happens to be installed is exactly the "works on my machine" failure to avoid.
- **Linkage:** static linking is the default. `bundled` copies the shared libraries next to the binary, using Conan's runtime deployer internally, and sets the runtime path. The operating system's own libraries (libc on glibc targets, system frameworks) are the only implicit dynamic links.
- **Existing DUB packages:** a curated **compatibility index** maps DUB package versions to native recipes, so useful packages work without their maintainers adopting Flint. DUB's own `systemDependencies` field is informational only and cannot be resolved automatically.
- **Replaceability:** because Conan never appears in user-facing files, the engine can be changed later without touching any project.

## 5. Safety enforced at build time

`flint build` runs the fast checks every time. `flint check` runs everything, as CI does.

**D code:**
- **Module defaults:** module-level `@safe:` and `-preview=dip1000` on every module.
- **`@trusted`:** only in `sys`/`ffi` modules, each with an adjacent `// SAFETY:` rationale and never as a block.
- **No other escape hatches:** no `@system` outside `ffi`, and string mixins only in registered generators.
- **Formatting:** `dfmt` byte-identical, and D-Scanner clean.
- **`@nogc` contracts:** a function documented as a hot path must compile as `@nogc` (the REST handlers above already do).
- **The project layout rules** from section 2.

**C code** in `native/` and in recipes:
- **Language and warnings:** C11 or C17 with `-Wall -Wextra -Werror` plus a curated warning set.
- **Hardening:** `-D_FORTIFY_SOURCE=3 -fstack-protector-strong -fstack-clash-protection -ftrivial-auto-var-init=zero`, with PIE and full RELRO on dynamic targets.
- **Static analysis:** clang-tidy with a fixed profile.
- **Sanitizers:** every `flint test --sanitize` run builds this C code with ASan and UBSan. That is the default in `flint check`.
- **No direct calls from application code:** D reaches C only through a typed `ffi` wrapper module, as the Flint packages do now.

**Dependencies:**
- `flint deps audit` checks hashes, known vulnerabilities and licences.
- `flint package --sbom` writes SPDX and CycloneDX files with every licence notice. That matters because LGPL components such as WebKitGTK carry obligations.

**Escape hatch:** a project can waive one rule for one file with `[waivers]` in `flint.toml`, and a waiver must give a reason. Every build lists active waivers in its output and receipt, so a reviewer sees them.

**Third-party DUB packages** from code.dlang.org are allowed through the compatibility index. A package that fails Flint's safety checks can be used only with an `[unchecked]` waiver that names the package and gives a reason. The waiver appears in every build's output, its receipt and `flint deps audit`.

## 6. Built for LLMs

These features are first-class, not afterthoughts:

- **`flint mcp`** is an MCP server built on `flint:mcp` itself. Its tools:
  - `search_api`, `get_symbol` and `get_example`;
  - `explain_error`;
  - `describe_project`, `resolved_config` and `dependency_graph`;
  - `generate`, `build`, `test` and `check`.

  An agent queries the exact API of the pinned Flint version instead of guessing from training data.
- **The API index:** `flint docs` searches an offline index generated from the source of the project's pinned libraries: signatures, DDoc, contracts and acceptance tests. The same index is published as `llms.txt` / `llms-full.txt` on the docs site.
- **Examples:** every public API symbol has a compiled, tested example. `flint examples` and the MCP tools return them, and an example that stops compiling fails CI.
- **Generators:** `flint generate` produces the canonical shape of each component, so agents don't invent structure. `flint new` writes an `AGENTS.md` stating the Flint way: layout, naming, the error model and what not to do.
- **Stable diagnostics:**
  - every error from the compiler wrapper, a check or the runtime has a code (`FLINT-E0412`), a one-line cause, the source location with a snippet, and a fix suggestion;
  - `flint explain FLINT-E0412` prints the long explanation with a correct example;
  - all of it is available as JSON.

## 7. Better errors and debugging

- **Compiler errors:** the forked DMD emits structured diagnostics, and `flint` presents them.
  - **Template errors:** the template instantiation stack is collapsed to the frames in the user's code. Phobos and Flint internals appear behind `--verbose`.
  - **Known messages are rewritten,** each with a fix. Examples: DIP1000 scope escapes, `@nogc` violations naming the allocating call, and `@safe` violations naming the operation.
  - A bad `@ConfigurationProperties` field or route signature fails with the field's name and the expected type, never a static-assert wall. This is the CLI-03 pattern, applied everywhere.
- **Runtime errors:** Flint's `Error` already carries a status and message. It gains an optional context chain ("while binding `database.uri`" or "while handling GET /api/users/42"). An uncaught failure prints a symbolized stack trace for the user's frames.
- **Debugging:**
  - `flint run --debug` builds with full debug info and starts `gdb` or `lldb` with Flint pretty-printers for `Result`, `Text`, arenas and contexts;
  - `flint doctor` explains environment problems in plain words.

## 8. Fast by default, tunable everywhere

- **Development builds** use the forked DMD with the resident compile server (`flint daemon` manages it), the parallel DUB pipeline and mold. These are the Milestone 6 settings that beat Go's build times.
- **Release builds** use LDC with `-O3`, ThinLTO and static default libraries, and `size` uses `-Oz`.
- **Caching:** every step is cached by content hash: D modules, native recipes, embedded C objects and generated code.
- **Tuning:** any flag can be overridden in `[profile.*]`, per package or per target. Overrides are recorded in the receipt and mark the build non-canonical for measurement (ADR-018).

## 9. Every operating system

- **Development on any OS today:** the official dev container holds the pinned toolchain, peers and recipes. On macOS and Windows, `flint` can run builds and tests inside it transparently (`flint build --in-container`, and automatically when the native toolchain isn't present). That gives every OS a working Flint environment while native support is built.
- **Native support per platform:**
  - **Linux x86-64 and aarch64, glibc and static musl:** tier 1, already certified.
  - **macOS arm64 and Windows x86-64:** need real runtime work:
    - a kqueue backend and an IOCP backend for the reactor;
    - native recipes for Apple clang and MSVC;
    - the compile server on those systems.

  Each is its own milestone. Gate 6 keeps reporting them as failing until then (ADR-017).
- **Containers:** `flint package --container` produces a `FROM scratch` image around the static musl binary. Milestone 6 already verified those binaries in empty roots.

## 10. Open source

Flint is free and open source under the **Apache License 2.0**, which gives an explicit patent grant and is what Spring uses. The `LICENSE` file moves from MIT to Apache-2.0 with a `NOTICE` file. Every package manifest already declares `Apache-2.0`, so this also removes an inconsistency. The CLI, the recipe index, the starters and the docs site are all public. Every release carries Sigstore signatures, a SBOM and the receipts that reproduce it.

## 11. Proving it: the vibe-coding benchmark

"Flint makes D just work" must be measured, not asserted.

- **Tasks:** the benchmark is a fixed set, checked in with acceptance tests. Examples:
  - a CRUD REST API with login, a database migration and validation;
  - a CLI with configuration and subcommands;
  - a background worker consuming a queue;
  - a TUI dashboard.
- **Who runs it:** coding agents, using only `flint mcp` and the generated `AGENTS.md`, with no prior Flint context.
- **What is scored:** for each task,
  - the share of runs that pass the acceptance tests;
  - the number of build–fix iterations;
  - the wall time;
  - the review size: lines and attributes in the generated code.
- **Comparison:** the same tasks run in Go and Spring Boot with the agents' usual tooling.
- **Gate:** every Flint release reports these numbers, and a regression in success rate fails it. When the results are published is not yet planned.

## Proposed milestone plan

| Milestone | Delivers |
| --- | --- |
| 7 — CLI core and project model | `flint new/build/run/test/check/fmt`, `flint.toml` and `flint.lock`, profiles, receipts, toolchain install and doctor, compile-server management, the layout and safety checks in the build, structured diagnostics v1. The Flint repository builds itself with `flint`. Linux. |
| 8 — Dependencies and packaging | Go-style D dependency resolution and proxy. The native resolver with Conan hidden inside, the Flint recipe remote (seeded from `native-lock.json`) and signed binary cache. Embedded C under the hardening rules. `flint package` static, bundled and container. SBOM and licence audit. |
| 9 — Knowledge, diagnostics and tooling | API index, `flint docs/examples/explain`, `flint mcp`, generators and `AGENTS.md`. Diagnostics v2: template-error condensation and message rewriting in the forked DMD, plus a test that every framework misuse yields one readable, field-level error. **`flint lsp`**: a language server on the resident compile server. **The vibe-coding benchmark**: fixed tasks run by coding agents using only `flint mcp`, scoring success rate and fix iterations against Go and Spring Boot (section 11). `flint watch` (incremental rebuild and restart), generated debugger configurations and pretty-printers. |
| 10 — Starters and the full-stack path | The DI conditional and auto-configuration addition. `flint-starter-web`, `-data`, `-security`, `-observability` first, then the rest. `flint add`. Attribute inference through the framework, so ordinary handlers need no `nothrow`/`@nogc`/`scope` annotations, with an attributes-per-handler metric. OpenAPI generated from controllers, typed TypeScript clients, SPA serving, and a complete auth starter: sessions, OAuth login, password hashing, email verification. Starters prefer structs and `Result`, and `flint check` flags nullable class fields in application code. |
| 11 — Every OS | Native macOS arm64 and Windows x86-64 ports, and native Linux aarch64: reactor backends (kqueue, IOCP), recipes, platform lanes, with Gate 6 green per platform. The dev container path for any host. The macOS and Windows ports started early, in parallel with Milestones 8–9. |
| 12 — Fast compiles everywhere | [ADR-025](ADR-025-fast-compiles-everywhere.md): the forked DMD as the development compiler on every platform. DMD's AArch64 backend completed in the fork for macOS and Linux arm64. The compile server, pipeline and direct linking ported to macOS and Windows. Per-platform compile-speed gates against Go on each runner. |
| 13 — The Spring port: foundations and proof slice | [ADR-030](ADR-030-flint-is-a-spring-port.md) phases 0 and 1: the API mapping rulebook, the upstream licence matrix, `flint api` coverage, the runtime and size levers, preparing the repository split, and a slice of Spring Framework and Spring Boot whose Guides and PetClinic-REST apps give identical output to Java Spring Boot and beat Go on every metric. |
| 14 — The Spring port: fan-out | ADR-030 phase 2, in parallel across the repository family: Data Commons and JDBC, Security, caching, scheduling, `RestClient`, Actuator and Micrometer, Thymeleaf, the JPA engine and classic PetClinic, `flint-ai`, and Spring's idiom on the engines with no Spring counterpart. |
| 15 — The Spring port: long tail | ADR-030 phase 3: Kafka, AMQP, Redis and MongoDB, Reactor and WebFlux, WebSocket and STOMP, Batch, Integration, Cloud, Session, GraphQL and the remaining Boot modules. |

Milestone 10's remaining starter work is superseded by ADR-030: starters are rebuilt in `flint-boot` under Boot's own module layout. No milestone after 15 is planned; agents should not start work beyond it.

## Decisions

Recorded on 2026-11-22.

1. **Native resolver:** Flint's resolver uses Conan internally, hidden completely behind `flint`, against Flint's own vetted recipe remote (section 4).
2. **Licence:** Apache-2.0.
3. **Starter name:** `flint-starter-<domain>`.
4. **Third-party DUB packages:** allowed through the compatibility index, with a visible `[unchecked]` waiver for any package that fails the safety checks.
5. **Milestone order:** as in the table above: dependencies and packaging (8) before knowledge and diagnostics (9).
6. **Gaps to close for "D just works"** (2026-11-22): the additions to Milestones 9, 10 and 13 above. The editor and language server, attribute noise, LLM familiarity measured by the benchmark, readable errors, the full-stack path, null class references, fast feedback, library breadth and trust signals.
7. **Compile speed is the selling point on every platform** (2026-11-22): [ADR-025](ADR-025-fast-compiles-everywhere.md), Milestone 12. The macOS, Windows and Linux aarch64 work in Milestones 11 and 12 proceeds in parallel.
