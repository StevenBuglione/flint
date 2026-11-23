# ADR-022: Milestone 7 decisions — the `flint` CLI core and the project model

Status: proposed by the Milestone 7 implementation on 2026-11-22, for the project owner's review. It implements the first row of [ADR-021](ADR-021-flint-platform.md)'s milestone plan within [ADR-018](ADR-018-flint-cli.md), whose decisions stand.

## Context

ADR-018 and ADR-021 fix what `flint` does. Building it forced choices they leave open: where the tool lives, how DUB is driven, what exactly `flint.toml` and `flint.lock` contain, what makes a build canonical, and which library gaps had to be closed. This ADR records those choices. The handoff archive stays byte-identical, so the public API additions are recorded here, as ADR-017 did for Milestone 6.

## Decisions

1. **Location.** `flint` is the application project `apps/flint/`, laid out as ADR-021 section 2 prescribes (`flint.toml`, `flint.lock`, `src/<root>/`, `test/<root>/`, `.flint/`). It is not a package under `packages/`, so the 37-package product surface is unchanged. Its project name is `flint-tool` (module root `flint_tool`) because the module root `flint` belongs to the core libraries; `[build] executable = "flint"` names the binary.

2. **Libraries.** `flint` uses `cli` (command schema, help, completion), `config` (the profiles and platform policy), `log` (`FLINT_LOG` trace of every child process), `os` (processes, interrupts, globbing), `term` (terminal capabilities), `serde` (TOML and JSON in, JSON out) and `test` (its unit tests), plus `arena` and `conc` for their types. It does **not** link `style`: `style` measures text with utf8proc and a C shim, and `flint` must bootstrap from DUB alone on a host without native providers (decision 14). Human output uses seven fixed SGR sequences, enabled from `term.describe`, `NO_COLOR` and `FLINT_COLOR`.

3. **DUB is an internal backend.** `flint` renders `.flint/generated/dub/dub.sdl` from `flint.toml` and rewrites it only when its content changes. Each canonical profile is a configuration with its own `targetPath` under `.flint/build/<profile>/`. The `unittest` configuration adds `test/` and the `unittests` and `debugInfo` build options to the project only, so dependencies are not rebuilt with their own unittests. `flint` runs the pinned DUB with `--build=plain --skip-registry=all`, `DUB_HOME=.flint/dub` and, for plain profiles, the profile's flags in `DFLAGS`: the mechanism `tools/measure_builds.py` already verified. The inherited `DFLAGS` is always removed and the pinned toolchain is put first on `PATH`.

4. **Profiles are data.** `policy/profiles.toml` holds the closed set `dev`, `test`, `release`, `size` and `sanitize`: compiler, compilers, DUB build type, flags, compile server and pipeline switches, and the native provider profile. `flint` reads it through `flint.config` (decision 16); `tools/ci.py` and `tools/measure_builds.py` read it through `tools/profiles.py`, which enforces the same schema. The flags are byte-identical to the literals they replace, and `tests/test_flint_cli.py` asserts that.

5. **Platform.** `policy/platform.toml` declares the platform version (`flint = "1.0"`) and the release (`0.7.0`). A project's `flint = "x.y"` must equal it (FLINT-E0107).

6. **`flint.toml` has a closed schema.** Sections are `[project]` (`name`, `version`, `flint`, `type`, `description`), `[build]` (`executable`), `[starters]`, `[dependencies]`, `[test-dependencies]`, `[profile.<name>]` (`dflags`, `lflags`), `[targets]` (`default`), `[[waivers]]` (`rule`, `file`, `reason`) and `[unchecked]`. Unknown keys fail with a did-you-mean suggestion. Milestone 7 resolves:
   - core packages, written `"flint:<package>" = {}`; their versions come from the platform version, so a version string is FLINT-E0305;
   - path dependencies, `name = { path = "..." }`, naming a Flint library project or a local DUB package;
   - remote `name = "x.y.z"` dependencies fail with FLINT-E0303 until Milestone 8.

   `[starters]` and `flint new --starter` expand to the starter's core packages until starters ship in Milestone 10.

7. **`flint.lock`.** The lock is rendered deterministically from the resolution, so verification is a byte comparison and a mismatch names the added, changed or removed packages. It records the platform and toolchain versions, the toolchain, patch, profile and safety policy hashes, and each package's kind, scope, dependencies and content hash. A stale lock is an error (FLINT-E0202, exit 3), as Go's default read-only module mode is; `flint lock` accepts the change. A missing lock is written by the first build unless `--locked` is given. A project inside the Flint checkout (such as `apps/flint`) records `pinned_by = "workspace commit"` instead of hashes, because the commit already pins its core packages; otherwise every library commit would invalidate the lock.

8. **Layout rules.** Sources live in `src/<root>/` and `test/<root>/`, where `<root>` is the project name with hyphens replaced by underscores. Module names must match file paths, `package.d` names its directory, and a module cannot be both `x.d` and `x/`. `config/` holds only `application.toml` and `application-<profile>.toml`, and YAML or JSON there is FLINT-E0407. A `generated/` directory outside `.flint/generated/` is FLINT-E0408, and `flint check` requires `.flint/` in `.gitignore`.

9. **Safety rules.** The rules of `tools/gates.py`'s structural gate are implemented once (`flint_tool.check`) and applied both to the workspace and to projects. In a project, `@trusted` and `@system` are allowed only in `<root>.sys.*` and `<root>.ffi.*`, string mixins are not allowed, and every `flint.*` or path-dependency import needs a direct dependency (test sources may also use test dependencies). `flint build` and `flint test` run the layout and safety subset (`flint test` also gives each workspace package the test environment `tools/ci.py` gives it, such as SDL's offscreen driver for `desktop`); `flint check` adds the configuration and repository rules, dfmt and D-Scanner. A waiver suppresses one code for one file and is listed in output and receipts.

10. **Receipts.** Every artifact gets `<artifact>.receipt.json` (schema `flint.receipt/1`) recording the tool, project, source commit and dirtiness, toolchain components and hashes, native install receipt, profile, the policy flags and the flags actually passed, additions, waivers, command, influential environment and output hashes. Workspace package artifacts live inside `packages/`, so their receipts are written to `.flint/receipts/` instead. A build is **canonical** when no flags were added (by `flint.toml` or the command line), the compiler is one of the profile's, and the toolchain verifies against its receipt. `flint receipt <artifact> [--canonical]` and `flint version --verify` check an artifact against its receipt and the current toolchain.

11. **Toolchain receipt.** `flint toolchain install` runs `tools/install_toolchains.py` for the DMD/DUB fork and LDC and writes `flint-toolchain.json` (schema `flint.toolchain/1`) into the toolchain directory from the installer's own output: archive hashes, installed binary hashes, fork patch and prelude hashes. An installation without the receipt cannot be traced to `toolchain/*.patch`. `flint` then warns (FLINT-E0804) and marks builds non-canonical, and `--verify` or `flint toolchain verify` turn that into exit 2. The installer is not modified.

12. **Diagnostics v1.** Every error `flint` raises has a catalogued `FLINT-Ennnn` code with a title, explanation, example and exit class. A diagnostic also has a cause, a fix, and a location with a snippet when one exists. Codes are never reused. The exit code is the most fundamental class among the errors: usage (4), then environment (2), then dependency (3), then the user's code (1). Warnings never change it. `flint explain <code>` and `flint explain --list` expose the catalogue.

13. **Machine output.** With `--json`, each command prints exactly one JSON document on stdout carrying `schema` (such as `flint.build/1`), `ok`, `exit_code` and `diagnostics`, plus its own fields. `flint run` replaces itself with the program in human mode so the program owns the terminal; `flint run --json` captures the program's output into the document instead.

14. **Bootstrap.** `python3 tools/install_toolchains.py --compiler flint` renders the same DUB recipe from `apps/flint/flint.toml` (a test compares it with `flint`'s), builds stage 1 with the pinned DUB, lets stage 1 rebuild `flint` with `flint build --force`, checks the result with `flint version --verify`, and installs it with its receipt in `.flint/bin/`. `flint` finds its installation from `FLINT_HOME` or by walking up from its executable.

15. **Compile server management.** `flint daemon status` lists `$XDG_RUNTIME_DIR/flint-dmd/*.sock`, a server's liveness lock and its key flags. `start` compiles a probe with a profile's flags and waits for the server, and refuses a socket directory too long for a Unix socket path, where the fork silently compiles without a server. `stop` sends SIGTERM to each server's process group and removes stale sockets.

16. **Fixture peers.** `policy/test-peers.toml` declares which workspace packages need which peers, how each peer is started and which pinned binaries it needs (ADR-018 resolved choice).
    - **Wrappers.** A peer is a wrapper command: the package's own fixture runner from its `ACCEPTANCE.md`, or `tools/pg_peer.py` for a disposable PostgreSQL cluster. The wrapper starts the peer, exports its address through `FLINT_*` variables and runs the rest of the command line.
    - **Test sequence.** `flint test` first runs the package's `dub test`, the offline pass, which also builds the test binary. It then runs the same binary inside the package's wrappers, outermost first.
    - **Pins.** Peer pins live in `policy/peer-lock.json`, each with its source URL, its digest and how that digest was verified. `tools/install_peers.py` verifies every archive before use and writes a `flint-peer.json` receipt per peer.
      - Valkey 9.1.2 is built with `make` from its tag archive, whose SHA-256 equals the project's published hash.
      - nats-server v2.15.3 is built from its tag with the pinned Go 1.27.4, with modules verified by `go.sum` and the checksum database.
      - MinIO `RELEASE.2025-10-15T17-29-55Z` is built from its tag with the pinned Go. MinIO no longer serves community binaries (`dl.min.io` answers 410), so a source build is the only reproducible choice.
      - Apache Kafka 4.1.2 matches its Apache-published SHA-512.
      - Eclipse Temurin JRE 21.0.13.1+2 matches its published SHA-256 and runs Kafka; no container is needed.
      - PostgreSQL 18.7 is built from the libpq source pinned in `policy/native-lock.json`, and Go comes from `policy/toolchains.json`.
    - **Go fixture servers** are built offline with the pinned Go.
    - **Missing peers.** A peer whose binary is missing is never taken from the system. The offline pass still runs, then FLINT-E0815 names the peer and fails the package.
    - **Live scenarios.** `[scenarios]` declares commands that `flint test --scenarios` runs after the unit tests. `mq`'s, `tools/mq_live.py`, starts a single-node KRaft Kafka on the pinned JRE and JetStream, plain and with TLS from a throwaway CA. It builds the scenario programs in `packages/engine-mq/fixtures` and runs all seven against them.
    - **`tools/ci.py`.** It never started peers; its `run_tests` lane is unchanged.

    `flint toolchain install` also stops the compile servers running the DMD it replaces, which otherwise make the installer's in-place extraction fail with "Text file busy". It writes the toolchain receipt as soon as DMD, DUB and LDC are installed, before the quality tools.

17. **Library gaps closed in the libraries** (the public API additions below) rather than worked around in `flint`.

## Public API additions

- **`flint.config`.** `ConfigOptions` gains two fields with defaults that keep today's behaviour:

  ```d
  string baseName = "application";  // files are <baseName>.toml and <baseName>-<profile>.toml
  bool readEnvironment = true;      // false: no .env, process environment or FLINT_PROFILE
  ```

  Checked-in policy files are read with `readEnvironment = false`, so nothing outside the files and explicit arguments can change them. An empty, overlong or non-key `baseName` is `invalidArgument`.

- **`flint.serde.owned`.**

  ```d
  Result!string serialize(T)(scope const ref T value, EncodeOptions options = EncodeOptions.init);
  ```

  It is the GC-owned counterpart of `deserialize!T`: strings, dynamic arrays and nested DTOs become compact JSON, with the field names, `JsonIgnore` and canonical ordering of `encodeJson` and the same depth and member bounds. The arena encoder `encodeJson` still rejects dynamic arrays at compile time.

- **`flint.term`.**

  ```d
  enum Stream : ubyte { output, error }
  struct StreamInfo { bool terminal; ColorProfile colors; Size size; }
  StreamInfo describe(Stream stream);
  ```

  `describe` reports whether stdout or stderr is a terminal, its colour profile (with the session's `TERM`, `COLORTERM` and `NO_COLOR` rules) and its window size, without changing terminal modes, entering the alternate screen or reading input. Line-oriented tools need this; `Session.open` takes over the terminal.

## Library fixes without API changes

- **`flint:os`.** DMD compiles `ffi/interrupt_latch.c` with ImportC and, in `-lib` mode, emits one object per function, which left the file-`static` descriptor unreachable from the split functions. Every DMD-built application linking `flint:os` as a library failed to link. The descriptor now has external linkage under the unique name `flint_os_interrupt_fd`.
- **`flint:term`.** glibc's `_FORTIFY_SOURCE` marks `write` `warn_unused_result`, which a `(void)` cast does not silence under `-Werror`. Ubuntu's default GCC therefore failed to build the package's C shim. The signal handler now assigns the result.

## Measurement method changes

`tools/measure_builds.py` now takes its `dmd`, `O3` and `Oz` flags from `policy/profiles.toml` (`dev`, `release` and `size`). The flags are unchanged. The script's own digest, which enters `measurement_protocol` and so the toolchain fingerprint, changes, and the protocol now also records `profiles_sha256`. As before, a base commit and a candidate compare only when measured with the same producer version. `tools/ci.py` takes the sanitizer lane's flags from the `sanitize` profile and the test build type from the `test` profile, with identical values.

## Consequences

- The developer loop, CI and measurement share one flag source, and every `flint` artifact can be traced through its receipt.
- `tools/gates.py` and `tools/quality.py` keep working unchanged in behaviour. `quality.py` now also covers `apps/`. `flint check --gate structural` prints byte-identical output, and the test suite compares verdicts on mutated copies of the workspace.
- Until `flint toolchain install` writes a receipt on a machine, that machine's builds are reported as non-canonical. They are not silently trusted.
- Remaining for later milestones: remote and native dependency resolution and `flint deps`/`package` (8); the API index, `docs`, `mcp`, generators, `AGENTS.md` and compiler-diagnostic rewriting (9); starters (10); and fixture peers for `flint test` (ADR-018), which `tools/ci.py` still starts.
