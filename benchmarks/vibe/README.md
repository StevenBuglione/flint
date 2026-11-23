# The vibe-coding benchmark

This benchmark measures whether Flint makes D "just work" for a coding agent, rather than asserting it (ADR-021 section 11, ADR-027 section 6).

A coding agent gets a task statement and a fresh project. The task's black-box acceptance test then scores what the agent built, by running the program and checking what it observes. The same test scores a Flint, Go or Spring Boot solution.

## Tasks

| Task | What the agent builds | Acceptance |
| --- | --- | --- |
| `rest-notes` | A notes REST API with registration, login, bearer tokens, validation and SQLite migrations | HTTP checks, a restart against its own database, and an inspection of the database file |
| `cli-todo` | A to-do CLI with subcommands, a TOML configuration file and exit codes | Command runs in a scratch `$HOME` |
| `queue-worker` | A worker that consumes a spool-directory queue with bounded concurrency and graceful shutdown | Queued and live jobs, invalid jobs, timing, SIGTERM and a restart |
| `tui-dashboard` | A full-screen dashboard that follows a metrics file | A pseudo-terminal: rendering, following, sorting, resizing, and terminal restoration |

Each task directory holds a `TASK.md`, which is the statement the agent sees, and an `acceptance.py` that defines `checks(program)`. `vibelib.py` holds the shared helpers. The tests use Python's standard library only.

## Running

```bash
python3 tools/vibe_bench.py list
python3 tools/vibe_bench.py reference cli-todo
python3 tools/vibe_bench.py prepare cli-todo --language flint --dir /tmp/todo
python3 tools/vibe_bench.py accept cli-todo --language flint --dir /tmp/todo
python3 tools/vibe_bench.py run cli-todo --language flint --agent codex --model gpt-6.2-sol --effort high --runs 3
python3 tools/vibe_bench.py report benchmarks/vibe/results/*.json
```

- `reference` scores the checked-in solutions under `reference/<language>/<task>`. A reference proves its task can be done and that the acceptance test is sound.
- `oracle` scores the minimal Python programs in `oracles/`. They prove each acceptance test sound where no reference exists yet, and are not benchmark entries.
- `prepare` creates the agent's workspace:
  - for Flint, `flint new` with the matching core packages and the generated `AGENTS.md`;
  - for Go, `go mod init`.

  It also writes `PROMPT.md`: a language preamble followed by `TASK.md`.
- `accept` builds a workspace and runs the acceptance test. With `--json` it saves the record.
- `run` prepares a workspace, runs the agent, then scores the workspace.
  - **Flint runs:** with Claude Code, the agent gets only the `flint` MCP server (`flint mcp --log`) and file tools, with no shell. Codex can't withhold its shell, so Codex runs have the shell in every language. Logging shims count the `flint`, `dub`, `dmd` and `ldc2` builds started through it, as they do for `go` and `mvn`. Records report `mcp_builds` and `shell_builds` separately, and failures for both.
  - **The owner's canonical agent:** `--agent codex --model gpt-6.2-sol --effort high` (Codex CLI 0.171.0).
  - **Go and Spring Boot runs:** the agent gets a shell and its usual tools.
  - **`--agent`:** `claude` (Claude Code), `codex` (Codex CLI), or `command` with `--agent-command '<template using {prompt} {dir} {mcp_log} {flint}>'`.

## The references

`reference/<language>/<task>` holds a checked-in solution per task and language. Each one is written the way that language's developers would write it, and each passes its whole acceptance test.

| Task | Flint | Go | Spring Boot |
| --- | --- | --- | --- |
| `rest-notes` | held | `net/http` routing patterns, modernc SQLite, embedded migrations, bcrypt | Web MVC, `JdbcClient`, Flyway, SQLite JDBC, Bean Validation, BCrypt |
| `cli-todo` | `flint:cli`, `flint:config` | `flag`, BurntSushi/toml | picocli commands as Spring beans, Jackson TOML |
| `queue-worker` | held | the standard library | `@Scheduled` polling, a bounded `ThreadPoolTaskExecutor` |
| `tui-dashboard` | held | `golang.org/x/term` | JLine |

The Flint references for `rest-notes`, `queue-worker` and `tui-dashboard` are on hold while the owner settles Flint's application model.

### Toolchains

The references build with pinned, checksummed toolchains, never with whatever is on the machine.

- **Go:** the Go 1.27.4 pinned in `policy/toolchains.json`, with `GOTOOLCHAIN=local` and `-mod=readonly`. Each `go.sum` is checked against the Go checksum database.
- **Spring Boot:** the Temurin JDK 21.0.13.1+2 and Maven 3.9.16 pinned in `policy/peer-lock.json`.
  - Maven runs with `--strict-checksums`, so every Maven Central artifact is checked against its published checksum. Artifacts go into `.flint/peers/m2`.
  - A reference must use `spring-boot-starter-parent` 4.2.0. The harness checks the resolved parent pom and BOM against their digests in `policy/peer-lock.json`.
  - A workspace with a Maven wrapper (`./mvnw`) is built with the wrapper and the pinned JDK.

The harness looks for the toolchains in this checkout, and in the main checkout when run from a git worktree. To install them:

```bash
python3 tools/install_peers.py --peer go --peer jdk --peer maven
```

### Running a reference

```bash
python3 tools/vibe_bench.py reference --language go
python3 tools/vibe_bench.py reference --language spring
python3 tools/vibe_bench.py reference rest-notes --language spring
python3 tools/vibe_bench.py reference cli-todo --language flint
```

To run one by hand:

- **Go:** build it with `go build -o notes .` in `reference/go/rest-notes`.
- **Spring Boot:** build it with `mvn -q -DskipTests package`, then run `java -jar target/notes-1.0.0.jar`.

For example, the REST service takes `PORT` and `DATABASE_PATH`, and the worker takes `--spool <dir>`.

## What is scored

For each run, the benchmark records the following.

- **Success:** every acceptance check passes. The share of passing checks is kept too.
- **Build–fix iterations:** the builds, test runs and checks the agent started, and how many failed.
  - For Flint, these come from the MCP call log.
  - For Go and Spring Boot, logging shims of `go`, `mvn` and `gradle` count them, but cannot see whether each one failed.
  - A Flint run also counts its API lookups.
- **Wall time** of the agent run.
- **Review size:** non-blank, non-comment source lines and attributes (D UDAs, Java annotations, Go struct tags).

`report` prints the per-task medians as a table. The results are JSON documents with the `flint.vibe/1` schema, written to `results/`.

## Status

- **The task set, the acceptance tests and the harness are in place.**
- **Oracles:** a Python oracle passes every acceptance test (42, 17 and 15 checks). Running them found and fixed two bugs in the tests themselves.
- **References:**
  - Go and Spring Boot references pass every acceptance test: 42 checks for `rest-notes`, 29 for `cli-todo`, 17 for `queue-worker` and 15 for `tui-dashboard`.
  - `cli-todo` has a Flint reference that passes all 29 checks. Writing it found three library gaps, each now fixed in the library: configuration keys bind relaxed, help covers subcommands, and `@safe` code can write to standard error (ADR-027 section 6).
- **Still to write:** the Flint references for `rest-notes`, `queue-worker` and `tui-dashboard`, held for the application-model decision.

### What running real agents needs

Agent runs use model capacity, so they start only when asked.

- **The agent CLI:** `claude` or `codex` is installed and signed in on the runner. A run has no network sandbox of its own.
- **A budget:** at least 3 runs per task and language, so 36 runs for the full matrix. A run is capped at one hour by `--timeout`.
- **For Spring Boot:** the pinned JDK and Maven (`tools/install_peers.py --peer jdk --peer maven`), and network access to Maven Central.
- **The model:** `--model` pins it, so results stay comparable.
