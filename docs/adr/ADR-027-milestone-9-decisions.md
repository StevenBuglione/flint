# ADR-027: Milestone 9 decisions — knowledge, diagnostics and tooling

Status: proposed by the Milestone 9 implementation, for the project owner's review. Numbered 027 because the Windows port took 026 at the same time. It implements the Milestone 9 row of [ADR-021](ADR-021-flint-platform.md) (sections 1, 6, 7 and 11) and builds on [ADR-022](ADR-022-milestone-7-decisions.md) and [ADR-023](ADR-023-milestone-8-decisions.md).

## Decisions

### 1. The API index, `flint docs`, `flint examples`, generators and `AGENTS.md`

1. **The index comes from the pinned compiler.** For each core package, the pinned DMD runs `-o- -X -D` over every module of the package, with the package's dependency closure on the import path.
   - **What it gives:** signatures exactly as the compiler sees them, DDoc comments and source locations, from the same semantic analysis that compiles the package. No second parser can drift from the language.
   - **Public names:** private modules (`sys/`, `ffi/`, `internal/`) are described too, because their declarations are often what a public module re-exports with `public import`. Such symbols are listed under the public module's name, with the real file and line.
   - **Signature layout:** the name is placed before the parameter list. Eponymous templates show their template parameters: `Result!T load(T)(ref scope const ConfigOptions options)`.

2. **Examples are the packages' own tests.** A symbol's examples are the unittest blocks in its package's `tests/` that use its name, in files that import its module, shortest first, up to three.
   - **Always tested:** every example shown is compiled and run by `flint test` and CI, so an example that stops compiling fails the build, as ADR-021 requires.
   - **Coverage today:** the index reports per-package coverage. At the first build it was 3,002 public symbols, 714 of them with at least one example. Coverage is reported, not claimed: raising it is test-writing work in each package.

3. **Cache.** The index is cached under `<flint>/.flint/index/`, keyed by the hash of every package's recipe, sources and tests.
   - **Cost:** building it takes about 1.5 s for all 37 packages, and a cached query about 0.1 s.
   - **Format:** the cache is JSON Lines, a header and then one symbol per line, so each document stays within `flint.serde`'s per-document limits (1,024 array elements, 1 MiB) however large the API grows. Those limits are part of the library's request-safety contract and were not raised.

4. **`flint docs [words | qualified.name] [--export DIR]`.**
   - **No query:** lists the packages with their own module-level descriptions and coverage.
   - **A qualified name:** shows the signature, the documentation and the tested examples.
   - **Words:** search ranks exact names, then name prefixes, then qualified-name and documentation matches. Every word must match.
   - **`--export`:** writes `llms.txt` (packages) and `llms-full.txt` (every symbol, with an example) for the docs site.
   - **Misses:** a query with no match is FLINT-E0007.

5. **`flint examples <topic>`** returns the best-matching symbols' tested examples, plus any golden application in `examples/` whose name or README matches the topic.

6. **`flint generate <entity|repository|service|controller|config|migration|agents> <Name> [--plan]`.**
   - **The shapes:** the canonical package-by-feature shapes of ADR-021 section 2, taken from the golden REST service: an `@Table` entity, a `CrudRepository` alias with its `SqlRepository` binding, a constructor-injected `@Service`, a `@RestController` with `@Get`/`@Post`, a `@ConfigurationProperties` struct, and `resources/migrations/V<n>__<name>.sql` with the next free number.
   - **Dependencies:** each generator adds the core packages it needs to `[dependencies]` and relocks.
   - **Formatting and overwrites:** generated D passes through the pinned dfmt, so it is already in the canonical format, and `--plan` shows exactly what would be written. Generators never overwrite a file (FLINT-E0008), except `AGENTS.md`, which `flint generate agents` refreshes.
   - **Verified:** all six components, generated into a new project, pass `flint check`. They also compile and pass the framework's own compile-time checks when wired together: the DI graph, route registration, the entity's SQL mapping and the configuration binding.

7. **`AGENTS.md`.** `flint new` writes it, specific to the project.
   - **Asking flint:** `flint docs`, `examples`, `explain` and `mcp`, `--json`, and the exit codes.
   - **The loop and the layout:** the build loop, and the layout with this project's module root.
   - **The code model:** `@safe:`, errors as values (`Result!T`, `Error`), structs, constructor injection, selective imports, and dependencies only in `flint.toml`.
   - **What not to do:** `@trusted` or `extern(C)` outside `ffi/`, mixins and home-made frameworks, flags outside profiles, editing generated files, and silent waivers.

### 2. `flint mcp` on `flint:mcp`, and blocking tools

1. **A separate executable.** `flint:mcp` depends on `http`, `web` and `reactor`, and through them on the native providers: curl, OpenSSL, nghttp2 and liburing.
   - **Why separate:** linking those into the `flint` executable would make bootstrapping the CLI depend on a native install, on every platform.
   - **How it starts:** the server is its own Flint project, `apps/flint-mcp`, built on `flint:mcp` itself. `flint mcp` builds it through flint (in under a second when it is current), sets `FLINT_EXECUTABLE`, and replaces itself with it, so the MCP client talks to `flint-mcp` on stdio in the client's directory. The build reports on standard error only, because standard output belongs to the protocol.

2. **The tools are the commands.** Each ADR-021 section 6 tool runs the matching `flint` command with `--json` in the project directory and returns its document, as text and as structured content.
   - **The mapping:**
     - `search_api` runs `docs`, `get_symbol` runs `docs <name>` and `get_example` runs `examples`.
     - `explain_error` runs `explain`.
     - `describe_project` and `dependency_graph` run `deps tree`, and `resolved_config` runs the new `flint config`.
     - `generate`, `build`, `test` and `check` run the commands of the same names.
   - **One contract:** the tools and the CLI share the same schemas, so an agent's view and a person's view cannot drift.
   - **Failures:** a failing command is a tool error (`isError`) carrying the full diagnostics. Invalid arguments are rejected by the DTO's schema and validation, as JSON-RPC -32602.
   - **Call log:** `flint mcp --log FILE` appends one JSON line per call (tool, arguments, exit code and milliseconds). The vibe-coding benchmark counts build–fix iterations from it.

3. **The library gap: blocking tools in `flint:mcp`.** `flint:mcp` required every tool to be `@safe nothrow @nogc` and to answer in the request arena, which is right for its hot path. A tool that runs a process cannot meet that.
   - **The addition:** `McpTool.blocking` and `BlockingToolResult`. A blocking tool has the signature `BlockingToolResult name(Dto input) @safe`; it may allocate, block and throw.
   - **How it runs:** the protocol path stays `nothrow @nogc`. It copies the call's arguments into storage owned by a `BlockingRunner`, publishes the call through an atomic state, and waits cooperatively, as the existing worker does.
   - **The managed worker:** one worker (`startManagedBackground`) decodes the arguments with `flint.serde.owned`, validates them with `flint.validate`, runs the tool and publishes its owned result, which the protocol copies into the reply. An exception becomes a tool error. The runner is started with the first blocking tool and stopped by `McpServer.close`.
   - **Scope:** one blocking call is in flight at a time, and blocking calls are not cancellable mid-run.
   - **No `@trusted`:** no `@trusted` code was added. The runner is given a tool index and looks the tool up through a delegate fixed at start, because dip1000 rightly refused to store the registry's `scope` delegate in it.
   - **Tests:** `packages/mcp/tests/blocking.d` covers decoding, validation failures, a thrown exception, the argument limit and the server lifecycle, on DMD and LDC.

4. **`flint config [--profile P]`** prints every key that `config/application.toml` and `application-<profile>.toml` set, with its value and `file:line`. It is the build-time view of ADR-021 section 2. Environment and `--set` layers are applied by the application at startup and are not shown yet.

### 3. The fast feedback loop: `flint watch`, debugging and pretty-printers

1. **`flint watch [--test | --build] [-- program arguments]`.** By default an executable is rebuilt and restarted on every change, and a library is retested.
   - **Detecting changes:** the watcher compares a snapshot (path, size and modification time) of `src/`, `test/`, `config/`, `native/`, `resources/` and `flint.toml` four times a second. The snapshot works on every platform and costs microseconds for a project, so neither inotify nor kqueue nor ReadDirectoryChangesW is needed yet. A burst of saves settles into one cycle.
   - **Incremental by construction:** each cycle runs `flint build` or `flint test`, which are already incremental (DUB's up-to-date checks, the content-hashed C cache and the resident compile server).
   - **A failing cycle:** prints the diagnostics and keeps the previous program stopped until the code builds again.
   - **Stopping:** the running program is stopped with SIGTERM, and SIGKILL after two seconds. Ctrl+C stops both.
   - **`--json`:** prints one `flint.watch/1` line per cycle (cycle, changed paths, action, ok, exit code, restarted), and the program's output then goes to standard error so the events stay parseable.

2. **Debugging.** `flint run --debug` builds the dev profile, which carries `-g`, and starts gdb, or lldb when gdb is missing (FLINT-E0822 when neither exists), with Flint's printers loaded. `flint generate debug` writes `.vscode/launch.json` (gdb and lldb configurations that build with `flint build` first and load the printers) and `.vscode/tasks.json` (build, test and watch).

3. **Pretty-printers:** `tools/debug/flint_gdb.py` and its lldb twin `flint_lldb.py`.
   - **What they print:**
     - a `Result` is `ok: <value>` or `error: <Status> 'message'`;
     - an `Error` gets its status name and byte offset;
     - `Buffer` and `Text` handles get their size and arena identity;
     - a `RequestArena` gets its use and peak;
     - a `Context` gets its deadline;
     - D strings are shown as text.
   - **A DMD quirk:** DMD emits the `Status` enum as an incomplete type in DWARF, so the printer reads the status as the `int` at the field's offset.
   - **Verified:** the gdb printers are tested against a real DMD `-g` build under gdb 15.1. The lldb summaries are written to the same layout but untested here, because the Linux host has no lldb; they are for the macOS port.

4. **One new `@trusted` function.** A program restarted by `flint watch` inherits flint's standard streams. `std.stdio`'s global `File`s are `@system` (they are `__gshared`), so `flint_tool.sys.posix.standardStream` returns them behind a SAFETY rationale: druntime initialises them before `main`, they are only read, and the copy is reference-counted over the same descriptor. Killing the program uses the existing `signalProcessGroup`, which also has a Windows implementation.

### 4. `flint lsp`

1. **Inside the CLI.** `flint lsp` speaks the Language Server Protocol on stdio (`Content-Length` framing, full text synchronisation) from within the `flint` executable. It needs no web stack.

2. **Diagnostics.** The open buffer is checked twice.
   - **The compiler:** the pinned DMD's semantic check, `-o- -c` with the dev profile's flags and the project's resolved import paths (core packages, path, repository and DUB dependencies).
   - **Flint's rules:** the policy rules for module `@safe:` defaults and `@trusted` confinement, with their `FLINT-Ennnn` codes.
   - **Unsaved buffers:** these are written to a private overlay directory that comes first on the import path, so the file on disk is never touched and imports between open buffers see each other's edits.
   - **Speed:** a check of a typical module takes 0.05–0.2 s.

3. **Hover, go-to-definition and completion** answer from the API index of the pinned libraries.
   - **Hover:** shows the signature, the documentation and the qualified name.
   - **Go-to-definition:** opens the declaration in the pinned package source.
   - **Completion:** offers the public names starting with the typed prefix, with their signatures.
   - **Project symbols:** the project's own symbols are not indexed yet.

4. **The compile server: measured, not assumed.** ADR-021 asks for a language server "on the resident compile server", so the fork's server was measured with the LSP's own work, on flint's `commands/project.d` (best of five, warm).
   - **The numbers:** a served `-c` compile took 0.195 s and an unserved one 0.205 s. A `-o-` semantic check took 0.162 s, and the fork never serves `-o-`.
   - **Why so little:** the server preloads only druntime and Phobos, while modules like these spend their time in the Flint packages they import.
   - **Decision:** the language server therefore uses the faster plain check and does not start a server.
   - **What would change it:** letting the server serve `-o-` checks, and preloading the pinned Flint packages as well as Phobos, would make it pay for editors. That is a change to ADR-016's "druntime and Phobos only" rule, so it is proposed for the owner rather than taken here.

## Consequences

- Editors get Flint-aware diagnostics as they type, and API hover, definition and completion, from `flint lsp`. `tests/test_flint_lsp.py` drives it as an LSP client: diagnostics following unsaved edits (a compiler error, then a policy error, then clean), and hover, definition and completion against the pinned API.
- Edit, save, see: `flint watch` rebuilds and restarts, or retests, in one incremental cycle per change, and `flint run --debug` and the generated launch configurations show Flint values readably. `tests/test_flint_watch.py` covers the watch cycles, recovery from a broken edit, the library mode, the launch configurations, the gdb printers and `flint run --debug` under gdb.
- An MCP client gets the exact pinned API, the diagnostics catalogue and the build loop from `flint mcp`. `tests/test_flint_mcp.py` drives it as a real stdio client: the handshake, the tool list and schemas, knowledge, the configuration, a failing build as a tool error, generation, invalid arguments and the call log.
- An agent or a person can ask the exact API of the pinned Flint version offline, see a tested example and generate canonical components. `tests/test_flint_knowledge.py` covers the index, search, export, examples, every generator and `AGENTS.md`.
