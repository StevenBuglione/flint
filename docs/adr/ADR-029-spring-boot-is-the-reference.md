# ADR-029: Spring Boot is the reference for Flint's application model

Status: accepted by the project owner on 2026-11-22.

Partly superseded by [ADR-030](ADR-030-flint-is-a-spring-port.md) (2026-11-23): Spring's names now apply wherever this ADR chose different ones (the names here stay as aliases), proxies are generated subclasses with Spring's semantics, and user code never sees the request arena.

## Context

The project owner's direction: a Java developer should open a Flint application and immediately feel that it is "just Spring Boot, in D". That covers the entry point (`@FlintApplication`, as `@SpringBootApplication`), the annotations, the conventions, the configuration keys and the test style.

Much of Flint already follows Spring:
- `@Component`, `@Service`, `@Repository` and `@RestController`;
- `@RequestMapping`, `@PathVariable`, `@RequestBody` and `@ControllerAdvice`;
- `@ConfigurationProperties`, `@PostConstruct` and `@PreDestroy`;
- `@Transactional`, `@Cacheable`, `@CacheEvict`, `@Scheduled`, `@Retryable` and `@CircuitBreaker`;
- `@PreAuthorize`, `@RolesAllowed` and `@KafkaListener`;
- `@Valid`, `@NotBlank`, `@Email`, `@Size`, `@Min` and `@Max`;
- `CrudRepository`, `Page` and `PageRequest`.

But an application still starts by listing every bean by hand (`runApplication!(NoteRepository, NoteService, NoteController)(args)`), and several names differ from Spring for no reason that D imposes.

## Decision

### 1. The rule

**Spring Boot is the reference.** For every application-facing concept, Flint uses Spring Boot's name, shape and default unless D makes that impossible or unsafe. Each deviation is listed in the table below with its reason. Review rejects any other difference.

Where Spring offers several ways to do one thing, Flint chooses the one Spring Boot's own guides teach (constructor injection, `application.*` configuration, starters) and makes it the only way (ADR-021).

The frozen `handoff/` contracts keep their existing names as aliases, so nothing breaks. The Spring names are canonical in documentation, generators, examples and `AGENTS.md`, and `flint check` suggests the Spring name wherever an alias is used.

### 2. The application entry point

A Flint application starts exactly as a Spring Boot application does:

```d
module shop.app;

import flint.boot;

@FlintApplication
class ShopApplication
{
    static int main(string[] args)
    {
        return FlintApplication.run!ShopApplication(args);
    }
}

mixin FlintMain!ShopApplication;   // D's process entry point calls ShopApplication.main
```

- **`@FlintApplication`** combines what `@SpringBootApplication` combines: configuration, auto-configuration from the declared starters, and component scanning.
- **`FlintApplication.run!App(args)`** matches `SpringApplication.run(App.class, args)`. It:
  - prints the startup banner and the active profiles;
  - binds configuration;
  - creates every bean, runs `CommandLineRunner`/`ApplicationRunner` beans, and starts the web server if the web starter is present;
  - returns the process exit code.
- **Component scanning** is compile-time, with no reflection:
  - `flint build` writes `.flint/generated/flint_scan.d`, listing every module under the application's package root (`src/<project>/`, which ADR-021's layout already fixes, as Spring's base package does);
  - `FlintApplication.run!App` imports that list and finds every `@Component`, `@Service`, `@Repository`, `@RestController`, `@Configuration` and `@ControllerAdvice` type by `__traits` introspection;
  - `@FlintApplication(scanBasePackages: [...])` narrows or extends the root, as in Spring.
- **The D deviation:** D's process entry point must be a free function, so `mixin FlintMain!App` generates `int main(string[] args)` calling `App.main`. Everything a developer writes looks like Spring.

### 3. Name mapping

Spring names apply wherever they don't already. The "Flint today" names stay as aliases.

| Spring Boot | Flint today | Flint canonical |
| --- | --- | --- |
| `@SpringBootApplication` | none (beans listed by hand) | `@FlintApplication` |
| `SpringApplication.run(App.class, args)` | `runApplication!(Beans...)(args)` | `FlintApplication.run!App(args)` |
| `@GetMapping` `@PostMapping` `@PutMapping` `@DeleteMapping` `@PatchMapping` | `@Get` `@Post` `@Put` `@Delete` | the Spring names |
| `@RequestParam` | `@QueryParam` | `@RequestParam` |
| `@RequestHeader`, `@CookieValue` | none | the Spring names |
| `ResponseEntity<T>` | `Result!T` with a status | `ResponseEntity!T` (status, headers, body), with `Result!T` still accepted |
| `@ExceptionHandler` in a `@ControllerAdvice` | `@ControllerAdvice` | both, as in Spring |
| `@Configuration` + `@Bean` methods | `BeanRegistrar!(Bind!(I, Impl))` | `@Configuration` classes with `@Bean` methods; `Bind` remains for interface-to-implementation wiring |
| `@Autowired` (constructor) | constructor injection, `@Inject` | constructor injection without annotation (Spring's recommended style); `@Autowired` accepted as an alias of `@Inject` |
| `@Qualifier`, `@Primary` | `@Named` | `@Qualifier` (alias `@Named`) and `@Primary` |
| `@Value("${key:default}")` | none | `@Value("${key:default}")`, checked at compile time against the bound configuration schema |
| `@Profile("dev")` | profile files only | `@Profile` on beans, plus `application-<profile>.*` files |
| `@ConditionalOnProperty` / `@ConditionalOnMissingBean` / `@AutoConfiguration` | `@ConditionalOnConfig`, `@ConditionalOnMissingBean`, `@AutoConfiguration` | Spring names (`@ConditionalOnProperty`, `@ConditionalOnBean`, `@ConditionalOnMissingBean`, `@ConditionalOnClass` where meaningful) |
| `CommandLineRunner`, `ApplicationRunner` | none | both interfaces |
| `@Entity`, `@Table`, `@Id`, `@GeneratedValue`, `@Column` | `@Table`, `@Id`, `@Column` | add `@Entity` and `@GeneratedValue` |
| Spring Data derived queries (`findByEmail`, `existsByName`, `countByStatus`) | `CrudRepository`, `@Query` | derived query methods parsed at compile time, with a compile error naming the field when a derived name doesn't match the entity |
| `JpaRepository`, `PagingAndSortingRepository`, `Pageable`, `Sort` | `CrudRepository`, `Page`, `PageRequest` | the Spring names (`Pageable` as an alias of `PageRequest`) |
| `@SpringBootTest`, `@WebMvcTest`, `@DataJpaTest`, `MockMvc`, `@MockBean` | `flint.test` `Mock` | `@FlintTest`, `@WebTest`, `@DataTest`, a `MockMvc` client and `@MockBean` |
| `@EnableScheduling`, `@Async` | `@Scheduled` | `@Scheduled` and `@Async`; enabling is implicit when the starter is present |
| Actuator `/actuator/health`, `/actuator/info`, `/actuator/metrics`, `/actuator/prometheus` | the actuator package | the same paths and JSON shapes |
| `spring-boot-starter-*` | `flint-starter-*` (ADR-021) | unchanged |
| `spring-boot-devtools` | `flint watch` | unchanged |
| `banner.txt` | none | `resources/banner.txt` |

### 4. Configuration keys

Configuration keys follow Spring Boot's, with `flint.` where Spring uses `spring.`:

- `server.port`, `server.address`, `server.servlet.context-path` → `server.context-path`, and `server.ssl.*`;
- `flint.application.name` and `flint.profiles.active`;
- `flint.datasource.url`, `.username`, `.password` and `.hikari.*` → `flint.datasource.pool.*`;
- `flint.jpa.*` → `flint.data.*`; `flint.cache.*`, `flint.kafka.*`, `flint.mail.*`, `flint.security.*`;
- `logging.level.<package>`, `logging.pattern.*`;
- `management.endpoints.web.exposure.include`, `management.server.port`.

Relaxed binding works as in Spring: `server.port`, `SERVER_PORT` and `--server.port=8081` all address the same key. The file format is `application.yaml` (section 6).

### 5. Required deviations

Each deviation exists because D or Flint's performance contract requires it:

- **No runtime reflection or classpath scanning.** Scanning, conditions and injection all resolve at compile time, which is why there's no start-up cost.
- **No proxies.** `@Transactional`, `@Cacheable`, `@Async` and `@PreAuthorize` are applied by generated call wrappers on registered beans. As in Spring, a bean calling itself bypasses them, and Flint reports that at compile time.
- **Request-scoped memory.** Handler arguments and results may live in the request arena (`RequestContext`). Spring code never sees this, so starters hide it unless a handler asks for it.
- **`Result!T` and errors.** Flint's hot paths don't throw. `ResponseEntity!T` and `@ExceptionHandler` give the Spring shape, and both exceptions and `Result` errors reach the same advice.

### 6. The configuration file format

Decided by the project owner on 2026-11-22: **`application.yaml`**, with Spring Boot's shape and keys. It is what a Spring developer expects to open, and the format coding agents write most reliably for Spring-style configuration. It holds the base configuration, `application-<profile>.yaml` holds the profile overrides, and `---` documents with `flint.config.activate.on-profile` act as Spring's multi-document files.

ADR-021 rejected YAML because of its implicit typing. That risk is contained here:
- the parser follows the YAML 1.2 core schema, so only `true` and `false` are booleans; `no` is a string;
- every value binds to a declared field type, so a mismatch is a located compile-time or start-up error;
- anchors, tags and multi-line scalar tricks are rejected, with a diagnostic naming the construct.

TOML (`application.toml`) stays readable for existing projects, with the same keys. Having both base files is an error, as `flint.config` already rules for TOML and JSON. `flint new` and the generators write YAML, and `flint config migrate` converts TOML to YAML. `flint` generates a JSON Schema from the bound `@ConfigurationProperties` types, so editors complete and validate keys, as Spring's configuration metadata does.

### 7. What developers see

The canonical examples, starter examples, `flint new`, `flint generate` and `AGENTS.md` are rewritten to the Spring shape:
- the entry point from section 2;
- package-by-feature controllers, services and repositories with constructor injection;
- `@GetMapping`, `@RequestParam` and `ResponseEntity`;
- `@Entity` with derived queries;
- `@FlintTest` with `MockMvc`.

`docs/spring-boot-to-flint.md` maps every Spring concept a Java developer uses to its Flint equivalent, side by side.

### 8. Library architecture: Spring Framework, Spring Boot, starters

Decided by the project owner on 2026-11-22: Flint's libraries are layered exactly as Spring's are. Each layer has one job, and code lives in only one layer.

| Spring | Flint | What lives there |
| --- | --- | --- |
| Spring Framework (`spring-core`, `spring-beans`, `spring-context`, `spring-web`, `spring-jdbc`, `spring-data-*`, `spring-security`, ...) | **The Flint framework libraries**: the 37 packages (`flint:arena` … `flint:web`, `flint:data`, `flint:security`, ...) | Programming models, annotations and programmatic APIs. Each library works on its own, with explicit construction. It knows nothing of Boot, reads no `application.*` file and carries no global defaults. |
| `spring-boot` | **`flint:boot`** | `@FlintApplication`, `FlintApplication.run`, `FlintMain`, compile-time component scanning, the banner, runners, profiles, binding `application.*` to `@ConfigurationProperties`, the application lifecycle, and failure analysis: start-up errors explained with the key, bean or type that caused them. |
| `spring-boot-autoconfigure` | **`flint:boot-autoconfigure`** | One `@AutoConfiguration` per framework library: `WebServerAutoConfiguration`, `DataSourceAutoConfiguration`, `SecurityAutoConfiguration`, `CacheAutoConfiguration` and so on. Each is guarded by `@ConditionalOnClass` (the library is linked, decided at compile time), `@ConditionalOnProperty` and `@ConditionalOnMissingBean`, and owns its properties types (`ServerProperties`, `DataSourceProperties`, ...). **Every default lives here and nowhere else.** |
| `spring-boot-actuator`, `spring-boot-actuator-autoconfigure` | **`flint:boot-actuator`** (on `flint:actuator`) | Health, info, metrics and Prometheus endpoints, with Spring's paths and JSON. |
| `spring-boot-test`, `spring-boot-test-autoconfigure` | **`flint:boot-test`** (on `flint:test`) | `@FlintTest`, `@WebTest`, `@DataTest`, `MockMvc` and `@MockBean`. |
| `spring-boot-starter-*` | **`flint:starter-*`** | **No code.** A starter is a dependency bundle plus the configuration section that `flint add` writes. `flint:starter` (the base, like `spring-boot-starter`) is `boot` + `boot-autoconfigure` + `log`. Every other starter depends on it. |

Rules:

- **A starter contains no D source.** `flint check` fails one that does. Behaviour belongs in a framework library (the programming model) or in `flint:boot-autoconfigure` (wiring and defaults).
- **Starters are named after the Spring Boot starter for the same domain, where one exists:**
  - `starter-web`, `starter-validation` and `starter-json`;
  - `starter-data-jdbc` (Flint's repositories over SQL);
  - `starter-security` and `starter-oauth2-client`;
  - `starter-actuator` (not "observability"), `starter-cache`, `starter-mail`, `starter-test`;
  - `starter-kafka` for the Kafka and JetStream clients.

  Flint-only domains keep descriptive names: `starter-mcp`, `starter-ai`, `starter-cli`, `starter-tui`, `starter-desktop` and `starter-wasm`.
- **Framework libraries never import `flint:boot` or `flint:boot-autoconfigure`.** The dependency direction is framework → boot → autoconfigure → starters, and the structural gate checks it as it checks the existing tiers.
- **Auto-configuration is overridable in Spring's ways:**
  - a user's own bean of the same type wins (`@ConditionalOnMissingBean`);
  - properties tune the defaults;
  - `@FlintApplication(exclude: [DataSourceAutoConfiguration])` turns one off.
- **`flint:starter-web` and `flint:starter-observability` move to this shape now:**
  - `runApplication` and the run loop go to `flint:boot`;
  - the server, SPA and static-resource wiring and `ServerProperties` go to `flint:boot-autoconfigure`;
  - the actuator wiring goes to `flint:boot-actuator`;
  - the starters keep only their dependency lists and configuration sections, and `starter-observability` is renamed `starter-actuator`.

## Consequences

- **New libraries:** `flint:boot`, `flint:boot-autoconfigure`, `flint:boot-actuator` and `flint:boot-test` join the release surface as Boot's layer, separate from the 37 framework libraries. Starters become code-free.
- **Public API additions:** `flint.boot` (`FlintApplication`, `FlintMain`, the runners and the banner), the mapping annotations, `ResponseEntity`, `@Value`, `@Profile`, the `@Configuration`/`@Bean` style, derived queries and the test slices. They are recorded in the Milestone 10 decisions ADR (ADR-028) as they land.
- **Names:** the old names keep working, and `flint check` steers code to the Spring names.
- **Scale:** this widens Milestone 10, and the vibe-coding benchmark waits for it, since agents and Java developers should meet the Spring shape first.
