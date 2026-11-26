# Flint AOT contract

Flint AOT is the build step that replaces Spring's runtime reflection (ADR-030 section 3). It reads the application's modules with the compiler's semantic analysis and writes plain D that the framework runtime, `flint.engine.aot`, consumes at startup. This document is the contract between the two sides:

- **the generator** lives in the `flint` repository, `apps/flint/src/flint_tool/engine/aot/`;
- **the runtime** (`flint.engine.aot.*`, DUB `flint:engine-aot`) lives in `flint-framework` and is implemented by the framework-core session;
- **the annotations** the generator recognizes are owned by the framework, Boot and portfolio packages that declare them.

Contract version: **3**, additive over 1 and 2 (sections 4.10 and 4.11); the runtime accepts all three. A change to anything below bumps the version, and the generator writes the version into every generated module, so a mismatched runtime fails to compile instead of misbehaving.

## 1. What runs when

| Step | When | Cost in the edit loop |
| --- | --- | --- |
| Interface hash of every module under `src/` and of every auto-configuration module the closure lists | every `flint build` | lexing only: about 1 ms per thousand lines |
| Semantic extraction of the modules whose interface key changed | only when a key changed | one `-o-` compile through the compile server |
| Generation of the modules whose model, or a model they consulted, changed | only then | in-process, no compile |
| Compiling the generated modules | DUB, like any source; unchanged files are not rewritten | only for regenerated modules |

Editing a method body changes no interface key, so it runs no extraction, rewrites no generated file and recompiles nothing generated.

### 1.1 Semantic extraction

DMD's `-X` JSON leaves out UDAs and does not evaluate attribute arguments, and the compile server refuses `-X`. The generator therefore extracts the model with the compiler itself: it writes a root module, `.flint/generated/aot-extract/flint_aot_extract.d`, that imports the modules to extract and evaluates a compile-time describer over each of them (`__traits(derivedMembers)`, `getAttributes`, `getOverloads`, `__parameters`, `tupleof`, `fullyQualifiedName`). The describer prints one JSON document per module through `pragma(msg)`. The compile is an ordinary `dmd -c` into a throwaway object (the root holds no code), with the project's import paths and `-preview=dip1000`: the forked compile server serves `-c` compiles but not `-o-` ones. Only signatures are analysed; function bodies of the extracted modules are never compiled. Served, gs-rest-service's application-module extraction takes 0.05 s instead of 0.09 s, with byte-identical generated output on the three Phase 1 apps. The describer does not describe annotation types the generator already holds from this environment (listed in a generated `flint_aot_known` module), except those declared in the project's own modules, which an edit may change. A fresh environment starts with none, and a stored annotation set still includes the skipped types, so every shared model entry remains self-sufficient.

The model therefore holds real types (fully qualified, after aliases), evaluated attribute values (enum members by name, constants folded), and the attribute types' own declarations. Class-presence conditions are answered in the same compile with `__traits(compiles, { import M : T; })`.

**Native extraction.** The forked DMD can produce the same lines without the describer: with `-flint-aot-extract=<file>` it walks the already analysed AST of the modules the file lists (`module <name>` lines in request order, then `known <name>` for each annotation type the generator already holds) and prints the describer's `FLINT-AOT-MODULE`, `-TYPE` and `-ANNOTATION` lines, byte for byte (dmd-arm64, design 3A). The root then only imports the modules and asks the presence questions. The generator tries it first. A compiler that rejects the switch, any unforked DMD (`unrecognized switch '-flint-aot-extract=`) or LDC (`Unknown command line argument '-flint-aot-extract=`), gets the describer compile instead, so the describer remains the normative definition of every field. Only those two messages, with no line extracted, fall back: the fork's own errors (an unreadable request, a requested module the root does not import, an attribute that fails to evaluate) fail the extraction and are reported, never retried through the describer. The build's summary line ends with the extractor that ran, `native extractor`, `describer`, or both when they differed, whenever something was extracted: `Generated 33 Flint AOT modules for X (15 extracted in 402 ms, 42 from the shared cache, 34 written, 621 ms, describer)`. With the platform prelude, petclinic-rest's 15 modules took 33 ms natively against 379 ms through the describer (dmd-arm64, venus).

**The platform prelude.** When `flint build` serves the project compile with a platform prelude, the extraction compile gets the same `FLINT_DMD_SERVER_PRELUDE`: the platform step runs before the AOT step, and the prelude is passed only for an active platform, a server-enabled profile, and a non-test dev build, the condition of the project compile. The extraction compile also passes the prelude's `-version=` identifiers (the platform modules' versions, which every project compile carries) whenever the platform is active, prelude or not, and they are part of the environment key. A worker refuses a request that lacks a version its prelude defines, so without them the extraction ran in-process: about 80 ms instead of 7 on gs-rest-service's cold build. A worker that refuses the request leaves the compile in-process, with the same output. The server then has every platform module analysed, so only the requested modules are analysed per build: the describer took 334 ms instead of 450 ms on petclinic-rest (dmd-arm64).

The extractor and the model's JSON schema (`flint.aot.model/1`) are internal to the generator. The runtime never sees them.

### 1.2 Interface keys

A module's interface text is its token stream with every function body removed, except:

- bodies of functions whose return type is inferred (`auto`, `auto ref`), which are part of their signature;
- bodies of functions whose name appears anywhere else in the interface text (in an attribute argument, an enum or static initializer, a template constraint or a mixin), repeated until no new name appears, because CTFE may run them;
- function literals inside initializers, which are kept with their initializer.

`unittest` blocks are removed, and string literals keep their full text. A module's **extraction key** hashes its interface text (for a project module, without the top-level constants, variables and non-template functions whose name occurs nowhere else in the project's interface texts, literals included: only types are described, so such a declaration cannot change a model, and an added name shadows nothing that is unnamed), the interface texts of the project modules it imports (transitively), the generator version, the compiler identity, the platform version and the closure's package hashes. The **output key** hashes every cached model by content, the annotation types, the class-presence answers, which modules are the project's, the auto-configuration order, the environment and the generator version: while it is unchanged, nothing is analysed or written, including after a re-extraction that reproduced the same models (early cutoff). When it changes, every generated module is re-rendered, but a file is rewritten only when its text changed, so DUB recompiles only those. The keys and the cached models live in `.flint/cache/aot/state.json`. **The shared cache.** `flint build` also keeps, in `<FLINT_CACHE>/aot/` beside the platform cache (else `<home>/.flint/cache/aot/`), the models of modules outside `src/` (Boot's auto-configurations, imported configurations) by extraction key, each with the annotation types its extraction compile announced, and the class-presence answers by environment key. A cold build of any project with the same toolchain and closure takes them from there and extracts only its own modules. The project's own modules' models and its generated output (with the application, diagnostics and removals the step reports) are kept apart, in `<FLINT_CACHE>/projects/<first 16 hex digits of the SHA-256 of the project root>/aot/`, so the platform part can be copied alone: the cold build benchmark starts each trial from a platform-only cache, as Go's from a std-only GOCACHE. A cached cold build of a project (a clean `.flint`, the shared cache kept) therefore extracts and generates nothing: gs-rest-service's AOT step takes 13 ms instead of 665 ms (optimized tool). Each extraction compile's annotation types are stored once by content hash, and models refer to them. Entries are written through a rename, so concurrent builds never read half a file; an unreadable or older-format entry is extracted again.

## 2. Annotation conventions the generator relies on

Rulebook R2 makes every Java annotation a UDA struct with the same name and attributes. The generator additionally relies on these shapes.

- **Meta-annotations** are UDAs on the struct declaration. `@Component struct Service { ... }` makes every `@Service` a `@Component`.
- **`@AliasFor`** (`flint.core.annotation.AliasFor`) is a UDA on an attribute field:
  ```d
  struct AliasFor { string attribute; ClassRef annotation; string value; }
  ```
  `attribute` and `value` alias each other as in Java. `annotation` names the meta-annotation; `ClassRef.init` means "this annotation".
- **`Class`-valued attributes** are `ClassRef` values made with `classOf!T` (both in `flint.core.annotation`, a leaf module):
  ```d
  struct ClassRef { string name; }          // the fully qualified D name
  enum ClassRef classOf(T) = ClassRef(__traits(fullyQualifiedName, T));
  ```
  `@ConditionalOnMissingBean(classOf!DataSource)` reads like Java's `DataSource.class`. Where Java offers a `String` alternative so that the class need not be present (`@ConditionalOnClass(name = ...)`), the D attribute is the same string. This extends R4 to annotation attributes and is proposed to the rulebook as R4.1.
- **Single values for array attributes (proposed R2.1).** Java accepts `@GetMapping("/x")` for a `String[]` attribute, and D's struct literal does not: a `string` does not convert to `string[]`, and D has no implicit construction. An annotation whose array attribute Java lets take one value gets two `static opCall` overloads, one taking the element and one the array (defaulted to `null`), each with every attribute as a named parameter with Java's default:
  ```d
  struct GetMapping
  {
      string[] value; string[] path; string[] produces;
      static GetMapping opCall(string value, string[] path = null, string[] produces = null);
      static GetMapping opCall(string[] value = null, string[] path = null, string[] produces = null);
  }
  ```
  `@GetMapping("/x")`, `@GetMapping(["/x", "/y"])`, `@GetMapping(produces: ["application/json"])`, `@GetMapping("/x", produces: [...])` and a bare `@GetMapping` all work on DMD and LDC, and the struct's fields stay what the generator reads. `tests/aot/annotations/` shows the pattern.
- **Tooling gap.** dfmt 0.15.2 and D-Scanner do not parse named arguments (`@AliasFor(annotation: ...)`, `@Transactional(readOnly: true)`), which every Spring-shaped module needs; the pinned tools need an update before such modules can pass `tools/quality.py`.
- **A bare type UDA** (`@RestController` without parentheses) means the attribute with its defaults.
- **Enum-valued attributes** keep Java's enum names (`RequestMethod.GET`).
- **Annotation modules are leaves** (rulebook R2), so generated code may import them.

### 2.1 Merging

The generator composes annotations exactly as Spring's `MergedAnnotations` with the `INHERITED_ANNOTATIONS` search strategy does at runtime:

- an annotation is *present* on an element when it is declared there or is a meta-annotation (at any depth) of one declared there;
- a meta-annotation's attributes take the values the annotations below it give through explicit `@AliasFor(annotation: ...)`, at any depth (an alias may target a meta-meta-annotation). The nearest declaring annotation wins, even when its attribute holds its default, as Spring maps the attribute through the alias either way;
- implicit aliases (attributes aliasing the same meta-attribute) mirror each other, on the composed annotation too, and a set one wins over one at its default. So does the set member of a mirror pair in the meta-annotation: GetMapping's `value` and `path` both alias RequestMapping's mirrored `value` and `path`;
- a single value aliasing an array attribute becomes a one-element array (`string pkg` aliasing `string[] basePackages`);
- the nearest declaration of a type wins; for equal distance, the first declared wins;
- the same alias pair given two different non-default values is an error (FLINT-E1103), as Spring's `AnnotationConfigurationException` is. So are misconfigured declarations: an intra-annotation alias not declared on both attributes, or one with different types or defaults; an explicit alias whose target is not a meta-annotation of the declaring annotation, or whose type is neither the target's type nor its element type;
- class-level advice annotations apply to every public method that declares none of its own;
- a method's annotations are searched through its type hierarchy, as Spring's `TYPE_HIERARCHY` strategy does, for request mappings and advice; so are a class's for advice and Spring MVC's class-level `@Controller`, `@RequestMapping`, `@ResponseBody`, `@CrossOrigin` and `@ControllerAdvice`. The aggregates are the element, then its interfaces, then its superclasses (for a method, the methods it overrides there). Each is merged on its own and the first aggregate with a match wins, nearest within it, as Spring's `MergedAnnotationFinder` does: a subclass's meta-annotated `@Transactional` beats its superclass's direct one. Handler methods inherited from a base class are handlers. Its own come first, then those of the interface and superclass methods it implements or overrides (same name and parameter types, in model types). A handler's parameter annotations (`@PathVariable`, `@RequestBody`, `@Valid`) are found the same way, as Spring MVC's `HandlerMethodParameter` finds them on an implemented interface, such as petclinic-rest's openapi-generated `OwnersApi`;
- aliases inside nested annotation values are resolved, as Spring synthesizes nested annotations;
- type descriptors carry each supertype's annotations as a further aggregate (`aggregateIndex`, section 4.11);
- not yet: `@Inherited` (INHERITED_ANNOTATIONS) for stereotypes and conditions, a documented deviation in the runtime too.

Generated code receives the merged result as a value of the annotation type, built field by field so that no constructor or `opCall` is involved, and boxed in `Any`: `Any.of(() { Transactional a; a.readOnly = true; return a; }())`.

### 2.2 Recognized annotations

The generator acts on these merged annotations by fully qualified D name. Every other annotation is carried into descriptors untouched.

| Purpose | Annotations (D names) |
| --- | --- |
| Application | `flint.boot.autoconfigure.FlintBootApplication`, `flint.boot.autoconfigure.AutoConfiguration`, `flint.boot.autoconfigure.AutoConfigureAfter`, `AutoConfigureBefore`, `AutoConfigureOrder` |
| Components | `flint.stereotype.Component`, `Service`, `Repository`, `Controller`; `flint.context.annotation.Configuration` (with `proxyBeanMethods`) |
| Bean methods | `flint.context.annotation.Bean`, `Primary`, `Fallback`, `Lazy`, `DependsOn`, `Scope`, `Description`, `Role`, `Order` (`flint.core.annotation.Order`) |
| Injection | `flint.beans.factory.annotation.Autowired`, `Qualifier`, `Value` |
| Lifecycle | `flint.jakarta.annotation.PostConstruct`, `PreDestroy`; the interfaces `flint.beans.factory.InitializingBean`, `DisposableBean` |
| Conditions | `flint.context.annotation.Profile`; `flint.boot.autoconfigure.condition.ConditionalOnProperty`, `ConditionalOnBean`, `ConditionalOnMissingBean`, `ConditionalOnSingleCandidate`, `ConditionalOnClass`, `ConditionalOnMissingClass`, `ConditionalOnWebApplication`, `ConditionalOnNotWebApplication`, `ConditionalOnBooleanProperty` |
| Web | `flint.web.bind.annotation.RequestMapping` and its composed `GetMapping`, `PostMapping`, `PutMapping`, `DeleteMapping`, `PatchMapping`; `RestController`, `ControllerAdvice`, `RestControllerAdvice`, `ResponseBody`, `ResponseStatus`, `ExceptionHandler`, `PathVariable`, `RequestParam`, `RequestHeader`, `RequestBody`, `CookieValue`, `ModelAttribute`, `CrossOrigin` |
| Events | `flint.context.event.EventListener` |
| Properties | `flint.boot.context.properties.ConfigurationProperties`, `EnableConfigurationProperties`, `ConfigurationPropertiesScan` |
| JSON and validation | everything in `flint.jackson.annotation` and `flint.jakarta.validation.constraints`, plus `flint.jakarta.validation.Valid`; carried in descriptors |
| Data | `flint.data.annotation.Id`, `Transient`; `flint.data.relational.core.mapping.Table`, `Column`; repository interfaces deriving from `flint.data.repository.Repository` |
| Advice | `flint.transaction.annotation.Transactional`, `flint.cache.annotation.Cacheable`, `CachePut`, `CacheEvict`, `Caching`, `flint.scheduling.annotation.Async`, `flint.validation.annotation.Validated`, `flint.security.access.prepost.PreAuthorize`, `PostAuthorize`, `flint.resilience.annotation.Retryable`, `ConcurrencyLimit` |

The legacy ADR-028 attribute `flint.di.internal.conditions.ConditionalOnConfig("section")` is read as `@ConditionalOnProperty(prefix: "section", name: ...)`-style presence and is decided at startup like any other property condition, so `config/application.toml` is no longer a string import for AOT applications.

## 3. Generated layout

```
.flint/generated/aot/
  flint_aot_registry.d             module flint_aot_registry
  flint_aot/shop/owners.d          module flint_aot.shop.owners    (from src/shop/owners.d)
  flint_aot/shop/package.d         module flint_aot.shop           (from src/shop/package.d)
  flint_aot/flint/boot/autoconfigure/jdbc.d   (from an auto-configuration module of the closure)
```

- **One generated module per extracted module** that contributes anything; a module that contributes nothing gets no file. The path mirrors the source path under `flint_aot/`.
- **Imports of a generated module:** the `flint.engine.aot.*` modules it uses, and, with `static import`, its own user module, the modules declaring the types it spells out (a constructor parameter's type, a proxied method's parameter types) and the annotation and enum modules of the merged values it builds. It never imports another generated module. Everything it spells is qualified, so nothing it imports can shadow a name. In tables, types are named by their fully qualified string. A generated module for a module outside `src/` (an auto-configuration or another platform module) never imports a project module: `flint build` compiles those as a separate library, `.flint/generated/aot-library`, that DUB keeps across edits (19390bd1, `flint-cli.md` "The AOT library"). The generator checks this and reports FLINT-E1116 when, say, a compiled SpEL `@bean` reference in an auto-configuration would name a project bean's class. A platform module may describe its own data types: when it declares `Descriptor[] flintAotDescriptors()` (module level, non-template, `@safe`), the generator emits no data descriptor, accessor or container descriptor for the types it declares. That module's generated registration calls `foreach (descriptor; M.flintAotDescriptors()) registry.descriptor(descriptor);` instead, so those template instances (`descriptorOf!T`, `Any.of!T`, `typeNameOf!T`, and through container types whole `List`/`Map`/`Stream` hierarchies) compile once with the platform. Beans, conditions, factories and controller descriptors stay generated. Owner decision 2670d5be; agreed with boot, which adds the exporters. Container types the generated code still registers (an application's `List!X` properties and handler arguments, `Map`s and `Set`s of `flint.java.util`) go through `flint.java.util.descriptors`' erased builders (`rawListDescriptor`, `rawSetDescriptor`, `rawMapDescriptor`), named by the runtime's canonical names as literals, with no `descriptorOf` instance. A `create` function (`Any.of(cast(List!X) new ArrayList!X())`) is emitted only when a binder or reader creates the container: a writable property or a handler argument. Getter-only containers are filled in place. `Optional!T` and `std.typecons.Nullable!T` keep `descriptorOf`. Template instances are named in tables by those literals too, never `typeNameOf!(T)`. When a described type holds `flint.java.util.date.Date` at any depth, and the closure has Jackson's `JavaUtilDateModule` and Boot's `JsonMapperBuilderCustomizer`, the application's own generated module contributes a `JsonMapperBuilderCustomizer` bean, `flintAotJavaUtilDateModuleCustomizer`, that adds the module. Reading a `Date` through descriptors needs it (Jackson's pay-for-use split, third-party-apis), and Boot's `JacksonAutoConfiguration` applies every customizer; the platform's generated code is left project-free.
- **The registry** imports only `flint.engine.aot.registry`. It declares each generated module's entry point by its `extern(C)` name, calls them in definition order (section 5.4), and installs itself in its module constructor:
  ```d
  module flint_aot_registry;
  import flint.engine.aot.registry : AotRegistry, installRegistry;
  @safe:
  extern (C) void flint_aot_register_4shop6owners(scope AotRegistry registry) @safe;
  extern (C) void flint_aot_register_4shop3web(scope AotRegistry registry) @safe;
  private void populate(scope AotRegistry registry)
  {
      registry.begin(1 /* contract version */, 2 /* modules */);
      flint_aot_register_4shop6owners(registry);
      flint_aot_register_4shop3web(registry);
      registry.end();
  }
  shared static this() { installRegistry(&populate); }
  ```
  The `extern(C)` name is `flint_aot_register_` followed by each module-name segment prefixed with its length, so it is unique and needs no import. The prototypes are D functions with C linkage, defined by the generated modules as `@safe` functions, not foreign code.
- **Service providers (`META-INF/services`).** As `java.util.ServiceLoader` discovers providers, every package of the closure, and the project root, may hold `META-INF/services/<fully qualified interface>`: one provider class per line, `#` starting a comment. The registry adds `static import <module>;` for each listed provider's module, once, in listing order: packages in closure order, files by name, lines in order. Nothing else may reference a provider's module, for example a JDBC driver that registers itself from `shared static this()` with `DriverManager.registerDriver`. The import keeps the module, its ModuleInfo and its constructors in a static or `Oz` link (size-levers' request for the SQL driver split; the first listing is `flint.java.sql.Driver` in flint:postgresql and flint:sqlite-jdbc). A provider whose module is not in the closure is FLINT-E1117, at the listing's file and line. The listings are part of the output key; a project whose packages list nothing gets the same registry and key as before.
- **Generated code is plain D:** `@safe:`, no template declarations, no string mixins, no `__traits`. The only templates it instantiates are `Any.of!T`, `Any.get!T` and `Permanent`'s carving and sizing functions (below), and the annotation struct literals it constructs are not templates.
- **Start-up tables in shared blocks (`flint.engine.aot.permanent`).** A collection's pause is mostly the first touch of each live object, about 50 ns apiece, and a module's tables were hundreds of small GC objects (coordination census, 2026-11-25). So `describe_<id>(ref Permanent permanent)` and the registration carve them from one `Permanent`, whose blocks are 2 KB chunks (druntime's largest small size class, so the data stays in small pages and druntime's small-object collection threshold, live small pages times `heapSizeFactor`, is unchanged):
  - every list (`permanent.list!(T)(...)`): string lists, merged annotations, property, method, constructor, parameter and argument tables, compiled expressions, and annotation array values whose spelling fixes the element type (strings, members of one enum, annotations of one type; other arrays stay GC literals);
  - every annotation value's box (`permanent.any(value)`, a real `Box!T`, or inline as `Any.of` puts it);
  - every `Descriptor` (`permanent.make!(Descriptor)(...)`).

  The generator counts what each function carves and emits the reservation as `private enum size_t describeBytes_<id>` per descriptor and `permanentBytes` for the registration (its own tables plus its descriptors'), made of `Permanent.bytes!T`, `boxBytes!T` and `objectBytes!C` terms. The registration starts with `auto permanent = Permanent(permanentBytes);`. A proxy factory reserves `describeBytes_<id>` for its own descriptor. The reservation sizes the last chunk; any request still succeeds, and a piece larger than a chunk gets a block of its own, as a literal would (`Permanent.blocks` counts the blocks). Values are the literals' values: lists are mutable arrays whose appends copy, boxes are returned by `ref`, objects run their constructors. Blocks are scanned, never finalized, so only types with nothing to destroy are carved.
- **Symbols** in a generated module are `private` except the proxy and configuration subclasses (section 7), whose names end in `__FlintProxy` and `__FlintConfiguration`, and the `extern(C)` entry point. Generated names never start with a user's identifier followed by `__Flint` by accident: the generator rejects user identifiers containing `__Flint` (FLINT-E1104).
- Every generated module starts with `// Generated by Flint AOT (contract 1) from <source path>. Do not edit.`

## 4. Runtime types

Each module below is a leaf of `flint:engine-aot` with no `package.d`. Signatures are the contract; layout and internals are the runtime's. All functions are `@safe`. Startup code may allocate and throw; the per-request members marked *hot* are `nothrow` and must not allocate on the GC except where noted.

### 4.1 `flint.engine.aot.any`

```d
/// An erased value for Object-typed APIs: the value's type name and a small inline buffer.
struct Any
{
    static Any of(T)(T value);                 // copies value; inline when it fits in 2 words, else GC
    auto ref T get(T)();                       // by ref for boxed structs, by value otherwise; throws on mismatch
    bool isNull() const nothrow @nogc;         // Any.init, or a null class/array
    string typeName() const nothrow @nogc;     // fully qualified D name of the boxed type
    Object asObject();                         // class references only, else null
}
```

`T` covers class and interface references, structs, enums, arrays and the built-in scalars. `get!T` succeeds for the exact type, for a base class or interface of a boxed class, and for `const` views. Generated code mutates a boxed struct through `self.get!(T)().field = value`, so `get` returns boxed structs by reference.

### 4.2 `flint.engine.aot.descriptor`

```d
enum TypeKind { scalar, string_, enum_, array, struct_, class_, interface_ }

struct MergedAnnotation
{
    string type;                               // fully qualified annotation name
    Any value;                                 // the merged struct literal
    ubyte distance;                            // 0 = declared, 1+ = meta-annotation depth
    ubyte aggregateIndex;                      // contract 3: 0 = the element, n = its nth supertype or overridden method
    string error;                              // runtime merger only: AnnotationConfigurationException message
}

struct ParameterDescriptor
{
    string name;
    string type;                               // fully qualified D type, as written by the compiler
    MergedAnnotation[] annotations;
}

struct PropertyDescriptor                      // a JSON / binding / validation property
{
    string name;                               // Java Beans name: field name, or getX/isX/setX minus the prefix
    string type;
    MergedAnnotation[] annotations;            // from the field, getter and setter, merged
    Any function(ref Any self) @safe get;      // null when write-only
    void function(ref Any self, Any value) @safe set;   // null when read-only
}

struct ConstructorDescriptor
{
    ParameterDescriptor[] parameters;
    MergedAnnotation[] annotations;
    Any function(scope Any[] arguments) @safe invoke;
}

struct MethodDescriptor
{
    string name;
    string returnType;
    ParameterDescriptor[] parameters;
    MergedAnnotation[] annotations;            // method-level, merged with class-level advice
    uint index;                                // position in the declaring descriptor's methods
}

final class Descriptor
{
    this(string name, TypeKind kind);           // generated code calls exactly this constructor
    string name;                               // fully qualified D name
    TypeKind kind;
    string[] supertypes;                       // classes and interfaces, nearest first
    MergedAnnotation[] annotations;
    PropertyDescriptor[] properties;
    ConstructorDescriptor[] constructors;      // preferred first (@JsonCreator, single, or default)
    MethodDescriptor[] methods;                // only advised, mapped or listener methods
    Any function() @safe create;               // default instance; null when there is none
    string[] enumConstants;                    // for enums, in declaration order

    const(MergedAnnotation)* annotation(string type) const nothrow @nogc;   // hot
}
```

**Aggregates (contract 3).** `annotations` lists the element's own merged entries (aggregate 0) first, then those of each supertype, one entry per (type, aggregate), in Spring's `TYPE_HIERARCHY` order: the class, its interfaces (recursively), then the superclass and its interfaces; for a method, the methods it overrides or implements. `Descriptor.annotation(type)` reads aggregate 0 only (Spring's `INHERITED_ANNOTATIONS`, without `@Inherited`): stereotypes, `@Lazy`, `@Primary`, `@Scope` and conditions. The free `findAnnotation(annotations, type)`, `AnnotationUtils.findAnnotation`, `OrderUtils` and `MergedAnnotations.from(..., SUPERCLASS | TYPE_HIERARCHY)` read every aggregate and take the first aggregate holding the type, then the lowest distance, as Spring's `MergedAnnotationFinder` does. The generator never sets `error`; `descriptorOf!T`'s merger sets it on every entry of an element whose `@AliasFor` declarations are misconfigured (where the generator reports FLINT-E1103), and `MergedAnnotations.get` throws `AnnotationConfigurationException` with it.

`constructors` lists every public constructor of a struct or class, with parameter names and merged annotations. For a struct without a constructor (a Java record, rule R11) whose fields are all public, `constructors[0]` is its field-wise canonical constructor, with parameters named after the fields in declaration order. That is how message conversion and row mapping find a record's creator; contract 2 may add an explicit flag.

Descriptors exist for the types the generator found reachable: every request-body, response and `@ConfigurationProperties` type, every type with a constraint or Jackson annotation, every entity, every user struct and every non-bean user class, and their property types transitively. Built-in scalars, `string`, arrays, `flint.java.util.Optional!T` and `Nullable!T` are the runtime's own descriptors, looked up by the same type names.

### 4.3 `flint.engine.aot.bean`

```d
enum ScopeKind { singleton, prototype, request, session }

interface BeanFactory
{
    Object getBean(string name);
    Object getBeanOfType(string type, string qualifier = null);          // throws NoSuchBeanDefinitionException,
                                                                         // NoUniqueBeanDefinitionException
    Object findBeanOfType(string type, string qualifier = null);         // null when absent (optional injection)
    Object[] getBeansOfType(string type);                                // List<T> / T[] injection, in @Order order
    Any resolveValue(string expression, string targetType);              // @Value("${...}"), converted
    void bind(string prefix, Any target);                                // @ConfigurationProperties, JavaBean style
    Any bindConstructor(string prefix, string type);                     // constructor binding
}

struct BeanDefinition
{
    string name;
    string type;                               // the bean's declared type
    string[] types;                            // every type it can be injected as: class chain and interfaces
    string[] dependsOn;                        // @DependsOn, plus a @Bean method's configuration bean; strict
    string[] qualifiers;                       // @Qualifier values on the definition
    ScopeKind scope_;
    bool primary, fallback, lazyInit;
    int order;                                 // @Order, int.max when absent
    bool autoConfiguration;                    // defined by an auto-configuration class
    string source;                             // "src/shop/owners.d:12"
    Object function(BeanFactory factory) @safe create;
    void function(Object bean, BeanFactory factory) @safe initialize;   // @Autowired fields and setters,
                                                                        // @PostConstruct, afterPropertiesSet; or null
    void function(Object bean) @safe destroy;  // @PreDestroy, destroy(), inferred close/shutdown; or null
    bool function(ConditionContext context) @safe condition;            // null when unconditional
    Object function(Object target, BeanFactory factory) @safe proxy;    // wraps the target; null when not advised
}
```

### 4.4 `flint.engine.aot.condition`

```d
interface ConditionContext
{
    bool acceptsProfile(string profile);                 // Spring's default-profile rule included
    bool property(string name, string havingValue, bool matchIfMissing);   // @ConditionalOnProperty's rule
    bool hasBeanOfType(string type);                     // among definitions registered so far
    bool hasBeanNamed(string name);
    bool hasSingleCandidate(string type);
    bool isWebApplication(string type);                  // "ANY", "SERVLET", "REACTIVE"
}
```

`property` applies Boot's rule: with `havingValue` empty the property must exist and not equal `false` (ignoring case); otherwise it must equal `havingValue` (ignoring case). A `flint.*` name also matches its `spring.*` alias.

### 4.5 `flint.engine.aot.mapping`

```d
enum ArgumentKind { pathVariable, requestParam, requestHeader, requestBody, cookieValue,
                    modelAttribute, byType }

struct ArgumentSpec
{
    ArgumentKind kind;
    string name;                               // the attribute's name, else the D parameter name
    string type;                               // the parameter's fully qualified type
    bool required;
    string defaultValue;                       // ValueConstants.DEFAULT_NONE when absent
    bool validate;                             // @Valid or @Validated on the parameter
    MergedAnnotation[] annotations;
}

interface HandlerArguments
{
    Any get(size_t index);                     // resolved and converted to ArgumentSpec.type
}

alias HandlerInvoker = void function(Object bean, HandlerArguments arguments, ref Any result) @safe;

struct HandlerMapping
{
    string bean;                               // bean name of the controller
    string[] paths;                            // class and method paths already combined
    string[] methods;                          // HTTP methods; empty = all
    string[] params, headers, consumes, produces;
    ArgumentSpec[] arguments;
    string returnType;
    bool responseBody;                         // @ResponseBody, directly or through @RestController
    int responseStatus;                        // @ResponseStatus code, 0 when absent
    string reason;
    const(MethodDescriptor)* method;
    HandlerInvoker invoke;
    string source;
}

alias ExceptionInvoker = void function(Object bean, Exception exception, HandlerArguments arguments,
        ref Any result) @safe;

struct ExceptionHandlerSpec
{
    string bean;
    string[] exceptionTypes;                   // from @ExceptionHandler, else the exception parameter's type
    bool advice;                               // declared in a @ControllerAdvice
    string[] adviceBasePackages;               // @ControllerAdvice(basePackages); empty = all
    ArgumentSpec[] arguments;                  // the exception parameter is ArgumentKind.byType
    string returnType;
    bool responseBody;
    int responseStatus;
    ExceptionInvoker invoke;
    string source;
}
```

Invokers convert an engine result to user types only through `HandlerArguments.get` and `Any.get!T`; exceptions thrown by user code propagate to the dispatcher, which maps them through the exception handlers (ADR-030 section 4: engines return `Result`, generated dispatch is the user boundary).

### 4.6 `flint.engine.aot.event`

```d
struct EventListenerSpec
{
    string bean;
    string eventType;                          // the parameter's type
    string condition;                          // SpEL, empty when absent
    int order;
    void function(Object bean, ref Any event) @safe invoke;
}
```

### 4.7 `flint.engine.aot.proxy`

```d
struct Invocation
{
    const(MethodDescriptor)* method;
    Object target;
    Any[] arguments;                           // every argument, boxed, in order
    Any result;                                // set by proceed, or by an interceptor that short-circuits
}

alias Proceed = void delegate(ref Invocation invocation) @safe;

interface AdviceChain
{
    /// Run the interceptors that apply to invocation.method, then `proceed` unless one short-circuits.
    void invoke(ref Invocation invocation, scope Proceed proceed);
    /// For @Async: run the same chain later on the task executor; `proceed` owns copies of the arguments.
    void invokeDetached(Invocation invocation, Proceed proceed);
}

/// Build the chain for one proxied bean from the advisors the context registered (transaction, cache,
/// async, validation, method security, retry), ordered by their Ordered value.
AdviceChain adviceChain(BeanFactory factory, const Descriptor descriptor);

/// Spring's Objenesis: an instance of `proxyClass` whose fields hold their initial values and whose
/// constructor did not run. The proxy's base-class state is never read: every overridable public method
/// forwards to the target.
Object allocateProxy(const TypeInfo_Class proxyClass);
```

### 4.8 `flint.engine.aot.query`

```d
enum QueryKind { list, single, optional, count, exists, delete_, stream }

struct DerivedQuery
{
    string repository;                         // the repository interface
    string method;
    string domainType;
    string sql;                                // with ? placeholders in parameter order
    string[] parameters;                       // the method parameter feeding each placeholder
    string[] likeTransforms;                   // per placeholder: "", "starting", "ending", "containing"
    QueryKind kind;
    int limit;                                 // First/Top N, 0 = none
    string source;
}
```

### 4.9 `flint.engine.aot.registry`

```d
interface AotRegistry
{
    void begin(uint contractVersion, size_t modules);  // throws when the version is not the runtime's
    void bean(BeanDefinition definition);
    void descriptor(Descriptor descriptor);
    void mapping(HandlerMapping mapping);
    void exceptionHandler(ExceptionHandlerSpec handler);
    void listener(EventListenerSpec listener);
    void query(DerivedQuery query);
    void application(string type, string[] scanPackages);
    void end();
}

alias RegistryPopulator = void function(scope AotRegistry registry) @safe;
void installRegistry(RegistryPopulator populate) nothrow @nogc;   // called once, from a module constructor
RegistryPopulator installedRegistry() nothrow @nogc;              // null when the program has no registry
```

### 4.10 Contract 2 additions

All are fields with defaults, so contract-1 code still compiles. The generator emits:

| Type | Field | Value |
| --- | --- | --- |
| `BeanDefinition` | `uint rank` | definition order plus one; 0 means unranked |
| `HandlerMapping` | `string beanType`, `MergedAnnotation[] typeAnnotations` | the controller's type and its merged class-level annotations (class plus method `@CrossOrigin` combine) |
| `ExceptionHandlerSpec` | `string beanType`, `string[] adviceAssignableTypes`, `string[] adviceAnnotations`, `string[] produces` | `@ControllerAdvice` selectors and `@ExceptionHandler(produces)` |
| `ArgumentSpec` | `string elementType` | an array's element type, or the first template argument (`HttpEntity!T`, `Optional!T`) |
| `ConstructorDescriptor` | `bool canonical` | true for a record's field-wise constructor |
| `Descriptor` | `Any function(long ordinal) enumValue` | a user enum's constant by declaration index, `Any.init` out of range |
| `ConditionContext` | `bool isAutoConfigurationExcluded(string type)` | called on every auto-configuration definition |

Generated registries call `registry.begin(2, ...)`. The runtime's other builders (`length`, `element`, `fromElements`, `toKeys`, `toValues`, `fromEntries`, `wrap`, `unwrap`) cover built-in collection types; user descriptors leave them null.

### 4.11 Contract 3 additions

Method-level SpEL compiled to D (section 9.1), in the new leaf module `flint.engine.aot.expression`:

| Type | Member | Meaning |
| --- | --- | --- |
| `EvaluationContext` | `argument(i)`, `result()`, `methodName()`, `rootFunction(name, args)`, `rootProperty(name)`, `bean(name)`, `placeholder(text)` | what a compiled expression reads |
| `CompiledExpression` | `Any function(EvaluationContext) @safe` | one compiled expression |
| `ExpressionSpec` | `annotation`, `attribute`, `source`, `evaluate` | one SpEL-valued attribute |
| `MethodDescriptor` | `ExpressionSpec[] expressions`, `expression(annotation, attribute)` | the method's compiled expressions |
| `EventListenerSpec` | `CompiledExpression conditionExpression` | a compiled `@EventListener(condition)` |
| `MergedAnnotation` | `ubyte aggregateIndex` | 0 for the element, n for its nth supertype or overridden method (section 4.2) |
| `ArgumentSpec` | `Descriptor descriptor` | `descriptorOf!T` of the parameter type; null for scalars and `string` |
| `HandlerMapping` | `Descriptor returnDescriptor` | `descriptorOf!T` of the return type; null for scalars and `void` |

The descriptor fields spare dispatch a by-name table lookup per request; a null one means "look up the name", so older generated code keeps working. The generator sets them for request bodies and response bodies whose types the generated tables register, so they are the same instances a lookup would find. It fills a type descriptor's `annotations` with the type's own merge as aggregate 0, then each interface's and each superclass's, in TYPE_HIERARCHY order, as `descriptorOf!T` does. Method and parameter tables hold the method's (parameter's) own merge as aggregate 0, the overridden methods' as aggregates 1..n, and, for a method, the declaring class's advice annotations as the last aggregate. Every table is sorted by aggregate and nearest first within one, so a reader taking the first match in table order gets Spring's lookup order. A handler's `ArgumentSpec.annotations` keeps the merged view.

Generated registries call `registry.begin(3, ...)`.

### 4.12 Contract 4 additions

| Type | Member | Meaning |
| --- | --- | --- |
| `HandlerMapping` | `HandlerArrayInvoker invokeArguments` | `invoke` over the resolved `Any[]` arguments (each converted to its `ArgumentSpec.type`), so dispatch builds no `HandlerArguments` object and may pass stack storage |
| `ExceptionHandlerSpec` | `ExceptionArrayInvoker invokeArguments` | the same for exception handlers |

Both are null in older generated code; callers then use `invoke`.

Flint AOT emits both forms for every mapping and exception handler: `handle_<id>` and `handleArray_<id>` (`exception_<id>` and `exceptionArray_<id>`) share one call expression and differ only in reading argument `i` as `arguments[i]` instead of `arguments.get(i)`. The array form's parameter is `scope Any[] arguments` in an `@safe` module, so under `-preview=dip1000` a generated body cannot keep the slice; the CLI suite compiles the emitted signatures with a body that stores it and expects the compile to fail. The runtime still declares `aotContractVersion = 3`, so generated registries still call `registry.begin(3, ...)`; code that sets the fields needs flint:engine-aot from b181a524 on.

### 4.13 The per-endpoint fast path (default on)

Flint's per-endpoint fast path ([`phase1/fast-path.md`](phase1/fast-path.md)) adds one field and a leaf module, `flint.engine.aot.fast`. Nothing changes for generated code that doesn't use it.

| Type | Member | Meaning |
| --- | --- | --- |
| `HandlerMapping` | `FastInvoker fast` | after `invokeArguments`; **null means today's generic path** |
| `FastInvoker` | `bool function(Object bean, ref scope FastArguments arguments, ref Any result) @safe` | binds the handler's arguments from `arguments`, calls the handler and stores its value; returns `false` only before the handler ran |
| `FastArguments` | `bool delegate(string name, string defaultValue, bool required, out string value) @safe requestParamString` | `@RequestParam String` binding as `RequestParamMethodArgumentResolver` and the conversion service bind it; `false` declines (missing and required, or beyond the fast path's bounds); the value is GC memory |
| `FastExchange` | `method`, `path`, `acceptCount`, `accept`, `parameter`, `respond`, `materialize` | one request as the container holds it before any servlet object exists, borrowed for the call and passed `ref scope` |
| `FastDispatch` | `hasFastPath()`, `dispatchFast(ref scope FastExchange)` | implemented by `DispatcherServlet`; returns a `FastOutcome` (`declined`, `written`, `materialized`) |

**What Flint AOT emits.** Unless the build opts out (`FLINT_AOT_FAST_PATH=0`; `AotRequest.fastPath`, part of the output key), and only for a mapping that `fastShape` accepts (fast-path.md 3.1):
- `fast_<id>`;
- `mapping.fast = &fast_<id>;`;
- once per application with at least one such mapping, two beans in the application's own generated module:
  - `flintAotFastPathConfigurer`, the `WebMvcConfigurer` that builds the table;
  - `flintAotFastPathOffer`, the `WebServerFactoryCustomizer` that gives the servlet engine `serveFast`.

  Both are probed for presence like the date customizer. Without the option, or without a qualifying mapping, the output is byte-identical to a build without this section, and nothing of the fast path is linked.

## 5. Beans

### 5.1 What becomes a bean

- The application class carries `@FlintBootApplication`, or ADR-029's `@FlintApplication` (`flint.boot.FlintApplication`, a class used as a bare UDA), which is its alias. Flint AOT runs only when the closure contains `flint:engine-aot`, so ADR-029 applications on the legacy `flint.boot.application` keep their scan module.
- A class with a merged `@Component` (so also `@Service`, `@Repository`, `@Controller`, `@RestController`, `@Configuration`, `@ControllerAdvice`) in a scanned module. The scanned modules are those under the `@FlintBootApplication` class's package, or under `scanBasePackages`, exactly as `@ComponentScan` would see them.
- Each `@Bean` method of a `@Configuration` (or lite `@Component`) class, named after the method unless `@Bean(name)` says otherwise.
- A `@ConfigurationProperties` class listed by `@EnableConfigurationProperties` or found by `@ConfigurationPropertiesScan`, named `<prefix>-<fully qualified name>` as Boot names it.
- Each auto-configuration class of the closure, with its `@Bean` methods, after every user definition. A package lists its auto-configurations, one fully qualified class per line, in `META-INF/flint/flint.boot.autoconfigure.AutoConfiguration.imports` at its root, as Boot's `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` does. Auto-configuration beans are named by their fully qualified class name, as in Boot. The `exclude` and `excludeName` of `@FlintBootApplication` and `@EnableAutoConfiguration` (declared or merged) remove auto-configurations at build time. `flint.boot.enableautoconfiguration=false` (Boot's `spring.boot.enableautoconfiguration`) removes all of them at startup: every auto-configuration definition's condition starts with `c.property("flint.boot.enableautoconfiguration", "true", true)`. Boot's `spring.autoconfigure.exclude` list (`flint.autoconfigure.exclude`) removes single auto-configurations at startup through `!c.isAutoConfigurationExcluded("<fqn>")` (contract 2), which Boot's binder answers with relaxed binding.

The default bean name is the class name with its first letter lowered, keeping Spring's rule that a name starting with two capitals stays as it is (`URLService`).

### 5.2 Construction and injection

- **Constructor.** The `@Autowired` constructor, else the only constructor, else the default constructor; more than one candidate is FLINT-E1105. Each parameter becomes an injection point.
- **Injection points** resolve at startup, not at build time, because conditions are decided at startup:
  - a class or interface type: `getBeanOfType(type, qualifier)`;
  - `T[]` or `flint.java.util.List!T`: `getBeansOfType(T)`;
  - `Optional!T`, `Nullable!T` or `@Autowired(required: false)`: `findBeanOfType`;
  - `@Value("${...}")`: `resolveValue(expression, type)`;
  - a parameter whose type no definition in the closure can provide and that is not optional is FLINT-E1106, unless the type is an infrastructure type the runtime registers itself (`Environment`, `ApplicationContext`, `BeanFactory`, `ApplicationEventPublisher`, `ResourceLoader`, `ConversionService`).
- **Fields and setters** marked `@Autowired`, `@Value` or `@Inject` are set in `initialize`, private fields included (generated code addresses them with `tupleof`, which is how Flint replaces field reflection).
- **Lifecycle,** in Spring's order: injection, `@PostConstruct` methods (superclass first), `InitializingBean.afterPropertiesSet`, `@Bean(initMethod)`. At shutdown, in reverse creation order: `@PreDestroy`, `DisposableBean.destroy`, `@Bean(destroyMethod)` or an inferred public no-argument `close` or `shutdown`. Lifecycle methods must be public (a deviation: D gives another module no access to private methods; FLINT-E1108 names the method).

### 5.3 `@Configuration` classes

With `proxyBeanMethods` true (the default), the generator emits `<Name>__FlintConfiguration : <Name>`, which overrides every `@Bean` method to return the container's instance, so inter-bean method calls see singletons exactly as Spring's CGLIB-enhanced configuration does. The bean's own factory calls the original through `super`. A `final` or non-public `@Bean` method in such a class is FLINT-E1109, Spring's "@Bean method must not be private or final". Static `@Bean` methods are called directly and need no instance. With `proxyBeanMethods: false` the class is used as written.

### 5.4 Definition order and conditions

`dependsOn` names only `@DependsOn` values and, for a `@Bean` method, its configuration bean. A `@Bean` method's condition starts with `c.hasBeanNamed(<its configuration bean>)`, so its configuration bean exists whenever it does, and the runtime treats a missing name as an error, as Spring does for `@DependsOn`. Startup per bean: `create`, the `Aware` callbacks, `BeanPostProcessor.before`, `initialize(target)`, `BeanPostProcessor.after`, then `proxy(target)`.

The registry adds definitions in Spring's order (`ConfigurationClassParser`, then the deferred auto-configuration imports):

1. every scanned component's class definition, by module name and then source order;
2. for each scanned configuration in that order: the classes it `@Import`s, then its `@EnableConfigurationProperties` types, then its `@Bean` methods. Imported configurations therefore register before the importer's `@Bean` methods, which override theirs (gh-24643). An imported class is placed at its first importer, once every importer's class definition is decided. It is defined once, as scanned when it is also scanned. Its condition is `(c.hasBeanNamed(<importer>) || ...) && <its own terms>` over the importers that are defined. `@Import` on an implemented interface or a superclass counts (gh-34820);
3. the auto-configurations, sorted by `@AutoConfigureOrder`, `@AutoConfigureAfter` and `@AutoConfigureBefore`, each as its class definition, its imports and then its `@Bean` methods. Registration order is that order: the registry calls the generated modules in the order of their first definition, and each module registers its definitions in order. Since contract 2, every definition also carries `rank` (its position plus one), so the runtime can sort across modules.

The runtime walks that order once, at startup, before creating anything:

1. evaluate each definition's `condition` against what has been registered so far (`@ConditionalOnBean` and `@ConditionalOnMissingBean` therefore see user beans before auto-configurations, as in Boot);
2. drop the definitions whose condition is false, and the `@Bean` methods of a configuration class that was dropped;
3. create singletons in definition order, creating each dependency on demand; a cycle among constructor dependencies is `BeanCurrentlyInCreationException`.

The generator also checks at build time that the constructor dependencies have no cycle across all *potential* candidates, and reports one as FLINT-E1110 when every definition on it is unconditional.

### 5.5 How each condition is emitted

| Condition | Decided | Generated code |
| --- | --- | --- |
| `@ConditionalOnClass`, `@ConditionalOnMissingClass` | build time, in the extraction compile | the definition is emitted or left out; nothing at runtime |
| `@Profile("prod & !cloud")` | startup | `(c.acceptsProfile("prod") && !c.acceptsProfile("cloud"))`, the profile expression compiled to D at build time; a malformed expression is FLINT-E1102 |
| `@ConditionalOnProperty(prefix, name, havingValue, matchIfMissing)` | startup | one `c.property(...)` per name, joined with `&&` |
| `@ConditionalOnBooleanProperty` | build time validation and startup matching | Exactly one of `name` and `value` supplies the property names. Each name emits `c.property(name, havingValue ? "true" : "false", matchIfMissing)`. |
| `@ConditionalOnBean`, `@ConditionalOnMissingBean` | startup, in definition order | `c.hasBeanOfType(...)` / `!c.hasBeanOfType(...)`; with no type on a `@Bean` method, its return type |
| `@ConditionalOnSingleCandidate` | startup | `c.hasSingleCandidate(type)` |
| `@ConditionalOnWebApplication` | startup | `c.isWebApplication("SERVLET")` |
| legacy `@ConditionalOnConfig("section")` | startup | `c.property("section", "", false)` over the section's presence |
| `exclude`, `excludeName` | build time | the auto-configuration and its `@Bean` methods are left out |
| `flint.boot.enableautoconfiguration` | startup | `c.property("flint.boot.enableautoconfiguration", "true", true)` on every auto-configuration definition |

Every condition of a definition, including those inherited from its configuration class, is conjoined into one generated function:

```d
private bool condition_dataSource(ConditionContext c) @safe
{
    return c.acceptsProfile("prod") && c.property("flint.datasource.url", "", false)
        && !c.hasBeanOfType("flint.jdbc.datasource.DataSource");
}
```

## 6. Web, events and descriptors

- **Request mappings.** Class-level and method-level `@RequestMapping` attributes are merged and combined at build time with `PathPattern` combine rules (`/owners` + `/{id}` → `/owners/{id}`; an empty method path keeps the class path). A handler parameter without a binding annotation is a `requestParam` that is not required when its type is a simple type (scalar, `string`, enum, and arrays of them), and a `modelAttribute` otherwise, as in Spring MVC. Parameters whose type the runtime resolves itself (`HttpServletRequest`, `HttpServletResponse`, `HttpHeaders`, `Principal`, `Locale`, `UriComponentsBuilder`, `BindingResult`, `Errors`, `Model`) are `byType`.
- **Invokers** are one generated function per handler:
  ```d
  private void handle_OwnerController_findOwner(Object bean, HandlerArguments a, ref Any result) @safe
  {
      result = Any.of((cast(shop.web.OwnerController) bean).findOwner(a.get(0).get!long));
  }
  ```
- **Exception handlers** and **event listeners** get the same treatment, in `ExceptionHandlerSpec` and `EventListenerSpec` tables. A listener's event types are `@EventListener(classes)` (or `value`), else its single parameter's type, as in Spring's `resolveDeclaredEventTypes`; one `EventListenerSpec` is registered per type. A method with declared classes may take no parameter (it is called without the event) or one parameter that each class extends.
- **Descriptors** serve message conversion (Jackson), validation (the constraint annotations are in `PropertyDescriptor.annotations`, with `@Constraint` composition already merged) and `@ConfigurationProperties` binding. The runtime never asks the type system anything the descriptor does not hold.

## 7. AOP proxies

A bean is proxied when any of its public methods, or its class, carries a merged advice annotation from section 2.2. The generator emits one subclass per proxied class:

```d
final class OwnerService__FlintProxy : shop.owners.OwnerService
{
    private shop.owners.OwnerService __flintTarget;
    private AdviceChain __flintChain;
    private Descriptor __flintDescriptor;

    private this()                                   // never called; D needs it when the base has no default
    {
        super((shop.owners.OwnerStore).init);
    }

    void __flintBind(shop.owners.OwnerService target, AdviceChain chain, Descriptor descriptor)
    {
        __flintTarget = target;
        __flintChain = chain;
        __flintDescriptor = descriptor;
    }

    override string findName(long id)                // advised
    {
        auto invocation = Invocation(&__flintDescriptor.methods[0], __flintTarget, [Any.of(id)]);
        __flintChain.invoke(invocation, (ref Invocation call) { call.result = Any.of(__flintTarget.findName(id)); });
        return invocation.result.get!(string)();
    }

    override string describe(long id)                // not advised: forwards
    {
        return __flintTarget.describe(id);
    }
}

private Object proxy_ownerService(Object target, BeanFactory factory)
{
    auto permanent = Permanent(describeBytes_OwnerService);
    auto descriptor = describe_OwnerService(permanent); // the same builder the registration uses
    auto proxy = cast(OwnerService__FlintProxy) allocateProxy(typeid(OwnerService__FlintProxy));
    proxy.__flintBind(cast(shop.owners.OwnerService) target, adviceChain(factory, descriptor), descriptor);
    return proxy;
}
```

- **Spring's self-invocation semantics.** The target is an ordinary instance constructed by the bean's factory. The proxy forwards every overridable public method to it, so a call from inside the target (`this.findName(...)` from `rename`) reaches the target directly and runs no advice, as with Spring's JDK and CGLIB proxies. Callers that received the bean from the container hold the proxy.
- **What can be advised:** public, non-final, non-static, `@safe` methods that are not `nothrow`, `@nogc` or `pure`. A `final` method on a proxied class runs on the proxy instance with initial field values, as with CGLIB; the generator warns about each one (FLINT-E1111, a warning). A protected or private advised method is FLINT-E1112: D does not let the proxy call another instance's protected method. `@system` methods inherited from `Object` (`toString`) are left to the base class.
- **Order at startup:** the runtime calls `create`, then `initialize` on the target, then `proxy` on the target, and exposes the proxy; `destroy` receives the target. Fields read directly on the proxy are never initialized, as with CGLIB.
- **`@Async`** methods return `void` and call `invokeDetached`, whose `proceed` closure owns copies of the arguments; a non-`void` `@Async` method is FLINT-E1113 until `flint.java.util.concurrent` lands.
- **Ordering, propagation, rollback rules, cache resolution, retry and security expressions** are the runtime's: the generated code only provides the merged annotations on the `MethodDescriptor` and the boxed arguments and result.
- **Interfaces.** When the bean is injected by an interface it implements, the same subclass serves, so Flint never needs a second, JDK-style proxy.

### 7.1 Static AspectJ before advice

A scanned singleton component with `@Aspect` may declare public `@safe` instance methods with `@Before`, no
parameters and a `void` return type. An aspect on its own does not register a component. This slice accepts
unconditional singleton aspect beans and the selector `execution(* qualified.Type.method(..))`. The class name
must be the extracted D name of a concrete class with no extracted subclasses. The method name selects its declared
instance overloads across return and parameter types. Selectors that require inherited dispatch, named pointcuts,
other advice kinds, and argument bindings require later proxy slices.

Flint AOT selects methods before writing the existing proxy subclass. It records their descriptor indexes in a
generated advisor, registered in the same container as transaction, cache and other advisors. When a bean's
chain is assembled, the generated advisor checks its target name and those indexes. Advising the call executes the
aspect method and continues through the same chain. Each advisor resolves and caches the aspect singleton on the
first invocation, so chain assembly can finish before resolving an aspect that may inject the bean being proxied.
Equal-order advisors keep
definition order, with the generated aspect advisors registered after the ordinary definitions. An explicit
`@Order` sets the aspect order, with `int.max` as the default. Runtime ordering through `Ordered` is deferred.

Unselected methods follow the existing forwarding rule, and target self-invocations bypass the subclass. The
generated advisor uses existing contract 3 interfaces and fields. An unsupported selector produces FLINT-E1180
on the advice declaration. Unsupported advice or registration shapes produce FLINT-E1181.

## 8. Derived queries

Methods of an interface that derives from `flint.data.repository.Repository!(T, ID)` (directly or through `CrudRepository`, `ListCrudRepository`, `PagingAndSortingRepository`) and carries no `@Query` are parsed with Spring Data's `PartTree` grammar:

- subjects `find`, `read`, `get`, `query`, `search`, `stream`, `count`, `exists`, `delete`, `remove`, with `Distinct` and `First`/`Top<N>`;
- predicates joined by `And` and `Or`, over properties of the domain type (nested paths are FLINT-E1114 until Data JDBC lands their joins);
- the operators `Is`, `Equals`, `Not`, `LessThan`, `LessThanEqual`, `GreaterThan`, `GreaterThanEqual`, `Before`, `After`, `Between`, `IsNull`, `IsNotNull`, `NotNull`, `Like`, `NotLike`, `StartingWith`, `EndingWith`, `Containing`, `NotContaining`, `In`, `NotIn`, `True`, `False`, `IgnoreCase`, `AllIgnoreCase`;
- `OrderBy<Property>Asc|Desc`.

Table and column names follow Spring Data Relational's default naming (snake case), overridden by `@Table` and `@Column`. The SQL is ANSI with `?` placeholders. A method name the grammar rejects, or a property the domain type lacks, is FLINT-E1101 with Spring Data's message. The repository implementation classes that run these queries arrive with `flint-data-jdbc` in Phase 2; Phase 1 emits the `DerivedQuery` table only.

## 9. SpEL

SpEL is compiled to typed D at build time (`engine/aot/spel.d`); nothing interprets it at runtime.

- **`@Value("#{...}")`** compiles completely today, including templates that mix text and several `#{...}` (`"Shop #{...} is #{...}"`). The generated factory computes the value inline and converts it to the parameter's or field's type.
- **The subset:**
  - literals: integers, reals, `'text'` with `''` escapes, `true`, `false`, `null`. Literals are typed as Spring's
    tokenizer types them: an unsuffixed integer (decimal or `0x` hex) is an `int`, and one outside the int range is
    an error (Spring's NOT_AN_INTEGER); `L` makes a `long`; a `.`, an exponent or `d` makes a `double`, and `f` a
    `float`. Operators apply Java's binary numeric promotion, so `int` arithmetic wraps at 32 bits.
    `String.length()` and `size()` are `int`. Real literals go through `flint.engine.aot.expression.spelDouble`
    (`spelFloat`), which keeps DMD from folding them at 80-bit precision, so `0.1 + 0.2` is Java's
    0.30000000000000004. Placeholders in a numeric position still convert to `long`. Integer `^` is Spring's
    `(long) Math.pow` (`spelPowLong`: a negative exponent truncates toward zero, an overflow saturates); it is typed
    `long`, where Spring returns an `int` when both operands are ints and the result fits, with the same value. The shared parity corpus
    `tests/aot/spel-parity/cases.json` runs every case through this compiler and the runtime interpreter
    (`flint:expression`);
  - `${key:default}` placeholders. Spring resolves them before parsing, so a placeholder takes the type its use needs: a number beside a number, `true`/`false` in a boolean context, a string elsewhere, including inside quotes;
  - `@bean` references, typed from the bean definitions by name, with their public fields, Java Beans getters (`@clock.time` → `getTime()`) and public methods;
  - `#variables` and root functions where the use site provides them (section 9.1);
  - the arithmetic operators `+ - * / % ^` (also `div`, `mod`), with `+` concatenating when either side is text;
  - comparisons `== != < <= > >=` (also `eq ne lt le gt ge`) and `null` tests. Textual operators (`eq`, `and`,
    `div`, ...) ignore case, as Spring's do. Strings order by UTF-16 code units, as `String.compareTo`
    (`spelCompareStrings`). `null` orders before every value (Spring's StandardTypeComparator), and the other
    operand is still evaluated;
  - `and`, `or`, `not`, `&&`, `||`, `!`;
  - `?:` ternary, `?:` Elvis and `?.` safe navigation. A ternary whose branches differ in type yields a runtime
    `Any` holding the chosen branch's own value, as Spring's does (`true ? 1 : 2L` is an Integer). Elvis takes the
    fallback, evaluated only then, for null or an empty string; a number or boolean is never null, so it is the
    value itself; a runtime value is tested by `spelElvis`;
  - indexing of arrays and strings;
  - `length()`, `size()`, `isEmpty()`, `toUpperCase()`, `toLowerCase()`, `trim()`, `startsWith()`, `endsWith()` and `contains()` on strings.
- **Outside the subset** (`T(...)`, `new`, `.?[...]` selection, `.![...]` projection, `matches`, `instanceof`, `between`, unknown names): FLINT-E1107 with the construct named. Expressions in the subset never fail at runtime for a reason the build could have seen.
- **Generated code** may call `std.conv.to`, `std.uni.toUpper`/`toLower`, `std.string.strip` and `std.algorithm.searching.startsWith`/`endsWith`/`canFind`, through `imported!`.

### 9.1 Method-level expressions

`@Cacheable(key, condition, unless)`, `@CacheEvict`, `@CachePut`, `@PreAuthorize`, `@PostAuthorize` and `@EventListener(condition)` use the same compiler. There `#name`, `#p0` and `#a0` are the method's arguments (typed from its signature), `#result` is its result, `#root.methodName` and `#root.args` are available, and the security root's functions (`hasRole`, `hasAnyRole`, `hasAuthority`, `isAuthenticated`, `principal`, `authentication`) are runtime calls whose results are converted where used. Each compiles to a function `Any spel_<type>_<method>_<n>(EvaluationContext context)`, listed in the method descriptor's `expressions` (contract 3), or set as `EventListenerSpec.conditionExpression`. petclinic-rest's `@PreAuthorize("hasRole(@roles.OWNER_ADMIN)")` becomes `context.rootFunction("hasRole", [Any.of((cast(Roles) context.bean("roles")).OWNER_ADMIN)])`.

A method carrying `@Cacheable`, `@CachePut`, `@CacheEvict` or `@Caching` also gets a container descriptor
(`descriptorOf`, contract 3's `length`/`element` builders) for each array or collection parameter. The cache advice's
key generator compares those arguments element by element, as Spring's `SimpleKey` does with `Arrays.deepEquals`,
through the descriptors it resolves once per advised method.

### Jakarta Persistence entity mappings

When the application includes `flint:engine-jpa`, Flint AOT reads direct Jakarta `@Entity` declarations in
application source, and the `@MappedSuperclass` declarations available to extraction. Each generated source
unit with entities exports `jpaMappings()` returning an `immutable(EntityMapping)[]`. The provider can consume
that table directly. The generic AOT registry has no dependency on the provider.

The first slice supports one primary table, one `@Id`, public instance fields of type `long`, `string` or
`LocalDate`, and a reachable no-argument constructor. Field ordinals start at the oldest mapped superclass.
`@Transient` fields do not have ordinals. SQL column nullability and D field null representability are recorded
separately. A unit with a DATE mapping also exports `jpaTypedCodec()` for the standard JDBC DATE conversions.

Generated thunks use checked casts, and the provider's separate exact-type guard validates concrete entities.
`PostLoad` invokes fieldless listeners first, then mapped-superclass and entity callbacks. Stateful listeners
need a persistence-unit owner. Unsupported mapping shapes use FLINT-E1140–E1143.

## 10. Diagnostics

| Code | Meaning |
| --- | --- |
| FLINT-E1100 | the extraction compile failed: the compiler's own errors follow |
| FLINT-E1101 | a derived-query method name or property is invalid |
| FLINT-E1102 | a `@Profile` expression is malformed |
| FLINT-E1103 | `@AliasFor` attributes disagree, or an alias names a missing attribute |
| FLINT-E1104 | a user identifier contains `__Flint`, which generated code reserves |
| FLINT-E1105 | a bean class has several constructor candidates and none is `@Autowired` |
| FLINT-E1106 | an injection point has no potential candidate in the closure |
| FLINT-E1107 | a SpEL expression is outside the compiled subset, or names something that does not exist |
| FLINT-E1108 | a lifecycle or injected method is not public |
| FLINT-E1109 | a `@Bean` method of a proxied configuration is final or not public |
| FLINT-E1110 | unconditional beans form a constructor-injection cycle |
| FLINT-E1111 | a final public method of a proxied class will not be advised (a warning) |
| FLINT-E1112 | an advised method is protected or private |
| FLINT-E1113 | an `@Async` method returns a value |
| FLINT-E1114 | a derived query uses a nested property path |
| FLINT-E1115 | a bean (a `@Bean` method's return type) is not a class or interface |
| FLINT-E1116 | a generated module for a module outside `src/` would import a project module |
| FLINT-E1117 | a `META-INF/services` provider's module is not in the build closure |
| FLINT-E1118 | `@ConditionalOnBooleanProperty` needs exactly one of `name` or `value` |

Every diagnostic names the source file and line of the declaration that caused it.

AspectJ diagnostics:

| Code | Meaning |
| --- | --- |
| FLINT-E1180 | an AspectJ execution selector uses unsupported syntax, requires inherited dispatch, or names an undeclared method |
| FLINT-E1181 | an AspectJ advice or registration shape is unsupported |

Reserved blocks for the Phase 2 lanes (flint-aot, 2026-11-26). A lane takes the next free code in its block, adds its
row above in the commit that first emits it, and has flint-aot review the commit:

| Block | Owner | For |
| --- | --- | --- |
| FLINT-E1118–E1129 | flint-aot | general generator diagnostics |
| FLINT-E1130–E1139 | `sol-data` | Data JDBC repositories, `@Query`, repository beans |
| FLINT-E1140–E1159 | `sol-jpa` | JPA entity mappings, accessors, lazy proxies, build-time JPQL |
| FLINT-E1160–E1169 | `sol-template` | SpEL beyond section 9, compiled templates |
| FLINT-E1170–E1179 | `sol-context` | cache, scheduling, `@Async`, HTTP service proxies |
| FLINT-E1180–E1189 | `sol-aop` | aspects, pointcut expressions, programmatic proxies |

## 11. Ownership and change

- The generator, the extractor and this document belong to the flint-aot session in `flint`. Runtime signatures in section 4 change only by a contract version bump agreed with framework-core.
- The runtime owns everything behind the signatures: storage, ordering of advisors, conversion, binding and dispatch.
- An annotation's owner may add attributes freely; renaming or removing one that section 2.2 lists needs a contract change.
- The generator's tests (`apps/flint/test/flint_tool/engine/aot_test.d`) generate the sample in `tests/aot/sample`, compile it with `packages/engine-aot` and a minimal test container (`tests/aot/support/aot_context.d`), run it, and compare its output with `tests/aot/sample/expected.txt`. The annotation modules in `tests/aot/annotations` are fixtures with Spring's names, not the framework's.

## 12. Status

Implemented and tested on DMD and LDC: extraction (section 1.1), interface keys and the cache (1.2), merging with meta-annotations and `@AliasFor` (2.1, except the "not yet" items), bean definitions with constructor, field and `@Value` injection, lifecycle, `@Configuration` subclasses, definition order and every condition of section 5.5, proxies (section 7), request-mapping, exception-handler and event-listener tables, descriptors with fields, `tupleof` access and Java Beans accessors (inherited ones included), creators and enum values, derived queries (section 8), SpEL compiled to D for `@Value` and method-level annotations (section 9), and every diagnostic of section 10. The gs-rest-service and petclinic-rest shapes generate and type-check against the real framework, Boot and validation annotations. `flint build` runs the step when a module mentions `FlintBootApplication`.

The legacy `flint:engine-di` container keeps its compile-time `import("application.toml")` for ADR-028 applications. Flint AOT applications do not use it: their `@ConditionalOnConfig` and `@ConditionalOnProperty` are startup conditions (section 5.5). Removing the legacy path waits for the ADR-028 golden applications to move to `@FlintBootApplication`.

Not yet: `@ConfigurationProperties` constructor binding (JavaBean binding is generated), `@Inherited` and interface-method annotations (section 2.1), and repository implementation classes (Phase 2, with `flint-data-jdbc`).

## 13. Measured cost in the edit loop

Measured on 2026-11-23 on a 32-thread AMD Ryzen AI MAX+ 395 workstation (Linux x86-64, the forked DMD 2.114.0) under a load average of about 9 from other sessions. This is an ordinary workstation, not the designated runner. Each cell is the median of nine runs (five for cold runs) of the generator step exactly as `flint build` runs it (`runAot`, non-optimized build of the tool), timed from process start to exit. The edits alternate between two texts, so every run sees a real change.

| App | Cold: all modules extracted | No change | Method-body edit | Interface edit (one route's path) |
| --- | --- | --- | --- | --- |
| `tests/aot/sample` (5 modules) | 78.7 ms | 2.1 ms | 2.0 ms, nothing extracted or written | 36.9 ms: 1 module extracted (28 ms compile), 1 file written |
| synthetic, 21 modules, each importing the previous | 131.9 ms | 3.2 ms | 3.3 ms | 146.6 ms: the edited module and its 19 transitive importers extracted |
| synthetic, 101 modules, the same chain | 532.9 ms | 20.4 ms | 20.5 ms | 530.7 ms: 100 modules extracted (439 ms compile) |

**The benchmark's incremental edit.** `tools/spring_builds.py` measures an incremental build by appending `enum flintMeasureEdit0 = 0;` to the app's `package.d`. That used to change the module's extraction key: the step ran one extraction compile and re-rendered every generated module, 81 ms in an optimized build of the tool (63 ms compile). Since a constant nothing names is left out of the key, and the output key follows model content, the step takes 3 ms, with nothing extracted or written. An edit to a name used elsewhere (a constant in an annotation) still re-extracts, and regenerates only if a model changed.

**Cold builds and the shared cache.** gs-rest-service's cold step extracts 23 modules: its own, and 22 Boot auto-configuration modules that import most of the web stack. That compile is 0.52 s, 38% of the cached cold `flint build` m7 measured. With the shared cache warm, the step extracts only the app module: 604 ms becomes 143 ms (59 ms of compile; non-optimized tool, median of three), with byte-identical output.

A regenerated module compiles in about 10 ms (`dmd -c`, checked profile), in parallel with the rest of the build.

**Against Go.** The recorded Linux edit builds are 97.1 ms for Flint's REST application and 194.2 ms for Go's (`docs/milestones/06-linux-compile-fork.md`), leaving 97 ms of headroom. On an application of Phase 1's size, a body edit adds 2 ms and an interface edit adds about 37 ms plus one 10 ms parallel compile, so the edit loop stays below Go's. An interface edit to a module that many others import (transitively) re-extracts all of them, at about 4.4 ms each, because a module's evaluated attributes and supertypes can depend on declarations several imports away. Before Phase 1 measures PetClinic's edit loop on the runner, the extraction should gain early cutoff: compare each re-extracted model with the cached one and stop at importers whose inputs did not change.

How the cost came down while building it: the first describer built each module's model as one CTFE string and deduplicated annotation types with a linear scan, taking 0.84 s and 680 MB for 100 modules; printing one line per type, announcing each annotation type once per compile from a template instance, and skipping `Object`'s methods brought that to 0.42 s and 375 MB. Splitting the cache into keys and per-module model files took the no-change path for 101 modules from 71 ms to 18 ms. The compile server neither helps nor hurts extraction: its preloaded Phobos is irrelevant to a compile that imports none, and the describer's CTFE dominates.
