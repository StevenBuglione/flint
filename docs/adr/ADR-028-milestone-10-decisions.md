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

## Consequences

- A starter can register its beans by default, an application can override any of them by registering the same key, and a starter's optional parts switch on with a configuration section. `packages/di/tests/context_behavior.d` covers auto-configured wiring, replacement by an explicit binding, `@ConditionalOnMissingBean`, the compile-time error for a disabled dependency, and the TOML section reader. The 17 negative fixtures are rejected as before.
