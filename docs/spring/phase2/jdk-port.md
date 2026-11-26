# Porting the Java standard library to D (pay only for what you use)

The owner decided on 2026-11-26 to port the parts of the Java SE standard library that Spring code and Spring applications use. It's a one-time tax that every later port draws on. Four gpt-6.2-sol lanes do it (sol-jdk-*), under [porting-guide.md](porting-guide.md) and the rules on this page. Those rules are stricter than a normal module's, because every Flint application links this code.

## Target and licence

- **API:** Java SE 21, the release `flint:java` already uses for its Unicode tables. Later additions (Java 25) are added only when Spring v7.1.0 or Boot v4.2.0 code calls them. Names follow rulebook R1: `java.util.HashMap` becomes `flint.java.util.HashMap`.
- **OpenJDK is GPL-2.0 with the Classpath Exception, so it's clean-room only** (ADR-030 section 6, `policy/upstream-licences.json`):
  - Implement from the Java SE API specification's behaviour, never from OpenJDK source.
  - Never copy OpenJDK code, Javadoc prose, or jtreg tests.
  - Public API names and signatures may be extracted for the API manifest. That is interface information, not implementation (*Google v. Oracle*).
  - Write DDoc in your own words.
- **Apache Harmony (Apache-2.0) may be ported from source,** with its header kept and "Modified by the Flint authors" added. It covers roughly Java 6. Port its tests where they still match Java 21 behaviour, and record them in `upstream-tests.json`.
- **Unicode and IANA tz data** are data under their own licences. Generate them into tables with a checked-in generator, as `framework/java/tools/GenCharacter.java` already does.
- **Tests:**
  - Harmony's tests where they apply;
  - original tests written against the specification;
  - Spring's own tests that exercise these classes.

  Original tests are reported as Flint tests.

## Scope

**In scope:**
- **`java.lang`:** boxed types with parse and format, `Math`, `StrictMath`, `StringBuilder`, `Character`, `CharSequence`, `Comparable`, `Iterable`, `AutoCloseable`, `Runnable`, `Thread` facades over fibers, `ThreadLocal` over `FiberLocal`, and the exception hierarchy. No reflection.
- **`java.util`:**
  - every collection, with live views where Java has them;
  - `Arrays`, `Collections`, `Objects`, `Optional*`, `Iterator`, `Spliterator`;
  - `BitSet`, `EnumMap`, `EnumSet`, `PriorityQueue`, `ArrayDeque`, `TreeMap`, `TreeSet`, `IdentityHashMap`, `WeakHashMap` (GC weak references);
  - `StringJoiner`, `UUID`, `Base64`, `HexFormat`, `Random`, `SplittableRandom`, `Locale` (data-driven, root plus English first), `Properties`, `Scanner`, `Formatter`;
  - `java.util.function` and `java.util.stream`, as a range facade with Java's names (R10).
- **`java.util.concurrent`:**
  - `ConcurrentHashMap`, `ConcurrentLinkedQueue`, the blocking queues, `CopyOnWrite*`;
  - atomics and `locks`;
  - `ExecutorService` and `ScheduledExecutorService` on fibers and the offload pool;
  - `CompletableFuture`, `CountDownLatch`, `Semaphore`, `TimeUnit`.
- **`java.time`:** the whole package, with tzdb as a separate data module, plus `java.time.format`.
- **`java.text`:** `NumberFormat`, `DecimalFormat`, `MessageFormat`, `ChoiceFormat`, `SimpleDateFormat`, `BreakIterator` (basic) and `Normalizer`.
- **`java.math`:** `BigInteger`, `BigDecimal`, `MathContext`, `RoundingMode`.
- **`java.util.regex`:** Java-semantics `Pattern` and `Matcher`, as a D engine. `std.regex` stays banned.
- **`java.io` and `java.nio`:**
  - streams, readers and writers, the buffered and byte-array variants, `PrintStream`, `PrintWriter`;
  - `java.nio.charset`, `ByteBuffer` and friends, and `java.nio.file` (`Path`, `Paths`, `Files`) over `flint:os`.
- **`java.net`:** `URI`, `URL` (parsing only), `URLEncoder`, `URLDecoder`, `InetAddress` and `InetSocketAddress` (resolution through the engines).
- **`java.security` and `javax.crypto`:** `MessageDigest`, `SecureRandom`, `Mac`, `KeyGenerator` and the cipher facades, **only as thin wrappers over the pinned OpenSSL.** No new cryptographic algorithm (`AGENTS.md`).
- **`java.util.zip`:** `CRC32`, `Deflater`, `Inflater` and the GZIP streams, over the pinned zlib.

**Excluded** (classified `excluded` with these reasons):
- UI and desktop: AWT, Swing, JavaFX, `java.awt.*`, `javax.swing.*`, `java.applet`, `javax.imageio`, `javax.print`, `javax.sound`. Flint's desktop engines replace them.
- Runtime reflection and class loading: `java.lang.reflect` (beyond what descriptors cover), `ClassLoader`, `java.lang.invoke` (runtime), `java.lang.instrument`, `java.lang.module`, `ServiceLoader` (Flint wires services at build time).
- Java serialization: `java.io.Serializable` machinery, `ObjectInputStream`, `ObjectOutputStream`.
- The rest of the JVM-only stack:
  - RMI, CORBA, JNDI, JMX (`java.lang.management`, `javax.management`), JFR;
  - `SecurityManager` and the policy APIs;
  - `javax.script`, `javax.tools`, `java.compiler`;
  - JVM-specific `sun.*` and `jdk.*` internals.
- `java.util.logging`: SLF4J and Flint's logging cover it.
- `java.sql`: already ported in `flint:java` for JDBC; it is extended only where `framework/jdbc` needs it.

## The pay-for-what-you-use rules

These exist because of what Phase 1 and the first Phase 2 slices measured:
- importing `flint.java.lang` cost about 440 template instances (sol-jpa);
- `std.uni` and `core.time.dur` dragged 300–450 KB of Phobos (`std.net.curl`, `std.socket`, regex, zip) into every probe (framework-core, S-9);
- one call to `equalsIgnoreCase` linked 21 KB of case tables into gs-rest.

Every JDK module must satisfy all eight rules.

1. **One leaf module per type family,** for example `flint.java.util.hashmap` or `flint.java.time.localdate`.
   - The package module (`flint.java.util`) only publicly imports its leaves, so Java-style imports keep working.
   - Framework and engine code imports the leaves, never the package module.
   - A leaf imports only the leaves it really uses.
2. **Separate DUB packages per area:** `flint:java` (lang and the core util interfaces), `flint:java-collections`, `flint:java-util` (UUID, Base64, HexFormat and other small java.util value types that are not collections), `flint:java-concurrent`, `flint:java-time`, `flint:java-text`, `flint:java-math`, `flint:java-regex`, `flint:java-io`, `flint:java-net`, `flint:java-security`.
   - A module depends only on the packages it uses.
   - Dependencies run one way: `flint:java` sits at the bottom, and nothing in it imports another `flint:java-*` package.
3. **Erased engine, thin typed facade** [B-1]:
   - generic collections are one non-template engine per shape, driven by a small descriptor (size, hash, equals, copy);
   - `HashMap!(K, V)` is a facade of a few lines;
   - a new element type must add almost no code.
4. **Big data is reached only from the functions that need it.** Unicode, tz, locale and case tables live in their own data leaves.
   - Common functions take an ASCII or fast path that never references the tables. `equalsIgnoreCase` on ASCII must not link the case tables.
   - Tables are immutable `static immutable` data in `.rodata`, compact (packed runs, not 16-byte entries), built by a checked-in generator.
   - No module constructors that build tables.
5. **No heavy Phobos.** `std.format`, `std.conv`, `std.uni`, `std.regex`, `std.socket`, `std.net`, `std.process`, `std.file`, `std.path`, `std.datetime`, `std.json`, `std.parallelism` and `std.concurrency` are banned in `flint:java*`. So are `core.time.dur!"..."` instantiations at run time; use compile-time constants.
6. **Engines are `nothrow @nogc` where Java's contract allows it.** User-visible objects are GC objects. Exceptions are thrown only at the Java boundary, with no backtrace for control-flow exceptions [R-11].
7. **Request-path behaviour is allocation-tested.** A collection operation that Java performs without allocating (`get`, `containsKey`, iteration of a `List`) allocates nothing in Flint.
8. **Fidelity over shortcuts.** Where Java specifies behaviour, Flint matches it:
   - iteration order;
   - live views;
   - `ConcurrentModificationException` on detectable misuse;
   - `HashMap` resize semantics where they're observable;
   - `BigDecimal` scale rules;
   - `String.format` conversions;
   - regex flags.

   The existing `flint:java` deviations (insertion-ordered `HashMap`, snapshot views) are fixed, or justified with a measured reason in the rulebook.

## The link-closure gate (built first)

Rules 1, 4 and 5 are enforced by a check, not by review. `sol-jdk-core` builds it as its first deliverable, with m7 reviewing the tool and framework-core reviewing the `flint:java` side.
- **What it checks:** for each JDK leaf, a probe program that uses only that leaf's public API, built with the release profile (O3 and Oz, ThinLTO, as `measure_builds` builds probes). Its **linker map** must contain:
  - no symbol from a banned Phobos family;
  - no symbol from a `flint.java*` leaf that isn't in the leaf's declared closure;
  - no data table that isn't declared for that leaf.
- **The declared closure** lives in a small checked-in file per package, for example `framework/java-collections/closure.json`, which lists the leaves each leaf may pull in.
- **Wiring:** a step in the module definition of done for every `flint:java*` package, plus a structural-gate check for the banned imports.
- **Size measurement:** loadable section bytes, not file size (decisions.md, 2026-11-26 01:20Z).
- **Budgets** (`jdk-leaf-rule`, decisions.md 2026-11-26 01:45Z): each leaf has its own budget, set at the measured value plus 10% and only shrinking afterwards. A package budget is the sum of its leaves; adding a leaf raises it by exactly that leaf's budget, with the trailer `Budget-Raise-Approved: jdk-leaf-rule`.

## Lanes

| Role | Owns | Order |
|---|---|---|
| `sol-jdk-core` | the link-closure gate; `flint:java` (lang) and `flint:java-collections` | 1. The gate. 2. Split today's `flint:java` into leaves without changing public names (framework-core reviews; it owns `flint:java`). 3. Collections faithful to Java (live views, orders, CME), plus `Arrays`, `Collections`, `Objects`, `Optional*`, streams and functions |
| `sol-jdk-time-text` | `flint:java-time`, `flint:java-text`, `Locale` | `java.time` with a tzdb data leaf, then `java.time.format`, then `java.text` |
| `sol-jdk-math-regex` | `flint:java-math`, `flint:java-regex`, `UUID`, `Base64`, `HexFormat` | `BigInteger` and `BigDecimal` (Harmony-derived where it helps), then a Java-semantics regex engine |
| `sol-jdk-concurrent-io` | `flint:java-concurrent`, `flint:java-io`, `flint:java-net`, `flint:java-security` (OpenSSL wrappers only) | concurrency on fibers and the offload pool, then io, nio and charset, then net, then the security facades |

**Reviewers:**
- framework-core: anything in `flint:java`, and any change to existing Spring modules that switch to the new leaves;
- data-access: `ExecutorService` and offload integration;
- web-http: anything on a request path;
- m7: the closure gate and policy registration.

**Phase 2 lanes that need a JDK type** first check whether a `sol-jdk-*` lane has it. If not, they ask that lane through agentctl, and use what exists meanwhile. Spring modules move to the new leaves gradually, each change checked by the apps' allocation gates and acceptance.
