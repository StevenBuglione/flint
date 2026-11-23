# spring-petclinic-rest on Flint

[spring-petclinic/spring-petclinic-rest](https://github.com/spring-petclinic/spring-petclinic-rest) at commit
220f4ba (the reference pinned in `benchmarks/spring/apps.json`), ported to Flint Boot. It runs the `postgres,jdbc`
profiles, the ones the benchmark runs: JDBC repositories on PostgreSQL. The JPA and Spring Data JPA repositories, and
the H2, HSQLDB and MySQL profiles, are not ported.

## Layout

One D module per Java package (rulebook R1), under `src/` with the Java package path:

| Java package | What it holds |
| --- | --- |
| `org.springframework.samples.petclinic` | `PetClinicApplication` |
| `.model` | the entities |
| `.repository`, `.repository.jdbc` | the repository interfaces and their JDBC implementations |
| `.service` | `ClinicService`, `UserService` |
| `.util` | `EntityUtils` |
| `.mapper` | the MapStruct interfaces and the `*MapperImpl` classes MapStruct generates |
| `.rest.api`, `.rest.dto` | the interfaces and models openapi-generator writes from `openapi.yml` |
| `.rest.controller.v1`, `.v2` | the controllers |
| `.rest.advice`, `.rest.validation` | the exception handler and `@PetAgeValidation` |
| `.security` | `Roles` |
| `org.springframework.data.jdbc.core` | `OneToManyResultSetExtractor`, from spring-data-jdbc-ext (petclinic's `spring-data-jdbc-core` 1.2.1), written clean-room |

`flint.toml` sets `base-package = "org.springframework"`, so both roots are inside the module root. `resources/` has
the properties, the PostgreSQL schema and data, and the messages.

Code that Java generates at build time is written out, since Flint has no annotation processors: the openapi-generator
models and interfaces, and the MapStruct implementations. Each module header lists its adaptations.

## Build and run

```bash
../../../../.flint/bin/flint build
```

Flint Boot reads `./resources` and `./config` from the working directory, so start the app from this directory.
Pass the datasource through the environment, as the `postgres` profile reads it:

```bash
POSTGRES_URL=jdbc:postgresql://127.0.0.1:5432/petclinic POSTGRES_USER=petclinic POSTGRES_PASS=petclinic SERVER_PORT=9966 .flint/build/dev/petclinic-rest
```

## Status

`spring_bench.py accept petclinic-rest`: 109 of 109 cases on PostgreSQL, wire-exact. Not ported yet:

- `BasicAuthenticationConfig` (`petclinic.security.enable=true`) is not ported.
