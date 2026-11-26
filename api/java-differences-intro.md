# Java differences

Flint keeps Spring's API: the same class names, method names and configuration keys, with `org.springframework.X` becoming `flint.X`. Where D cannot express a Java construct exactly, the element is **adapted** by a numbered rule, and where Flint deliberately leaves something out, it is **excluded** with a reason. This page is the complete, generated list of both, so no difference is tribal knowledge.

- The rules are defined in [api-mapping.md](api-mapping.md).
- The lists below are generated from every `api/*/mapping.json` by `python3 tools/api_differences.py --write`.
- The API gate fails when this page does not match the mappings.

## What a Spring developer needs to know

Most Spring code ports line by line. These are the places where it does not.

### Names and packages

**R1: packages and names.** `org.springframework.X` becomes `flint.X`, and the word "Spring" in a public name becomes "Flint". Third-party APIs keep their own root: `jakarta.persistence` becomes `flint.jakarta.persistence`.

```java
import org.springframework.boot.SpringApplication;
SpringApplication.run(App.class, args);
```
```d
import flint.boot : FlintApplication;
FlintApplication.run!App(args);
```

When two Java packages refer to each other in a cycle, which D does not allow, the shared declarations live in an internal module and are re-exported under their usual names. You still import them from the Spring path, and class-presence checks use it too; you never import the internal module. Runtime type names (`typeid`, `ClassInfo.name`), Flint AOT descriptors and error messages show the internal module's name, because that is where D declares the type (R1).

**R19: Java names that are D keywords** take a trailing underscore, Phobos's convention: `version`, `function`, `debug`, `module`, `scope`, `in`, `out` and the rest.

```java
int v = uuid.version();
```
```d
int v = uuid.version_();
```

**R22: packages that mix annotations and runtime types** split in two. The annotations stay in the package's module, and the runtime classes move to one sibling module ending in `_runtime`.

```java
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.condition.ConditionOutcome;
```
```d
import flint.boot.autoconfigure.condition : ConditionalOnClass;
import flint.boot.autoconfigure.condition_runtime : ConditionOutcome;
```

### Annotations and types

**R2: annotations** become D attributes (UDAs) with the same name, attributes and defaults. `value` comes first, so the short form still works.

```java
@GetMapping(value = "/owners/{id}", produces = "application/json")
```
```d
@GetMapping(value: "/owners/{id}", produces: "application/json")
```

**R4: `Class<T>` parameters** become template parameters, because D types are not runtime values. In an annotation attribute, a class is written `classOf!T` (a `ClassRef`, a name only). Where a `Class` value is used at run time (`isInstance`, `isAssignableFrom`), it is a `RuntimeClassRef` (`runtimeClassOf!T`), which answers through druntime's `ClassInfo`, and `RuntimeClassRef.init` is Java's `null` class. For now `isInstance` takes a D `Object`, so pass an interface value as `cast(Object) value`.

```java
Note note = restClient.get().uri("/notes/1").retrieve().body(Note.class);
@Transactional(rollbackFor = IOException.class)
```
```d
Note note = restClient.get().uri("/notes/1").retrieve().body!Note();
@Transactional(rollbackFor: [classOf!IOException])
```

**R21: type parameters that appear only in the return type.** Java infers `T` from the assignment, and D cannot. You get a plain method returning the bound type, plus an explicit `!T` form that casts and checks.

```java
ObjectNode node = tree.require();
```
```d
ObjectNode node = tree.require!ObjectNode();   // tree.require() returns JsonNode
```

**R3: interfaces** stay interfaces, and static methods stay static members. An interface made only of default methods, such as `WebMvcConfigurer`, becomes an abstract class (D-3), so you override only what you need.

**R6: getters and setters** keep their Java names: `getStatus()`, `setStatus(int)`. Records keep their accessor names: `name()`. There are no D `@property` shortcuts.

**R13: nested classes** stay nested under the same name, for example `ResponseEntity.BodyBuilder`.

### Values, nulls and equality

**R5: nullable values.** `Optional<T>` becomes `Optional!T`. A value that may be `null` where D's type is a value type becomes `Nullable!T`, including a `String` that may be `null` distinct from `""`.

```java
Long id = owner.getId();          // may be null
```
```d
Nullable!long id = owner.getId();
if (!id.isNull) use(id.get);
```

**R23: `Object` values** are `Any`, Flint AOT's erased value: a type name plus the value, stored inline for scalars and small structs. A `null` reference is `Any.init`, and a class reference keeps its identity.

```java
Object id = accessor.getIdentifier();
if (id instanceof Long l) use(l);
```
```d
Any id = accessor.getIdentifier();
long l;
if (id.tryGet!long(l)) use(l);
```

**D-7: typed `null`.** D resolves a bare `null` differently when two overloads take unrelated types, so those overload pairs offer typed `null` constants.

```java
filter.and(null);
```
```d
filter.and(ClassFilter.NULL);
```

**R11: identity and equality.** `equals`, `hashCode` and `toString` keep their names and map to D's `==`. Java's reference `a == b` is `a is b`. Records become structs with member-wise equality.

**R16: a record that implements an interface** becomes a `final class`, because only classes implement D interfaces. Equality stays member-wise. Java's `instanceof TextPart t` is `if (auto t = cast(TextPart) part)`.

**R17: shared constants of generic classes**, such as `Range.unbounded()`, are value-equal per type instead of one shared object. `equals` and `isUnbounded()` behave as in Java; reference identity is not preserved.

**D-NET-1: `java.net.URL` equality never uses DNS.** `equals` and `hashCode` compare the normalised URL. Java resolves host names inside `equals`, which blocks and is nondeterministic. `URI` behaves exactly as in Java.

### Enums

Every Java enum falls under exactly one of these four cases.

- **Constants only:** a D `enum` with the same names, unchanged.
- **R15, fields:** a struct with `static immutable` constants and Java's `name()`, `ordinal()`, `values()` and `valueOf()`.
- **R20, methods but no fields:** a D `enum`, with its methods as free functions called the same way (`access.cap(other)`).
- **R18, implements an interface:** a single-constant strategy enum becomes a class with `INSTANCE`; an option enum stays a D `enum` with overloads that accept it.

```java
HttpStatus status = HttpStatus.NOT_FOUND;
int code = status.value();
```
```d
HttpStatus status = HttpStatus.NOT_FOUND;   // R15: a struct constant
int code = status.value();
```

### Methods, exceptions and callbacks

**R7: overloads** stay overloads. Varargs (`Object... args`) become a D variadic façade.

**R8: exceptions** keep Spring's hierarchy and names. D has no checked exceptions, so there are no `throws` clauses (D-8).

**R9: functional interfaces** stay interfaces, and every method that takes one also accepts a D delegate, so lambdas work.

```java
http.authorizeHttpRequests(auth -> auth.anyRequest().authenticated());
```
```d
http.authorizeHttpRequests((auth) { auth.anyRequest().authenticated(); });
```

**R10: collections and streams.** `List<T>`, `Set<T>` and `Map<K,V>` are `List!T`, `Set!T` and `Map!(K, V)`, which convert to and from D arrays. `Stream<T>` keeps Java's method names.

**R12: builders** keep Java's method chains exactly: `ResponseEntity.ok().header(...).body(x)`.

**R14: strings** are UTF-8 inside Flint. Public methods that return an index keep Java's unit where the index crosses the API. Where Java's UTF-16 arithmetic would split a character outside the Basic Multilingual Plane (an emoji, say) and leave half of a surrogate pair, Flint keeps Java's counts and indices but writes U+FFFD for that half, because UTF-8 cannot hold a lone surrogate.

### Reflection and the closed world

Flint has no runtime reflection or class loading. Flint AOT generates, at build time, what Spring discovers at run time.

- **D-AOT-MEMBER:** Java's `Member` and `AccessibleObject` map to Flint AOT's member descriptors. Only metadata the generator produces is available; anything else throws `UnsupportedOperationException`.
- **D-1:** an application declares `mixin FlintMain!App;` beside its class, because D's entry point is a free function.
- Classpath scanning, load-time weaving, `ClassLoader` APIs, Java serialization, JMX and similar JVM machinery are **excluded**. Each one is listed below with its reason.

