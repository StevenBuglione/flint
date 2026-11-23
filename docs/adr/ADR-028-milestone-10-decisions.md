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

4. **The attributes-per-handler metric.**
   - **What it counts:** for each REST handler in `src/`, the `nothrow`, `@nogc`, `scope`, `pure`, `return` and `@trusted` attributes on it and its parameters. `flint check --json` reports `handlers` and `handler_attributes`.
   - **The test:** `tests/test_flint_starters.py` asserts that the starter example has one handler and zero attributes.

5. **FLINT-E0531: attributes the framework makes unneeded.** In an application that uses a starter, `flint check` and every build flag two cases:
   - **`nothrow` or `@nogc` on a worker-thread controller:** these change nothing when another handler of the same controller is not both, because the controller runs on a worker thread anyway.
   - **`scope` on an owned argument:** `scope` on a handler parameter other than `RequestContext`, `Request` or `RequestArena` changes nothing, because the framework passes that argument as an owned value.

   A deliberately all-`nothrow @nogc` controller is not flagged, since those attributes put it on the reactor. The rule reads tokens, and the existing per-file waiver applies.

### 4. Safety conventions: FLINT-E0530, nullable class fields

1. **The rule.** A field whose type is a class or interface that the project declares is flagged in application code (`src/`), by `flint check` and every build, in two cases:
   - **no constructor:** the field is null until something assigns it, so an aggregate with no constructor fails;
   - **an unassigning constructor:** some constructor of the aggregate leaves it unassigned (an assignment is `name = …` or `this.name = …`).

   A field initialised to `null` counts as unassigned.
2. **Why.** Constructor injection, which the starters use, assigns these fields, so canonical starter code passes. A null class field is the one null a `@safe` Flint program can still dereference.
3. **The limit.** The rule reads tokens, not types. It recognises classes the project declares, not class types from libraries. Starters prefer structs and `Result`, so an application rarely holds a library class.


### 5. The full-stack path: OpenAPI, TypeScript clients and SPA serving

1. **OpenAPI from controllers, at compile time.** `flint.web.openApiDocument!App(title, version)` builds an OpenAPI 3.1 document from the same route table and argument plan that serve requests, so it cannot drift from the application. It documents:
   - paths, with `:id` written as `{id}`;
   - methods, with `Controller.handler` as the operationId;
   - path and query parameters, and JSON request bodies;
   - success responses: 200, 201 for a POST that returns an entity, and 204 for `void`;
   - a default error schema.

   Schemas follow flint:serde: `@JsonName` renames a field, `@JsonIgnore` drops it, enums are string unions, and arrays and nested structs are inline objects whose `title` is the D type name.

2. **`--openapi` and `flint openapi`.**
   - **`--openapi`:** a starter-web application started with `--openapi` prints the document and exits.
   - **`flint openapi [-o FILE] [--typescript FILE]`:** builds the project, captures that document, and names it after `flint.toml`'s name and version.
   - **The TypeScript client:** `--typescript` also writes a dependency-free client: one interface per titled schema (fields in declaration order) and one typed method per operation over `fetch`, such as `noteGet(id: number): Promise<Note>`. A non-2xx response throws `ApiError` with the status and the server's message.
   - **Verified:** the example's client type-checks with `tsc --strict` (TypeScript 5.6.3).

3. **SPA serving.** With a `[spa]` section (`directory`, `index`), flint:starter-web registers `SpaController`, which serves the built front end:
   - **files:** a file by its path, with its media type;
   - **client-side routes:** `index` for any other GET;
   - **the API:** 404 for unmatched paths under `/api/`, so the controllers keep the API;
   - **containment:** `..` and `.` never leave the directory.

   Both beans are `@ConditionalOnConfig("spa")`, so an application without a front end has neither.

4. **Worker-thread replies of any size and media type.** Before this, a worker-thread handler's response was limited to 4,096 bytes and seven media types, and it ran in a 12 KB arena. Section 3 makes ordinary handlers run on the worker, so these limits would have broken ordinary applications. Now:
   - **The arena:** each worker owns a reusable 8 MiB request arena.
   - **Larger bodies:** a body larger than the packet is copied to the GC heap by the worker thread. The reactor copies it into the request arena and drops it.
   - **Any media type:** an unlisted media type travels as its string.
   - **Unchanged:** the reactor-inline path does not change.

### 6. `flint:starter-observability`, and `ServerCustomizer`

1. **`ServerCustomizer` in flint:web.** `interface ServerCustomizer { Error customize(ref Server server); }` is an extension point. `runApplication` gains an optional `configure` delegate, which runs after the server starts and before it polls.
   - **starter-web:** it collects every class registration that implements `ServerCustomizer` (keys of `Bind` and `Provided` included) and applies them in order.
   - **Failure:** a customizer's failure stops start-up.

2. **What the starter provides.**
   - **The bean:** `Observability` (`@Service`, `ServerCustomizer`) opens a `flint.actuator.Registry` from `[management]`: `path_prefix`, `service_name`, `otlp_endpoint` and `max_metric_series`.
   - **The endpoints:** it attaches `<prefix>/health/live`, `/health/ready` and `/metrics` (Prometheus text) to the application's server.
   - **Shutdown:** it closes at shutdown, which reports not-ready and finishes the export.
   - **The registry:** `registry()` hands it to the application for counters, histograms and health probes. The starter re-exports `Counter`, `Histogram`, `Health` and `HealthProbe`.
   - **Loopback only:** the actuator refuses a non-loopback listener without a `ManagementPolicy`. That policy stays the actuator's.

## Consequences

- `flint add web observability` gives health, readiness and metrics endpoints with no wiring. The example counts accepted jobs from a worker-thread handler, and `tests/test_flint_starters.py` reads the count back from `/actuator/metrics`.
- A starter application has a typed front-end contract: `flint openapi --typescript client.ts` turns its controllers into a document and a client, and a `[spa]` section serves the front end beside the API. `tests/test_flint_starters.py` checks the document, the client, the front-end routes and a 100 KB asset served by a worker-thread handler.
- `flint add web` and twenty lines of application code give a configured REST service with DI, ordinary handlers and string path variables. `tests/test_flint_starters.py` covers `flint add` (dependency, section, lock, a repeated add and an unknown starter), and the example serving a request and refusing a misspelt key with exit code 3.
- **Known limit:** SIGTERM and SIGINT stop a starter application without running `@PreDestroy` hooks, because flint:web's run loop does not yet watch for signals (flint:os dispatches only SIGINT, to callbacks). A worker-thread controller has one thread with 16 queued requests.
- A starter can register its beans by default, an application can override any of them by registering the same key, and a starter's optional parts switch on with a configuration section. `packages/di/tests/context_behavior.d` covers auto-configured wiring, replacement by an explicit binding, `@ConditionalOnMissingBean`, the compile-time error for a disabled dependency, and the TOML section reader. The 17 negative fixtures are rejected as before.
