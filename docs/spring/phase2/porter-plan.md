# The mechanical porter: plan and correctness gate

Owner direction, 2026-11-27: reduce the manual porting work to a science. The port then finishes much faster and uses far fewer AI credits, and a verifiable gate proves the porter correct, performance included. The coordinator's decision entry of the same date records this. The porter grows out of `flint port-spring` (tools/port-spring, rulebook v2), owned by sol-translator.

## Why now

Of the 48,406 Phase 2 Spring and third-party elements still deferred on 2026-11-27, the shapes break down as follows. Counted from api/*/mapping.json, keys of deferred elements, by signature:

| Shape | Elements | Share | Porter |
|---|---|---|---|
| Getters (`get*`/`is*`/`has*`, no arguments) | 7,780 | 16% | mechanical |
| Type declarations | 7,717 | 16% | mechanical, given the type's port plan (below) |
| Constructors | 5,640 | 12% | mostly mechanical: field assignment, `super(...)` and `this(...)` forwarding |
| Setters (`set*`, one argument) | 4,837 | 10% | mechanical |
| Fields, constants, annotation attributes | 3,498 | 7% | mechanical |
| `equals`, `hashCode`, `toString` | 797 | 2% | mechanical under R11 |
| Other method bodies | 18,137 | 38% | skeleton plus a lane-written body, until a statement form has a rule |

The JDK's about 14,900 in-scope remaining members follow the same split. Today's translator handles only a few of these shapes: annotations, plain enums, marker interfaces, constant holders and message-forwarding exceptions. Lanes hand-write everything else, including the 62% that is mechanical.

## What the porter does

1. **Port plan per type** (`api/port-plan/<upstream>.json`). The decisions a lane makes per type today, recorded as data the porter reads:
   - the D kind: struct, final class, class, interface, abstract class, enum or UDA;
   - erased or templated storage;
   - whether a GC-free path is required;
   - the destination module;
   - the rules with their IDs.

   Seed it from the existing 12,000 mapped elements, which already record these decisions. For a mechanical shape, a lane edits the plan, not D code.
2. **Declarations and mechanical bodies**, in order of yield:
   - (a) getters, setters, fields and `@ConfigurationProperties` classes (most of Boot's 13,000 deferred elements);
   - (b) type declarations from the plan, and trivial constructors;
   - (c) the R11 `equals`/`hashCode`/`toString` mixin, records as structs and R12 builders;
   - (d) R8 exception families with every constructor shape and the cause lifecycle (decisions of 2026-11-26/27);
   - (e) R15 enums with fields, constructors and constant bodies, and R3 interface statics and defaults.

   With every module it also writes:
   - DDoc from the Javadoc;
   - licence headers per the licence matrix;
   - mapping rows carrying `"generated": "<porter version>"` provenance.
3. **Skeleton mode** for every other body. The porter writes the whole module: every signature, mapping row, DDoc, header and test stub. Each body it can't translate becomes a marked region (`// port:body <element-id>`) holding `assert(0, "port:body <element-id>")`, and its mapping row stays deferred until a lane fills it. Lanes write only the marked bodies. **No placeholder lands on main** (coordinator, 2026-11-27 21:05Z): the porter gate fails on any `port:body` region still holding its `assert(0)`. Before landing, a lane either fills the body or runs `--strip-pending`, which drops that member's declaration and keeps its row deferred, the way hand ports treat unported members. Main therefore never contains a method that halts when called, and no `PortPending` API is needed.
4. **Body statement forms**, later and one rule ID at a time: expressions and control flow under the R14 string rules and Java's integer and null semantics. Symbols resolve from `flint api extract` manifests, never through javac at run time.
5. **Upstream test translation.** Assertion-shaped JUnit tests (assertEquals, assertThrows, basic AssertJ) become flint:test tests, so the generated code runs Spring's own tests. Plain-GPL jtreg sources are never copied (licence rule); for those, the oracle in (c) below stands in.

## The correctness gate: `python3 tools/gates.py --gate porter`

It is required in the root gate set and in every lane's definition of done, and it keeps a shrink-only baseline like the closure ratchet.

- **(a) Determinism.** The same pinned input and porter version produce byte-identical output. The gate regenerates every porter-provenance module and diffs it against the committed one.
- **(b) Corpus reproduction.** The porter runs over every element that is already hand-ported in a shape it supports. The generated declaration must be API-identical to the hand port: signature, attributes, and the mapping row's status and rules. The hand port's own tests are then compiled and run against the generated module on DMD and LDC. A divergence fails unless it is listed with a reason in the shrink-only baseline. The reproduction rate per shape is published.
- **(c) Behaviour oracle.** Every generated body gets a differential test against pinned Temurin 21.0.13: inputs are sampled from the declared types, recorded once from Java as a golden file, and replayed in D on both compilers. This is how lanes already verify by hand (Temurin oracle rows), applied to every generated body.
- **(d) Generated regions stay generated.** Each generated region carries a digest. An edit outside the `port:body` markers fails until the porter's rule or the type's port plan changes instead.
- **(e) Performance.**
  - A generated module is no larger than its hand port, in linked bytes (O3 and Oz) and template instances, wherever both exist in the corpus. It is within its leaf and package caps.
  - It passes the closure ratchet and the allocation gates. The apps' flint budget is judged by the merge train as for any change.
- **(f) Performance lint, `flint check --perf`.** Every playbook row whose rule a program can check statically becomes a lint rule carrying the row's ID. Examples: classes final by default, value types as structs, no `package.d` aggregators, no module-level thread-local state in framework packages, erased storage for class and interface elements, no `std.algorithm` in core modules. The row's "Enforced by" column then names the lint. Porter output must be lint-clean, and lanes' hand-written bodies are held to the same rules. This is also the fast CI performance check the owner asked for after Phase 1.

## How it changes the lanes

- Once a shape is supported and gates (a)–(e) are green for it, lanes run the porter first for that shape. Hand-porting a supported shape needs a written reason in the commit.
- A lane's job becomes: write the port plan, fill the `port:body` regions, and add oracle rows the generator can't infer.
- A lane that finds a mechanical shape the porter mishandles reports it to sol-translator as a rule request, and doesn't hand-patch generated regions.

## Metrics (proof-harness, daily, coordination/notes/porter-metrics/)

- The share of landed elements with porter provenance against hand-written ones, by repo.
- The corpus reproduction rate per shape.
- Elements landed per lane-hour, the proxy for AI credits spent per element.

## Owners

| Part | Owner |
|---|---|
| Porter, port plans, skeleton mode, gates (a)–(e) | sol-translator |
| `flint check --perf` framework and its gates.py wiring | m7-flint-cli |
| The first lint rule set, chosen from the playbook | framework-core with proof-harness |
| The `generated` provenance field and coverage by provenance | api-coverage |
| Daily metrics | proof-harness |

## Milestones

Each milestone ends with its gates green and reports two numbers:
- **correctness:** the corpus reproduction rate, per shape and per element;
- **yield:** how many deferred elements, Phase 2 Spring and third-party plus the JDK's in-scope members, the porter can now emit a gate-passing candidate for, by shape.

The order changed on 2026-11-27 18:45Z: skeleton mode moves ahead of M3, because it removes hand-written declarations for every type.

1. **M1 (done 18:26Z, d0caeccbd):** gates (a), (b) and (d) over the shapes already supported, the port-plan seed, and provenance in mapping.json.
2. **M2:** `@ConfigurationProperties` specs derived from the pinned Java and rendered by boot/tools/configuration_properties.py (M2a: 117/137 fields exact). Then R6 getters, setters and fields for ordinary classes, measured per element; the 40 pure-bean classes are also reproduced as whole types (M2b).
   - M2b, first part (tools/port-spring/accessors.py, `r6-accessor` shape), 2026-11-27. The corpus is 764 trivial accessors of hand-ported classes: 605 getters and 159 setters.
     - Correctness: 386 reproduced exactly on DMD and LDC with matching rows, 50.5% of the corpus and 66.7% of the 579 the rules accept. With the rules alone, before function attributes moved into the port plans, the count was 238. Hand ports have no common attribute convention: of 530 getters, 225 are bare and the rest mix `const`, `pure`, `nothrow` and `@nogc`.
     - The 193 divergences (some elements have more than one kind): 137 rows, mostly hand rows that don't cite the R5, R10 or R23 the type mapping applies; about 70 API differences (parameter names, `Nullable!string` under R5, arrays where R10 says `List!T`); 76 bodies over a renamed hand field.
     - Unsupported: 185, mostly types without a plan entry or a mapping, ambiguous hand overloads and members the hand class doesn't declare.
     - Yield: 8,572 deferred trivial accessors; the rules derive 5,587 (65%) given a default plan entry. The main blocker is 2,245 accessors over unmapped types: `java.time.Duration` 383, `DataSize` 67, `Charset` 57, `Instant` 26, `ClassLoader` 26.
     - Rule rulings, 2026-11-27: the ported JDK collections cite no R10 (the coordinator's R10 clarification, 9c163b2c3), so the porter's rows over `List!T`, `Set!T` and `Map!(K, V)` are `ported`; twelve reproduced hand rows dropped R10 with it, and the `r6-accessor` floor rose from 386 to 393 (one of them from the new java.time rows). An accessor over an excluded type is excluded with it, citing the type's exclusion: 84 of the 8,572 (`ClassLoader` 26, `java.lang.reflect` types 33, `ParameterNameDiscoverer` 14, `ResolvableType` 8). That leaves 2,901 blocked.
     - Yield after DataSize, Duration and Instant landed (2026-11-27 20:00Z): 6,076 of 8,571 deferred trivial accessors derived (71%), 84 excluded, 2,411 blocked.
   - M2b, second part (tools/port-spring/bean_types.py, `bean-class` shape), 2026-11-27: whole pure-bean classes, meaning hand-ported classes whose methods are all trivial accessors. The class header, private fields, mechanical constructors (R8's `file, line` family for `Throwable` subclasses) and accessors are derived, spliced over the hand class, compared on DMD and LDC (non-private API, R24) and tested with the owning package.
     - Correctness: of 36 pure-bean classes, 4 are reproduced with package tests (`TableParameterMetaData`, `CompromisedPasswordDecision`, `InvalidTimeoutException`, `SimpleTransactionStatus`), 11%, and 57% of the 7 the rules accept. The 3 divergences are on the hand side: `ParseException` renames Java's parameter `s` to `message`, `MissingRequestValueException` merges its constructors with default arguments, and `SqlParameterValue` takes a Java `@Nullable String` as a plain `string`.
     - Rejected: 29. Most need M4 bodies: constructors that build a message or call `Assert`, nested builder types, generic or unmapped bases, static members and `Class<?>` (R4).
3. **M3 (was M4):** skeleton mode for every type, with all declarations, signatures, mapping rows, DDoc and headers generated, and the bodies marked; plus JUnit test translation.
   - M3, first part (tools/port-spring/skeletons.py, `skeleton` shape), 2026-11-27. Every non-generic class and interface is declared whole: header, fields, constructors and methods with D signatures, DDoc and rows. Accessor and forwarding-constructor bodies are derived, and every other body is a `// port:body <element id>` region holding `assert(0, "port:body <element id>")`. That compiles in any attribute context and fails loudly until a lane fills it. R3 defaults go into `mixin template Defaults`, and R11 adds `mixin JavaObject`. R24 gives `final` accessors, and R8/R26 cover exception constructors. A member the rules can't declare yet is listed as `// port:pending <element id>: <reason>`. Placeholders never land on main; see the skeleton-mode rule above.
     - Correctness, against 1,298 hand-ported classes and interfaces: 173 types reproduced whole (13.4%). Of the 3,044 elements the skeletons declare that also have a hand row, 981 match on DMD and LDC (32.2%), the `skeleton` floor. Another 1,137 declared elements have no ported hand row; that's new declaration work, not divergence. 1,606 members are pending.
     - The 2,063 element divergences: 860 compile failures, mostly a hand interface whose signature differs (R5 `Nullable`, R23 `Any`), so its implementors' skeletons don't override; 823 rows; 634 API, mostly hand ports that drop or rename Java's parameter names and merge R8 constructors; 330 missing DUB dependencies (`:framework-test` on `HttpStatus`, `:jackson-databind` on `:java-math`); 84 attributes only (hand bodies add `pure nothrow @nogc`).
     - Yield, over the 11,867 deferred public classes and interfaces: 2,948 get a skeleton today (732 complete), declaring 12,189 elements, 5,197 of them with derived bodies. The main blockers are unmapped bases and member types, which are mostly other deferred types in the same upstreams. Naming those by R1, as if the batch were generated together (`--yield --predict`), raises it to 5,026 skeletons and 30,493 declared elements (11,109 with derived bodies).
   - M3, second part (skeletons.py `--emit`, 2026-11-27): emit mode writes whole modules for a batch of Java packages, one `port-skeleton/1` region per type, in dependency order within the batch (R1 names, D facts re-read with the batch overlaid until stable), compiled on DMD and LDC before anything is written. `--strip-pending` and the gate's placeholder check implement the no-placeholder rule above. The gate regenerates committed skeleton regions, and its corpus skips rows with porter provenance. README, "Emit mode".
     - First whole-upstream trial, all 2,874 deferred spring-framework classes and interfaces in one batch: 765 skeletons converged in 179 modules, declaring 3,418 elements, of which 1,970 have derived bodies and get rows under `--strip-pending`, and 1,486 are marked bodies. The trial didn't write: two batch bugs it found are fixed (a new parent module beside a new child must be `package.d`; `null` arguments were spelled `nulL`).
     - Refused: 688 with no mapped enclosing Java package for R1 (needs a module decision per package), 493 unmapped bases outside the batch, 343 generic types or bases, 237 unmapped or unresolved member types, 80 dropped by the compile check, 42 whose parent module is a `name.d` with children due (`flint.web.util.pattern`, `flint.web.servlet.resource`), 3 already declared by hand with deferred rows (reported to framework-core).
           - Cost: 37 minutes for the whole upstream, mostly the compile-check rounds that regenerate the batch. Batches per package group are the practical unit until that's incremental.
    - M3, third part (first real emit, 2026-11-27): `--emit org.springframework.jdbc.support.incrementer --in-place --strip-pending` wrote the new module `flint.jdbc.support.incrementer` (606 lines) from 22 deferred classes and interfaces. All 22 skeletons converged (0 rejected, 0 compile errors), declaring 67 elements with rows under porter provenance; 54 members are listed as pending. The module compiles inside `:jdbc` (`dub test :jdbc` passes its 32 modules on DMD and LDC). The `api`, `structural` and `quality` gates pass; `--gate porter --digests-only` finds 22 regions with no placeholder. The full porter gate is red only on six corpus divergences that predate this emit and are not in this package (decisions.md, 2026-11-27): the baseline was seeded at d0c66cd72, before `ad16a5d81` mapped `java.nio.charset.Charset` and before several hand ports entered the corpus. A splice import fix (decisions.md, 2026-11-28) then took framework-core's `AbstractResourceBasedMessageSource` from a package-wide compile failure to six element divergences.
4. **M4 (was M3):** `equals`/`hashCode`/`toString`, records, builders, exception families and enums, filling bodies inside skeletons. Also the behaviour oracle (c) and the first `flint check --perf` rules (f).
5. **M5:** body statement forms, one rule ID at a time, chosen by how many deferred elements each unlocks.
