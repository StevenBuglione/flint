# ADR-028: Milestone 10 decisions — starters and the full-stack path

Status: proposed by the Milestone 10 implementation, for the project owner's review. It implements the Milestone 10 row of [ADR-021](ADR-021-flint-platform.md) (section 3, and the full-stack items of the plan), and records the public API additions that ADR-017's process requires, because `handoff/` is frozen.

## Decisions

### 1. Conditional registration and auto-configuration in `flint:di`

1. **The API.** `flint.di` exports four additions.
   - **`@ConditionalOnConfig("section")`:** registers a bean only when the application's configuration has that section. A section is a table (`[database]`), a nested table (`[database.pool]`), an array of tables (`[[queues]]`), or a dotted or inline top-level key (`database.url = …`, `auth = { … }`).
   - **`@ConditionalOnMissingBean`:** registers a bean only when no other registration has the same key.
   - **`AutoConfiguration!(Entries...)`:** a starter's default registrations. Every entry yields to an explicit registration of the same key, as if it carried `@ConditionalOnMissingBean`, and honours its own `@ConditionalOnConfig`. Each starter exports one such list.
   - **`ConfiguredSections!("database", ...)`:** declares the present sections explicitly. Tests use it, and so do builds without flint.

2. **Resolved at compile time, with no start-up cost.**
   - **When:** conditions are applied while the bean list is flattened, before the dependency graph is built. A disabled bean is absent from the context type, and an enabled one is wired exactly like an explicit registration.
   - **Errors:** a bean that needs a disabled one fails with the existing message, "missing DI dependency X required by Y".
   - **Discovery:** there is no discovery beyond the lists the application names, so no module or package scanning.

3. **Configuration presence comes from `config/application.toml`.**
   - **The string import:** flint adds `config/` as a string-import path of the root recipe when the project has `config/application.toml`. `flint lsp` does the same in its checks.
   - **Reading it:** DI reads the file at compile time and lists its sections.
   - **What it means:** presence is decided by the checked-in base file, so the wiring is visible in review and identical in every environment. Values still bind at run time from every layer (profile files, `.env`, the environment and `--set`).
   - **The limit:** a section that exists only in a profile file or the environment does not enable a bean. Declare it, perhaps empty, in `application.toml`.

4. **Cost.**
   - **A context without conditions:** it is flattened exactly as before, behind a single CTFE check that instantiates nothing per bean. The DI bench grows from 1,515 to 1,525 template instances, within its 2,000 budget.
   - **A conditional context:** it costs a few instances per entry.

### 2. Starters: packages under `starters/`, and `flint add`

1. **A separate tier.** Starters live in `starters/<domain>/` and are DUB subpackages of the Flint home, named `flint:starter-<domain>`. Their modules are `flint.starter_<domain>`, following the rule for hyphenated names. They are listed in `policy/starters.json`.
   - **Why not in `policy/packages.json`:** the release gate and the build measurements are defined over exactly the 37 library packages. A starter adds no library surface, only wiring over that surface, so starters stay outside the 37.
   - **Resolution:** a starter resolves like a core package, with its own content hash outside the workspace. Its dependencies are core packages, and its modules count for the import rules, so a direct import still needs a direct dependency.
   - **Reflection:** a starter's own reflection, which selects configuration types and controllers from a resolved bean list, counts as framework internals, like the DI and web packages it composes.

2. **What a starter ships.** Each starter provides:
   - an `AutoConfiguration` list;
   - its `@ConfigurationProperties` schema;
   - `config.toml` (its documented section);
   - `README.md` (its documentation);
   - `example/`, a complete Flint project built in place, so its lock stays a workspace lock.

   A starter re-exports what an application writes, so an application imports the starter alone.

3. **`flint add <starter>...`.** Each name is a domain (`web`) or a full name (`starter-web`). For each starter, `flint add`:
   - declares `"flint:starter-<domain>" = {}`;
   - appends the starter's section from its `config.toml` to `config/application.toml` when the section is missing;
   - relocks.

   `--plan` prints the changes without writing them. An unknown name is FLINT-E0009, which lists the starters.

4. **`flint:starter-web`.** `runApplication!(Beans...)(args)` does the whole start-up of a web application:
   - it binds every `Provided!T` whose `T` is a `@ConfigurationProperties` struct, from one configuration snapshot with `--set` and `--profile`, so a key that no type claims is an error naming it;
   - it starts the context of `WebAutoConfiguration` and the beans;
   - it serves every `@RestController` bean on `[server]`;
   - it shuts the context down when the server stops.

   Exit codes: 3 when configuration does not bind, and 4 when start-up fails.

### 3. Attribute inference: the framework chooses where a handler runs

1. **Ordinary handlers need no `nothrow`, `@nogc` or `scope`.** A route handler is a plain method. flint:web reads its attributes at compile time, whether declared or inferred:
   - **On the reactor:** a controller whose handlers are all `nothrow @nogc` runs there, as before.
   - **On a worker thread:** any other controller is served through flint:web's existing worker (`@WorkerController`, which stays available for forcing it). It may allocate, throw (a 500) and call ordinary services.
   - **The `scope` parameter:** a handler needs a `ref scope RequestContext` parameter only when it uses the request arena.
   - **Why:** this follows ADR-021's goal that annotations are for performance work, not a price of entry.

2. **`string` path and query arguments.** flint:web accepts `string` path and query arguments as well as `Text`. They are decoded like `Text` and copied to the GC heap, so only worker-thread handlers take them.

3. **Cost.** The selection is one compile-time scan of each controller's routes. The web bench's template instances are unchanged at 261.

## Consequences

- `flint add web` and twenty lines of application code give a configured REST service with DI, ordinary handlers and string path variables. `tests/test_flint_starters.py` covers `flint add` (dependency, section, lock, a repeated add and an unknown starter), and the example serving a request and refusing a misspelt key with exit code 3.
- **Known limit:** SIGTERM stops a starter application without running `@PreDestroy` hooks, because flint:os dispatches only SIGINT. A worker-thread controller has one thread with 16 queued requests.
- A starter can register its beans by default, an application can override any of them by registering the same key, and a starter's optional parts switch on with a configuration section. `packages/di/tests/context_behavior.d` covers auto-configured wiring, replacement by an explicit binding, `@ConditionalOnMissingBean`, the compile-time error for a disabled dependency, and the TOML section reader. The 17 negative fixtures are rejected as before.
