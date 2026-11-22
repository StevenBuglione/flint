# ADR-026: Milestone 9 decisions — knowledge, diagnostics and tooling

Status: proposed by the Milestone 9 implementation, for the project owner's review. It implements the Milestone 9 row of [ADR-021](ADR-021-flint-platform.md) (sections 1, 6, 7 and 11) and builds on [ADR-022](ADR-022-milestone-7-decisions.md) and [ADR-023](ADR-023-milestone-8-decisions.md).

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

## Consequences

- An agent or a person can ask the exact API of the pinned Flint version offline, see a tested example and generate canonical components. `tests/test_flint_knowledge.py` covers the index, search, export, examples, every generator and `AGENTS.md`.
