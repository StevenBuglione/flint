# Flint Boot starters

A starter has no D source: it is a DUB package with `targetType "none"` whose dependencies bring in a feature, as Spring Boot's `spring-boot-starter-*` POMs do. Each one follows its upstream `build.gradle` in spring-boot v4.2.0 `starter/`. A module joins its starter in the same commit that adds it to `boot/module/`.

| Starter | Upstream dependencies | In Flint now | Joins when it lands |
| --- | --- | --- | --- |
| `flint-boot-starter` | starter-logging, autoconfigure, jakarta.annotation-api, snakeyaml | `boot`, `boot-autoconfigure`, `flint:jakarta-annotation` (YAML and the `flint.slf4j` logging system are built into `boot`) | `flint-boot-starter-logging` as its own starter, when an alternative logging system exists to exclude it for |
| `flint-boot-starter-json` | starter, module jackson | `boot-starter`, `boot-jackson` (properties so far) | `JacksonAutoConfiguration` in `boot-jackson` |
| `flint-boot-starter-web` | starter-jackson, starter-tomcat, http-converter, webmvc | `boot-starter`, `boot-starter-json`, `boot-webmvc`, `boot-web-server` (properties so far) | the MVC and server auto-configurations, `flint-boot-http-converter`, and the flint:webmvc and server packages (Flint's embedded server takes Tomcat's place) |
| `flint-boot-starter-jdbc` | starter, module jdbc, HikariCP | `boot-starter`, `boot-jdbc`, `boot-sql`, `boot-transaction` (properties so far) | `DataSourceAutoConfiguration` over Flint's pool (bound with `flint.datasource.hikari.*`), `JdbcTemplateAutoConfiguration`, the transaction and SQL-init auto-configurations |
| `flint-boot-starter-validation` | starter, module validation | `boot-starter` | `flint-boot-validation` |
| `flint-boot-starter-test` | starter, test, test-autoconfigure, JUnit, AssertJ, Mockito, JSONPath, … | `boot-starter`, `boot-test`, `boot-webmvc-test`, `boot-data-jdbc-test` | MockMvc and `RestTestClient` (spring-test, from web-mvc), Mockito's `@MockitoBean` engine |

The DUB names (`boot-starter-web`, …) become `flint:boot-starter-web` when `boot/` moves to `flint-boot` and the packages register as subpackages of its root, replacing the pre-ADR-030 `starters/` (task step 5).
