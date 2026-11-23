# Java → D API mapping rulebook

ADR-030 makes Flint a port of Spring. This rulebook defines how each public element of a pinned upstream Java API becomes a D element. It covers Spring Framework v7.1.0, Spring Boot v4.2.0, the portfolio projects, and the third-party APIs that developers use directly.

Every element in `api/mapping.json` is classified as one of:
- `ported`: same name and shape, with the D symbol recorded;
- `adapted`: shaped by a rule, recorded with its rule ID;
- `excluded`: recorded with a reason category.

`flint api coverage` fails on anything unclassified. A rule changes only through this file, with a version bump, and every element citing that rule is re-checked.

Rulebook version: **1**.

## Rules

### R1: Packages and names

A Java package becomes a D module, and type names stay identical.
- **Spring projects:** `org.springframework.X.Y` → `flint.X.Y`.
- **Other upstream projects** map under their own roots:
  - `jakarta.validation.constraints` → `flint.jakarta.validation.constraints`;
  - `com.fasterxml.jackson.databind` → `flint.jackson.databind`;
  - `org.slf4j` → `flint.slf4j`;
  - `io.micrometer.core.instrument` → `flint.micrometer.core.instrument`;
  - `reactor.core.publisher` → `flint.reactor.core.publisher`.

Where the word "Spring" appears in an identifier or a configuration key, it becomes "Flint" (`SpringApplication` → `FlintApplication`, `spring.datasource.url` → `flint.datasource.url`, with `spring.*` accepted as an alias). Nothing else is renamed.

A Java package with one public type still gets its own module. Framework modules have no `package.d` aggregators (ADR-030 section 5). Applications import the module that declares what they use, exactly as Java imports a package.

```java
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.http.ResponseEntity;
```
```d
import flint.web.bind.annotation : GetMapping;
import flint.http : ResponseEntity;
```

### R2: Annotations

An annotation becomes a UDA struct with the same name. Its attributes become fields with the same names and Java's defaults. The `value` element is the first field, so `@GetMapping("/x")` reads the same.
- **Meta-annotations** are UDAs on the struct declaration. Flint AOT composes them at build time, together with `@AliasFor`, the way Spring's `MergedAnnotations` does at runtime. `@RestController` is `@Controller` plus `@ResponseBody`.
- **Annotation modules are leaves:** they import only other UDA structs.

```java
@GetMapping(value = "/owners/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
```
```d
@GetMapping(value: "/owners/{id}", produces: MediaType.APPLICATION_JSON_VALUE)
```

### R3: Interfaces, abstract classes and static members

- **Stays the same:** a Java interface stays a D interface, and an abstract class stays abstract.
- **Static methods** on an interface become static members of the D interface.
- **Default methods:**
  - If an interface consists entirely of default methods and is meant to be implemented selectively, such as `WebMvcConfigurer` or `HandlerInterceptor`, it becomes an abstract class with the same name, so implementors override only what they need. This is deviation D-3.
  - If it mixes abstract and default methods, the defaults move into `mixin template Defaults`, which implementors mix in: `mixin WebFilter.Defaults;`.

### R4: `Class<T>` parameters

A parameter whose only purpose is a type token becomes a template parameter. The rest of the signature is unchanged.

```java
Note note = restClient.get().uri("/notes/1").retrieve().body(Note.class);
List<Owner> owners = jdbcTemplate.query(sql, new BeanPropertyRowMapper<>(Owner.class));
```
```d
Note note = restClient.get().uri("/notes/1").retrieve().body!Note();
Owner[] owners = jdbcTemplate.query(sql, new BeanPropertyRowMapper!Owner());
```

A template wrapper stays a one-liner over an erased engine that takes `T`'s Flint AOT descriptor (ADR-030 section 5).

### R5: `Optional` and nullable values

- **`Optional<T>`** → `flint.util.Optional!T`, a struct with Java's methods: `of`, `ofNullable`, `empty`, `isPresent`, `isEmpty`, `get`, `orElse`, `orElseGet`, `orElseThrow`, `map`, `filter`, `ifPresent`.
- **A `String` that may be `null` distinctly from `""`** → `Nullable!string`. D's `null` and `""` compare equal, so `@Nullable String` parameters must use `Nullable!string`.

### R6: Java Beans properties

Getters and setters keep their Java names (`getContentType()`, `setStatus(int)`). Records keep their accessor names (`name()`). Flint adds no D `@property` shortcuts to the API layer, so code reads as it does in Java.

### R7: Overloads

Overloads are kept as written.
- **The rule for `null`:**
  - Where Java resolves a `null` argument to the more specific of two related types, D does the same.
  - Where the two parameter types are unrelated (`String` and `Object`), the overload pair needs an entry in `api/mapping.json`, plus a test that calls each overload with `null` and asserts the target Java would choose.
  - When D can't express the choice, typed `null` constants are added and listed as deviation D-7.
- **Varargs** (`Object... args`) become a one-line `(Args...)` façade that builds an `Any[]` on the stack.

### R8: Exceptions

- **The hierarchy keeps Java's names and shape:**
  - `flint.lang.RuntimeException : Exception`;
  - `DataAccessException : NestedRuntimeException : RuntimeException`;
  - `ResponseStatusException`, `MethodArgumentNotValidException` and so on.
- **`throws` clauses** are dropped from signatures and kept in DDoc. D has no checked exceptions (deviation D-8).
- **Java `Error`s that application code catches**, such as `AssertionError` in tests, map to D `Exception` subclasses, because D `Error` skips cleanup.
- **Control-flow exceptions** that the framework throws and catches internally skip backtrace capture (ADR-030 section 4).

### R9: Functional interfaces

A functional interface stays an interface, and every API that takes one also accepts a D delegate with the same parameter and return types.
- The delegate parameter is a concrete, non-template type, so lambdas infer and no template is instantiated per call site.
- Lambda DSLs (`HttpSecurity.authorizeHttpRequests(auth -> ...)`) take such delegates.

### R10: Streams and collections

| Java | D |
| --- | --- |
| `List<T>`, `Set<T>`, `Map<K,V>` in signatures | `flint.util.List!T`, `Set!T`, `Map!(K, V)`: thin wrappers with Java's methods (`add`, `get`, `size`, `isEmpty`, `contains`, `forEach`, `stream`), convertible to and from D arrays and associative arrays |
| `Stream<T>` | a range façade with Java's method names (`filter`, `map`, `collect`, `toList`, `findFirst`, `anyMatch`) |

`Collectors` gets the common collectors.

### R11: Object identity and equality

| Java | D |
| --- | --- |
| `equals`, `hashCode`, `compareTo`, `toString` | method names kept; `mixin JavaObject;` maps them to `opEquals`, `toHash`, `opCmp` and `toString` |
| Reference `a == b` | `a is b` |
| `a.equals(b)` | `a.equals(b)` or `a == b` |
| Records | structs with member-wise equality |
| Plain classes | identity equality unless they override `equals` |

### R12: Builders and fluent APIs

Builders keep Java's method chain exactly (`ResponseEntity.ok().header(...).body(x)`, `RestClient.builder().baseUrl(...).build()`, `UriComponentsBuilder`). A builder is a struct whose setters return `ref` with `return` (DIP1000), or a final class where Spring users subclass it.

### R13: Nested and inner classes

| Java | D |
| --- | --- |
| Static nested class | `static` nested type with the same name (`ResponseEntity.BodyBuilder`, `HttpHeaders.Builder`) |
| Inner class | D nested class |
| Anonymous class | delegate where R9 applies, otherwise a D anonymous class |
| Nested type of a generic class | hoisted out of the template and aliased back, so it isn't instantiated per `T` |

### R14: Strings and text

Java strings index UTF-16 code units, and D strings index UTF-8 bytes. Every ported routine that does index arithmetic, such as `AntPathMatcher`, `UriComponentsBuilder`, `StringUtils` and `PathPattern`, is reviewed for this and tested with non-ASCII input. Public methods that return an index document the unit, and keep Java's unit wherever the index crosses the API.

## Erased types used by the rules

| Type | Purpose |
| --- | --- |
| `flint.lang.Any` | erased value for `Object`-typed APIs: a descriptor and a small inline buffer, with no `std.variant` |
| `flint.lang.Descriptor` | Flint AOT's per-type table: fields, accessors, constructors, annotations. It replaces runtime reflection. |
| `flint.util.Optional!T`, `List!T`, `Map!(K, V)` | façades from R5 and R10 |

## Deviations

Each deviation is the smallest change D or the closed world forces. Adding one means editing this table, with its reason.

| ID | Deviation | Reason |
| --- | --- | --- |
| D-1 | `mixin FlintMain!App;` beside the application class | D's entry point must be a free function |
| D-3 | All-default callback interfaces are abstract classes | D interfaces have no default method bodies |
| D-4 | `Class<T>` tokens are template parameters (R4) | D types are not runtime values |
| D-7 | Typed `null` constants for unrelated overload pairs | D resolves `null` differently for unrelated types |
| D-8 | No `throws` clauses | D has no checked exceptions |
| D-14 | String indices in UTF-8 internally (R14) | D strings are UTF-8 |

## Exclusions

An excluded element names one of these categories in `api/mapping.json`:

| Category | Examples |
| --- | --- |
| `jvm-runtime` | `ClassLoader` APIs, `Instrumentation`, `spring-instrument`, the CGLIB and ByteBuddy runtime, Objenesis |
| `jvm-platform` | JMX, JNDI, JSP, Java serialization, JFR, CRaC, RMI |
| `runtime-reflection` | classpath scanning at runtime, `RuntimeHints` (a no-op in Flint, since Flint AOT generates the equivalent), load-time weaving, `@Configurable` |
| `packaging` | `spring-boot-loader` (jar launcher), buildpacks, WAR deployment, `SpringBootServletInitializer` |
| `devtools` | the restart classloader and LiveReload (`flint watch` replaces them) |
| `jvm-language` | the Kotlin and Groovy DSLs, Kotlin coroutines bridges |
| `deferred` | XML bean definitions and anything planned but not yet scheduled; must name the phase |

## API-layer internals allowed to reflect

These may use `__traits`, mixins and generated code, in addition to the AGENTS.md list:
- Flint AOT, in `flint`;
- `flint.core.annotation` (merged annotations);
- `flint.beans`;
- `flint.context.annotation`;
- the request-mapping and message-converter internals of `flint.web`;
- `flint.jackson.databind` descriptors;
- `flint.jakarta.validation` metadata;
- the repository generators in the data repositories.

Application code may only apply UDAs and call documented APIs.

## `api/mapping.json` entries

An element key is an element id from the manifest, as `flint api extract` writes it, or a pattern over ids. In a pattern, `*` matches within one name and `**` matches anything, so `"org.springframework.jmx.**"` excludes a whole package. An exact id wins over any pattern, and a more specific pattern wins over a broader one. `upstream` may list several manifests. `docs/flint-cli.md` (API manifests) gives the precise rules.

```json
{ "rulebook": 1,
  "upstream": "spring-framework@v7.1.0",
  "elements": {
    "org.springframework.http.ResponseEntity": { "status": "adapted", "rules": ["R12", "R13"], "d": "flint.http.ResponseEntity" },
    "org.springframework.web.client.RestClient.ResponseSpec#body(Class)": { "status": "adapted", "rules": ["R4"], "d": "flint.web.client.RestClient.ResponseSpec.body!T" },
    "org.springframework.instrument.classloading.LoadTimeWeaver": { "status": "excluded", "category": "jvm-runtime" }
  } }
```
