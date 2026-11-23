# Phase 1: Flint Boot (spring-boot v4.2.0)

This document is the boot session's design note for ADR-030 Phase 1. It lives in `flint` until `flint-boot` is cut over; after that it moves to that repository's `docs/`.

## Layout

The layout follows spring-boot's own. Until cutover, the code lives under `boot/` in the monorepo. `boot/` moves to `flint-boot` whole, with its history (`tools/extract_repo.py`), and its subdirectories then become the repository root.

| spring-boot v4.2.0 | Flint path (pre-cutover) | DUB | D modules |
| --- | --- | --- | --- |
| `core/spring-boot` | `boot/core/flint-boot` | `flint:boot` | `flint.boot`, `flint.boot.context.properties.*`, `flint.boot.env`, `flint.boot.origin`, `flint.boot.diagnostics`, `flint.boot.logging`, `flint.boot.builder` |
| `core/spring-boot-autoconfigure` | `boot/core/flint-boot-autoconfigure` | `flint:boot-autoconfigure` | `flint.boot.autoconfigure`, `flint.boot.autoconfigure.condition`, … |
| `core/spring-boot-test` (+ `-test-autoconfigure`) | `boot/core/flint-boot-test` | `flint:boot-test` | `flint.boot.test.context`, `flint.boot.test.autoconfigure.web.servlet`, … |
| `module/spring-boot-webmvc`, `-jdbc`, `-jackson`, `-validation`, `-sql`, `-transaction` | `boot/module/flint-boot-*` | `flint:boot-webmvc`, … | `flint.boot.webmvc.autoconfigure`, `flint.boot.jdbc.autoconfigure`, … |
| `starter/spring-boot-starter*` | `boot/starter/flint-boot-starter*` | `flint:boot-starter`, `flint:boot-starter-web`, … | none: dependency lists only |

Until cutover, the new packages have their own `dub.sdl` and are not registered in the root `dub.sdl`. The pre-ADR-030 `boot/boot` package still owns the DUB name `flint:boot`, and two packages cannot share it. Step 5, after cutover, moves `boot/boot`, `boot/autoconfigure-*` and `starters/*` into this layout and retires the old names.

Run a package's tests with `dub test --root boot/core/flint-boot --compiler=dmd` (and `--compiler=ldc2`).

## Slice status

| Piece | Status | Upstream tests ported (passing / ported) |
| --- | --- | --- |
| `ConfigurationPropertyName`: relaxed names, `adapt`, equality, ordering | done | 90 of 91 `ConfigurationPropertyNameTests` (1 excluded, below) |
| `MapConfigurationPropertySource`, `SystemEnvironmentPropertyMapper` | first cut | Flint tests only so far |
| `.properties` loader (`OriginTrackedPropertiesLoader`, `PropertiesPropertySourceLoader`) | done | 45 of 46 `OriginTrackedPropertiesLoaderTests` (1 excluded) |
| YAML loader (`OriginTrackedYamlLoader`, `YamlPropertySourceLoader`) on Flint's D YAML engine | done | 13 / 13 `OriginTrackedYamlLoaderTests`, 5 / 5 `YamlPropertySourceLoaderTests`, plus 3 Flint YAML tests |
| `Binder`, `Bindable`, `BindResult`, `@ConfigurationProperties` | next | |
| Config data: `application.{properties,yaml}`, location groups, profile files, `---` with `flint.config.activate.on-profile`, profile groups and includes, `FLINT_PROFILES_ACTIVE`, `spring.*` aliases | done | 23 of 87 `ConfigDataEnvironmentPostProcessorIntegrationTests` (in-memory resources), plus 8 Flint tests |
| `FlintApplication`, `FlintApplicationBuilder`, runners, `ApplicationArguments`, banner, `mixin FlintMain` | after the binder | |
| `FailureAnalyzer`, Boot's console log format through `flint.slf4j` | after the binder | |
| autoconfigure, boot-test, starters | after flint-context and webmvc land | |

Excluded upstream tests, each with its reason:
- `ConfigurationPropertyNameTests.hashCodeIsStored` (`runtime-reflection`): reads a private field with `ReflectionTestUtils`.
- `OriginTrackedPropertiesLoaderTests.compareToJavaProperties` (`jvm-platform`): compares against `java.util.Properties`.

Total so far: **187 tests pass on DMD 2.114 and LDC 1.43**: 176 ported upstream tests and 11 Flint tests. The runner in `tests/boot_tests/support.d` runs each `unittest` on its own and prints the count.

## Design decisions

### Configuration values are text, typed by Flint AOT descriptors

Spring keeps `Object` values in property sources and converts them while binding. In Flint, every property source holds strings, and so does YAML: the engine resolves scalars as SnakeYAML's YAML 1.1 resolver does (`True`, `yes` and `on` become `true`; `~` becomes empty; `0x1A` becomes `26`; `1_000` becomes `1000`) and returns the text. Typed values come from binding: the `Binder` converts text to the target property's type, using the target's Flint AOT `Descriptor` (`flint.engine.aot.descriptor`, contract §4.2). This matches what `Environment.getProperty(key)` returns in Boot, and Boot's string-to-type conversion rules decide the result.

### YAML engine

Boot reads YAML with SnakeYAML, which is Java. `flint.boot.internal.yaml` is a D engine written for Boot's configuration subset:
- block mappings and sequences, including compact `- key: value` items and sequences at their key's indentation;
- plain scalars, single- and double-quoted scalars, and multi-line scalars;
- `|` and `>` block scalars with chomping and indentation indicators;
- flow `[...]` and `{...}`, comments, `---` and `...`;
- anchors, aliases and `<<` merges;
- the core `!!` tags.

Unknown tags are rejected, as Boot's restricted constructor rejects them. The engine was written from the YAML 1.1/1.2 specification; no SnakeYAML code was copied. Origins are tracked per scalar, so a binding failure names `application.yaml - line:column`, as Boot's does.

### Config data

`flint.boot.context.config.ConfigDataEnvironment` follows Boot's `processAndApply`: the initial contributors (command line, environment, default properties), the plain documents of every location group, the profiles (additional, then included, then `flint.profiles.active`, expanded through groups), and then the profile files and `on-profile` documents. Boot's contributor tree is flattened into one ordered list per location group, giving the documented order. A group's plain files sit below its profile files, a later location and a later profile win, and a later group wins over an earlier one. `flint.config.import`, `on-cloud-platform` detection, `random.*` and config trees are deferred to Phase 2; a document with `on-cloud-platform` stays inactive. JVM system properties have no native counterpart, so Boot's system-property tests use command-line arguments.

The `spring.*` alias is resolved in one place, `ConfigurationPropertySources.find`. A `flint.*` name is also looked up as `spring.*` in each source, and the `flint` spelling wins inside one source. `FLINT_PROFILES_ACTIVE` and `SPRING_PROFILES_ACTIVE` both work, through the environment mapper.

### Origins

`flint.boot.origin` ports `Origin`, `OriginProvider`, `OriginTrackedValue` and `TextResourceOrigin` with its `Location`. A resource is described by its Boot-style text (`class path resource [application.yaml]`), because Flint has no class path.

### Class path, resources and `spring-core` types

Boot's loaders take a spring-core `Resource`. Until framework-core's `flint.core.io` lands, they take a resource description and its bytes. "Class path" means the application's `resources/` directory, which `flint build` packages with the binary. `file:` locations are relative to the working directory, as in Boot. `OriginTrackedMapPropertySource` stands alone with `MapPropertySource`'s methods until `flint.core.env.MapPropertySource` exists, and is then rebased onto it.

### Exceptions

Boot's exceptions extend `RuntimeException`, `IllegalArgumentException` and `IllegalStateException` (rulebook R8). Until `flint:java` lands, `flint.boot.internal.lang` declares those names privately. The day framework-core publishes `flint.java.lang`, that file is deleted and its importers switch over.

### Deviations in this slice

- `.properties` files decode as ISO-8859-1 unless the caller passes `"UTF-8"`, as in Boot. Columns count code points, not UTF-16 units (D-14).
- `ConfigurationPropertyName.EMPTY` is `immutable`. A method that returns "the empty name" returns an equal, mutable empty name, so upstream's `isSameAs(EMPTY)` checks become `equals(EMPTY)`.
- XML properties files (`PropertiesPropertySourceLoader`'s `.xml`) are excluded as `jvm-platform`.

## Contracts needed from the other Phase 1 sessions

| From | What Boot needs | Status |
| --- | --- | --- |
| framework-core | `flint.java.lang` exception roots; `flint.core.env` (`PropertySource`, `EnumerablePropertySource`, `MapPropertySource`, `MutablePropertySources`, `ConfigurableEnvironment`/`StandardEnvironment`, `Profiles`, `SimpleCommandLinePropertySource`); `flint.core.io.Resource`; `flint.context.ConfigurableApplicationContext`; `flint.engine.aot` per the AOT contract | asked; `flint:java` and `flint:engine-aot` in progress |
| flint-aot | `@ConfigurationProperties` descriptors and `BeanFactory.bind`/`bindConstructor` hooks (contract §4.3); auto-configuration ordering and the `@ConditionalOn*` emission (contract §5.4, §5.5); `FlintBootApplication` detected as `flint.boot.autoconfigure.FlintBootApplication` | contract 1 published; Boot declares the annotations under exactly those names |
| web-mvc | `DispatcherServlet` and `WebMvcConfigurer` beans for `WebMvcAutoConfiguration`; `MockMvc` (spring-test) for `@AutoConfigureMockMvc` | to coordinate |
| third-party-apis | `flint.slf4j` `Logger`/`LoggerFactory` and a binding point for Boot's console appender; `flint.jackson.databind.ObjectMapper` (`JsonMapper` in Jackson 3) for `JacksonAutoConfiguration`; `flint.jakarta.validation.Validator` | to coordinate |
| data-access | `flint.jdbc.datasource` (`DataSource`), `JdbcTemplate`, `NamedParameterJdbcTemplate`, `JdbcClient`, `DataSourceTransactionManager` for the JDBC, transaction and SQL-init auto-configurations | to coordinate |

## Budgets

The package has no ADR-019 budget row yet. The size gate's linked-bytes budget for `flint:boot` is set when the package registers in `policy/framework.json`, with the first `measure_builds` run of gs-rest-service.
