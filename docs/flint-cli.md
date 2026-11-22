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
| `flint build [packages...] [--profile P] [--compiler C] [--dflags F]... [--lflags F]... [--verify] [--locked] [--force] [-- flags]` | Build the project, or workspace packages, with a canonical profile. Writes a receipt next to the artifact. |
| `flint run [--profile P] [--dflags F]... [--verify] [--locked] [-- args]` | Build if needed, then run with the project root as working directory. |
| `flint test [packages...] [--compiler dmd\|ldc\|both] [--sanitize] [--scenarios] [--verify] [--locked] [--force]` | Build and run unittests: the project's `src/` and `test/`, or `dub test` for workspace packages. `--sanitize` builds a project's tests, embedded C and native packages with ASan and UBSan. |
| `flint check [--gate structural] [--package P]...` | Every check CI runs: lock, layout, safety rules, configuration convention, dfmt, D-Scanner and clang-tidy over embedded C. In the workspace: `tools/gates.py`'s structural gate, then dfmt and D-Scanner. |
| `flint fmt [--check]` | Format with the pinned dfmt and the repository's `.editorconfig`. |
| `flint lock [--check]` | Write `flint.lock`, or verify it. |
| `flint deps tree\|why <package>\|update [packages...]\|vendor` | Print the graph, explain why a package is in it, raise repository-path requirements to their latest release, or copy repository modules and DUB packages into `vendor/` for offline builds. |
| `flint deps audit [--target T]` | Verify the lock and every module, DUB and native hash; list each component's licence and the LGPL/AGPL obligations; show `[unchecked]` waivers. |
| `flint package [--target T] [--container] [--sbom]` | Build the release executable for a target, verify it is static, and write a reproducible `tar.gz` with `bin/`, `config/` and `resources/`; `--container` adds a `FROM scratch` OCI image, `--sbom` SPDX 2.3 and CycloneDX 1.6 SBOMs. |
| `flint toolchain install [--toolchain-dir D] [--no-pgo] [--dmd-linker L] [--sanitizers] [--musl] [--plan]` | Install the pinned DMD/DUB fork, LDC, clang (embedded C, clang-tidy) and the native package engine, and write the toolchain receipt. `--sanitizers` adds the sanitizer-aware LDC runtime, `--musl` the static musl target. |
| `flint toolchain verify\|info [--toolchain-dir D]` | Check the toolchain against `policy/toolchains.json` and `toolchain/*.patch`, or describe it. |
| `flint doctor [--project D]` | Explain environment problems that would make a build fail or non-canonical. |
| `flint daemon start [--profile P]\|stop\|status` | Manage the forked DMD's compile server. |
| `flint version [--verify]` | Print the tool, toolchain and source identities. `--verify` checks this executable against its receipt. |
| `flint explain <code>\|--list` | Explain a diagnostic code with a correct example. |
| `flint receipt <artifact> [--canonical]` | Verify an artifact against its receipt and the current toolchain. |

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

## JSON output

With `--json`, a command prints exactly one JSON document on stdout. Every document has these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `schema` | string | Command schema and version, such as `flint.build/1`. |
| `ok` | bool | No errors. |
| `exit_code` | int | The process exit code. |
| `diagnostics` | array | Diagnostics, each with `code`, `severity` (`error`, `warning`, `note`), `title`, `message`, `file`, `line`, `column`, `snippet` and `fix`. |

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
| `flint.receipt/1` | `artifact`, `receipt`, `canonical`, `non_canonical_reasons`, `profile`, `commit` |

Usage errors that occur before a command runs use `flint.usage/1`. A field is added only with a new schema version.

## The project

```text
shop/
  flint.toml            the only manifest
  flint.lock            exact graph, content hashes, toolchain identity
  config/application.toml, application-<profile>.toml
  src/shop/app.d        module shop.app
  test/shop/..._test.d  tests mirror src/
  .flint/               generated recipe, builds, receipts, DUB cache (git-ignored)
```

### `flint.toml`

```toml
[project]
name = "shop"              # lower-case letters, digits, hyphens; module root "shop"
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
| `FLINT_CACHE` | The module cache, instead of `<installation>/.flint/cache`. |
| `FLINT_OFFLINE` | `1`: never touch the network; use the cache or `vendor/`. |
| `FLINT_DUB_INDEX` | An additional DUB compatibility index, for private packages. |
| `SOURCE_DATE_EPOCH` | Timestamps of `flint package` archives, images and SBOMs, for byte-reproducible packages. |

`flint` removes `DFLAGS` from its builds. It records `FLINT_DMD_SERVER`, `FLINT_DUB_PIPELINE`, `FLINT_DMD_DIRECT_LINK`, `FLINT_LINK_THREADS`, `CC` and `LD` in receipts when they are set.
