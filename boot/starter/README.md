# Flint Boot starters

A starter has no D source: it is a DUB package with `targetType "none"` whose dependencies bring in a feature, as Spring Boot's `spring-boot-starter-*` POMs do. Each one follows its upstream `build.gradle` in spring-boot v4.2.0 `starter/`. A module joins its starter in the same commit that adds it to `boot/module/`.

| Starter | Upstream dependencies | In Flint now | Joins when it lands |
| --- | --- | --- | --- |
| `flint-boot-starter` | starter-logging, autoconfigure, jakarta.annotation-api, snakeyaml | `boot`, `boot-autoconfigure`, `flint:jakarta-annotation` (YAML is built into `boot`) | `flint-boot-starter-logging` (the `flint.slf4j` provider with Boot's console format) |
| `flint-boot-starter-json` | starter, module jackson | `boot-starter` | `flint-boot-jackson` (`JacksonAutoConfiguration`) |
| `flint-boot-starter-web` | starter-jackson, starter-tomcat, http-converter, webmvc | `boot-starter`, `boot-starter-json` | `flint-boot-webmvc`, `flint-boot-http-converter`, `flint-boot-web-server` (Flint's embedded server takes Tomcat's place) |
| `flint-boot-starter-jdbc` | starter, module jdbc, HikariCP | `boot-starter` | `flint-boot-jdbc` (`DataSourceAutoConfiguration` over Flint's pool, bound with `flint.datasource.hikari.*`) |
| `flint-boot-starter-validation` | starter, module validation | `boot-starter` | `flint-boot-validation` |
| `flint-boot-starter-test` | starter, test, test-autoconfigure, JUnit, AssertJ, Mockito, JSONPath, … | `boot-starter`, `boot-test`, `boot-webmvc-test`, `boot-data-jdbc-test` | MockMvc and `RestTestClient` (spring-test, from web-mvc), Mockito's `@MockitoBean` engine |

The DUB names (`boot-starter-web`, …) become `flint:boot-starter-web` when `boot/` moves to `flint-boot` and the packages register as subpackages of its root, replacing the pre-ADR-030 `starters/` (task step 5).
