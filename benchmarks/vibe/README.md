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
python3 tools/vibe_bench.py run cli-todo --language flint --agent claude --runs 3
python3 tools/vibe_bench.py report benchmarks/vibe/results/*.json
```

- `reference` scores the checked-in solutions under `reference/<language>/<task>`. A reference proves its task can be done and that the acceptance test is sound.
- `prepare` creates the agent's workspace:
  - for Flint, `flint new` with the matching core packages and the generated `AGENTS.md`;
  - for Go, `go mod init`.

  It also writes `PROMPT.md`: a language preamble followed by `TASK.md`.
- `accept` builds a workspace and runs the acceptance test. With `--json` it saves the record.
- `run` prepares a workspace, runs the agent, then scores the workspace.
  - **Flint runs:** the agent gets only the `flint` MCP server (`flint mcp --log`) and file tools, with no shell.
  - **Go and Spring Boot runs:** the agent gets a shell and its usual tools.
  - **`--agent`:** `claude` (Claude Code), `codex` (Codex CLI), or `command` with `--agent-command '<template using {prompt} {dir} {mcp_log} {flint}>'`.

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
- **References:** `cli-todo` has a Flint reference that passes all 29 checks. Writing it found three library gaps, each now fixed in the library: configuration keys bind relaxed, help covers subcommands, and `@safe` code can write to standard error (ADR-027 section 6).
- **Still to write:** the other references, and the Go and Spring Boot references.

### What running real agents needs

Agent runs use model capacity, so they start only when asked.

- **The agent CLI:** `claude` or `codex` is installed and signed in on the runner. A run has no network sandbox of its own.
- **A budget:** at least 3 runs per task and language, so 36 runs for the full matrix. A run is capped at one hour by `--timeout`.
- **For Spring Boot:** a JDK 21 (present) and network access for the Maven wrapper.
- **The model:** `--model` pins it, so results stay comparable.
