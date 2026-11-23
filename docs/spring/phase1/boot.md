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

Every package is registered in `policy/boot.json` with its layer (`core`, `module` or `starter`), dependencies and `"repo": "boot"`. Each also has its own `dub.sdl`, with path dependencies. The pre-ADR-030 `boot/boot` package still owns the DUB name `boot` and the module `flint.boot`, so the new core is the DUB package `boot-core` until m7-flint-cli's scripted cutover renames the legacy package to `flint:legacy-boot`, when it becomes `flint:boot`. Until then `flint.boot.*` has two registered owners. The structural gate accepts a Boot-layer import when any of its owners is declared. Step 5 then retires `boot/boot`, `boot/autoconfigure-*` and `starters/*`, once the new core covers the applications that use them.

Run a package's tests with `dub test --root boot/core/flint-boot --compiler=dmd` (and `--compiler=ldc2`).

## Slice status

| Piece | Status | Upstream tests ported (passing / ported) |
| --- | --- | --- |
| `ConfigurationPropertyName`: relaxed names, `adapt`, equality, ordering | done | 90 of 91 `ConfigurationPropertyNameTests` (1 excluded, below) |
| `MapConfigurationPropertySource`, `SystemEnvironmentPropertyMapper` | first cut | Flint tests only so far |
| `.properties` loader (`OriginTrackedPropertiesLoader`, `PropertiesPropertySourceLoader`) | done | 45 of 46 `OriginTrackedPropertiesLoaderTests` (1 excluded) |
| YAML loader (`OriginTrackedYamlLoader`, `YamlPropertySourceLoader`) on Flint's D YAML engine | done | 13 / 13 `OriginTrackedYamlLoaderTests`, 5 / 5 `YamlPropertySourceLoaderTests`, plus 3 Flint YAML tests |
| `Binder`, `Bindable`, `BindResult`, `@DefaultValue`, `@ConfigurationProperties`, placeholders, `BindConverter` (booleans, numbers, `Duration`) | done for scalars, strings, enums (Boot's lenient matching), JavaBeans, value objects, arrays, `List`/`Set`, maps (D associative arrays and `Map`) and `Optional`, on contract 2's descriptor builders | 13 `BinderTests`, 13 `JavaBeanBinderTests`, 3 `ValueObjectBinderTests`, 12 `BindResultTests`, 3 `PropertySourcesPlaceholdersResolverTests`, 2 `DataObjectPropertyNameTests`, 3 `DurationStyleTests`; plus 3 Flint tests |
| Config data: `application.{properties,yaml}`, location groups, profile files, `---` with `flint.config.activate.on-profile`, profile groups and includes, `FLINT_PROFILES_ACTIVE`, `spring.*` aliases | done | 23 of 87 `ConfigDataEnvironmentPostProcessorIntegrationTests` (in-memory resources), plus 8 Flint tests |
| `FlintApplication` (run, exit, `flint.main.*`), runners, `ApplicationArguments`, banner (`FlintBootBanner`, `ResourceBanner`, ANSI), startup info, `mixin FlintMain`, `FlintApplicationBuilder` | done on framework-core's `flint.context`: the environment is a `StandardEnvironment`, and the default factory gives a `GenericApplicationContext` that loads Flint AOT's registry during refresh; Boot registers its `ConfigurationPropertiesBinder` | 22 `SpringApplicationTests` (stub context), 6 of 7 `DefaultApplicationArgumentsTests`, 14 of 15 `ResourceBannerTests`, plus 1 Flint test |
| `FailureAnalyzer`, `FailureAnalysis`, `LoggingFailureAnalysisReporter`, Bind / InvalidConfigurationPropertyName / ConfigDataNotFound analyzers; Boot's console log format | done end to end: `flint.boot.logging.slf4j.Slf4jLoggingSystem` installs Boot's format as `flint.slf4j`'s appender and applies `logging.level.*`; Boot's own lines go through SLF4J too | covered by the `SpringApplicationTests` failure tests; 5 Flint console-format and logging tests |
| `@FlintBootApplication`, `@EnableAutoConfiguration`, `@AutoConfiguration` and ordering, the `@ConditionalOn*` family | done (annotation leaves at AOT contract 1's names) | 1 Flint test (meta-annotations merge through `descriptorOf`) |
| `FlintApplicationBuilder` | done (context hierarchies deferred) | 4 of 23 `SpringApplicationBuilderTests` (the rest exercise parent/child contexts, class loaders and initializers) plus 1 Flint test |
| `@FlintBootTest`, `@TestConfiguration`, `FlintBootTestContext` | done over the context stand-in | 6 Flint tests modelled on Boot's `SpringBootTest*Tests` |
| `@WebMvcTest`, `@AutoConfigureMockMvc` (module `flint-boot-webmvc-test`), `@DataJdbcTest` (module `flint-boot-data-jdbc-test`) | annotations done; the slices run when MockMvc and Data JDBC land | |
| Starters: `flint-boot-starter`, `-web`, `-jdbc`, `-validation`, `-json`, `-test` | done as dependency lists over what exists (`boot/starter/README.md` lists what joins each) | |
| Boot's error path: `ErrorAttributeOptions` (core) and `ErrorProperties` (`flint.web.error.*`; Boot 4 deprecated `server.error.*` at error level) | done; `ErrorAttributes`, `DefaultErrorAttributes`, `BasicErrorController` and the Whitelabel view follow in `module/flint-boot-webmvc` on web-mvc's servlet API (agreed with web-mvc) | 5 Flint tests |
| Phase 1 properties classes with Boot's keys and defaults: `ServerProperties` (`server.*`), `WebProperties` (`flint.web.*`), `WebMvcProperties` (`flint.mvc.*`), `JacksonProperties` (`flint.jackson.*`, on flint.jackson's feature enums), `DataSourceProperties` (`flint.datasource.*`), `JdbcProperties` (`flint.jdbc.*`), `SqlInitializationProperties` (`flint.sql.init.*`), `TransactionProperties` (`flint.transaction.*`) | done in `boot/module/flint-boot-{web-server,webmvc,jackson,jdbc,sql,transaction}` and core autoconfigure; `@DurationUnit` honoured; nested read-only groups bind into their getter's object. Groups that need `DataSize`, `MediaType` or later modules are listed in each file's header. `flint.datasource.hikari.*` binds onto the pool the data-access module provides | 13 Flint tests |
| Phase 1 auto-configurations (web/MVC, Jackson, `DataSource` with `hikari`, transactions, validation, SQL init) | `JacksonAutoConfiguration`, `DataSourceAutoConfiguration` (a `FlintDataSource` pool bound with `flint.datasource.hikari.*`; the embedded default is in-memory SQLite `jdbc:sqlite:file:<name>?mode=memory&cache=shared`, user `sa`) `DataSourceTransactionManagerAutoConfiguration` (`JdbcTransactionManager`) and `JdbcTemplateAutoConfiguration` (`flint.jdbc.template.*`, with Boot's `NamedParameterJdbcTemplate`), `JdbcClientAutoConfiguration` done, each listed in its module's `AutoConfiguration.imports`. `DispatcherServletAutoConfiguration`, `WebMvcAutoConfiguration` (over Flint AOT's request mappings, the `JsonMapper` bean and the resolver beans) and `ErrorMvcAutoConfiguration` (`DefaultErrorAttributes`, `BasicErrorController` at `flint.web.error.path`, the Whitelabel page) in boot-webmvc; `FlintServletWebServerAutoConfiguration` (`FlintServletWebServerFactory` customised by `server.*`) and `ServletWebServerApplicationContext` in boot-web-server. Validation (`defaultValidator`) and SQL init (`DataSourceInitializationAutoConfiguration`) are in boot-validation and boot-jdbc | 3 Jackson + 11 `DataSourcePropertiesTests` + 7 auto-configuration tests + 5 `JdbcTemplateAutoConfigurationTests` (2 of the auto-configuration tests need `FlintNativeSqlite`, run locally against the pinned SQLite) |
| `@MockitoBean` | deferred: spring-test's `org.springframework.test` maps to `flint.test`, which the base test library already owns, and Mockito needs a mock engine (generated subclasses); raised with the coordinating session | |

Excluded upstream tests, each with its reason:
- `ConfigurationPropertyNameTests.hashCodeIsStored` (`runtime-reflection`): reads a private field with `ReflectionTestUtils`.
- `OriginTrackedPropertiesLoaderTests.compareToJavaProperties` (`jvm-platform`): compares against `java.util.Properties`.

Total so far: **354 tests pass on DMD 2.114 and LDC 1.43** (329 in flint-boot, 6 in flint-boot-autoconfigure, 6 in flint-boot-test, 13 in the modules): 301 ported upstream tests and 53 Flint tests. The runner in `tests/boot_tests/support.d` runs each `unittest` on its own and prints the count.

## Design decisions

### Configuration values are text, typed by Flint AOT descriptors

Spring keeps `Object` values in property sources and converts them while binding. In Flint, every property source holds strings, and so does YAML: the engine resolves scalars as SnakeYAML's YAML 1.1 resolver does (`True`, `yes` and `on` become `true`; `~` becomes empty; `0x1A` becomes `26`; `1_000` becomes `1000`) and returns the text. Typed values come from binding: the `Binder` converts text to the target property's type, using the target's Flint AOT `Descriptor` (`flint.engine.aot.descriptor`, contract §4.2). This matches what `Environment.getProperty(key)` returns in Boot, and Boot's string-to-type conversion rules decide the result.

### Nullable properties

Boot's `@Nullable Integer`, `Boolean` and `Duration` fields are `flint.java.util.Optional!T`, bound through the descriptors' `unwrap`/`wrap` builders (contract 2). `@Nullable String` fields are `string` with a `null` default. Lists are D arrays and maps are `flint.java.util.Map!(K, V)`.

### Binding on descriptors

`Binder` is an erased engine. `bind(name, Descriptor, ref Any)` walks the type's Flint AOT descriptor:
- value types (scalars, strings, enums, `Duration`) convert from text;
- JavaBeans get each settable property bound under its dashed name (`maxPoolSize` binds `max-pool-size` and every relaxed spelling);
- value objects, whose preferred constructor takes parameters, are built through that constructor, with `@DefaultValue` for absent parameters.

`bind!T`, `bindOrCreate!T` and `Bindable!T` are one-line façades that look up or build `T`'s descriptor. Nested types are found in the binder's `DescriptorTable`, which the AOT registry fills.

Erased construction of enums, arrays and maps needs builders that `Descriptor` does not have yet. Boot asked framework-core and flint-aot for `Any.ofEnum`, `fromElements`/`toElements` and `fromEntries`/`toEntries`. Until they land, binding those types reports an `IllegalStateException` that names the gap.

Converted value types follow Boot's `ApplicationConversionService`:
- booleans accept `true`/`false`, `on`/`off`, `yes`/`no` and `1`/`0`;
- integers follow `NumberUtils.parseNumber` (sign, `0x`, `#`), and an out-of-range value fails;
- a `Duration` takes Boot's simple style (`10s`, `500ms`; a bare number means milliseconds) or ISO-8601.

`java.time.Duration` maps to `core.time.Duration` until `flint.java.time` exists.

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

### FlintApplication

`FlintApplication.run` follows `SpringApplication.run`:
- the arguments;
- the environment (config data, then `flint.main.*` bound onto the application);
- logging (application name and group, `logging.level.*`, ANSI);
- the banner;
- "Starting …" and the profile line;
- context creation through `ApplicationContextFactory`;
- the `flintApplicationArguments` and `flintBootBanner` singletons;
- refresh;
- "Started … in … seconds (process running for …)";
- the runners.

A failure is explained by the failure analyzers and logged as "APPLICATION FAILED TO START". Otherwise it is logged as "Application run failed". Either way the context is closed and the exception rethrown.

Deviations:
- `mixin FlintMain!App` (D-1) generates `main`, which runs the application and then waits on `awaitTermination()`. Java's non-daemon server threads keep a JVM alive after `main` returns, and a D `main` has to wait explicitly.
- "Starting X using Flint 0.7.0 with PID …" replaces "using Java 21".
- The context is framework-core's `flint.context.ConfigurableApplicationContext`. `ApplicationEnvironment` extends `StandardEnvironment`: its property sources are config data's, and `getProperty` uses Boot's relaxed names with the `spring.*` alias. Before refresh, `FlintApplication` registers `flintApplicationArguments`, `flintBootBanner` and the `@ConfigurationProperties` binder (`EnvironmentConfigurationPropertiesBinder`, which framework-core's bean factory calls from each generated `@ConfigurationProperties` bean). It then defers the generated registry, so startup conditions see them.
- `DefaultApplicationContextFactory` gives a `GenericApplicationContext` for `NONE`. For `SERVLET` it uses the factory the web server module registers (Boot finds it in `spring.factories`). `mixin FlintMain` waits on a `KeepAliveApplicationContext`, which the servlet web server context implements.
- The servlet web server follows Boot's model: `ServletWebServerApplicationContext` hands every `ServletContextInitializer` bean to the `ServletWebServerFactory`, and `FlintServletWebServerFactory` lets each configure the engine's `ServletContext` (`addServlet`/`addFilter`, web-http's `932e798`). `DispatcherServletRegistrationBean` is one. `server.shutdown=graceful` (the default) drains the engine when the context closes; the drain runs on the closing thread, where Tomcat's `GracefulShutdown` has its own. `ServletContextInitializer` and `ServletRegistrationBean` live in boot-web-server, not core, which keeps no servlet types.
- Filters register as Boot registers them: `FilterRegistrationBean` (URL patterns or servlet names, `/*` by default; dispatcher types, `REQUEST` by default; match-after; init parameters), and `ServletContextInitializerBeans` adapts plain `Filter` and `Servlet` beans under their bean names unless a registration bean covers them, sorting every initializer by `Ordered`.
- Failure analyzers are listed explicitly: Boot core's own, plus `addFailureAnalyzers` from modules. Flint's closed world has no `spring.factories` scan.
- `@FlintApplication` (the ADR-029 alias of `@FlintBootApplication`) is the class `flint.boot.FlintApplication` used as a bare UDA. Flint AOT reads that type UDA as `@FlintBootApplication`.

### Origins

`flint.boot.origin` ports `Origin`, `OriginProvider`, `OriginTrackedValue` and `TextResourceOrigin` with its `Location`. A resource is described by its Boot-style text (`class path resource [application.yaml]`), because Flint has no class path.

### Class path, resources and `spring-core` types

Boot's loaders take a spring-core `Resource`. Until framework-core's `flint.core.io` lands, they take a resource description and its bytes. "Class path" means the application's `resources/` directory, which `flint build` packages with the binary. `file:` locations are relative to the working directory, as in Boot. `OriginTrackedMapPropertySource` stands alone with `MapPropertySource`'s methods until `flint.core.env.MapPropertySource` exists, and is then rebased onto it.

### Exceptions

Boot's exceptions extend `flint.java.lang`'s `RuntimeException`, `IllegalArgumentException` and `IllegalStateException` (rulebook R8). `BindResult.get` throws `flint.java.util.NoSuchElementException`. Cause chains follow Java's `getCause()`, through `flint.boot.diagnostics.causeOf`, not D's `Throwable.next`.

### Deviations in this slice

- `.properties` files decode as ISO-8859-1 unless the caller passes `"UTF-8"`, as in Boot. Columns count code points, not UTF-16 units (D-14).
- `ConfigurationPropertyName.EMPTY` is `immutable`. A method that returns "the empty name" returns an equal, mutable empty name, so upstream's `isSameAs(EMPTY)` checks become `equals(EMPTY)`.
- XML properties files (`PropertiesPropertySourceLoader`'s `.xml`) are excluded as `jvm-platform`.

## Contracts needed from the other Phase 1 sessions

| From | What Boot needs | Status |
| --- | --- | --- |
| framework-core | `flint.java.lang` exception roots, `flint.core.env`, `flint.context`, the binder hook and the contract-2 descriptor builders (all in use);  `flint.core.env` (`PropertySource`, `EnumerablePropertySource`, `MapPropertySource`, `MutablePropertySources`, `ConfigurableEnvironment`/`StandardEnvironment`, `Profiles`, `SimpleCommandLinePropertySource`); `flint.core.io.Resource`; `flint.context.ConfigurableApplicationContext`; `flint.engine.aot` per the AOT contract | asked; `flint:java` and `flint:engine-aot` in progress |
| flint-aot | `@ConfigurationProperties` descriptors and `BeanFactory.bind`/`bindConstructor` hooks (contract §4.3); auto-configuration ordering and the `@ConditionalOn*` emission (contract §5.4, §5.5); `FlintBootApplication` detected as `flint.boot.autoconfigure.FlintBootApplication` | contract 1 published; Boot declares the annotations under exactly those names |
| web-mvc | `DispatcherServlet` and `WebMvcConfigurer` beans for `WebMvcAutoConfiguration`; `MockMvc` (spring-test) for `@AutoConfigureMockMvc` | to coordinate |
| third-party-apis | `flint.slf4j` `Logger`/`LoggerFactory` and a binding point for Boot's console appender; `flint.jackson.databind.ObjectMapper` (`JsonMapper` in Jackson 3) for `JacksonAutoConfiguration`; `flint.jakarta.validation.Validator` | to coordinate |
| data-access | `flint.jdbc.datasource` (`DataSource`), `JdbcTemplate`, `NamedParameterJdbcTemplate`, `JdbcClient`, `DataSourceTransactionManager` for the JDBC, transaction and SQL-init auto-configurations | to coordinate |

## The actuator

The actuator is three Boot packages and a starter: boot-actuate (`flint.boot.actuate`: endpoint ids, API versions, links, `management.endpoints.web.*` and the exposure filter), boot-health (`flint.boot.health`: statuses, indicators, the registry, aggregation, groups, the probes, `HealthEndpoint` and its web extension) and boot-webmvc's `flint.boot.webmvc.actuate` (the endpoints as Spring MVC handlers). `flint.boot.availability` (core) tracks liveness and readiness, which `FlintApplication` publishes as Boot does.

- **No discovery.** Boot discovers `@Endpoint` beans and their `@ReadOperation` methods by reflection, which the rulebook leaves to Flint AOT. Until the generator emits endpoint operations, an endpoint's web side is an `ExposableWebEndpoint` bean (health's is `HealthWebEndpoint`). `WebMvcEndpointHandlerMapping` turns each exposed operation, and the links resource, into Flint AOT request-mapping rows.
- **Framing follows Spring:** the links resource is a `@ResponseBody` return (`Content-Length`), the operations `ResponseEntity`s (chunked).
- **JSON.** flint.jackson does not yet unwrap (`@JsonUnwrapped`), write map values as their runtime class, or keep a renamed property whose name an ignored one also has. The health descriptors therefore declare `status`, `description`, `components` and `details` through their own getters (each class's, since descriptors list a class's own members). Reported to third-party-apis.
- **Groups.** The primary group and the probe groups (`management.endpoint.health.probes.enabled`, on by default) are configured; `management.endpoint.health.group.*`, additional paths, `WHEN_AUTHORIZED` (no security context yet) and the slow-indicator log follow.

The legacy `boot/actuator` (DUB `boot-actuator`) keeps its name until the cutover renames it `legacy-boot-actuator`; the new package is `boot-actuate` until then (asked of m7-flint-cli for the cutover's rename map).

## Security

boot-security (`flint.boot.security`, spring-boot-security) and `flint-boot-starter-security` sit on framework-core's Spring Security (`flint:security-*`):

- `SecurityAutoConfiguration` binds `flint.security.*` (`SecurityProperties`: the default user, its generated password and roles).
- `UserDetailsServiceAutoConfiguration` gives an `InMemoryUserDetailsManager` with that user. It applies unless the application defines an `AuthenticationManager`, `AuthenticationProvider` or `UserDetailsService`, and it logs a generated password as Boot does.
- `ServletWebSecurityAutoConfiguration` imports Boot's default `SecurityFilterChain` (every request authenticated, HTTP Basic), unless the application defines a chain. It also imports `@EnableWebSecurity`, unless a `springSecurityFilterChain` bean exists. Boot's nested configurations are module-level classes that it `@Import`s, since Flint AOT reads top-level classes.
- `SecurityFilterAutoConfiguration` registers `springSecurityFilterChain` through `DelegatingFilterProxyRegistrationBean` (boot-web-server), at `flint.security.filter.order` (-100) and for every dispatcher type by default. The proxy looks the bean up on the first request. `ServletContextInitializerBeans` does not adapt the target bean a second time.

Deviations:
- The default chain has no form login yet: Flint's Spring Security has no `formLogin`.
- `DefaultAuthenticationEventPublisher`, `SecurityDataConfiguration` and `PathPatternRequestMatcher.Builder` follow with their types.
- The OAuth2, SAML and `AuthenticationManagerResolver` back-offs always match, because Flint has none of those types.
- The filter's proxy is a private class until flint.web has spring-web's `DelegatingFilterProxy`.

## Configuration properties: one spec, three outputs

`boot/tools/configuration_properties.py` holds the specification of every Phase 1 `@ConfigurationProperties` class: Boot's field names, types, defaults and Javadoc. It renders three things from it:
- the D classes;
- Boot's configuration metadata per module (`META-INF/flint/flint-configuration-metadata.json`, the format of Boot's `spring-configuration-metadata.json`);
- `boot/configuration-metadata/application.schema.json`, a JSON Schema for `application.yaml`.

```bash
python3 boot/tools/configuration_properties.py --write   # regenerate
python3 boot/tools/configuration_properties.py --check   # CI: fail when an output is stale
```

The schema covers the module properties and the keys Boot core reads, such as `flint.main.*`, `flint.profiles.*`, `flint.config.*` and `logging.level.*`. It accepts every `flint.*` key under `spring.*` too. Enum values are offered in kebab case and as constants, because Boot binds them leniently. Editors that use yaml-language-server pick it up from a first line of `# yaml-language-server: $schema=<path or URL>/application.schema.json`, or from a `yaml.schemas` setting that maps `application*.yaml` to it.

## gs-rest-service: the port

`benchmarks/spring/flint/gs-rest-service/` is the guide's `complete/` project as a Flint Boot application: `@FlintBootApplication`, `mixin FlintMain` (D-1), the guide's `Greeting` and `GreetingController`, and `flint:boot-starter-web`. `flint build` runs Flint AOT and links Boot's auto-configurations from the starters' `AutoConfiguration.imports`; `flint-spring.json` gives the harness its build.

- The Java package `com.example.restservice` is the module `com.example.restservice` (`src/com/example/restservice/package.d`), through `flint.toml`'s `base-package` (`7b3963e`).
- `flint.toml` lists the packages the source imports besides the starter (`flint:boot-core`, `flint:boot-autoconfigure`, `flint:java`, `flint:web`), because Flint requires a direct dependency for every import (FLINT-E0507).
- `@RequestParam(value: "name", defaultValue: "World")` uses D's named arguments, which the pinned D-Scanner and dfmt parse since m7's `8642a068`. Boot's own sources still spell some UDAs as CTFE constants from before; they can move to named arguments.
- The engine needs the pinned llhttp: locally, a native block in `packages/engine-web/dub.sdl` (never committed), as engine-servlet's socket tests do.

`python3 tools/spring_bench.py accept gs-rest-service --start <binary> --url http://127.0.0.1:<port>` passes 17/18 cases in exact wire mode (2026-11-23, the DMD dev build and the LDC release build). The remaining case is the Whitelabel page's `Content-Language: en-US`, which web-http adds through `ServletResponse.setLocale` and `DispatcherServlet.render`.

## gs-relational-data-access and petclinic-rest: Boot's part

gs-relational-data-access (`benchmarks/spring/flint/gs-relational-data-access/`) is the guide's `CommandLineRunner` on `flint:boot-starter-jdbc`: `DataSourceAutoConfiguration` gives the embedded SQLite data source, `JdbcTemplateAutoConfiguration` the template the runner's constructor takes. The one change from the guide is SQLite's `id INTEGER PRIMARY KEY` for H2's `id SERIAL`, as in the Go comparator. It passes its suite, 1/1 in exact mode (2026-11-23, DMD dev and LDC release builds). It needed `FlintBootConfiguration` to carry `@Configuration`, as Boot's `@SpringBootConfiguration` does, so the application class is a bean whose runner runs.

spring-petclinic-rest (item 10, data-access) needs, from Boot, beyond what gs-rest-service and gs-relational-data-access use:

| Need | Where it comes from | State |
| --- | --- | --- |
| `server.servlet.context-path=/petclinic/` | `ServerProperties.Servlet.setContextPath` cleans a trailing slash, as Boot's does | done |
| `spring.sql.init.*` with `platform`, `mode=always` and `classpath*:db/${platform}/schema.sql` | `DataSourceInitializationAutoConfiguration` over `ApplicationDataSourceScriptDatabaseInitializer` and `AbstractScriptDatabaseInitializer`, on data-access's `ResourceDatabasePopulator` (`cb49983`) | done; `classpath*:` reads as `classpath:` (Flint's class path is a fixed list of roots), and `username`/`password` wait on `DataSourceBuilder` |
| `@DependsOnDatabaseInitialization` (7 uses) | `flint.boot.sql.init.dependency` | annotation done; the dependency configurer joins with SQL init |
| `spring.messages.basename=messages/messages` | `MessageSourceAutoConfiguration` (`flint.messages.*`) over framework-core's `ResourceBundleMessageSource` | done; Boot's `ResourceBundleCondition` is not evaluated (startup conditions read properties and beans, not resources), which only matters without a bundle |
| `@ConditionalOnProperty("petclinic.security.enable")` | Flint AOT's startup conditions | done |
| Bean Validation of request bodies | `ValidationAutoConfiguration` (boot-validation) | `defaultValidator` done, over the context's Flint AOT descriptors (Hibernate Validator's reflection); `methodValidationPostProcessor` registered over web-http's `MethodValidationPostProcessor` (`9b80a9e`) |
| `extends SpringBootServletInitializer` | WAR deployment | not ported (no servlet container deployment in Flint); the port drops the superclass, a noted deviation |
| The actuator's links, health and health groups | boot-actuate (spring-boot-actuator and its auto-configuration), boot-health (spring-boot-health), boot-webmvc's endpoint mapping, `flint-boot-starter-actuator` | done: `/actuator` links, `/actuator/health` with the `liveness` and `readiness` probe groups, Boot's media types, framing and default exposure (health); see "The actuator" below |
| Spring Security headers, `@PreAuthorize` | boot-security over framework-core's Spring Security (`da3da94`) and Flint AOT's `@Import` (`15a340b`) | done; see "Security" below |

## Budgets

The package has no ADR-019 budget row yet. The size gate's linked-bytes budget for `flint:boot` is set when the package registers in `policy/framework.json`, with the first `measure_builds` run of gs-rest-service.
