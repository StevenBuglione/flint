# Mechanical Spring translator

`flint port-spring` generates a D source candidate and an API mapping fragment for a pinned Java declaration. The owning port lane reviews both files before applying them. The translator matches declarations to `flint api extract` manifests and uses rulebook v2.

The optional C helper builds independently of the Flint CLI. CMake verifies the MIT-licensed tree-sitter runtime and generated Java grammar archives against pinned SHA-256 digests.

```sh
cmake -S tools/port-spring -B .flint/port-spring
cmake --build .flint/port-spring
flint api fetch jakarta-persistence
flint port-spring --project jakarta-persistence --tag 3.2.0 \
  --type jakarta.persistence.FieldResult --module flint.jakarta.persistence \
  --output .flint/field-result
```

The output directory must be new. It receives one D module and `mapping.json` with exact entries for deferred declarations. Identical existing ports are left alone. Changes to existing ports require `--replace-ported`, and the owning lane reviews the proposed replacements. Use `--json` to read both without creating files. Use `--helper` for a helper built at a different path and `--cache` for the same cache override used with `flint api fetch`.

This slice supports public top-level annotations with primitive, string and class-token fields, scalar and array defaults in the supported literal forms, and explicit JDK meta-annotation imports. It moves `value` first, uses `ClassRef` for Java class tokens under R4, and applies R19 to D keyword names. The CLI reports Java `@Inherited` for AOT review. Unsupported types, default expressions and annotation metadata produce a diagnostic before any candidate is written. The slice accepts Apache, MIT and BSD source ports covered by the licence matrix. EPL source translation requires destination-package support.

A custom meta-annotation with no attributes can become a D UDA on the struct. Its exact mapped symbol must already be in the destination D module. The CLI checks the Java import scope and declaration order against the pinned manifest before emitting the markers. Custom metadata with arguments or on annotation members requires a separate translation.

Java `@Deprecated` on an annotation or attribute becomes D `deprecated` on the corresponding struct or field. The warning includes a literal `since` version, a `forRemoval = true` notice, and the replacement hint from the adjacent Javadoc `@deprecated` tag when supplied.

For a class-valued attribute, `void.class` and `X.class` with the exact declared bound `Class<? extends X>` become `ClassRef.init`. The CLI verifies the sentinel against the pinned declaration and names it in the proposed R2/R4 mapping note. Other class literals require a separate translation.

An annotation can use an enum that already maps to its destination D module. The CLI checks the field type and each default against the pinned manifest and uses the exact mapped D symbols for the enum and constants. It resolves fully qualified names, explicit Java type and static imports, and unambiguous on-demand imports from known manifest scopes. R15 enums require a separate translation.

Nested annotation fields and arrays use the same reference lookup and require an exact R2 mapping to the destination module. A zero-argument default uses the nested struct's `.init` when every Java attribute has a default. A single enum constant supplied as `@Nested(CONSTANT)` or `@Nested(value = CONSTANT)` initializes the mapped first field when every other attribute has a default. The CLI resolves the field type using the nested declaration's imports and the constant using the imports at the use site. A required array field uses D's default initialization, and an explicit Java empty array uses `[]`.

Public top-level enums keep Java constant order. The R20 method slice recognizes one public instance method that checks an enum argument with Spring's `Assert.notNull` and returns the lesser ordinal through a conditional expression. It emits a same-module UFCS function whose receiver is named after the enum (`Access cap(Access access, Access maxPermitted)`), or `receiver` when that name is the Java parameter's; a D keyword takes R19's underscore. D rejects a null argument at compile time under R5 and R20. Constants with arguments or class bodies, other method bodies, fields and implemented interfaces require separate translations.

The R8 exception slice accepts a public subclass of Spring's `TransactionUsageException` with one public `String` constructor whose body is exactly `super(message)`. The CLI checks the base class and its constructors against the pinned manifest and existing mapping. It emits a D constructor in `flint.transaction` that preserves the message and caller location. A checked `@SuppressWarnings("serial")` has no effect on the D declaration. Other exception hierarchies and constructor shapes require separate translations.

The R3 marker interface recipe accepts a public top-level interface with an empty body and one parent, Spring's `Ordered`. The CLI resolves the parent through the pinned manifest and requires the exact ported mapping to `flint.core.Ordered`. A DMD and LDC golden verifies that the mapped parent is a D interface and that the generated subtype preserves inheritance.

The R1 constant-holder recipe accepts a public final class with one private empty constructor and public static final `String` fields initialized by supported literals. The draft uses a final D class with a disabled constructor and `enum string` fields. Configuration keys beginning with `spring.` and constant expressions require separate translation rules.

## Generated regions and provenance

The emitted declarations sit in one generated region:

```d
// port:generated port-spring/1 spring-framework@v7.1.0 org.springframework.transaction.InvalidIsolationLevelException sha256:<hex>
class InvalidIsolationLevelException : TransactionUsageException
{ ... }
// port:end
```

The marker records the porter output version (`porterVersion` in `flint_tool.api.portspring`), the pinned upstream and the Java type, so the gate can regenerate the region, and the SHA-256 of the region's text without its `// port:body <element-id>` ... `// port:end-body` regions. A lane fills only those body regions; any other edit fails gate (d) until the porter rule or the type's port plan changes and the region is regenerated. Proposed mapping rows carry `"generated": "port-spring/<N>"` (agreed with api-coverage, 2026-11-27). Bump the version whenever any shape's output changes. A type in a module whose path takes R19's keyword underscore (`flint.ai.template_`) cites R19 on its type row.

## The correctness gate

`python3 tools/gates.py --gate porter` (or `tools/porter_gate.py`) proves the porter against the hand-ported corpus (docs/spring/phase2/porter-plan.md, M1):

- **(a) Determinism.** Every corpus type is ported twice, the second time in reverse order under another locale and time zone, and the outputs must match byte for byte. Every committed generated region is regenerated at its recorded request and must match.
- **(b) Corpus reproduction.** Every hand-ported public top-level type with an exact mapped type row is offered to the porter. An accepted declaration must propose no mapping change. It is spliced into a copy of the module that declares the hand port, and `gate/porter_describe.d` prints both declarations' compile-time API on DMD and on LDC: kind, visibility, UDAs, deprecation, bases, member types with their parameter defaults, function attributes, field initializers and enum values. The descriptions must match. The owning package's unit tests (`dub test :<package>`) then run against the spliced tree on both compilers. A failure counts against a splice only when the unspliced tree passes.
- **(d) Generated regions** keep their digests.

Rejected types are unsupported, not divergences, and are published with their reasons. A divergence fails unless `api/porter-baseline.json` lists it with a reason. That list only shrinks, and the reproduced count per shape only grows (`--write-baseline` refuses a new divergence). The report at `artifacts/porter/report.json` gives the reproduction rate per Java kind and per shape. The gate needs `flint`, the helper, the pinned source caches of every upstream (`flint api fetch --cache <absolute dir>`), DMD, LDC and DUB, and exits 2 when one is missing. `--no-tests` and `--only <type>` are for development and never pass the gate.

```sh
python3 tools/measure_queue.py hold -- python3 tools/gates.py --gate porter \
  --flint .flint/bin/flint --helper .flint/port-spring/flint-port-spring --cache "$PWD/.flint/cache/api"
```

### R6 accessors, per element

`accessors.py` handles trivial Java getters (`return this.f;`) and setters (`this.f = p;`) of instance fields. It derives each D member by fixed rules, without reading the hand port:
- the Java name (R19 for D keywords) and visibility;
- `override` when a superclass in the pinned manifests declares the same method, and `final` for a Java `final` method;
- the D type through the mapping rows: R5 for nullable strings, boxed values and `Optional`; R23 for `Object`. `List`, `Set`, `Collection` and `Map` become the ported JDK types `List!T` and friends, a ported dependency with no rule (R10). An accessor over an excluded type (such as `ClassLoader`, `jvm-runtime`) is excluded with it, citing the type's exclusion;
- the function attributes recorded in the type's port plan under `"accessors": {"getter": [...], "setter": [...]}`, none when absent;
- a body over the field's Java name, or `name_` when the field would collide with a method name;
- the mapping row: `ported`, or `adapted` with the rules applied.

The gate offers it every trivial accessor of a hand-ported class whose row is ported or adapted with a D symbol. The derived member replaces the hand member in a copy of the declaring module, and `porter_describe.d` must print the same member lines on DMD and LDC. The rows must also agree. If the derived body doesn't compile against the hand class, an `assert(0)` body is used for the API comparison and the element counts as a body divergence. The reproduced count is the `r6-accessor` floor, and divergences are listed per element under `"accessorDivergences"` in `api/porter-baseline.json`. Both only move one way. Accessors the rules reject (an unmapped type, `Class<?>` under R4, Java `char`, type variables, an ambiguous hand overload) are reported as unsupported.

```sh
python3 tools/port-spring/accessors.py --helper .flint/port-spring/flint-port-spring --cache "$PWD/.flint/cache/api" \
  --compare --json artifacts/porter/accessors.json      # compiles: run under hold
python3 tools/port-spring/accessors.py ... --yield      # deferred trivial accessors the rules derive
python3 tools/port-spring/accessors.py ... --render 'org.springframework.http.ResponseCookie#getDomain()'
python3 tools/port-spring/accessors.py ... --seed-plan artifacts/porter/accessors.json
```

`--seed-plan` records, per type and accessor kind, the attributes every hand accessor of that kind shares, so attributes become lane-owned plan data. A lane's existing entry wins. `test_accessors.py` covers detection, the type and row rules, plan attributes and splicing.

### Pure-bean classes, whole types

`bean_types.py` takes the hand-ported classes whose methods are all trivial accessors and derives the whole D class by fixed rules:
- the header: `abstract` or `final`, and the superclass and interfaces through their mapped D symbols (Java's `Throwable` and `Exception` are D's own, R8);
- one private D field per Java instance field, named and typed as the accessors are, with a literal initializer when Java has one. A private `serialVersionUID` is dropped;
- each constructor whose body is an optional `super(...)` or `this(...)` call over parameters and literals, then assignments of parameters or literals to its own fields. A `Throwable` subclass follows R8's D convention: every constructor also takes `string file = __FILE__, size_t line = __LINE__` and is `pure nothrow`. `this(...)` forwards `file, line`, and `super(...)` uses the landed D base constructor that adds `file, line` to the Java arguments, with a `null` cause where the base takes one. The base's overloads come from its API description;
- every accessor from `accessors.derive`, with `override` also where Java says `@Override` and the landed D base chain declares the name;
- the rows: the class `ported`, each constructor `ported` or `adapted` with its parameter types' rules, and each accessor's row.

The gate splices each derived class over the hand class, adding a selective import for any rulebook type the module lacks (`Nullable`, `List`, `Any`). It compares the class's non-private API on DMD and LDC, since R24 leaves private fields to the port, compares the rows and runs the owning package's tests. The reproduced count is the `bean-class` floor, and divergences are listed per type under `"beanDivergences"`. Both move only one way. Classes with nested types, generics, static members, non-private fields or constructor bodies that compute (a message built from parameters, an `Assert` call) are rejected and left to M4. `test_bean_types.py` covers detection, the derived class, R8 constructors, imports and the API filter.

```sh
python3 tools/port-spring/bean_types.py --helper .flint/port-spring/flint-port-spring --cache "$PWD/.flint/cache/api" \
  --compare --json artifacts/porter/bean-types.json     # compiles and runs package tests: run under hold
python3 tools/port-spring/bean_types.py ... --render org.springframework.transaction.InvalidTimeoutException
```

### Skeleton mode, every declaration

`skeletons.py` declares a whole Java class or interface in D: the header, fields, constructors and methods with their D signatures, DDoc from the Javadoc's main description, and the mapping rows. A body is derived where a mechanical shape covers it (trivial accessors, constructors that only forward and assign). Every other body is a marked region that the lane fills:

```d
int increment()
{
    // port:body org.springframework.example.Counter#increment()
    assert(0, "port:body org.springframework.example.Counter#increment()");
    // port:end-body
}
```

`assert(0)` compiles in every attribute context, including `pure nothrow @nogc` and a constructor whose D base has no default constructor. It fails loudly until the body is written, and the element's row stays deferred until then. The signature rules are the accessors' (R5, R10, R19, R23), plus:
- visibility as in Java (`package` for package-private); `static`, `abstract` and `final` as in Java; `override` where a Java superclass declares the method, or Java says `@Override` and the landed D base chain declares the name;
- `throws` clauses are dropped (R8), and `@Deprecated` becomes `deprecated`;
- a `Throwable` subclass's constructors take R8's `file, line` pair and are `pure nothrow`, and a `@Nullable String` message stays a plain `string` (R26, also in `bean_types.py`);
- `equals`, `hashCode` and `toString` keep their names (R11), with `mixin JavaObject;` when the class declares `equals` or `hashCode`;
- an interface's default methods are declared in the interface and carried, with their bodies, by `mixin template Defaults` (R3). A class mixes in each interface it implements directly whose D declaration has `Defaults` (or, before the interface lands, whose Java declaration has default methods). An interface whose plan kind is `abstract class` becomes one (deviation D-3);
- a `public` or `protected` `final` instance field becomes R24's `final` accessor over a private `name_` field, a non-final one stays a D field, and a `static final` field with a literal initializer becomes an `enum`;
- a field initializer that isn't a literal, or an initializer block, makes every constructor body a marked region, since Java runs them there;
- a non-accessor method's function attributes come from the type's port plan under `"methods"`, keyed by the Java signature (`"applyRelativePath(String,String)": ["pure", "nothrow"]`): a hand port's mechanical body often carries `pure nothrow @nogc` that no rule can infer from the Java declaration. Accessors read their own `"accessors"` entry the same way.

A member the rules can't declare yet (a generic method, varargs under R7, an unmapped type, a nested type under R13) is left out with a `// port:pending <element id>: <reason>` line, so the rest of the skeleton stays usable. Generic types and unmapped bases are rejected.

The gate offers it every hand-ported class and interface. Each skeleton is spliced over the hand type, with selective imports for the mapped types, rulebook types and `JavaObject` the module lacks, and both are described on DMD and LDC. A member is reproduced when its description lines (all overloads of its D name, without the overload index) match and its row agrees. A type is reproduced when its whole non-private API matches and nothing is pending. Bodies don't affect the API, so package tests don't run for this shape. When a module with several spliced types doesn't compile, each type is retried alone, and a hand type the compiler can't describe is rejected. The reproduced element count is the `skeleton` floor. `"skeletonDivergences"` lists the number of divergent elements per type, and a new type or a higher count fails. `test_skeletons.py` covers the declarations, mechanical and marked bodies, pending members, R3, R8/R26, R11, R24, imports and the API comparison, and compiles a skeleton on DMD and LDC to check that a marked body fails with its element id.

```sh
python3 tools/port-spring/skeletons.py --helper .flint/port-spring/flint-port-spring --cache "$PWD/.flint/cache/api" \
  --compare --json artifacts/porter/skeletons.json      # compiles: run under hold
python3 tools/port-spring/skeletons.py ... --render org.springframework.transaction.support.DefaultTransactionStatus
python3 tools/port-spring/skeletons.py ... --yield      # deferred classes and interfaces the rules can declare
```

#### Emit mode: modules lanes fill and land

`--emit` generates the D modules for a batch of Java packages (their deferred public classes and interfaces) or type ids, all together:

```sh
python3 tools/port-spring/skeletons.py ... --emit org.springframework.util --emit org.springframework.core --output .flint/draft
python3 tools/port-spring/skeletons.py ... --emit org.springframework.util --in-place                  # a draft in the tree
python3 tools/port-spring/skeletons.py ... --emit org.springframework.util --in-place --strip-pending  # what lands
```

How a batch is built:
- **Names.** Each type is named by R1, so a type in the batch can use another before either lands. A type the batch can't generate loses its predicted name, and the types that use it drop out with it.
- **Destination.** Each type goes into its package's D module. That's an existing module's file (a type it already declares by hand is refused: map its rows instead), or a new file in the source root of the nearest parent module, written as `package.d` when the module has children. A new file carries the first Java file's header, the `Ported from` marker naming every source file, the licence line and the modification notice. Only `port-source` upstreams are accepted.
- **Regions.** Each type is one `// port:generated port-skeleton/1 <upstream> <type> sha256:<digest>` region. Re-emitting replaces the regions and keeps every body a lane wrote between its `port:body` markers. Missing selective imports go after the module's existing imports.
- **Dependencies.** A type needing a module its DUB package doesn't depend on is refused.
- **D facts.** Base constructors, the base chain's members and which interfaces declare `Defaults` are read with the batch's own output overlaid. The derivation repeats until the output stops changing, so regenerating from the committed tree gives the same text.
- **Compile check.** Every emitted module is compiled against its package on DMD and LDC. A type that compile errors point into is left out and the batch generated again. Nothing is written while an error remains.

Placeholders never land (coordinator, 2026-11-27). A draft holds `assert(0)` placeholders and writes no mapping rows. Once the lane has written the bodies it can, `--strip-pending` leaves out every member whose body is still a placeholder and lists it as `// port:pending <element>: the body is not written yet (--strip-pending)`. That member's row stays deferred, the way hand ports treat unported members:
- If every constructor of a class is left out, the class gets `@disable this();`, since D's implicit constructor would be API that Java doesn't have.
- An unwritten R3 default leaves the interface along with its `Defaults` body.
- A class that no longer compiles because of a stripped member (an interface method it must implement) is left out. Its draft region stays and is reported under `keptRegions` until its bodies are written.

Then `--in-place` writes the rows for every declared element whose body is derived or written. Each row carries `"generated": "port-skeleton/1"`. A hand row that is ported or adapted is never replaced. The gate's corpus skips rows with porter provenance, so generated types never count as reproducing themselves.

The porter gate fails on any `port:body` region that still holds its placeholder, anywhere in the tree (this also runs with `--digests-only`). It regenerates every committed `port-skeleton` region from the tree with the bodies its file holds, and fails on any difference.

`tools/port_plan.py --seed` writes `api/port-plan/<project>-<version>.json` from the mapped type rows and the hand ports' D kinds, keeping entries a lane already edited; `--check` validates the plans against the manifests and mapping rows.

## Verification

`test_annotations.py` exercises the C helper and compiles the emitted UDA with DMD and LDC. `test_jakarta.py` walks every Jakarta Persistence annotation in the pinned manifest, compares generated fields and mappings to the existing hand port where available, checks the emitted headers, and compiles every generated D file on both compilers.

`test_spring_markers.py` translates Spring Framework's `Component` and compares the marker and field with the hand port. It checks the extracted AOT models and runs a direct and transitive lookup with both compilers.

`test_boot_enum_method.py` translates Actuator's `Access.cap` and compares every pair of enum values with the hand port. It checks the R20 mapping and pins rejection of `cap(null)` at compile time on DMD and LDC.

`test_exceptions.py` exercises the native constructor checks. `test_spring_exception.py` compares Spring's `InvalidIsolationLevelException` with the hand port and exercises the generated class hierarchy, cause, message, and caller location on DMD and LDC.

`test_interface.py` exercises the native marker interface checks. `test_spring_interface.py` compares Spring's `PriorityOrdered` with the hand port and tests implementing it and upcasting to `Ordered` on DMD and LDC.

`test_holder.py` exercises native validation of constant holders. `test_spring_holder.py` checks the final class, disabled constructor, and all 18 literal values of Spring AI's `SpringAIModels` on DMD and LDC. It also verifies the 19 mapping rows.

```sh
python3 tools/port-spring/tests/test_annotations.py
python3 tools/port-spring/tests/test_enum.py
python3 tools/port-spring/tests/test_exceptions.py
python3 tools/port-spring/tests/test_interface.py
python3 tools/port-spring/tests/test_holder.py
python3 tools/port-spring/tests/test_jakarta.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_jakarta_enums.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_spring_markers.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_boot_enum_method.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_spring_exception.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_spring_interface.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_spring_holder.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
```

On venus, run each build and test under the shared measurement hold.
