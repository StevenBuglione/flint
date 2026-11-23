# Flint AOT contract

Flint AOT is the build step that replaces Spring's runtime reflection (ADR-030 section 3). It reads the application's modules with the compiler's semantic analysis and writes plain D that the framework runtime, `flint.engine.aot`, consumes at startup. This document is the contract between the two sides:

- **the generator** lives in the `flint` repository, `apps/flint/src/flint_tool/engine/aot/`;
- **the runtime** (`flint.engine.aot.*`, DUB `flint:engine-aot`) lives in `flint-framework` and is implemented by the framework-core session;
- **the annotations** the generator recognizes are owned by the framework, Boot and portfolio packages that declare them.

Contract version: **1**. A change to anything below bumps the version, and the generator writes the version into every generated module, so a mismatched runtime fails to compile instead of misbehaving.

## 1. What runs when

| Step | When | Cost in the edit loop |
| --- | --- | --- |
| Interface hash of every module under `src/` and of every auto-configuration module the closure lists | every `flint build` | lexing only: about 1 ms per thousand lines |
| Semantic extraction of the modules whose interface key changed | only when a key changed | one `-o-` compile through the compile server |
| Generation of the modules whose model, or a model they consulted, changed | only then | in-process, no compile |
| Compiling the generated modules | DUB, like any source; unchanged files are not rewritten | only for regenerated modules |

Editing a method body changes no interface key, so it runs no extraction, rewrites no generated file and recompiles nothing generated.

### 1.1 Semantic extraction

DMD's `-X` JSON leaves out UDAs and does not evaluate attribute arguments, and the compile server refuses `-X`. The generator therefore extracts the model with the compiler itself: it writes a root module, `.flint/generated/aot-extract/flint_aot_extract.d`, that imports the modules to extract and evaluates a compile-time describer over each of them (`__traits(derivedMembers)`, `getAttributes`, `getOverloads`, `__parameters`, `tupleof`, `fullyQualifiedName`). The describer prints one JSON document per module through `pragma(msg)`. The compile is an ordinary `dmd -o-` with the project's import paths and `-preview=dip1000`, so the compile server serves it and only signatures are analysed; function bodies of the extracted modules are never compiled.

The model therefore holds real types (fully qualified, after aliases), evaluated attribute values (enum members by name, constants folded), and the attribute types' own declarations. Class-presence conditions are answered in the same compile with `__traits(compiles, { import M : T; })`.

The extractor and the model's JSON schema (`flint.aot.model/1`) are internal to the generator. The runtime never sees them.

### 1.2 Interface keys

A module's interface text is its token stream with every function body removed, except:

- bodies of functions whose return type is inferred (`auto`, `auto ref`), which are part of their signature;
- bodies of functions whose name appears anywhere else in the interface text (in an attribute argument, an enum or static initializer, a template constraint or a mixin), repeated until no new name appears, because CTFE may run them;
- function literals inside initializers, which are kept with their initializer.

`unittest` blocks are removed, and string literals keep their full text. A module's **extraction key** hashes its interface text, the interface texts of the project modules it imports (transitively), the generator version, the compiler identity, the platform version and the closure's package hashes. The **output key** hashes every extraction key and the class-presence answers: while it is unchanged, nothing is analysed or written. When it changes, every generated module is re-rendered, but a file is rewritten only when its text changed, so DUB recompiles only those. The keys and the cached models live in `.flint/cache/aot/state.json`.

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
- a meta-annotation's attributes take the values the declaring annotation gives through explicit `@AliasFor(annotation: ...)` and through implicit aliases (two attributes that alias the same meta-attribute alias each other);
- a convention-free alias that keeps its default does not override;
- the nearest declaration wins; for equal distance, the first declared wins;
- the same alias pair given two different non-default values is an error (FLINT-E1103), as Spring's `AnnotationConfigurationException` is;
- class-level advice annotations apply to every public method that declares none of its own;
- not yet: class-level annotations inherited from superclasses through `@Inherited`, and advice annotations declared on interface methods (Spring 6+ applies them to the implementing methods).

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
- **Imports of a generated module:** the `flint.engine.aot.*` modules it uses, and, with `static import`, its own user module, the modules declaring the types it spells out (a constructor parameter's type, a proxied method's parameter types) and the annotation and enum modules of the merged values it builds. It never imports another generated module. Everything it spells is qualified, so nothing it imports can shadow a name. In tables, types are named by their fully qualified string.
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
- **Generated code is plain D:** `@safe:`, no template declarations, no string mixins, no `__traits`. The only templates it instantiates are `Any.of!T` and `Any.get!T`, and the annotation struct literals it constructs are not templates.
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

## 5. Beans

### 5.1 What becomes a bean

- The application class carries `@FlintBootApplication`, or ADR-029's `@FlintApplication` (`flint.boot.FlintApplication`, a class used as a bare UDA), which is its alias. Flint AOT runs only when the closure contains `flint:engine-aot`, so ADR-029 applications on the legacy `flint.boot.application` keep their scan module.
- A class with a merged `@Component` (so also `@Service`, `@Repository`, `@Controller`, `@RestController`, `@Configuration`, `@ControllerAdvice`) in a scanned module. The scanned modules are those under the `@FlintBootApplication` class's package, or under `scanBasePackages`, exactly as `@ComponentScan` would see them.
- Each `@Bean` method of a `@Configuration` (or lite `@Component`) class, named after the method unless `@Bean(name)` says otherwise.
- A `@ConfigurationProperties` class listed by `@EnableConfigurationProperties` or found by `@ConfigurationPropertiesScan`, named `<prefix>-<fully qualified name>` as Boot names it.
- Each auto-configuration class of the closure, with its `@Bean` methods, after every user definition. A package lists its auto-configurations, one fully qualified class per line, in `META-INF/flint/flint.boot.autoconfigure.AutoConfiguration.imports` at its root, as Boot's `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` does. Auto-configuration beans are named by their fully qualified class name, as in Boot. The `exclude` and `excludeName` of `@FlintBootApplication` and `@EnableAutoConfiguration` (declared or merged) remove auto-configurations at build time. `flint.boot.enableautoconfiguration=false` (Boot's `spring.boot.enableautoconfiguration`) removes all of them at startup: every auto-configuration definition's condition starts with `c.property("flint.boot.enableautoconfiguration", "true", true)`. Boot's `spring.autoconfigure.exclude` list (`flint.autoconfigure.exclude`) needs a membership test that `ConditionContext` lacks and is proposed for contract 2.

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

`dependsOn` names only `@DependsOn` values and, for a `@Bean` method, its configuration bean. A `@Bean` method's condition includes its class's, so its configuration bean exists whenever it does, and the runtime treats a missing name as an error, as Spring does for `@DependsOn`. Startup per bean: `create`, the `Aware` callbacks, `BeanPostProcessor.before`, `initialize(target)`, `BeanPostProcessor.after`, then `proxy(target)`.

The registry adds definitions in Spring's order: user components by module name and then source order, then the `@Bean` methods of each configuration class after the class itself, then auto-configurations sorted by `@AutoConfigureOrder`, `@AutoConfigureAfter` and `@AutoConfigureBefore`, then their `@Bean` methods. Registration order is that order: the registry calls the generated modules in the order of their first definition, and each module registers its definitions in order. (Two auto-configuration modules whose classes interleave in that order would register out of order; a `rank` field in a later contract version would remove the limit.)

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
| `@ConditionalOnBooleanProperty` | startup | `c.property(name, value ? "true" : "false", matchIfMissing)` |
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
- **Exception handlers** and **event listeners** get the same treatment, in `ExceptionHandlerSpec` and `EventListenerSpec` tables.
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
    auto descriptor = describe_OwnerService();       // the same builder the registration uses
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

## 8. Derived queries

Methods of an interface that derives from `flint.data.repository.Repository!(T, ID)` (directly or through `CrudRepository`, `ListCrudRepository`, `PagingAndSortingRepository`) and carries no `@Query` are parsed with Spring Data's `PartTree` grammar:

- subjects `find`, `read`, `get`, `query`, `search`, `stream`, `count`, `exists`, `delete`, `remove`, with `Distinct` and `First`/`Top<N>`;
- predicates joined by `And` and `Or`, over properties of the domain type (nested paths are FLINT-E1114 until Data JDBC lands their joins);
- the operators `Is`, `Equals`, `Not`, `LessThan`, `LessThanEqual`, `GreaterThan`, `GreaterThanEqual`, `Before`, `After`, `Between`, `IsNull`, `IsNotNull`, `NotNull`, `Like`, `NotLike`, `StartingWith`, `EndingWith`, `Containing`, `NotContaining`, `In`, `NotIn`, `True`, `False`, `IgnoreCase`, `AllIgnoreCase`;
- `OrderBy<Property>Asc|Desc`.

Table and column names follow Spring Data Relational's default naming (snake case), overridden by `@Table` and `@Column`. The SQL is ANSI with `?` placeholders. A method name the grammar rejects, or a property the domain type lacks, is FLINT-E1101 with Spring Data's message. The repository implementation classes that run these queries arrive with `flint-data-jdbc` in Phase 2; Phase 1 emits the `DerivedQuery` table only.

## 9. SpEL

Expressions in `#{...}` (`@Value`), `@Cacheable(key, condition, unless)`, `@EventListener(condition)` and `@PreAuthorize` will be compiled to D later in Phase 1. Until then the generator reports FLINT-E1107 for `#{...}` in `@Value`, and passes the other expression strings through in the merged annotations for a runtime interpreter. `${...}` placeholders are not SpEL and work now.

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
| FLINT-E1107 | SpEL is not compiled yet |
| FLINT-E1108 | a lifecycle or injected method is not public |
| FLINT-E1109 | a `@Bean` method of a proxied configuration is final or not public |
| FLINT-E1110 | unconditional beans form a constructor-injection cycle |
| FLINT-E1111 | a final public method of a proxied class will not be advised (a warning) |
| FLINT-E1112 | an advised method is protected or private |
| FLINT-E1113 | an `@Async` method returns a value |
| FLINT-E1114 | a derived query uses a nested property path |
| FLINT-E1115 | a bean (a `@Bean` method's return type) is not a class or interface |

Every diagnostic names the source file and line of the declaration that caused it.

## 11. Ownership and change

- The generator, the extractor and this document belong to the flint-aot session in `flint`. Runtime signatures in section 4 change only by a contract version bump agreed with framework-core.
- The runtime owns everything behind the signatures: storage, ordering of advisors, conversion, binding and dispatch.
- An annotation's owner may add attributes freely; renaming or removing one that section 2.2 lists needs a contract change.
- The generator's tests (`apps/flint/test/flint_tool/engine/aot_test.d`) generate the sample in `tests/aot/sample`, compile it with `packages/engine-aot` and a minimal test container (`tests/aot/support/aot_context.d`), run it, and compare its output with `tests/aot/sample/expected.txt`. The annotation modules in `tests/aot/annotations` are fixtures with Spring's names, not the framework's.

## 12. Status

Implemented and tested on DMD and LDC: extraction (section 1.1), interface keys and the cache (1.2), merging with meta-annotations and `@AliasFor` (2.1, except the "not yet" items), bean definitions with constructor, field and `@Value` injection, lifecycle, `@Configuration` subclasses, definition order and every condition of section 5.5, proxies (section 7), request-mapping, exception-handler and event-listener tables, descriptors with fields, `tupleof` access and Java Beans accessors, derived queries (section 8), the SpEL diagnostic (section 9) and every diagnostic of section 10. `flint build` runs the step when a module mentions `FlintBootApplication`.

The legacy `flint:engine-di` container keeps its compile-time `import("application.toml")` for ADR-028 applications. Flint AOT applications do not use it: their `@ConditionalOnConfig` and `@ConditionalOnProperty` are startup conditions (section 5.5). Removing the legacy path waits for the ADR-028 golden applications to move to `@FlintBootApplication`.

Not yet: `@ConfigurationProperties` constructor binding (JavaBean binding is generated), `@Retryable`'s and `@Cacheable`'s SpEL, `@Inherited` and interface-method annotations (section 2.1), and repository implementation classes (Phase 2, with `flint-data-jdbc`).

## 13. Measured cost in the edit loop

Measured on 2026-11-23 on a 32-thread AMD Ryzen AI MAX+ 395 workstation (Linux x86-64, the forked DMD 2.114.0) under a load average of about 9 from other sessions. This is an ordinary workstation, not the designated runner. Each cell is the median of nine runs (five for cold runs) of the generator step exactly as `flint build` runs it (`runAot`, non-optimized build of the tool), timed from process start to exit. The edits alternate between two texts, so every run sees a real change.

| App | Cold: all modules extracted | No change | Method-body edit | Interface edit (one route's path) |
| --- | --- | --- | --- | --- |
| `tests/aot/sample` (5 modules) | 78.7 ms | 2.1 ms | 2.0 ms, nothing extracted or written | 36.9 ms: 1 module extracted (28 ms compile), 1 file written |
| synthetic, 21 modules, each importing the previous | 131.9 ms | 3.2 ms | 3.3 ms | 146.6 ms: the edited module and its 19 transitive importers extracted |
| synthetic, 101 modules, the same chain | 532.9 ms | 20.4 ms | 20.5 ms | 530.7 ms: 100 modules extracted (439 ms compile) |

A regenerated module compiles in about 10 ms (`dmd -c`, checked profile), in parallel with the rest of the build.

**Against Go.** The recorded Linux edit builds are 97.1 ms for Flint's REST application and 194.2 ms for Go's (`docs/milestones/06-linux-compile-fork.md`), leaving 97 ms of headroom. On an application of Phase 1's size, a body edit adds 2 ms and an interface edit adds about 37 ms plus one 10 ms parallel compile, so the edit loop stays below Go's. An interface edit to a module that many others import (transitively) re-extracts all of them, at about 4.4 ms each, because a module's evaluated attributes and supertypes can depend on declarations several imports away. Before Phase 1 measures PetClinic's edit loop on the runner, the extraction should gain early cutoff: compare each re-extracted model with the cached one and stop at importers whose inputs did not change.

How the cost came down while building it: the first describer built each module's model as one CTFE string and deduplicated annotation types with a linear scan, taking 0.84 s and 680 MB for 100 modules; printing one line per type, announcing each annotation type once per compile from a template instance, and skipping `Object`'s methods brought that to 0.42 s and 375 MB. Splitting the cache into keys and per-module model files took the no-change path for 101 modules from 71 ms to 18 ms. The compile server neither helps nor hurts extraction: its preloaded Phobos is irrelevant to a compile that imports none, and the describer's CTFE dominates.
