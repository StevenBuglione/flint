# Java → D API mapping rulebook

ADR-030 makes Flint a port of Spring. This rulebook defines how each public element of a pinned upstream Java API becomes a D element. It covers Spring Framework v7.1.0, Spring Boot v4.2.0, the portfolio projects, and the third-party APIs that developers use directly.

Every element in `api/mapping.json` is classified as one of:
- `ported`: same name and shape, with the D symbol recorded;
- `adapted`: shaped by a rule, recorded with its rule ID;
- `excluded`: recorded with a reason category.

`flint api coverage` fails on anything unclassified. A rule changes only through this file, with a version bump, and every element citing that rule is re-checked.

Rulebook version: **2**. Version 2 moves Java's standard types to `flint.java.*` and Flint's own machinery to `flint.engine.*`, so that `flint.*` is free for Spring's packages (see "Namespaces" below).

## Rules

### R1: Packages and names

A Java package becomes a D module, and type names stay identical.
- **Spring projects:** `org.springframework.X.Y` → `flint.X.Y`.
- **Other upstream projects** map under their own roots:
  - `jakarta.validation.constraints` → `flint.jakarta.validation.constraints`;
  - `com.fasterxml.jackson.databind` → `flint.jackson.databind`;
  - `org.slf4j` → `flint.slf4j`;
  - `io.micrometer.core.instrument` → `flint.micrometer.core.instrument`;
  - `reactor.core.publisher` → `flint.reactor.core.publisher`;
  - Java's standard library, `java.X` (`java.lang`, `java.util`, `java.util.function`, `java.util.stream`, `java.time`), → `flint.java.X`.

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

- **`Optional<T>`** → `flint.java.util.Optional!T`, a struct with Java's methods: `of`, `ofNullable`, `empty`, `isPresent`, `isEmpty`, `get`, `orElse`, `orElseGet`, `orElseThrow`, `map`, `filter`, `ifPresent`.
- **A `String` that may be `null` distinctly from `""`** → `Nullable!string`. D's `null` and `""` compare equal, so `@Nullable String` parameters must use `Nullable!string`.
- **Any other Java value that may be `null` where the D type is a value type** → `Nullable!T` (`std.typecons.Nullable`, as for strings). This covers boxed `Long`/`Integer` IDs and `@Nullable` boxed parameters and returns: `Persistable!ID.getId()` returns `Nullable!long` when `ID` is `long`. Coordinator, 2026-11-26, under the owner's standing approval.
- **Reference types** (classes, interfaces) keep plain `null`. **`Optional!T` is only for `java.util.Optional`**, never for a nullable value.

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
  - `flint.java.lang.RuntimeException : Exception`;
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
| `List<T>`, `Set<T>`, `Map<K,V>` in signatures | `flint.java.util.List!T`, `Set!T`, `Map!(K, V)`: thin wrappers with Java's methods (`add`, `get`, `size`, `isEmpty`, `contains`, `forEach`, `stream`), convertible to and from D arrays and associative arrays |
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

### R15: Enums with fields

Three rules cover every Java enum, so no enum needs a case-by-case decision:
- **Constants only:** a D `enum` with the same constant names, `ported`.
- **Fields** (with or without methods): R15, below.
- **Methods but no fields and no interface:** R20.
- **An interface:** R18.

Adopted by the coordinator on 2026-11-26 under the owner's standing approval. It was proposed in `docs/spring/phase1/web-mvc.md`; R18 replaces that proposal's interface clause.

An enum with fields becomes a struct:
- **Constants** are `static immutable` instances in Java's order.
- **Members:** Java's `name()`, `ordinal()`, `values()`, `valueOf(String)` and `toString()`, plus the enum's own field getters and methods.
- **Equality** is by value, per R11: two constants are equal when they are the same constant.
- **Existing ports:** `HttpStatus` and `HttpMethod` (D-15 in web-mvc.md). `HttpStatus` also converts to `HttpStatusCode` through `alias this`, and keeps that shape.

Mapping: the enum, its constants and its members are `adapted` with rule `R15`, or `ported` where a member keeps Java's exact shape.

### R16: Sealed interfaces and the records that implement them

R16 says how R3 and R11 combine when a record implements an interface (coordinator, 2026-11-26, from sol-ai's `MessagePart`):
- **The interface stays a D interface** (R3), sealed or not. Its constants become static members.
- **A record that implements an interface is a `final class`**, because only classes implement D interfaces. It mixes in `JavaObject` and defines member-wise `equals`, `hashCode` and `toString`, so R11's record equality holds. Its accessors keep the record names (`text()`, `payload()`).
- **A record that implements no interface stays a struct** (R11).
- **`sealed` and `permits` have no D equivalent.** Each permitted class is `final`, and the interface's doc comment lists the permitted classes. No closed-world mechanism (tagged unions, visitors, registries) is added.
- **User code reads as in Java:** `List!MessagePart`, a `withAttributes` that returns `MessagePart`, and `if (auto t = cast(TextPart) part)` for `instanceof TextPart t`.

Mapping: the records are `adapted` with rules `R16` (plus `R11` where equality is the point). The interface is `ported`.

### R17: Shared constants of generic classes

Java often shares one instance of a generic class as a constant: Spring Data's `Range.unbounded()`, `Bound.unbounded()` and the initial `ScrollPosition`s (D-DATA-2, and the D-DATA-5 that sol-data proposed). D cannot share one object across instantiations of a class template, and Flint keeps no mutable module-level state. Coordinator, 2026-11-26, under the owner's standing approval:
- **A constant whose class has fields** becomes a value-equal instance created per type instantiation (`Range!int.unbounded()` and `Range!string.unbounded()` are separate objects). `equals`, `hashCode` and the `is*()` queries (`isUnbounded()`, `isInitial()`) return Java's results. Reference identity (`==` on references, `a is b`) is not preserved, so code must compare with `equals`.
- **A constant whose class has no fields** keeps one shared instance through `flint.engine.aot.objects.statelessInstance`, exactly as in Java.

Mapping: the factory method or constant is `adapted` with rule `R17`. A lane cites R17 instead of adding a per-module deviation.

### R18: Enums that implement an interface

D enums cannot implement interfaces. Coordinator, 2026-11-26, under the owner's standing approval:
- **A singleton enum** (one constant, used as a strategy object, such as Spring Data's `PersistableIsNewStrategy`) becomes a `final` fieldless class that implements the interface. Its one instance is shared through `statelessInstance` and exposed as the static constant (`INSTANCE`), so identity holds as in Java. It keeps `name()`, `ordinal()`, `toString()` and `values()` as Java has them.
- **A multi-constant enum used as option values** (Jakarta's `LockModeType`, `FlushModeType`; D-JPA-2) stays a D `enum`. Methods that take the interface type gain overloads at the API boundary that accept the enum, as in `em.find!Owner(id, LockModeType.PESSIMISTIC_WRITE)`.
- **Enums already ported as structs with `alias this` to an interface struct** (`HttpStatus` to `HttpStatusCode`, R15) keep that shape.

Mapping: the enum and its constants are `adapted` with rule `R18`.

### R19: Java names that are D keywords

A Java identifier that is a D keyword or a name D reserves takes a trailing underscore, which is Phobos's convention. Examples: `version`, `function`, `debug`, `delegate`, `alias`, `body`, `in`, `out`, `ref`, `scope`, `module`, `import`, `cast`, `typeof`, `mixin`, `template`, `invariant`, `unittest`. Coordinator, 2026-11-26, under the owner's standing approval.
- **Members:** `UUID.version()` → `version_()`, `Logger.debug(...)` → `debug_(...)` (D-SLF4J-2, docs/spring/phase1/third-party.md).
- **Package path segments:** `java.util.function` → `flint.java.util.function_` (D-15 in docs/spring/phase1/framework-core.md).
- **The `template` module** is the exception AGENTS.md already names: `flint:engine-template` is `flint.engine.templates`.

Mapping: the element is `adapted` with rule `R19`. Lanes cite R19 instead of a new deviation.

### R20: Enums with methods but no fields or interfaces

A Java enum that declares methods but has no instance fields and implements no interface stays a D `enum`. Coordinator, 2026-11-26, under the owner's standing approval, from sol-observability's Actuator `Access`:
- **Constants** keep Java's names and order, so a constant's position is its `ordinal()`.
- **Methods** become free functions in the same module, called by UFCS (`access.cap(other)`), so call sites read as in Java. A selective import lists the functions beside the enum: `import flint.boot.actuate.endpoint : Access, cap;`.
- **Static methods** become same-module free functions too, called without a receiver: Spring AI's `FinishReasonCategory.categorize(s)` is `categorize(s)`, imported by name.
- **Java's `null` behaviour** for enum-typed parameters (`cap(null)` throws) is kept through a typed `null` overload (D-7).
- **Enums with fields** follow R15, and **enums that implement an interface** follow R18.

Mapping: the constants are `ported`, and the methods are `adapted` with rule `R20`.

### R21: Type parameters that appear only in the return type

Java infers `<T extends B> T m()` from the assignment context, which D does not have. Coordinator, 2026-11-26, under the owner's standing approval, from sol-jackson's `JsonNode.require()`:
- **A non-template `m()`** returns the bound `B`.
- **An explicit `m!T()`** returns `T` through a checked downcast over the same erased implementation. On a mismatch it throws Java's `ClassCastException`, or the exception the API documents for that case.
- Both share one implementation, so the template adds only the cast.
- **Where it recurs:** `getBean`-like lookups and attribute accessors. A method whose type parameter also appears in a parameter is not covered; `Class<T>` tokens stay R4.

Mapping: the method is `adapted` with rule `R21`; its `d` names the method (`flint.jackson.databind.JsonNode.require`), never the template instance.

## Namespaces

Each D namespace has one owner, so a Spring package never collides with Flint's own code:

| Namespace | Holds | DUB names |
| --- | --- | --- |
| `flint.X` | Spring's package `org.springframework.X`, and only that (`flint.http`, `flint.web`, `flint.cache`, `flint.data`, `flint.security`, `flint.ai`, `flint.util`, …) | Spring's artifact name with `spring` → `flint`: `flint:core`, `flint:beans`, `flint:context`, `flint:web`, `flint:webmvc`, `flint:jdbc`, `flint:tx`, `flint:boot`, `flint:boot-autoconfigure`, `flint:boot-starter-web` |
| `flint.java.X` | Java's standard types the APIs expose (`Optional`, `List`, `Map`, `RuntimeException`, functional interfaces, streams, `java.time`) | `flint:java` |
| `flint.jakarta.X`, `flint.jackson.X`, `flint.slf4j`, `flint.micrometer.X`, `flint.reactor.core.X` | the third-party APIs of R1 | one package per upstream artifact |
| `flint.engine.X` | Flint's engines: reactor, web transport, HTTP client transport, SQL, cache, mq, mail, storage, security primitives, AOT runtime (`Any`, `Descriptor`), and the rest | `flint:engine-X` |
| base libraries in the `flint` repository (`flint.arena`, `flint.conc`, `flint.cli`, `flint.config`, `flint.log`, `flint.os`, `flint.serde`, `flint.term`, `flint.test`, `flint.validate`) | the CLI's closure | unchanged |

The framework-side engines that today use `flint.<name>` (`flint.web`, `flint.http`, `flint.reactor`, `flint.data`, `flint.security`, `flint.cache`, `flint.mail`, `flint.ai`, …) move to `flint.engine.<name>`, and their DUB names to `flint:engine-<name>`. This is a mechanical rename, done once, before the split. Base libraries that Spring has no package for keep their names.

**`flint.test` is shared, split by subpackage.** The base library (`flint:test`, in the CLI's closure) owns `flint.test` itself (`package.d`), `flint.test.internal` and `flint.test.sys`. spring-test (`flint:framework-test`) owns its own subpackages under the same root: `flint.test.annotation`, `.context`, `.http`, `.jdbc`, `.json`, `.util`, `.validation` and `.web`, so `MockMvc`, `@MockitoBean` and `RestTestClient` keep Spring's package paths. spring-test has no types in its root package, so the two never collide. The base library must not add a module under any of spring-test's subpackage names, and spring-test must not use `internal` or `sys`.

## Erased types used by the rules

| Type | Purpose |
| --- | --- |
| `flint.engine.aot.Any` | erased value for `Object`-typed APIs: a descriptor and a small inline buffer, with no `std.variant` |
| `flint.engine.aot.Descriptor` | Flint AOT's per-type table: fields, accessors, constructors, annotations. It replaces runtime reflection. |
| `flint.java.util.Optional!T`, `List!T`, `Map!(K, V)` | façades from R5 and R10 |

## Deviations

Each deviation is the smallest change D or the closed world forces. Adding one means editing this table, with its reason.

| ID | Deviation | Reason |
| --- | --- | --- |
| D-1 | `mixin FlintMain!App;` beside the application class | D's entry point must be a free function |
| D-3 | All-default callback interfaces are abstract classes | D interfaces have no default method bodies |
| D-4 | `Class<T>` tokens are template parameters (R4) | D types are not runtime values |
| D-7 | Typed `null` constants for unrelated overload pairs, including `ClassFilter.NULL` for class filters and delegates | D resolves `null` differently for unrelated types |
| D-8 | No `throws` clauses | D has no checked exceptions |
| D-14 | String indices in UTF-8 internally (R14) | D strings are UTF-8 |
| D-MICROMETER-1 | `Tags` has a private constructor and private concrete implementations. The null overloads of `Tags.of`, `Tags.and` and `Tags.concat` use typed null values (D-7). | The fieldless empty implementation reuses Flint's allocation-free Java constant support. D's overload resolution needs an explicit type for null across unrelated string, tag and iterable overloads. |
| D-JACKSON-10 | `java.util.Date` reading and `@JsonFormat` pattern and time-zone writes are in `JavaUtilDateModule` (`flint.jackson.databind.module_`). Plain Date writes are built in. Two places register the module: Flint AOT's generated `JsonMapperBuilderCustomizer`, whenever the application's described types hold a `Date`, and the templated `ObjectMapper` methods (`readValue!T`, `treeToValue!T`, `convertValue!T`, `writeValueAsString!T`, `writeValueAsBytes!T`, `writeValue!T`, `ObjectWriter.writeValueAsString!T`) when `T` holds one at any depth. One path remains: Flint's erased methods (`readValue(content, typeName)`, `convertValue(Any, typeName)`) on a mapper built by hand over descriptors the user added, for a type holding a `Date`, without `addModule`. Spring code cannot reach it, since it names types by `Class<T>` (`readValue!T`) or uses Boot's mapper. That path throws `InvalidDefinitionException`: "`java.util.Date` is read, and formatted with a @JsonFormat pattern or time zone, by JavaUtilDateModule, which this mapper does not have: register it with JsonMapper.builder().addModule(new JavaUtilDateModule()) (deviation D-JACKSON-10)". The test "java.util.Date: plain writes need no module; erased reads without one name JavaUtilDateModule (D-JACKSON-10)" in framework/jackson-databind/tests/java_util_date_test.d pins it. When `readerFor` or `TypeReference` are ported, they must register the module the same way the templated methods do, with tests. | Jackson builds Date support into every mapper; linking it everywhere costs every web app about 70 KB of calendar and parsing code, when the error body only writes a Date. A build-time check on the erased path would have to make `JsonMapper.Builder.descriptors()` reference the module, which links it into every application and defeats pay-for-use. |
| D-JDBC-1 | A JDBC driver package (`flint:postgresql`, `flint:sqlite-jdbc`) is linked through its `META-INF/services/flint.java.sql.Driver` listing, which Flint AOT turns into a `static import` in the application's registry (`30cebc6a`); the driver module's `shared static this()` registers it with the `DriverManager`, and constructing it enables the engine driver. Flint AOT runs only for `@FlintBootApplication` projects, so a plain `flint:jdbc` or `DriverManager` program without Boot enables its driver itself: `flint.engine.jdbc.enablePostgres()`/`enableSqlite()`, or by importing and constructing the driver class. | In a static link nothing references an unimported module, so Java's class-path autoloading has no equivalent without a build step; the engine links a native driver only when it is enabled (performance playbook S-1a). |
| D-JPA-1 | The Jakarta Persistence and Criteria public modules selectively re-export mutually referencing interfaces from the internal `flint.jakarta.persistence.contracts` module. Mapping annotations are declared in a leaf and available from `flint.jakarta.persistence`. | Java packages may reference each other. Flint requires an acyclic D import graph and keeps the original public import paths. |
| D-DATA-2 | Initial offset and keyset positions compare by value. The zero-start position function and the initial positions are created by their factories. | The Java implementation caches these stateful objects. Flint's process-wide instance helper accepts classes with no fields. |
| D-DATA-3 | Typed property paths and the legacy typed sort resolve named D getter aliases. For example, `Sort.sort!Person().by!(Person.getAddress)().by!(Address.getCity)()` sorts by `address.city`. The same chain uses `then!(Address.getCity)()` on a typed property path. A missing intermediate object yields the D result type's `init`, which is null for class references and the type's default value for value types. | Spring reads serialized lambdas or records getter calls through a runtime proxy. Compile-time aliases provide the getter name and return type in Flint's closed world. Java can represent a missing result as null even when the getter's value type is boxed. |
| D-SPEL-1 | Java's `new TypedValue(value)` becomes `TypedValue(value)`. `TypedValue.NULL` remains a member. `BooleanTypedValue.forValue` returns a `TypedValue` directly when that factory is ported. | A `TypedValue` is copied by value so small values and null require no wrapper allocation during expression evaluation. D structs have no subclasses. |
| D-SPEL-3 | `StandardEvaluationContext.setDescriptorTable(const DescriptorTable)` configures property reads before sharing the context (R4). Spring API callers can receive a context configured by application composition. | Property reads use the application's generated descriptor table. Flint has no runtime class discovery. |
| D-JPA-2 | Jakarta built-in option enums such as `LockModeType` remain D enums. `EntityManager` option overloads accept them at the API boundary, as in `em.find!Owner(id, LockModeType.PESSIMISTIC_WRITE)`. Provider-defined options use `FindOption` and `RefreshOption`. | D enums cannot implement interfaces. The enum keeps `NamedQuery.lockMode` a compile-time UDA value. |
| D-DATA-4 | In `Window!int`, `positionAt(index)` selects by index and `positionAt!int(item)` selects by value. | R5 represents Java's boxed `Integer` as `int`, so the Java overloads otherwise have identical D signatures. |
| D-VALIDATION-3 | Whole-input regex matching stops after 20,000,000 VM steps with a budget exception. Hibernate Validator maps the exhausted match budget to HV000028. | The bounded engine keeps a backtracking match from stalling a request thread. Java does not impose this bound. |
| D-TEST-1 | `JsonComparator.of` uses the Jackson tree for Spring's strict and lenient JSON comparison modes. `ContentResultMatchers.json` accepts an explicit comparator or delegate. | Spring 7.1 discovers JsonUnit or JSONassert on the classpath. Flint's closed world uses one built-in comparator, with an explicit hook for custom behavior. |

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
