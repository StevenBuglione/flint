# Phase 1: the container (flint-java, the AOT runtime, spring-core, spring-beans, spring-context)

Status: implemented on `main`, owned by the framework-core session. The packages move to `flint-framework` at cutover.

This note records how Flint ports the Phase 1 container of Spring Framework v7.1.0. It follows ADR-030, the rulebook
([`../api-mapping.md`](../api-mapping.md)) and the Flint AOT contract ([`../aot-contract.md`](../aot-contract.md),
contract 1). Where it needs a rule the rulebook doesn't have yet, it proposes one under "Rulebook proposals".

## Packages

| Upstream | DUB name | Directory | D modules |
| --- | --- | --- | --- |
| Java SE API (clean room) | `flint:java` | `framework/java` | `flint.java.lang`, `flint.java.io`, `flint.java.util`, `flint.java.util.function_`, `flint.java.util.stream` |
| AOT contract section 4 (contract 2) | `flint:engine-aot` | `framework/engine-aot` | `flint.engine.aot.{any,descriptor,name,bean,condition,mapping,event,proxy,query,registry,objects}` |
| spring-core | `flint:core` | `framework/core` | `flint.core`, `flint.core.annotation` (leaf), `flint.core.annotation.types`, `flint.core.convert`, `flint.core.convert.converter`, `flint.core.convert.support`, `flint.core.env`, `flint.core.io`, `flint.util` |
| spring-beans | `flint:beans` | `framework/beans` | `flint.beans`, `flint.beans.factory`, `flint.beans.factory.annotation` (leaf), `flint.beans.factory.config`, `flint.beans.factory.support` |
| spring-context | `flint:context` | `framework/context` | `flint.context`, `flint.context.annotation`, `flint.context.event`, `flint.context.support`, `flint.stereotype` (leaf), `flint.validation`, `flint.validation.annotation` (leaf), `flint.validation.beanvalidation` |

`@PostConstruct` and `@PreDestroy` are `flint.jakarta.annotation` (third-party-apis, `framework/jakarta-annotation`).

Dependency edges: `engine-aot` depends on nothing; `java` on `engine-aot` and `serde` (Java's `Double.toString`
rendering); `core` on `java` and `engine-aot`; `beans` on `core`; `context` on `beans` and `jakarta-validation`. In `policy/framework.json`,
`also` lists the further package roots a module owns: spring-core holds `flint.core`, `flint.util` and `flint.lang`,
spring-context `flint.context`, `flint.stereotype` and `flint.validation`. engine-aot's entry carries `unsafe`, the one audited `sys`
directory of the Spring layer; `tools/gates.py` applies the package `@trusted` rules there and nowhere else.

## The AOT runtime

`flint:engine-aot` implements contract section 4 exactly, in leaf modules. Runtime decisions behind the signatures:
- **Type names** are `__traits(fullyQualifiedName, T)` as DMD prints it. LDC repeats a template instance's eponymous
  member (`app.Opt!(Owner).Opt`); `canonicalTypeName` removes it, so names agree across compilers and with the
  generator.
- **`Any`** stores class references, scalars and strings inline and boxes structs, arrays and maps. `get!T` returns
  by `ref` for boxed structs and by value otherwise. Integral enums have their own slot, and `Any.ofEnum` builds one
  from `Descriptor.enumValues`, so erased converters can produce enums known only by name.
- **`descriptorOf!T`** builds the same `Descriptor` at compile time for hand-written code and tests, merging
  annotations as section 2.1 says (declared first, meta-annotations by distance, `@AliasFor` mirrors and
  meta-aliases, nearest wins).
- **`allocateProxy`** uses druntime's `_d_newclass` (initializer copied, no constructor), in the one allowlisted
  `@trusted` function of `flint.engine.aot.sys.allocate`.
- **`flint.engine.aot.objects`** (`objectEquals`, `objectToHash`, `objectToString`) is the audited bridge to
  druntime's attribute-less `Object` methods; see "`@safe` and Java's `Object`".
- **Advice** comes from `Advisor` beans ordered by `getOrder()`; `invokeDetached` uses a `DetachedExecutor` bean, or
  runs inline when there is none.

## API decisions

### The erased core and the `final`-overload pattern (proposed D-22)

D resolves a template overload through a class reference only when no class in the hierarchy declares a member of
the same name; an `alias` cannot bring interface templates into a class's overload set. So a Java interface whose
overloads mix erased methods with `Class`-typed ones (R4) declares every Java overload `final` and adds one virtual
primitive named `<method>Erased`:

| Interface | Virtual primitives | Java-named `final` overloads |
| --- | --- | --- |
| `PropertyResolver` | `getPropertyErased(key, TypeDescriptor)` | `getProperty(key)`, `getProperty(key, default)`, `getProperty!T(key)`, `getProperty!T(key, default)`, `getRequiredProperty`, `getRequiredProperty!T` |
| `ConversionService` | `canConvertErased`, `convertErased` | `canConvert(TypeDescriptor, TypeDescriptor)`, `convert(Any, TypeDescriptor, TypeDescriptor)`, `canConvert!(S, T)`, `convert!T(source)` |
| `ConverterRegistry` | `addConverterErased`, `removeConvertibleErased` | `addConverter(GenericConverter)`, `addConverter!(S, T)(Converter)`, `addConverter!(S, T)(delegate)`, `removeConvertible!(S, T)` |
| `BeanFactory` | `getBeanErased(name, requiredType, args)`, `isTypeMatchErased` | `getBean(name)`, `getBean(name, args...)`, `getBean!T()`, `getBean!T(name)`, `getBeanProvider!T`, `isTypeMatch!T` |
| `ListableBeanFactory` | `getBeanNamesForTypeErased`, `getBeanNamesForAnnotationErased` | `getBeanNamesForType!T`, `getBeansOfType!T`, `getBeanNamesForAnnotation!A`, `getBeansWithAnnotation!A` |
| `ApplicationEventPublisher` | `publishEventErased(ApplicationEvent)` | `publishEvent(ApplicationEvent)`, `publishEvent!T(payload)` |

Application code calls the Java names; subclasses customize through the primitives. The other framework sessions
should use the same pattern wherever an interface has `Class`-typed overloads.

### Collections and `java.lang`

- `List!T`, `Set!T`, `Map!(K, V)` are interfaces with Java's methods, implemented by final-able classes, plus the
  erased `RawCollection` and `RawMap` that descriptor-driven engines walk without a template instance per element.
- `HashMap` and `HashSet` iterate in insertion order; `keySet`, `values` and `entrySet` are snapshots; `Map.get` of
  a missing key is `V.init`. `List!int` uses `removeAt` for indices.
- `RuntimeException`'s protected four-argument constructor with `writableStackTrace = false` presets the
  `TraceInfo`, so druntime captures no trace: framework control-flow exceptions use it (ADR-030 section 4).
- `java.util.function` is `flint.java.util.function_`.

### `@safe` and Java's `Object`

druntime's `Object.opEquals`, `toHash` and `toString` have no attributes, so they cannot be called through an
`Object` reference in `@safe` code, and `a == b` between class references is `@safe` only with a typed `@safe
opEquals`. The API layer never uses `==` or `toString` on an arbitrary class `T`; it calls `javaEquals`,
`javaHashCode` and `valueOf` (`flint.java.lang`), which go through `flint.engine.aot.objects`. `mixin JavaObject`
adds a typed `opEquals`, so `owner1 == owner2` stays `@safe` in application code. Two collections held as interfaces
compare with `equals`, as in Java.

### Environment

- `flint.` keys, with `spring.` accepted: every lookup of a `flint.` key that finds nothing retries the `spring.`
  key, in `PropertySourcesPropertyResolver`. `AbstractEnvironment.ACTIVE_PROFILES_PROPERTY_NAME` is
  `flint.profiles.active`, so `FLINT_PROFILES_ACTIVE=prod` works through `SystemEnvironmentPropertySource`'s relaxed
  names, and `spring.profiles.active` still works.
- `PropertySource` is not generic: its parameter typed only `getSource()`. Values are `Any`.
- D has no JVM system properties: `getSystemProperties()` is an empty mutable map.
- `DefaultConversionService.getSharedInstance()` returns a new instance: framework packages keep no mutable
  module-level state.

### Resources

A class path resource is the application's embedded resources (`installEmbeddedResources`, which `flint build`
generates from `src/main/resources`), then the directories in `FLINT_CLASSPATH` (default `resources` and
`src/main/resources`). `getURL`, `getURI`, `getFilePath` and channels are excluded (`jvm-platform`).

### Annotations

`flint.core.annotation` stays the leaf module the AOT contract names (`AliasFor`, `Order`, and `ClassRef`/`classOf`,
which live in `flint.java.lang` as Java's `Class` so third-party annotation modules can use them without spring-core,
and are re-exported here).
`MergedAnnotations`, `MergedAnnotation!A`, `AnnotationAwareOrderComparator`, `OrderUtils` and `AnnotationUtils`
are in `flint.core.annotation.types` (proposed D-21) and read the merged tables of AOT descriptors; nothing
reflects. Other mixed packages (`flint.context.annotation`, `flint.context.event`) keep their runtime types in the
annotation's module, as in Java, because applications import those types (`AnnotationConfigApplicationContext`,
`ContextRefreshedEvent`) from there; their annotation structs import only other annotation modules.

### The container

- **Definitions** are `RootBeanDefinition`s over the generated `flint.engine.aot.bean.BeanDefinition` records.
  `GenericApplicationContext.deferAotRegistry` (what `AnnotationConfigApplicationContext` uses) loads the installed
  or given registry inside `refresh()`, just before the factory post-processors, as Spring's
  `ConfigurationClassPostProcessor` does; `loadAotRegistry` loads it immediately. Each definition's condition is
  evaluated against what is registered so far, in definition order (contract 5.4), so singletons registered before
  `refresh()` (Boot's application arguments, banner, properties binder) are visible to the conditions. `registerBean!T` registers a
  hand-written definition for tests and code without generated definitions.
- **Creation** follows Spring: `dependsOn` first, then create, `BeanNameAware`/`BeanFactoryAware`,
  `postProcessBeforeInitialization`, the generated `initialize` (injection, `@PostConstruct`, `afterPropertiesSet`),
  `postProcessAfterInitialization`, then the generated proxy. Destruction runs in reverse creation order, dependents
  first, and the destroy callback receives the target, not the proxy. A request for a bean in creation is
  `BeanCurrentlyInCreationException` with Spring's message.
- **Resolution by type** uses the definition's `types` (class chain and interfaces), then `@Qualifier` values, bean
  names and aliases; among several candidates the single `@Primary`, else the single non-`@Fallback`, else
  `NoUniqueBeanDefinitionException` with Spring's message. `List` injection orders by `PriorityOrdered`, then
  `Ordered`/`@Order`, then registration. The context registers itself, its environment, its factory and its
  conversion service as resolvable dependencies (contract 5.2's infrastructure types).
- **`dependsOn`** is strict: a name with no definition is `NoSuchBeanDefinitionException`, as `@DependsOn` is in
  Spring (the generator emits only `@DependsOn` values and a `@Bean` method's configuration bean).
- **`@ConfigurationProperties`**: the generated `initialize` calls `BeanFactory.bind`/`bindConstructor`, which
  delegate to the `ConfigurationPropertiesBinder` bean (`flint.beans.factory.config`) that Flint Boot registers;
  without one they throw `IllegalStateException("@ConfigurationProperties needs flint:boot")`. The context's
  `isAutoConfigurationExcluded` reads `flint.autoconfigure.exclude` through the same binder (`bindList`), or the
  environment's comma list when Boot is absent.
- **Refresh** is Spring's `AbstractApplicationContext.refresh` sequence. `${...}` in `@Value` resolves strictly
  against the environment, then converts with the environment's conversion service.
- **Events**: `ApplicationListener!E` is an abstract class (proposed D-23), so it dispatches on `E` without
  reflection; `@EventListener` methods come from the AOT table through `ApplicationListenerMethodAdapter`, matching
  the event's class chain (`TypeInfo_Class`), or a payload's type. A listener with a SpEL condition fails at refresh
  until contract section 9 lands.
- **Lifecycle**: `SmartLifecycle` beans with auto-startup start on refresh in ascending phase order and stop on
  close in descending order; `mixin SmartLifecycle.Defaults` gives Java's default methods (R3).
- `registerShutdownHook()` records the request; Flint Boot's graceful shutdown closes the context on SIGTERM and
  SIGINT. `FactoryBean` and `@Bean` metadata on `BeanDefinition` (`getFactoryBeanName`) are not supported: generated
  code wires `@Bean` methods.

### Validation

`org.springframework.validation` is `flint.validation` in `flint:context`, as upstream ships it in spring-context.

- **Errors.** `Errors` keeps Java's methods; its Java default methods are implemented once in `AbstractErrors` (R3),
  which `AbstractBindingResult` and `SimpleErrors` extend. Values are `Any`; field types and `supports` take type
  names (R4). `failOnError` and `validateObject` are `final` interface methods over the abstract ones.
- **Property access.** `BeanPropertyBindingResult` and `SimpleErrors` read fields, including nested `a.b` paths,
  through Flint AOT descriptors in a `DescriptorTable` (the context's table, or `descriptorOf!T` for the typed
  constructors) instead of a `BeanWrapper`. An unknown property reads as `Any.init`.
- **Message codes.** `DefaultMessageCodesResolver` is Spring's algorithm, including the gh-37642 limit of 8 stripped
  keys. D enums cannot implement interfaces, so `Format` is passed to its own `setMessageCodeFormatter` overload and
  `toDelimitedString` is on the resolver.
- **Bean validation.** `SpringValidatorAdapter` maps each Jakarta `ConstraintViolation` to a `ViolationFieldError`
  or `ViolationObjectError` with Spring's field, codes, arguments and rejected value. `LocalValidatorFactoryBean`
  bootstraps from the provider registered with `Validation.registerProvider` (Flint has no `ServiceLoader`).
  `setConfigurationInitializer` customizes that configuration, which is how Boot hands Hibernate Validator its
  descriptor table without making `flint:context` depend on Hibernate. `OptionalValidatorFactoryBean` stays inactive
  without a provider. Validation groups are not applied, because the Jakarta port validates the default group only.
- `Validator.forInstanceOf` matches the type name, so it does not accept subtypes. `DataBinder`, method validation
  and `MessageSource` rendering are deferred to Phase 2.

## Erased builders (contract 2)

`Descriptor` carries erased builders that Boot's binder, Jackson and validation use: `enumValue(ordinal)`,
`length`/`element`/`fromElements` for arrays, `List!T` and `Set!T`, `toKeys`/`toValues`/`fromEntries` for maps, and
`unwrap`/`wrap` for `Optional!T`. `descriptorOf!T` fills them for enums, arrays and associative arrays directly, and
for flint:java's collections and `Optional` through static `__flint*` hooks those types declare; Flint AOT emits the
same fields for generated descriptors.

## Upstream tests ported

| Upstream class | Java tests | Ported | Skipped (reason) |
| --- | --- | --- | --- |
| util.AssertTests | 109 | 103 | 6: a null `Class` argument cannot be a template parameter |
| util.StringUtilsTests | 73 | 58 | 15: `Locale` |
| util.ObjectUtilsTests | 140 | 98 | 42: reflection, `Class` objects, JDK value types |
| util.CollectionUtilsTests | 32 | 23 | 9: `Properties`, `Enumeration`, `Class`, `SortedSet`, `CompositeMap` |
| util.AntPathMatcherTests | 27 | 27 | |
| util.PlaceholderParserTests | 23 | 23 | |
| util.PropertyPlaceholderHelperTests | 10 | 10 | |
| util.NumberUtilsTests | 24 | 10 | 14: `NumberFormat`, `BigInteger`, `BigDecimal` |
| util.PatternMatchUtilsTests | 9 | 9 | |
| util.LinkedMultiValueMapTests | 11 | 11 | |
| util.MultiValueMapTests | 12 | 12 | |
| core.env (11 classes, JOpt excluded) | 184 | 170 | 14: `SpringProperties`, `CharSequence` values, a null variadic array, commons-logging |
| core.OrderComparatorTests | 17 | 17 | |
| core.SimpleAliasRegistryTests | 15 | 14 | 1: `ConcurrentHashMap`'s null key |
| core.AttributeAccessorSupportTests | 5 | 5 | |
| core.convert GenericConversionServiceTests | 67 | 35 | 32: `Class` tokens, primitives versus wrappers, reflection, unported converters |
| core.convert DefaultConversionServiceTests | 157 | 37 | 120: converters not registered in Phase 1 (BigDecimal, time, Locale, UUID...), reflection |
| core.io ClassPathResourceTests, ResourceTests | 58 | 20 | 38: class loaders, `UrlResource`, NIO, `InputStreamResource` |
| validation.DefaultMessageCodesResolverTests | 14 | 14 | |
| validation.ValidationUtilsTests | 9 | 9 | |
| validation.ValidatorTests | 2 | 1 | 1: `supports` of a subclass needs the class hierarchy |
| validation.beanvalidation SpringValidatorAdapterTests, ValidatorFactoryTests | 25 | 0 | 25: need Hibernate Validator and a `MessageSource`; the adapter is tested against a stub provider |

Each test file lists its skipped Java tests and the reason. The beans and context test ports are in progress.

## Rulebook proposals

| ID | Proposal | Reason |
| --- | --- | --- |
| D-15 | `java.util.function` is `flint.java.util.function_` | `function` is a D keyword |
| D-16 | `HashMap`/`HashSet` iterate in insertion order | Java leaves the order unspecified; deterministic output |
| D-17 | `Map.keySet`/`values`/`entrySet` are snapshots | no live views without per-type view classes |
| D-18 | `Map.get` of a missing key is `V.init` | D has no boxed null for value types |
| D-19 | `List!int` index removal is only `removeAt` | `remove(int)` would collide with `remove(T)` |
| D-20 | Streams are sequential | no parallel stream engine |
| D-21 | `flint.core.annotation` is a leaf; its runtime types are `flint.core.annotation.types` | the AOT contract requires the leaf |
| D-22 | Interfaces with `Class`-typed overloads declare Java's overloads `final` over `<method>Erased` primitives | D cannot overload templates across a class hierarchy |
| D-23 | `ApplicationListener!E` is an abstract class | erased dispatch on `E` without reflection |
| D-24 | `PropertySource` is not generic; `DefaultConversionService.getSharedInstance()` is not shared | erased core; no mutable module state |

## Verification

`dub test :engine-aot`, `:java`, `:core`, `:beans` and `:context` on DMD and LDC; `python3 tools/gates.py --gate
structural`; `python3 tools/quality.py`. `flint api headers` passes on every ported file, and
`flint api coverage --repo framework` classifies spring-beans and spring-context completely and spring-core's Phase 1
packages; elements not ported yet are `excluded`/`deferred` with phase 2.
