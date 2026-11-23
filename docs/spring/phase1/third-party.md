# Phase 1: the third-party APIs

ADR-030 Phase 1 needs the third-party APIs that Spring applications touch directly: Jackson, SLF4J, Jakarta Validation (with Hibernate Validator's behaviour) and Jakarta Annotations. This note records how they are ported, what they sit on, and how byte-for-byte equality with the Java originals is proven. It is the design record until the cutover moves the implementation to `flint-framework`.

## Upstreams and licences

Each upstream is pinned in `api/upstreams.json` and checked against `policy/upstream-licences.json` before any code is ported. The versions are the ones Spring Boot v4.2.0 manages (`platform/spring-boot-dependencies`).

| Upstream | Version | Licence | Use | Flint module |
| --- | --- | --- | --- | --- |
| jackson-annotations | 2.21 (Jackson 3.1 keeps the 2.x annotations) | Apache-2.0 | port-source | `flint.jackson.annotation` |
| jackson-core | 3.1.8 | Apache-2.0 | port-source | `flint.jackson.core` |
| jackson-databind | 3.1.8 | Apache-2.0 | port-source | `flint.jackson.databind` |
| slf4j-api | 2.0.20 | MIT | port-source | `flint.slf4j` |
| jakarta.validation-api | 3.1.1 | Apache-2.0 | port-source | `flint.jakarta.validation` |
| hibernate-validator | 9.1.6.Final | Apache-2.0 | port-source | `flint.hibernate.validator` |
| jakarta.annotation-api | 3.0.0 | EPL-2.0 OR GPL-2.0 WITH Classpath-exception-2.0 | epl-module | `flint.jakarta.annotation` |

Jackson 3 moved `com.fasterxml.jackson.core` and `.databind` to `tools.jackson.*`, while the annotations stay in `com.fasterxml.jackson.annotation`. Flint maps all three under `flint.jackson.*` (rulebook R1).

Every ported file starts with the upstream project, path and tag, the upstream copyright line, its licence, and "Modified by the Flint authors". jakarta.annotation-api is EPL-2.0 or GPL-2.0 with the Classpath exception. Flint takes the EPL-2.0 option and keeps the module separately licensed: `framework/jakarta-annotation` carries `license "EPL-2.0"`, the upstream `LICENSE` and `NOTICE.md`, and nothing else. The gate rejects EPL text in any other module.

## Where the modules live

Spring-layer DUB packages live under `framework/<artifact>/source/flint/...`, outside the 37 engine packages, and are listed in `policy/framework.json`. `tools/gates.py` (`framework_layers`) gives them the package rules:
- module paths match files;
- module-scope `@safe:`;
- only declared imports, and no imports of an engine's `internal`, `sys` or `ffi`;
- no module-level thread-local state;
- no `@trusted` or `@system`: the API layer stays `@safe`;
- the EPL-2.0 boundary.

`tools/workspace.py` maps them to the `framework` repo, so the split carries them to `flint-framework`.

| DUB package | Module root | Depends on |
| --- | --- | --- |
| `flint:jakarta-annotation` | `flint.jakarta.annotation` | nothing |
| `flint:slf4j-api` | `flint.slf4j` | `log`, `reactor` (`FiberLocal`), `engine-aot` (`Any`) |
| `flint:jackson-annotations` | `flint.jackson.annotation` | nothing (a leaf of UDA structs) |
| `flint:jackson-core` | `flint.jackson.core` | `serde` |
| `flint:jackson-databind` | `flint.jackson.databind` | `jackson-core`, `jackson-annotations`, `engine-aot`, `java` |
| `flint:jakarta-validation` | `flint.jakarta.validation` | `engine-aot`, `java` |
| `flint:hibernate-validator` | `flint.hibernate.validator` | `jakarta-validation`, `validate` |

## Annotations as UDAs

Rulebook R2 applies as written. A bare `@JsonIgnore` or `@NotNull` attaches the *type* in D, not a value, so everything that reads annotations, including Flint AOT (contract section 2), reads a type UDA as `X.init`. Java's element defaults are the field initializers, so `@Size(max: 30)` keeps `min = 0`, `message = "{jakarta.validation.constraints.Size.message}"`.

## Jackson

### Configuration Boot actually uses

Spring Boot 4.2's `JacksonAutoConfiguration` builds a `JsonMapper` with `findAndAddModules()` and changes no feature unless `flint.jackson.*` (alias `spring.jackson.*`) says so. Byte equality therefore means equality with Jackson 3.1.8's own defaults, which differ from Jackson 2's in ways that show in every response:

| Feature | Jackson 3 default | Effect on output |
| --- | --- | --- |
| `MapperFeature.SORT_PROPERTIES_ALPHABETICALLY` | **true** | properties are sorted by name (Java `String` order, UTF-16 code units) |
| `MapperFeature.SORT_CREATOR_PROPERTIES_FIRST` | true | creator properties come first, in creator order, then the rest alphabetically |
| `DateTimeFeature.WRITE_DATES_AS_TIMESTAMPS` | false | `java.time` values are ISO-8601 strings |
| `DateTimeFeature.WRITE_DURATIONS_AS_TIMESTAMPS` | false | `Duration` is `PT1H30M` |
| `EnumFeature.WRITE_ENUMS_USING_TO_STRING` | true | enums print their `toString`, which is the constant name unless overridden |
| `DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES` | false | unknown input properties are skipped |
| `DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES` | true | `null` for an `int` is an error |
| `JsonWriteFeature.ESCAPE_NON_ASCII` | false | non-ASCII is written as raw UTF-8 |
| `JsonWriteFeature.ESCAPE_FORWARD_SLASHES` | false | `/` is not escaped |
| `JsonWriteFeature.WRITE_NAN_AS_STRINGS` | true | `NaN` and the infinities are quoted strings |
| `StreamWriteFeature.USE_FAST_DOUBLE_WRITER` | false | doubles print through `Double.toString` |
| `StreamWriteFeature.WRITE_BIGDECIMAL_AS_PLAIN` | false | `BigDecimal.toString`, which may use an exponent |

### Property order

Jackson's `POJOPropertiesCollector._sortProperties` decides the order, and Flint ports it on top of the descriptor's Java-Beans properties:
1. `@JsonPropertyOrder` names first, in the order given;
2. then creator properties, in creator parameter order;
3. then the rest, alphabetically (or in declaration order with `@JsonPropertyOrder(alphabetic: false)` and the feature disabled).

The creator is chosen with Jackson 3.1.8's rules (`_addCreators`): an explicit `@JsonCreator`; else a constructor whose parameters all carry `@JsonProperty`; else a record's canonical constructor; else exactly one public non-default constructor whose parameters are all named, even next to a default constructor (`ConstructorDetector.DEFAULT` allows that in 3.x). Spring Boot compiles with `-parameters`, so Java parameter names are always available, as they are to Flint AOT.

**Records.** Rulebook R11 maps a Java record to a D struct. A struct with no explicit constructor is treated as a record: its canonical constructor is the field-wise one, so its properties print in declaration order. That matches `record Greeting(long id, String content)` → `{"id":1,"content":"Hello, World!"}`. Flint AOT emits that constructor as `constructors[0]` (requested from the flint-aot session).

### Numbers

`flint.serde.java_number` renders `Double.toString` and `Float.toString` as JDK 19+ does. It reuses serde's shortest-digits engine and adds the JDK's layout and its two-digit rendering of the smallest subnormals. It was checked against OpenJDK 21.0.13 on 11,986,636 values (random bit patterns, written decimals, integers and the specials) with no mismatch. Integers print in decimal, `BigDecimal` as `BigDecimal.toString`.

### Engine

Generic façades are one-liners over an erased engine (ADR-030 section 5): `readValue!T(json)` looks up `T`'s descriptor by its canonical name and calls `readValue(json, const Descriptor)`, which returns an `Any`. Serializers and deserializers are built once per descriptor and mapper configuration and cached in the mapper, as Jackson's `SerializerCache` does. No template is instantiated per user type beyond the one-line façade.

The streaming layer is `flint.jackson.core`'s `JsonGenerator` and `JsonParser`. Both enforce Jackson's stream constraints: `StreamReadConstraints` on reads, and `StreamWriteConstraints`' nesting limit (500) on writes, which stops an indirect cycle in an object graph with `StreamConstraintsException` ("Document nesting depth (501) exceeds the maximum allowed (500, …)") before the stack overflows. A direct self-reference fails earlier with Jackson's "Direct self-reference leading to cycle". Constraints are set per factory with `JsonFactoryBuilder.streamWriteConstraints`; the process-wide `overrideDefaultStreamWriteConstraints` is not ported (D-JACKSON-8). The generator writes to a caller-supplied sink, so the web layer's message converter can write straight into its response buffer. The parser tokenizes with serde's scanner rules and keeps Jackson's token model (`JsonToken`, `currentName`, `getNumberType`).

### Arrays, Optional, enums and records

Values whose descriptors carry the erased thunks (contract 2) serialize and deserialize through them:

- **Arrays and collections.** `length`/`element`/`fromElements` serve D arrays and element-built collections. `byte[]` and `ubyte[]` are Base64, as Jackson's `ByteArraySerializer` writes them, and also read from number arrays that wrap at 255.
- **Maps.** `toKeys`/`toValues`/`fromEntries` serve associative arrays. Keys convert as Jackson's `StdKeyDeserializer` converts them.
- **Optional.** `unwrap`/`wrap` serve `Optional!T` and `Nullable!T`. An empty optional writes `null`, and `null` reads back as empty.
- **Enums.** Enums read by name, by index or by a quoted index, through `enumValue`. Enum bits map back to constants through `enumValues`. The unknown-value message lists the names in `CompactStringObjectMap` order, as Jackson's does.
- **`@JsonAnyGetter`.** A map property marked `@JsonAnyGetter` writes its entries, in the map's iteration order, after the regular properties, and writes nothing when the map is null. It works with `RawMap` collections and associative arrays.
- **`@JsonNaming`.** `flint.jackson.databind.annotation.JsonNaming(classOf!(PropertyNamingStrategies.SnakeCaseStrategy))` overrides the mapper's strategy for one class. The seven standard strategies are bound. A custom strategy class raises `InvalidDefinitionException`, because Flint never constructs a class from its name (deviation D-JACKSON-7).
- **Records.** A constructor marked `canonical` is the record's creator unless another constructor carries `@JsonCreator`. A missing primitive creator argument fails under `FAIL_ON_NULL_FOR_PRIMITIVES`, which defaults to on in Jackson 3, with Jackson's message.

### java.time

`flint.jackson.databind.ext.javatime` ports Jackson 3's built-in java.time support (`tools.jackson.databind.ext.javatime`) over `flint.java.time`:

- **Writing.** By default values are ISO-8601 strings: `ISO_LOCAL_DATE`, `ISO_LOCAL_TIME` (seconds always printed, minimal fraction), `ISO_LOCAL_DATE_TIME`, `ISO_INSTANT`, `ISO_OFFSET_DATE_TIME`, and `ISO_OFFSET_DATE_TIME` for `ZonedDateTime` (`ISO_ZONED_DATE_TIME` with `WRITE_DATES_WITH_ZONE_ID`). `Duration` prints as `PT…`, and zone offsets and IDs as their IDs.
- **Timestamps.** `WRITE_DATES_AS_TIMESTAMPS` writes local values as arrays and instants as `DecimalUtils` decimals (`1700000000.005000000`, `5E-9`), or as milliseconds when `WRITE_DATE_TIMESTAMPS_AS_NANOSECONDS` is off. `WRITE_DURATIONS_AS_TIMESTAMPS` does the same for durations.
- **`@JsonFormat`.** `pattern` formats and parses with `DateTimeFormatter.ofPattern`. `shape` NUMBER or ARRAY forces timestamps, and STRING forces text.
- **Reading.** Reading accepts what Jackson accepts:
  - ISO strings, trimmed, with "" read as null;
  - an ISO date-time where a date or time is expected;
  - a trailing `Z` on a `LocalDateTime`;
  - epoch days for `LocalDate`;
  - decimal or integer epoch seconds for instants and durations, including digit-only strings for instants;
  - the timestamp arrays.

  Offset and zoned values are adjusted to the context zone, UTC (`ADJUST_DATES_TO_CONTEXT_TIME_ZONE`). Errors carry Jackson's messages, including the formatter description that Java's `DateTimeFormatter.toString` prints.
- **Zones.** Region zones need the time-zone database, which `flint.java.time` has not ported yet. Until then `ZoneId.of("Europe/Paris")` throws, and only UTC and fixed offsets work.

`flint.java.time` itself (framework-core owns it) is clean-room from the Java SE 21 specification. Its proof is `framework/java/tests/golden/time_format.tsv`: 542 format, parse and error results from JDK 21.

### java.util.Date

`flint.jackson.databind.stddateformat` ports Jackson's `java.util.Date` support (`JavaUtilDateSerializer`, `JavaUtilDateDeserializer`, `StdDateFormat`, and the Date map keys) over framework-core's `flint.java.util.Date`, `Calendar` and `TimeZone` and `flint.java.text.SimpleDateFormat`. Boot's error body carries its `timestamp` as a `Date`, so this is what the error path writes.

- **Writing.** By default a date is StdDateFormat's ISO-8601 text in UTC with exactly three fraction digits: `"2026-11-19T15:01:50.000Z"`. Years past 9999 get a `+`, and years before the Common Era are written as ISO years (`+0000` is 1 BC). `WRITE_DATES_AS_TIMESTAMPS` writes epoch milliseconds, and map keys follow `WRITE_DATE_KEYS_AS_TIMESTAMPS`.
- **`@JsonFormat`.** `shape` NUMBER writes milliseconds. A `pattern` formats with `SimpleDateFormat` in the annotation's `timezone`, or UTC, and so do `shape` STRING, `timezone` and `locale` without a pattern, with StdDateFormat. When reading, a pattern or time zone parses with that format, `lenient = FALSE` makes the calendar strict, and failures name the expected format as Jackson does.
- **Reading.** Reading accepts what StdDateFormat accepts:
  - ISO-8601 with or without seconds, fraction (up to nine digits) and offset;
  - plain dates;
  - extended years such as `+20100-01-01T00:00:00Z`;
  - RFC 1123 (`Sat, 17 Jan 2009 06:13:58 GMT`);
  - stringified timestamps.

  Fields out of range carry over like a lenient `GregorianCalendar` (`2010-13-45` is 2011-02-14). Integer tokens are milliseconds. `""`, blank strings and `"null"` read as null, and arrays follow `UNWRAP_SINGLE_VALUE_ARRAYS` and `ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT`. Errors carry Jackson's messages.
- **Calendar.** As upstream delegates to the JDK, `StdDateFormat` works through flint:java's `GregorianCalendar`, `TimeZone` and `SimpleDateFormat`. They are clean room from the Java SE specification and owned by framework-core (see framework-core.md). The calendar is Gregorian from 1582-10-15 and Julian before, as Java's is, so `-62135596800000` writes `0001-01-03`. Weeks follow the `en_US` rules, and two-digit years are read into the 80 years before and the 20 years after now.
- **Zones and locales.** Only UTC, GMT and fixed `GMT±hh:mm` zones resolve, and names are English (D-JACKSON-9).
- **Pay for use.** Plain writes are built in: ISO-8601 text, timestamps and map keys, with no calendar object, so a web app writing Boot's error timestamp links only those. Reading a `Date` and `@JsonFormat` pattern and time-zone writes live in `JavaUtilDateModule` (`flint.jackson.databind.module_`).
  - **Who registers it.** Flint AOT emits a `JsonMapperBuilderCustomizer` that adds it whenever the application's described types hold a `Date`, and the templated `ObjectMapper` methods (`readValue!T`, `convertValue!T`, `writeValueAsString!T`, ...) register it when `T` holds one.
  - **The exception.** Only a mapper built by hand over hand-added descriptors and used through the erased methods can lack it, and that throws `InvalidDefinitionException` naming `addModule(new JavaUtilDateModule())` (D-JACKSON-10).
  - **The Module API.** Jackson 3's `JacksonModule`, `JacksonModule.SetupContext`, `SimpleModule`, `JsonMapper.Builder.addModule`/`addModules` and `ObjectMapper.registeredModules` are ported for this.

### Byte-equality proof

The tests compare Flint's output with golden files that the real Jackson 3.1.8 wrote. `framework/jackson-databind/tests/golden/` holds the Java generator, run on OpenJDK 21 with the jars Boot 4.2.0 resolves, next to the JSON it produced. A test fails on any byte difference. The generator source is committed so anyone can regenerate the files.

## SLF4J

- **Arguments.** `Logger.info(String format, Object... arguments)` and its fixed-arity overloads are `(Args...)` façades (rulebook R7). They check the level first and only then box the arguments into `Any[]` on the stack, so a disabled call allocates nothing.
- **Formatting.** `MessageFormatter` is ported as written: `{}` anchors, `\{}` escapes, `\\{}` double escapes, a trailing `Throwable` argument becomes the event's throwable, and arrays print as `[a, b]`. Arguments print as Java's `String.valueOf` would: `null`, `true`, `Double.toString`, the enum constant name, and `Class: message` for throwables.
- **MDC.** `MDC` is backed by `shared FiberLocal!MdcContext` (ADR-030 section 4), so every handler fiber has its own map, as a virtual thread has its own `ThreadLocal`. The context map is copy-on-write, so a `LoggingEvent` keeps a stable snapshot.
- **Providers.** Java finds an `SLF4JServiceProvider` with `ServiceLoader`. Flint's closed world installs one explicitly with `LoggerFactory.installProvider` (deviation D-SLF4J-1). That's the hook Boot's logging system uses for its console format. Without a provider, the default writes through the `flint.log` engine, where Java's default would be the NOP logger.
- **Boot's format.** Boot's default console pattern needs the timestamp, level, PID, thread, logger name, message and throwable. `LoggingEvent` (from `org.slf4j.event`) carries all of these to the provider, so the format itself is the Boot session's to write.

## Jakarta Validation and Hibernate Validator

- **API.** `flint.jakarta.validation` ports the API: `Validator`, `ValidatorFactory`, `Validation`, `ConstraintViolation`, `ConstraintValidator`, `ConstraintValidatorContext`, `Path`, `@Valid` and `@Constraint`, plus the constraint UDAs in `.constraints`.
- **Implementation.** `flint.hibernate.validator` ports Hibernate Validator's implementation: the built-in validators, `ResourceBundleMessageInterpolator` semantics over the English `ValidationMessages.properties`, and the path and violation model.
- **Engine.** Text checks reuse the `flint.validate` engine (`NotBlank` whitespace, scalar counts for `@Size`, the e-mail grammar, the regular-expression automaton) through an engine-facing module, not its internals.
- **Temporal constraints.** `@Past`, `@PastOrPresent`, `@Future` and `@FutureOrPresent` validate `Instant`, `LocalDate`, `LocalDateTime`, `LocalTime`, `OffsetDateTime` and `ZonedDateTime` against the system clock (UTC), with Hibernate's zero tolerance. Any other type raises HV000030.
- **Custom constraints.** A constraint annotation is a UDA struct marked `@Constraint(validatedBy: [classOf!V])`. Its validator class implements `ConstraintValidator!(A, T)`. Flint never constructs a class from its name, so the application binds the validator with Hibernate's programmatic API: `config.createConstraintMapping().constraintDefinition!A().validatedBy!V()`, then `addMapping`. `validatedBy` instantiates a small erased adapter where the binding is written. The context supports `disableDefaultConstraintViolation` and `buildConstraintViolationWithTemplate(...).addConstraintViolation()`, with Hibernate's ordering (the default violation first) and HV000033. An annotation whose descriptor carries `@Constraint` with no binding raises HV000030.
- **Patterns.** Jakarta `@Pattern` (run-time patterns) accepts `\p{L}` and `\P{L}` (also `\pL`, `\p{IsL}`, `\p{IsLetter}`), as `java.util.regex` matches them. The letter table is generated from JDK 21's `Character.getType` (`packages/validate/tools/GenLetters.java`). `\s`, `\S` and `[\s\S]` follow Java's ASCII whitespace. The engine's own compile-time `@Pattern` still rejects Unicode property escapes, as its specification requires.
- **Containers.** `@Size` and `@NotEmpty` count D arrays and associative arrays through their descriptors. `@Valid` cascades into array elements (`petArray[0].type`), map values (`petsByName[tom].type`) and an `Optional`'s value (`maybePet.name`). A D array is never null for `@NotNull`/`@Null`, since `[]` is null (as D-JACKSON-6).
- **Numbers.** The number constraints follow the validator Hibernate picks for each type: `@Min`/`@Max` compare a `long` exactly with the `long` bound, a `float` with `Float.compare` and a `double` with `Double.compare` (so `-0.0` is below `0`, and `@Negative` accepts it); `@DecimalMin`/`@DecimalMax` compare exactly in decimal (`BigDecimal.valueOf(double)` for floating point, so `0.1` is below `0.100000000000000005`). A `String` is `new BigDecimal(text)`: no whitespace, and an unparsable one is invalid rather than HV000030. `@Digits` counts `Float.toString` digits for a `float`, strips trailing zeros for numbers and keeps them for a `String`. `flint.hibernate.validator.internal.decimal` does the decimal arithmetic on text, since `flint.java` has no `BigDecimal`.
- **Initialize checks.** Attributes Hibernate's `initialize` rejects fail with its HV000032, naming the validator class, with the `IllegalArgumentException` cause: HV000016 (a `@DecimalMin`/`@DecimalMax` value that isn't a `BigDecimal`), HV000017/HV000018 (negative `@Digits` lengths), HV000019 to HV000021 (`@Size` bounds) and HV000022 (a malformed `@Pattern`). `@Digits` on `NaN` or an infinity raises HV000028 with `BigDecimal`'s `NumberFormatException`.
- **Run-time patterns.** `@Pattern` (and `@Email`'s `regexp`) run on `flint.hibernate.validator.internal.regex`, a clean-room `java.util.regex` engine written from the `Pattern` Javadoc (OpenJDK is not in the licence matrix): classes with intersection, the predefined, POSIX and `\p{L}` classes, groups (named, atomic), look-ahead and look-behind, back-references, greedy, reluctant and possessive quantifiers (counted ones unrolled up to 100,000 instructions), anchors and `\b`, inline flags and `Pattern.Flag`'s `UNIX_LINES`, `CASE_INSENSITIVE`, `COMMENTS`, `MULTILINE` and `DOTALL`. `tests/golden/regex.tsv` records JDK 21's result for 367 (pattern, flags, input) cases and every one agrees, except three features that raise "not supported yet" instead of answering: `UNICODE_CASE` with `CASE_INSENSITIVE`, `UNICODE_CHARACTER_CLASS`, and `\N{name}` (also Unicode properties other than letters, `\X`, `CANON_EQ`). Such a pattern fails with HV000032; a malformed one with HV000022, as Hibernate does. The matcher backtracks on an explicit stack (input length never deepens the call stack) and stops after 20,000,000 steps (D-VALIDATION-3), raising HV000028.
- **Messages.** The default messages are Hibernate Validator's English bundle, interpolated with its rules: `{min}`-style parameters, and the `${validatedValue}` and ternary expression subset that the built-in messages use. Templates go through a port of Hibernate's tokenizer (`TokenCollector` and its parser states): `$` is text in the parameter pass (`${min}` gives `$0`), backslash escapes the next character, and a template with an unbalanced or nested brace (HV000168, HV000169) comes back unchanged, as Hibernate logs and returns it.

## Deviations

| ID | Deviation | Reason |
| --- | --- | --- |
| D-JACKSON-1 | Java's `null` `JsonToken` (no token, end of input) is `JsonToken.NOT_AVAILABLE` | A D enum has no null; blocking parsers never otherwise report `NOT_AVAILABLE` |
| D-JACKSON-2 | `JsonNode.properties()`, `propertyNames()` and `values()` return D arrays | Cheaper than `flint.java.util` sets; R10 allows conversion |
| D-JACKSON-3 | `JsonMapper.Builder.changeDefaultPropertyInclusion(valueInclusion, contentInclusion)` takes the two settings instead of an operator over `JsonInclude.Value` | `JsonInclude.Value` is not ported; Boot sets exactly these two |
| D-JACKSON-4 | `JsonFormat.with` is `with_` | `with` is a D keyword |
| D-JACKSON-5 | Generators write to an `OutputSink` delegate (or a `ByteArrayBuilder`) | Stands in for `java.io.OutputStream` (R9) |
| D-JACKSON-7 | `@JsonNaming` binds only `PropertyNamingStrategies`' standard strategies | No construction from a class name (closed world); a custom strategy needs an explicit binding API first |
| D-JACKSON-6 | A null D array writes as `[]` (`""` for Base64 `byte[]`), not `null` | D's `[]` is null; an empty array and a null one can't be told apart |
| D-JACKSON-8 | `StreamWriteConstraints.overrideDefaultStreamWriteConstraints` is not ported, and `Builder.maxNestingDepth(-1)` throws `Exception`, not `IllegalArgumentException` | Framework packages keep no mutable module-level state; jackson-core does not depend on `flint.java` |
| D-JACKSON-9 | A `java.util.Date` `@JsonFormat` `timezone` must be UTC, GMT or a fixed `GMT±hh:mm` offset; any other ID throws `InvalidDefinitionException` instead of falling back to GMT as `TimeZone.getTimeZone` does. Dates format and parse with English names, and a pattern with names in a non-English `locale` throws | Region zones need the time-zone database, which Flint has not ported; refusing is safer than writing a wrong offset. Non-English names would need locale data |
| D-JACKSON-10 | `java.util.Date` reading and `@JsonFormat` pattern and time-zone writes are in `JavaUtilDateModule`, which Flint AOT's generated customizer and the templated `ObjectMapper` methods register; a hand-built mapper used through the erased methods without it throws `InvalidDefinitionException`. `JacksonModule.version()` is not ported, `getRegistrationId` returns a string, and `SimpleModule`'s serializer and deserializer registries are not ported yet. When `readerFor` or `TypeReference` are ported, they must register the module the same way the templated methods do, with tests (full entry in api-mapping.md) | Jackson builds Date support into every mapper; in Flint that would link about 70 KB of calendar and parsing into every web app, which only writes Dates. Spring code reaches Jackson through the templated methods or Boot's mapper, both of which register it |
| D-SLF4J-1 | `LoggerFactory.installProvider` binds a provider; the default writes through `flint.log` | Closed world: no `ServiceLoader`; Java's default would be the NOP logger |
| D-SLF4J-2 | `Logger.debug` is `debug_` | `debug` is a D keyword |
| D-VALIDATION-1 | Hibernate Validator registers itself with `Validation` when linked in | Replaces `META-INF/services` discovery |
| D-VALIDATION-2 | `ConstraintViolation<T>` is erased: beans and values are `Any`, classes are Flint type names | Erased core (ADR-030 section 5, R4) |
| D-VALIDATION-3 | A `@Pattern` match stops after 20,000,000 steps with HV000028 | Java's backtracking has no bound; a request thread must not hang on a catastrophic pattern (ReDoS) |

## Evidence

All commands run from the repository root with the toolchain on `PATH`.

| Check | Command | Result |
| --- | --- | --- |
| Java number text | `java Gen` (JDK 21.0.13) then the D comparer, two seeds | 11,986,636 values, 0 mismatches |
| Jackson streaming | `dub test :jackson-core --compiler=dmd` and `=ldc2` | 10 golden files byte-equal; 33 ported upstream cases |
| Jackson databind | `dub test :jackson-databind --compiler=dmd` and `=ldc2` | 21 golden files byte-equal; TestNamingStrategyStd's tables |
| Jackson shapes | same | `shapes.tsv`: arrays, `byte[]` (Base64), `Optional`, maps, enums (including Jackson's key order in the unknown-value message), records and `@JsonNaming`, 9 writes and 20 reads identical |
| petclinic-rest DTOs | same | `petclinic.tsv`: 14 response bodies recorded from the real spring-petclinic-rest (Boot 4.2.0) read into D twins of its openapi-generator DTOs and write back byte for byte, plus a `ValidationMessageDto` with its `@JsonAnyGetter` map |
| Jackson java.time | same | `javatime.tsv`: 23 writes and 59 reads (values and messages) identical to Jackson 3.1.8 |
| Jackson java.util.Date | same | `dates.tsv`: 1,172 cases, all identical to Jackson 3.1.8 except one it refuses (D-JACKSON-9). They cover writes across the Julian/Gregorian cutover, BCE and five-digit years; 80 `SimpleDateFormat` patterns; ISO-8601, RFC 1123 and timestamp reads, with error messages; strict and lenient calendars; and map keys |
| java.time | `dub test :java --compiler=dmd` and `=ldc2` | `time.tsv` and `time_format.tsv` identical to JDK 21; epoch days walked over 1600–2400 |
| Jackson annotations | `dub test :jackson-annotations --compiler=dmd` and `=ldc2` | defaults and shorthand |
| SLF4J | `dub test :slf4j-api --compiler=dmd` and `=ldc2` | MessageFormatterTest, BasicMarkerTest, MDCAdapterTestBase ported; logger behaviour |
| Validation | `dub test :jakarta-validation` and `:hibernate-validator`, both compilers | 45 violations identical to Hibernate Validator's: `@Past`/`@Future` on java.time, `@Size`/`@NotEmpty` on arrays and maps, `@Valid` into arrays, maps and `Optional`, spring-petclinic-rest's `@Pattern` expressions (`\p{L}`) on non-ASCII input and its `PetAgeValidator` custom constraint |
| Annotations | `dub test :jakarta-annotation`, both compilers | defaults, repetition |
| ProcessSlot | `dub test :conc`, both compilers, and LDC `-fsanitize=thread` | no reports |
| Structure | `python3 tools/gates.py --gate structural`; `python3 -m unittest test_guards` (in `tools/`) | pass; the framework-layer tests pass |
| Lint | `python3 tools/quality.py --path framework/<module>/source` | 0 issues for every module |
| API | `flint api coverage --repo framework` | jakarta-annotation, jackson-core, jackson-databind, jackson-annotations, slf4j-api, jakarta-validation and hibernate-validator at 100% classified |

The classification is name-based: an element counts as ported when the Flint module declares its type and member name, so overload-level gaps (for example the `BigDecimal` overloads) show up as deferred only when the name itself is missing.

## Pending, with their owners

- **framework-core and third-party-apis: `flint.java.util.regex`.** The engine exists as `flint.hibernate.validator.internal.regex`; the public `Pattern`/`Matcher` API in `framework/java` and the Unicode categories, `UNICODE_CASE` and `UNICODE_CHARACTER_CLASS` remain (`decisions.md`, 2026-11-23, third-party-apis, item 26's regex finding).
- **framework-core (`flint:engine-aot`, `flint:java`):**
  - descriptor access for D arrays, `Optional!T` and enum values (`Any` can't build an enum from a type name);
  - `create()` on the descriptors of `ArrayList!T`, `HashSet!T` and `LinkedHashMap!(K, V)`;
  - `@safe` equality and hash on `Any`, so `flint.java.util` collections can hold it;
  - the time-zone database for region `ZoneId`s.

  `flint.java.time` and `ClassRef` have landed. Jackson now covers D arrays, associative arrays, `Optional`, enum reading, record canonical constructors and `@JsonNaming`. Validation still lacks groups and custom constraints.
- **flint-aot:**
  - a record's field-wise constructor as `constructors[0]` for structs;
  - descriptors for the concrete collection types of collection-typed properties.
- **web-mvc:** the message converter calls `ObjectMapper.writeValue(OutputSink, Any)` and `readValue(const(ubyte)[], string type)`.
- **boot:** `JacksonAutoConfiguration` builds `JsonMapper.builder().descriptors(table)` and maps `flint.jackson.*` keys onto the builder. The logging system calls `FlintLogServiceProvider.loggers().setLevel(...)` and `setAppender(...)` for `logging.level.*` and the console pattern.

## Status

| Module | State |
| --- | --- |
| `flint.jakarta.annotation` | on `main` (EPL-2.0 module) |
| `flint.serde.java_number`, `flint.serde.json_read`, `flint.validate.patterns`, `flint.conc.slot` | on `main` (engine additions) |
| `flint.jackson.annotation` | on `main` |
| `flint.jackson.core` | on `main`, byte-equal with Jackson 3.1.8 |
| `flint.jackson.databind` | on `main`, byte-equal with Jackson 3.1.8 under Boot's default mapper |
| `flint.slf4j` | on `main` |
| `flint.jakarta.validation`, `flint.hibernate.validator` | on `main`, messages identical to Hibernate Validator 9.1.6 |
