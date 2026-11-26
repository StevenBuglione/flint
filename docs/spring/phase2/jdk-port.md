# Porting the Java standard library to D (pay only for what you use)

The owner decided on 2026-11-26 to port the parts of the Java SE standard library that Spring code and Spring applications use. It's a one-time tax that every later port draws on. Four gpt-6.2-sol lanes do it (sol-jdk-*), under [porting-guide.md](porting-guide.md) and the rules on this page. Those rules are stricter than a normal module's, because every Flint application links this code.

## Target and licence

- **API:** Java SE 21, the release `flint:java` already uses for its Unicode tables. Later additions (Java 25) are added only when Spring v7.1.0 or Boot v4.2.0 code calls them. Names follow rulebook R1: `java.util.HashMap` becomes `flint.java.util.HashMap`.
- **flint.java is ported from OpenJDK (owner, 2026-11-26 04:30Z).** Every `flint:java*` package is GPL-2.0-only WITH Classpath-exception-2.0, like OpenJDK, and declares that licence in its `dub.sdl`, with its own LICENSE and NOTICE (checked by the structural gate, 5650649a). Port OpenJDK implementations and jtreg tests from source, keeping each file's header and adding "Modified by the Flint authors". Spring and Apache-2.0 code use these packages freely, because the Classpath Exception covers linking. Never mix Apache-2.0-derived files into a `flint:java*` package.
- **Apache Harmony is not used.** Its few derived files have been replaced by OpenJDK ports or original code. Don't port new Harmony code or tests.
- **Unicode and IANA tz data** are data under their own licences. Generate them into tables with a checked-in generator, as `framework/java/tools/GenCharacter.java` already does.
- **Tests:**
  - OpenJDK's jtreg tests where they apply;
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
   - `flint:java-util` owns the `flint:conc` dependency for UUID entropy. Import its utility leaves directly so `flint:java` can remain below them.
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
- **The declared closure** lists the leaves and data each probe may pull in. New probe records live in separate files so lanes can add them independently.
- **Wiring:** a step in the module definition of done for every `flint:java*` package, plus a structural-gate check for the banned imports.
- **Size measurement:** loadable section bytes using the same ELF calculation as the package budget. The count includes `.bss` and excludes per-thread `.tbss` (decisions.md, 2026-11-26 01:20Z and 02:47Z).
- **Budgets** (`jdk-leaf-rule`, decisions.md 2026-11-26 01:45Z): each leaf has its own budget, set at the measured value plus 10% and only shrinking afterwards. A package budget is the sum of its leaves; adding a leaf raises it by exactly that leaf's budget, with the trailer `Budget-Raise-Approved: jdk-leaf-rule`.

Run `python3 tools/gates.py --module framework/java --definition-of-done --step link-closure` on the Linux ELF
runner. The audit uses `dub`, `ldc2`, `readelf` and `nm`. For investigation, run
`python3 tools/jdk_link_closure.py --package java --evidence <directory>` to retain linker maps and build logs.
GNU ld's archive records identify the referring object and symbol for retained Phobos families when available.
On venus, run both commands under the measurement queue's hold wrapper.

Add each new record under `closure-probes/<D leaf module>/<probe-name>.json` in its package directory.
The fully qualified D module names the leaf, and the file stem is the probe name. The JSON object has a
package-relative `source` under `closure/` or `bench/`, a `leaves` list of other modules the probe may retain,
and a `data` list. The probe's own leaf is implicit.

Existing `closure.json` files use schema `flint.jdk-closure/1` and map each leaf to named records under
`probes`. The gate reads both layouts and requires each leaf and probe name pair and each source fixture
to be unique in a package. When moving a record to its own file, remove the old entry in the same commit
and keep its leaf and probe name so its closure history stays intact.

Put new table-only modules under a `.data` component so the gate can identify their symbols. Write separate
probes for common operations and operations that intentionally need optional data. Use runtime input to exercise
the operation.

The initial JDK packages' existing violations are recorded in
[`framework/java/closure-baseline.json`](../../../framework/java/closure-baseline.json). The structural and
link-closure checks reject new violations and require stale entries to be removed. A new probe whose declared
closure needs the legacy `flint.java.lang` aggregate may seed the initial baseline's known module records in the
same commit as the probe (decision `523bd5bd`). Retained code, tables and banned Phobos have separate diagnostics.
The release check fails with any violation still present.

## Lanes

| Role | Owns | Order |
|---|---|---|
| `sol-jdk-core` | the link-closure gate; `flint:java` (lang) and `flint:java-collections` | 1. The gate. 2. Split today's `flint:java` into leaves without changing public names (framework-core reviews; it owns `flint:java`). 3. Collections faithful to Java (live views, orders, CME), plus `Arrays`, `Collections`, `Objects`, `Optional*`, streams and functions |
| `sol-jdk-time-text` | `flint:java-time`, `flint:java-text`, `Locale` | `java.time` with a tzdb data leaf, then `java.time.format`, then `java.text` |
| `sol-jdk-math-regex` | `flint:java-math`, `flint:java-regex`, `UUID`, `Base64`, `HexFormat` | `BigInteger` and `BigDecimal` (ported from OpenJDK), then a Java-semantics regex engine |
| `sol-jdk-concurrent-io` | `flint:java-concurrent`, `flint:java-io`, `flint:java-net`, `flint:java-security` (OpenSSL wrappers only) | concurrency on fibers and the offload pool, then io, nio and charset, then net, then the security facades |

**Reviewers:**
- framework-core: anything in `flint:java`, and any change to existing Spring modules that switch to the new leaves;
- data-access: `ExecutorService` and offload integration;
- web-http: anything on a request path;
- m7: the closure gate and policy registration.

**Phase 2 lanes that need a JDK type** first check whether a `sol-jdk-*` lane has it. If not, they ask that lane through agentctl, and use what exists meanwhile. Spring modules move to the new leaves gradually, each change checked by the apps' allocation gates and acceptance.
