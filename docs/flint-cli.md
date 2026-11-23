# The `flint` command

`flint` is the single entry point for creating, building, running, testing, checking and packaging Flint code with the pinned toolchain ([ADR-018](adr/ADR-018-flint-cli.md), [ADR-021](adr/ADR-021-flint-platform.md), [ADR-022](adr/ADR-022-milestone-7-decisions.md), [ADR-023](adr/ADR-023-milestone-8-decisions.md)). It is written in D on Flint's own libraries and lives in [`apps/flint`](../apps/flint).

## Install

From a checkout with the pinned toolchain installed (`flint toolchain install`, or `tools/install_toolchains.py` as in [toolchain/README.md](../toolchain/README.md)):

```bash
python3 tools/install_toolchains.py --compiler flint
export PATH="$PWD/.flint/bin:$PATH"
flint doctor
```

The bootstrap builds a first `flint` with DUB. That binary rebuilds `flint` through itself and verifies the result against its own receipt before installing it. `flint` finds its installation by walking up from its executable, or from `FLINT_HOME`.

## Quick start

```bash
flint new shop
cd shop
flint build
flint run -- --name Ada
flint test --compiler both
flint check
```

## Commands

| Command | What it does |
| --- | --- |
| `flint new <name> [--starter a,b] [--type executable\|library] [--path DIR] [--plan]` | Create a project in the canonical layout, with `flint.lock`. Never overwrites. `--plan` prints the files instead. |
| `flint build [packages...] [--profile P] [--compiler C] [--dflags F]... [--lflags F]... [--verify] [--locked] [--force] [--no-platform-cache] [--static] [-- flags]` | Build the project, or workspace packages, with a canonical profile. Links the platform modules from the platform cache unless `--no-platform-cache` is given. A dev build links them as one shared object; `--static` links their archives, as release and size builds do. Writes a receipt next to the artifact. |
| `flint run [--profile P] [--dflags F]... [--debug] [--verify] [--locked] [-- args]` | Build if needed, then run with the project root as working directory. `--debug` starts gdb (or lldb) with Flint's pretty-printers. |
| `flint watch [--test\|--build] [-- args]` | Rebuild and restart the executable (or retest a library) on every change to `src/`, `test/`, `config/`, `native/`, `resources/` or `flint.toml`. A failing cycle shows its diagnostics and waits. `--json` prints one `flint.watch/1` line per cycle. |
| `flint test [packages...] [--compiler dmd\|ldc\|both] [--sanitize] [--scenarios] [--verify] [--locked] [--force]` | Build and run unittests: the project's `src/` and `test/`, or `dub test` for workspace packages. `--sanitize` builds a project's tests, embedded C and native packages with ASan and UBSan. |
| `flint check [--gate structural] [--package P]...` | Every check CI runs: lock, layout, safety rules, configuration convention, dfmt, D-Scanner and clang-tidy over embedded C. In the workspace: `tools/gates.py`'s structural gate, then dfmt and D-Scanner. |
| `flint fmt [--check]` | Format with the pinned dfmt and the repository's `.editorconfig`. Sources are LF on every host: `--check` reports CRLF line endings, and `flint new` writes `.gitattributes` with `* text=auto eol=lf` so git's `autocrlf` keeps them LF on Windows. |
| `flint lock [--check]` | Write `flint.lock`, or verify it. |
| `flint deps tree\|why <package>\|update [packages...]\|vendor` | Print the graph, explain why a package is in it, raise repository-path requirements to their latest release, or copy repository modules and DUB packages into `vendor/` for offline builds. |
| `flint deps audit [--target T]` | Verify the lock and every module, DUB and native hash; list each component's licence and the LGPL/AGPL obligations; show `[unchecked]` waivers. |
| `flint package [--target T] [--container] [--sbom]` | Build the release executable for a target, verify it is static, and write a reproducible `tar.gz` with `bin/`, `config/` and `resources/`; `--container` adds a `FROM scratch` OCI image, `--sbom` SPDX 2.3 and CycloneDX 1.6 SBOMs. |
| `flint toolchain install [--toolchain-dir D] [--no-pgo] [--dmd-linker L] [--sanitizers] [--musl] [--plan]` | Install the pinned DMD/DUB fork, LDC, clang (embedded C, clang-tidy) and the native package engine, and write the toolchain receipt. On Linux x86-64, DMD links with the pinned mold unless `--dmd-linker` names another linker (`system` keeps the C compiler's default). `--sanitizers` adds the sanitizer-aware LDC runtime, `--musl` the static musl target. |
| `flint toolchain verify\|info [--toolchain-dir D]` | Check the toolchain against `policy/toolchains.json` and `toolchain/*.patch`, or describe it. |
| `flint doctor [--project D]` | Explain environment problems that would make a build fail or non-canonical. |
| `flint daemon start [--profile P]\|stop\|status` | Manage the forked DMD's compile server. |
| `flint version [--verify]` | Print the tool, toolchain and source identities. `--verify` checks this executable against its receipt. |
| `flint explain <code>\|--list` | Explain a diagnostic code with a correct example. |
| `flint docs [words\|qualified.name] [--export DIR]` | Search the pinned Flint API, built offline by the pinned compiler: signatures, documentation and the tested examples from each package's own tests. `--export` writes `llms.txt` and `llms-full.txt`. |
| `flint config [--profile P]` | Every key `config/application.toml` and its profile file set, with its value and `file:line`. |
| `flint lsp` | A language server on stdio: diagnostics from the pinned compiler and Flint's rules as you type (unsaved buffers included), and hover, go-to-definition and completion for the pinned Flint API. |
| `flint mcp [--log FILE]` | Serve the knowledge tools and the build loop to MCP clients over stdio (ADR-021 section 6): `search_api`, `get_symbol`, `get_example`, `explain_error`, `describe_project`, `resolved_config`, `dependency_graph`, `generate`, `build`, `test` and `check`. Each tool returns the matching command's `--json` document. `--log` records each call. |
| `flint examples <topic>` | Compiled, tested examples for a topic, and matching golden applications. |
| `flint generate <entity\|repository\|service\|controller\|config\|migration\|agents\|debug> <Name> [--plan]` | Write the canonical shape of a component (package-by-feature), add the core packages it needs and relock. `agents` refreshes `AGENTS.md`, and `debug` writes VS Code launch and task configurations that load Flint's pretty-printers. Never overwrites a component. |
| `flint add <starter>... [--plan]` | Wire starters (`web`, ...; listed in `policy/starters.json`): add `flint:starter-<name>` to `[dependencies]`, append its configuration section to `config/application.toml` when missing, and relock (ADR-028). |
| `flint openapi [-o FILE] [--typescript FILE]` | Build a starter-web project, take the OpenAPI 3.1 document flint:engine-web generated from its controllers (the app's `--openapi`), name it after `flint.toml`, and write it; `--typescript` also writes a typed `fetch` client (ADR-028). |
| `flint receipt <artifact> [--canonical]` | Verify an artifact against its receipt and the current toolchain. |
| `flint api fetch [projects...] [--cache DIR] [--tests]` | Download the upstream source archives pinned in `api/upstreams.json` into the reference cache, verified by SHA-256 (ADR-030). Never compiles them. `--tests` fetches the test-source archives of `api/upstream-tests.json` (for porting upstream tests) into `<project>-<version>-tests`. |
| `flint api extract --source DIR --project P --version TAG [-o FILE] [--exclude PREFIX]...` | Write the API manifest of an upstream Java source tree: every public and protected type and member ([API manifests](#api-manifests)). |
| `flint api coverage [--repo R] [--manifest FILE...] [--mapping FILE] [--show N] [--release] [--update-baseline]` | Classify every manifest element against the repo's mapping and print per-module percentages. With a `coverage-baseline.json` it fails only when a module's unclassified count rises or a checklist marked complete is not. `--release`, or no baseline, fails on any unclassified element. `--update-baseline` lowers the baseline. `--repo` takes every manifest `api/upstreams.json` assigns to the repo. |
| `flint api diff <old> <new>` | List the API elements added, removed or changed between two manifests. |
| `flint api headers [paths...]` | Check that every D file ported from an upstream carries ADR-030's header, for an upstream the licence matrix lets Flint port at that tag. |
| `flint api checklist --slice FILE --output DIR` | Write one Markdown checklist per module of a porting slice, each element with the status the repo's mapping gives it, and an index `README.md`. |

Every command accepts `--json` and `--help`. Commands acting on a project take `--project DIR` (or `-C DIR`). `flint` never prompts.

Inside the Flint checkout, the root `flint.toml` declares the workspace. There `flint build`, `flint test` and `flint check` act on the core packages. For example, `flint test cli config --compiler both` runs `dub test :cli` and `dub test :config` on both compilers with the canonical flags.

## Fixture peers

`policy/test-peers.toml` declares the peers of workspace test suites. `flint test` runs each such package twice. The first run is offline (`dub test`). The second runs the same test binary inside the package's peers.

| Package | Peers |
| --- | --- |
| `ai` | loopback AI dialect peer |
| `storage` | loopback S3 peer, MinIO |
| `http` | Go HTTP/1.1, HTTP/2 and TLS peers |
| `security` | Go HTTPS JWKS peer |
| `mail` | Go SMTP and HTTPS provider peers |
| `cache` | Valkey 9.1.2 and the Go RESP3 peer |
| `sql`, `data`, `migrate` | disposable PostgreSQL 18.7 cluster |

`flint test --scenarios` also runs the live scenarios a package declares. `mq` runs seven scenarios against a real Apache Kafka 4.1.2 broker and against NATS JetStream 2.15.3, plain and over TLS.

Install every pinned peer with `python3 tools/install_peers.py --peer all`. The pins and their checksum sources are in `policy/peer-lock.json`. A peer without a pinned binary is never taken from the system. The offline tests still run, then FLINT-E0815 names the missing peer and fails the package. `flint doctor` lists each peer binary.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success. Warnings never change the exit code. |
| 1 | The user's code failed: build, test, check, layout or manifest. |
| 2 | The environment or toolchain is wrong, or a receipt does not verify. |
| 3 | Dependency resolution or the lock failed. |
| 4 | Usage error, including running outside a project. |

When several errors occur, the most fundamental class wins: 4, then 2, then 3, then 1.

## Diagnostics

Every error `flint` raises has a stable code. Run `flint explain --list` for the catalogue.

```text
error[FLINT-E0401] module name does not match its file path
  --> src/shop/order/service.d:1
  1 | module shop.orders.service;
  cause: declares `module shop.orders.service;` but its path names `shop.order.service`
  fix: declare `module shop.order.service;` or move the file
```

| Range | Area |
| --- | --- |
| E00xx | Command line |
| E01xx | `flint.toml` |
| E02xx | `flint.lock` |
| E03xx | Dependencies |
| E04xx | Project layout and module paths |
| E050x–E051x | Safety rules |
| E052x | Workspace structure (the structural gate) |
| E06xx | Formatting and lint |
| E07xx | Build, test and run |
| E08xx | Toolchain and environment |
| E09xx | Receipts |
| E10xx | API manifests (`flint api`) |

### Compiler errors from library code

With the DMD fork, an error that a Flint package, druntime or Phobos raises on your behalf is reported at your line, with the library's message and one line for the hidden frames. Misusing a framework API, such as a JSON field of a type that cannot be read, is one error that names the field:

```text
src/shop/orders.d(15,20): Error: Order.callback: `void delegate() @safe` cannot be read from JSON or configuration; use bool, an integer, float, double, an enum, string, an array, or a struct of these
       raised in library code at packages/serde/source/flint/serde/internal/json_codec.d(441,21), through 6 hidden frames (`flint build --verbose` shows them)
```

`--verbose` prints the compiler's full instantiation trace instead. LDC builds always print the full trace (ADR-027 section 5).

## JSON output

With `--json`, a command prints exactly one JSON document on stdout. Every document has these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `schema` | string | Command schema and version, such as `flint.build/1`. |
| `ok` | bool | No errors. |
| `exit_code` | int | The process exit code. |
| `diagnostics` | array | Diagnostics, each with `code`, `severity` (`error`, `warning`, `note`), `title`, `message`, `file`, `line`, `column`, `snippet` and `fix`. `file` uses `/` on every host, Windows included. |

Command fields:

| Schema | Fields |
| --- | --- |
| `flint.new/1` | `project`, `module_root`, `files`, `dependencies`, `starters`, `plan` |
| `flint.build/1` | `project`, `profile`, `compiler`, `artifact` (`path`, `receipt`, `canonical`, `non_canonical_reasons`), `packages` (workspace), `files_checked`, `waivers` |
| `flint.run/1` | `project`, `profile`, `artifact`, `program` (`command`, `exit_code`, `signalled`, `stdout_text`, `stderr_text`) |
| `flint.test/1` | `project`, `runs` (`name`, `compiler`, `ok`, `summary`, `artifact`, `receipt`, `peers`, `missing_peers`, `peer_summary`), `passed`, `failed` |
| `flint.check/1` | `project`, `checks`, `files`, `waived`, `waivers`, `structural` (as `tools/gates.py` reports it), `quality` (`files`, `unformatted`, `issues`, `formatter`) |
| `flint.fmt/1` | `files`, `changed`, `check` |
| `flint.lock/1` | `path`, `state` (`written`, `unchanged`, `current`, `missing`, `stale`), `packages` |
| `flint.deps/1` | `action`, `project`, `nodes` (tree), `paths` (why), `changes` (update, vendor), `target`, `components`, `verified`, `obligations` (audit) |
| `flint.package/1` | `project`, `target`, `libc`, `fully_static`, `needed`, `build_receipt`, `image`, `image_digest`, `components`, `outputs` (`kind`, `path`, `sha256`, `bytes`) |
| `flint.toolchain/1` | `action`, `directory`, `components`, `fork`, `commands`, `plan` |
| `flint.doctor/1` | `checks` (`name`, `status`, `detail`) |
| `flint.daemon/1` | `action`, `directory`, `servers` (`socket`, `pid`, `alive`, `flags`) |
| `flint.version/1` | `tool`, `toolchain`, `commit`, `dirty`, `receipt` |
| `flint.explain/1` | `codes` (`code`, `exit_code_class`, `title`, `explanation`, `example`) |
| `flint.docs/1` | `query`, `release`, `packages` (`name`, `module_name`, `description`, `symbols`, `with_examples`, `problem`), `symbols` (`qualified`, `name`, `kind`, `package_name`, `module_name`, `signature`, `comment`, `file`, `line`, `examples`), `exported` |
| `flint.examples/1` | `topic`, `examples` (`symbol`, `signature`, `example` (`file`, `line`, `code`)), `applications` |
| `flint.watch/1` | one line per cycle: `cycle`, `changed`, `action`, `ok`, `exit_code`, `restarted` |
| `flint.config/1` | `project`, `profile`, `files`, `keys` (`key`, `value`, `source`) |
| `flint.generate/1` | `project`, `kind`, `name`, `files` (`path`, `content`), `dependencies_added`, `next`, `plan` |
| `flint.receipt/1` | `artifact`, `receipt`, `canonical`, `non_canonical_reasons`, `profile`, `commit` |
| `flint.api-fetch/1` | `cache`, `fetched` (`project`, `version`, `directory`, `cached`, `licence`) |
| `flint.api-extract/1` | `project`, `version`, `output`, `files`, `types`, `methods`, `excludes`, `modules` (`name`, `types`, `methods`, `constructors`, `fields`, `constants`, `attributes`, `components`) |
| `flint.api-coverage/1` | `mapping`, `repo`, `mode` (`ratchet`, `release`, `update-baseline`), `baseline`, `rulebook`, `unclassified`, `regressions`, `improvements`, `complete`, `manifests` (`manifest`, `project`, `version`, `summary`, `modules`; each tally has `name`, `total`, `ported`, `adapted`, `excluded`, `unclassified`, `classified_percent`), `unclassified_ids` (`project@version` → element ids) |
| `flint.api-headers/1` | `files`, `ported`, `problems` |
| `flint.api-checklist/1` | `checklists` (`name`, `file`, `types`, `elements`, `open`) |
| `flint.api-diff/1` | `older`, `newer`, `added`, `removed`, `changed`, `differences` (`change`, `kind`, `id`, `details`) |

Usage errors that occur before a command runs use `flint.usage/1`. A field is added only with a new schema version.

## API manifests

ADR-030 makes Flint a port of Spring. The `flint api` commands prove the port is complete, element by element, against the pinned upstream sources.

**Fetch.** `api/upstreams.json` in the Flint home pins each upstream archive by URL and SHA-256:
- the Spring projects as GitHub tag archives: Framework v7.1.0, Boot v4.2.0, and the portfolio tags Boot v4.2.0 manages (Security 7.2.0, Data Commons, Relational and JPA 4.2.0, Batch v6.1.0), plus Spring AI v2.1.0;
- third-party APIs as Maven `-sources.jar`s, at the versions Boot v4.2.0 manages: Jakarta Validation 3.1.1, Persistence 3.2.0 and Servlet 6.1.0, Jackson databind 3.1.8, SLF4J 2.0.20 and Micrometer core 1.18.0.

`flint api fetch` unpacks them into `<flint home>/.flint/cache/api/<project>-<version>/` (`FLINT_CACHE` relocates the cache, `--cache` overrides it). A digest mismatch is an error, and nothing in the cache is ever compiled. `FLINT_OFFLINE=1` uses the cache only.

**Extract.** `flint api extract` reads declarations with a Java parser written in D. It skips method bodies and initializers by balanced brackets, after a lexer that understands comments, strings, characters and text blocks. Its output is the manifest, `api/upstream/<project>-<version>.json` by default (`flint.api-manifest/1`). That manifest lists:
- every public and protected type, top-level and nested: its kind (`class`, `interface`, `enum`, `record`, `annotation`), modifiers, annotations, type parameters and supertypes;
- each visible member: methods, constructors (including a class's implicit default constructor and a record's canonical one), fields, enum constants, annotation attributes with their defaults, and record components, with their signatures and annotations.

Interface members count as public, and the members of a type that is not visible are not listed. Which files count:
- In a Gradle or Maven tree, only `<module>/src/main/java`, where no other `src` directory lies above it. That leaves out `src/test`, `src/testFixtures`, `src/jmh` and build plugins' sample projects. The module is the directory above `src`.
- A flat `-sources.jar` is one module named after the project.
- Packages named `internal` are always left out, as are `package-info.java` and `module-info.java`.
- Each pin's `exclude` prefixes are left out (`buildSrc`, `framework-docs`, Boot's smoke and integration tests), plus any `--exclude`.

Kotlin and Groovy sources are not read.

Every element has an id, which the mapping and diffs key on:
- a type's id is its canonical Java name, such as `org.springframework.http.HttpStatus.Series`;
- a member's id is the type id, `#` and its signature: `query(String,RowMapper)`, `<init>(DataSource)`, or a field, constant, attribute or component name.

Signatures erase annotations and type arguments, as Java's overload identity does. The manifest holds one type per line, so it diffs line by line.

`--version` is accepted for `--tag`, since `flint.cli` reserves `--version` for itself.

**Classify.** Each repo's mapping classifies the upstreams `api/upstreams.json` assigns to it (`repo`):
- **Location.** In this monorepo the mapping is `api/<repo>/mapping.json`: `api/framework/mapping.json` covers Spring Framework and the third-party APIs, and `api/boot/mapping.json` covers Spring Boot. `tools/extract_repo.py` moves it to `api/mapping.json` in the extracted repo.
- **Manifests stay in `flint`.** The manifests and pins remain here under `api/`, with the tooling.
- **Running it.** `flint api coverage --repo framework` takes that mapping and every extracted manifest of the repo.

The mapping has the shape the rulebook ([`docs/spring/api-mapping.md`](spring/api-mapping.md)) describes:

```json
{"rulebook": 2,
 "upstream": ["spring-framework@v7.1.0", "spring-boot@v4.2.0"],
 "elements": {
   "org.springframework.http.HttpStatus": {"status": "ported", "d": "flint.engine.http.HttpStatus"},
   "org.springframework.http.ResponseEntity": {"status": "adapted", "rules": ["R12", "R13"], "d": "flint.engine.http.ResponseEntity"},
   "org.springframework.jmx.**": {"status": "excluded", "category": "jvm-platform"},
   "org.springframework.beans.factory.xml.**": {"status": "excluded", "category": "deferred", "phase": "3"}}}
```

The entries follow these rules:
- **Keys.** A key is an element id or a pattern: `*` matches within one name (no `.`, `#`, `(`, `)` or `,`), and `**` matches anything.
- **Precedence.** An exact id wins. Among patterns, the longest literal text before the first wildcard wins, then fewer `**`, then the longer pattern.
- **Status.** `ported` needs a D symbol `d` under `flint.`. `adapted` needs one or more of the rules R1–R14. `excluded` needs one of the rulebook's categories, and `deferred` must also name its `phase`.
- **Rulebook version.** `rulebook` must equal the version in the rulebook.
- **Upstreams.** Each manifest classified must be listed under `upstream`.

`flint api coverage` prints, per module, the element count and how many are ported, adapted, excluded and unclassified, then the first `--show` unclassified ids (default 20). `--json` lists every unclassified id. How it judges the counts depends on the mode:
- **Ratchet** (the default when `coverage-baseline.json` sits beside the mapping). The baseline records every module's unclassified count. A count above it, or a manifest it has not recorded, fails with FLINT-E1007. A count below it is reported, so you can lower the baseline: `flint api coverage --repo framework --update-baseline` rewrites it and refuses to raise any number.
- **Complete checklists.** In every mode, a checklist that `docs/spring/*/slice.json` (or `--slice`) marks `"complete": true` must have every element classified and none excluded as `deferred`, or the run fails with FLINT-E1008. Developer-facing elements must be ported or adapted, not postponed.
- **Release** (`--release`, or no baseline). Any unclassified element fails with FLINT-E1002. This is what the release requires (ADR-030 section 8).

Run `flint api coverage --repo framework` or `--repo boot` before each push, and lower the baseline in the same commit as the classifications that earn it.

**Checklists.** A slice file (`flint.api-slice/1`) names a porting slice's checklists. Each entry gives an upstream (`project@version`), a module, and optionally package patterns (the mapping's `*` and `**`):

```json
{"schema": "flint.api-slice/1", "title": "Phase 1",
 "checklists": [
   {"name": "spring-core", "upstream": "spring-framework@v7.1.0", "module": "spring-core",
    "packages": ["org.springframework.core", "org.springframework.core.convert.**"]},
   {"name": "spring-jdbc", "upstream": "spring-framework@v7.1.0", "module": "spring-jdbc"}]}
```

`flint api checklist --slice FILE --output DIR` writes `DIR/<name>.md` for each entry and an index, `DIR/README.md`, with per-checklist counts. A checklist has one table per type: the status, the element as Java declares it, and its id, which is the key a mapping entry uses. Statuses come from the upstream's repo mapping. A checklist is a view, so never edit it: classify in the mapping and regenerate. Phase 1's slice is [`docs/spring/phase1/slice.json`](spring/phase1/slice.json), and its checklists are in [`docs/spring/phase1/checklists/`](spring/phase1/checklists/README.md).

**Ported headers.** A file that carries upstream code says so before its `module` declaration (ADR-030 section 7):

```d
// Ported from spring-framework v7.1.0: spring-core/src/main/java/org/springframework/util/Assert.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
```

`flint api headers` checks every such file. It fails with FLINT-E1006 when:
- the project and version are not pinned in `api/upstreams.json`;
- the pin's licence entry (`matrix`) in `policy/upstream-licences.json` is `clean-room` or `native-c`, or pins another tag;
- the upstream's copyright line is missing (the entry's `header`, or any `Copyright` line when the entry names none);
- the licence line for the licence and use is missing: the Apache License 2.0, the MIT License, the BSD 3-Clause option, or the Eclipse Public License 2.0;
- "Modified by the Flint authors" is missing;
- an `epl-module` upstream is ported into a package whose `dub.sdl` does not declare `license "EPL-2.0"`.

**Gate.** `python3 tools/gates.py --gate api [--repo R] [--workspace W] [--flint PATH] [--release]` runs both proofs for each repo, at the repo's checkout in the workspace. `tools/ci.py` runs it on every change, in ratchet mode:
- `flint api headers` over the repo's packages;
- `flint api coverage` of its mapping over every manifest `api/upstreams.json` assigns to it, with the manifests and pins read from the `flint` checkout.

It fails on any header problem, invalid mapping, coverage regression or unfinished complete checklist. With `--release` it also fails on any unclassified element, as the release requires.

**Follow upstream.** `flint api diff old.json new.json` lists added (`+`), removed (`-`) and changed (`~`) elements. For a changed element it names each property that differs, such as `type: int -> long` or `annotations: (none) -> @Deprecated(since = "7.0.5")`. Parameter names and member order are not API. From v7.0.0 to v7.1.0, Spring Framework added 687 elements, removed 151 and changed 257.

```bash
flint api fetch spring-framework spring-boot
flint api extract --source .flint/cache/api/spring-framework-v7.1.0 --project spring-framework --version v7.1.0
flint api coverage --repo framework
flint api coverage --repo boot
```

## The project

```text
shop/
  flint.toml            the only manifest
  flint.lock            exact graph, content hashes, toolchain identity
  AGENTS.md             the Flint way for coding agents (flint generate agents refreshes it)
  config/application.toml, application-<profile>.toml
  src/shop/app.d        module shop.app
  test/shop/..._test.d  tests mirror src/
  .flint/               generated recipe, builds, receipts, DUB cache (git-ignored)
```

### `flint.toml`

```toml
[project]
name = "shop"              # lower-case letters, digits, hyphens; module root "shop"
base-package = "com.example.shop"  # optional: Spring's package; module root and src/com/example/shop/
version = "0.1.0"          # semantic version
flint = "1.0"              # platform version: toolchain, core packages and rules
type = "executable"        # or "library"
description = "Online shop"

[build]
executable = "shopd"       # binary name, default: the project name

[starters]                 # until Milestone 10, expands to the starter's core packages
web = {}

[dependencies]
"flint:log" = {}                       # core package; versions come from `flint`
model = { path = "../model" }          # a Flint library project or a local DUB package
"github.com/acme/money" = "1.2.0"      # repository path: minimum release, minimal version selection
"dub:dyaml" = "0.10.0"                 # a DUB package from the compatibility index

[test-dependencies]
"flint:test" = {}

[profile.release]          # additions on top of a canonical profile; marks builds non-canonical
dflags = ["-mcpu=native"]

[profile.dev]
debug = false              # opt out of debug information (never the default; `flint run --debug` keeps it)

[targets]
default = ["linux-x86_64-glibc"]

[[waivers]]                # lift one rule for one file, with a reason
rule = "FLINT-E0502"
file = "src/shop/legacy.d"
reason = "vendored parser, tracked in #12"

[unchecked]                # DUB packages that fail Flint's safety checks, with a reason
"dub:dyaml" = "YAML parsing until flint:serde reads YAML"

[native]                   # native packages from Flint's recipe index, static by default
zlib = "1.4"
openssl = { version = "3.5.9", linkage = "bundled" }   # shared library in lib/, run path $ORIGIN/../lib
libpq = { version = "18", system = true }              # the host's library: non-portable

[native.c]                 # embedded C (default: native/**/*.c), C17, hardened, warnings are errors
include_dirs = ["native/include"]
standard = "c11"
defines = ["SHOP_FAST=1"]
```

`[project] license = "MIT"` sets the SPDX licence that SBOMs and `flint deps audit` report. D reaches embedded C and native packages only through `src/<root>/ffi/` modules (FLINT-E0513).

### Profiles

`policy/profiles.toml` defines the canonical profiles. `flint`, `tools/ci.py` and `tools/measure_builds.py` all read it.

| Profile | Compiler | Flags |
| --- | --- | --- |
| `dev` | forked DMD, compile server, parallel DUB | `-preview=dip1000 -debug -g -boundscheck=on` |
| `test` | DMD and LDC | each package's own recipe; the project adds `-unittest -g` |
| `release` | LDC | `-preview=dip1000 -release -boundscheck=safeonly -O3 --flto=thin -link-defaultlib-shared=false` |
| `size` | LDC | as release, with `-Oz` |
| `sanitize` | LDC | ASan and UBSan on the sanitizer-aware runtime |

### The platform cache

The pinned platform modules (the core packages, framework modules and Boot libraries a project resolves) play the role of Go's standard library (ADR-030 section 5). `flint build` compiles each one once per compiler, flags, platform version and target, keeps the archive in `<cache>/platform/<key>/`, and links it into every project that needs it. Third-party modules (path, repository and DUB dependencies) always compile from source.

- **Key.** A module's key hashes the compiler's and DUB's executables, the platform release, the profile's flags, the target, the module's DUB settings, the content of every file DUB lists for it, and its dependencies' keys. Editing a module re-keys it and everything that imports it, because their inlined functions and template instances may change.
- **Priming.** On a miss, `flint build` reports `Priming N platform module(s)`, builds them with one DUB run from a synthetic root (`.flint/generated/platform-describe`), and stores each archive under a temporary name before renaming it. It keeps the four newest archives of each module.
- **Linking.** `.flint/generated/platform/dub.sdl` lists each module as its import paths and settings, without sources. The project's recipe depends on it and links the archives as one group, so archive order does not matter.
- **Reproducible.** The prime build runs from the Flint home, and every archive's member headers are normalized as `ar D` does (time, owner and group zero, mode 644). A rebuild of the same source with the same toolchain and flags then has the same bytes, in another project and another cache. `tests/test_flint_platform_cache.py` checks it.
- **Interfaces.** Modules are imported from their pinned source. DMD 2.114's `-H` interface files drop the function bodies that compile-time evaluation needs, and its `-inline` full output loses the imports behind expanded UDA sequences, so `.di` files would not compile Flint's modules. Holding the modules' semantic analysis belongs to the compile server.
- **Compile-server prelude.** `.flint/generated/platform/dmd-server-prelude.txt` lists, one per line, the import paths (`-I<dir>`), version identifiers and flags of the platform modules the project depends on, then their D module names. A dev-profile build passes it to DMD as `FLINT_DMD_SERVER_PRELUDE`; test, release and size builds do not, and neither does a profile that turns the compile server off. The file depends only on the platform's source, settings and flags. The forked compile server preloads those modules and keys itself by the file's content, so an edit build analyses only the project's own modules ([toolchain/README.md](../toolchain/README.md)).
- **Shared dev linking.** A DMD dev build links the platform as one shared object (owner decision 2, 2026-11-23), so an edit relinks only the project. The project's platform archives and the cached AOT library are linked once, with the native libraries they use, into `<cache>/platform/shared-<key>/libflint-platform.so`. The project then links that object and druntime and Phobos as a shared library (`-defaultlib=libphobos2.so`), so every D module shares one runtime, with run paths to both. The key covers the platform key and the native linker flags. On gs-rest-service a one-line edit drops from about 0.5 s to about 0.23 s (busy laptop, not evidence). `--static` links the archives instead, and test, release, size and LDC builds always do. The receipt lists the object as `flint-platform-shared`. A dev binary therefore needs the cache and the DMD installation at run time. `flint package` builds release binaries, which do not.
- **Off.** Use `--no-platform-cache` or `FLINT_PLATFORM_CACHE=0`. Sanitizer and cross-target builds always compile from source. On this first slice the cache is enabled on Linux hosts only, until the macOS and Windows archivers are checked.

The receipt's `platform_archives` lists each linked module with its key and archive SHA-256; it is empty when the modules compiled from source.

### The AOT library

A Boot application's Flint AOT modules (docs/spring/aot-contract.md) build in two parts. The project compiles the registry and the modules generated for its own `src/` modules. The modules generated for the platform and for dependencies, such as Boot's auto-configuration, are in `.flint/generated/aot-library`. They import no project module and change only with the platform or the closure, so they build as a library that DUB keeps across edits. Without the split, a one-line edit to gs-rest-service recompiled all eleven generated modules, and its edit build took 0.98 s. With the split it recompiles three and takes 0.69 s. When the build links the platform cache, the AOT library is cached there too. Its key covers the generated files' text, the diagnostic flags and the platform cache's inputs and module keys. A cold build of any project with the same closure then links the archive without compiling the library, and the receipt lists it under `platform_archives` as `flint-aot-library`. `flint_aot_library.d`, compiled with the project, imports each library module. When DMD archives the library with `-lib`, each function becomes its own archive member, so a module's `ModuleInfo` reaches the link only through an import. The `ModuleInfo` in turn brings the static constructors of the platform modules the module imports.

### Receipts

Every artifact has `<artifact>.receipt.json` (`flint.receipt/1`) next to it. Workspace package artifacts have theirs in `.flint/receipts/`. A receipt records the identities behind the artifact: tool, project, manifest and lock hashes, source commit and dirtiness, toolchain components and hashes, native install receipt, profile, flags actually passed, additions, waivers, command, influential environment and output hashes. An artifact is **canonical** when no flags were added, the compiler belongs to the profile, and the toolchain verifies against its receipt. `flint receipt --canonical` and measurement refuse anything else.

## Environment

| Variable | Effect |
| --- | --- |
| `FLINT_HOME` | The Flint installation, instead of the one above the executable. |
| `FLINT_TOOLCHAIN_DIR` | The toolchain directory, instead of `<installation>/.tools`. |
| `FLINT_COLOR` | `auto` (default), `always` or `never`. `NO_COLOR` is honoured. |
| `FLINT_LOG` | Append a JSON line per child process `flint` runs (argv, directory, status, duration). |
| `FLINT_PROFILE` | Read by applications: selects `config/application-<profile>.toml`. |
| `FLINT_PROXY` | Fetch repository-path modules and DUB packages from `<proxy>/<path>` instead of `https://<path>`; `off` never fetches. |
| `FLINT_CACHE` | The module and platform cache, instead of `<installation>/.flint/cache`. Its `digests.log` keeps the SHA-256 of files every build reads, such as toolchain executables, flint itself, platform sources and an unchanged artifact. Each digest is reused while the file keeps its size, modification time and inode, as git's index does. Downloads and lock verification always hash in full. |
| `FLINT_PLATFORM_CACHE` | `0`: compile the platform modules from source, as `--no-platform-cache` does. |
| `FLINT_OFFLINE` | `1`: never touch the network; use the cache or `vendor/`. |
| `FLINT_DUB_INDEX` | An additional DUB compatibility index, for private packages. |
| `SOURCE_DATE_EPOCH` | Timestamps of `flint package` archives, images and SBOMs, for byte-reproducible packages. |

`flint` removes `DFLAGS` and `FLINT_DMD_SERVER_PRELUDE` from its builds and sets the prelude itself. It records `FLINT_DMD_SERVER`, `FLINT_DUB_PIPELINE`, `FLINT_DMD_DIRECT_LINK`, `FLINT_LINK_THREADS`, `CC` and `LD` in receipts when they are set.
