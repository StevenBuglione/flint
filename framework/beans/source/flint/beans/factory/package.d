// Ported from spring-framework v7.1.0: spring-beans/src/main/java/org/springframework/beans/factory
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
/*
 * Copyright 2002-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Modified by the Flint authors: ported from spring-framework v7.1.0,
 * spring-beans/src/main/java/org/springframework/beans/factory/{BeanFactory,ListableBeanFactory,
 * HierarchicalBeanFactory,ObjectFactory,ObjectProvider,Aware,BeanNameAware,BeanFactoryAware,InitializingBean,
 * DisposableBean,SmartInitializingSingleton,NoSuchBeanDefinitionException,NoUniqueBeanDefinitionException,
 * BeanCreationException,BeanCreationNotAllowedException,BeanCurrentlyInCreationException,BeanInitializationException,
 * BeanIsAbstractException,BeanNotOfRequiredTypeException,FactoryBeanNotInitializedException,
 * UnsatisfiedDependencyException,BeanDefinitionStoreException}.java. Class-typed lookups are template façades (R4)
 * over erased primitives (deviation D-CORE-2); bean types are canonical D names.
 */

/++
`org.springframework.beans.factory`: the bean container API.

`getBean!T()`, `getBean!T(name)`, `getBeansOfType!T()` and `getBeanProvider!T()` are Java's `Class`-typed
lookups (R4); they are `final` façades over the erased `getBeanErased`, `getBeanNamesForTypeErased` and
`getBeansOfTypeErased`, which implementations provide (deviation D-CORE-2).
+/
module flint.beans.factory;

import std.typecons : Nullable;

import flint.beans : BeansException, FatalBeanException;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.java.lang : NullPointerException;
import flint.java.util : LinkedHashMap, Map;
import flint.java.util.stream : Stream;
import flint.core.env : Environment;

@safe:

package(flint.beans) alias NullableString = Nullable!string;

/++
The root interface for accessing a bean container.
+/
interface BeanFactory
{
    /// The prefix that dereferences a `FactoryBean`: `&myBean` is the factory, `myBean` its object.
    enum FACTORY_BEAN_PREFIX = "&";

    /++
    The erased primitive behind every `getBean`: the bean named `name` (or, with a null `name`, the single bean
    of `requiredType`), checked against `requiredType` when it is given. Throws `NoSuchBeanDefinitionException`,
    `NoUniqueBeanDefinitionException`, `BeanNotOfRequiredTypeException` or `BeansException`.
    +/
    Object getBeanErased(string name, string requiredType, Any[] args);

    /// Whether a bean (definition or singleton) named `name` exists.
    bool containsBean(string name);
    /// Whether `name` is a singleton.
    bool isSingleton(string name);
    /// Whether `name` is a prototype.
    bool isPrototype(string name);
    /// Whether the bean `name` can be injected as the type `typeName`.
    bool isTypeMatchErased(string name, string typeName);
    /// The canonical type name of the bean `name`, or null (Java's `getType`, a `Class`, R4).
    string getTypeName(string name);
    /// The aliases of `name`.
    string[] getAliases(string name);

    /// The bean named `name`.
    final Object getBean(string name)
    {
        return getBeanErased(name, null, null);
    }

    /// The bean named `name`, created with explicit constructor arguments when it is a prototype.
    final Object getBean(string name, Any[] args...)
    {
        return getBeanErased(name, null, args.dup);
    }

    /// The bean named `name` as a `T`. Throws `BeanNotOfRequiredTypeException` when it is not one.
    T getBean(T)(string name)
    {
        return cast(T) getBeanErased(name, typeNameOf!T, null);
    }

    /// The single bean of type `T`.
    T getBean(T)()
    {
        return cast(T) getBeanErased(null, typeNameOf!T, null);
    }

    /// A provider for beans of type `T`, resolved on use.
    ObjectProvider!T getBeanProvider(T)()
    {
        return new BeanObjectProvider!T(this);
    }

    /// Whether the bean `name` can be injected as a `T`.
    bool isTypeMatch(T)(string name)
    {
        return isTypeMatchErased(name, typeNameOf!T);
    }
}

/// A `BeanFactory` that can enumerate all its bean instances.
interface ListableBeanFactory : BeanFactory
{
    /// Whether a definition named `beanName` exists.
    bool containsBeanDefinition(string beanName);
    /// How many definitions exist.
    int getBeanDefinitionCount();
    /// Every definition name, in registration order.
    string[] getBeanDefinitionNames();
    /// The names of beans injectable as `typeName`, in registration order.
    string[] getBeanNamesForTypeErased(string typeName, bool includeNonSingletons = true, bool allowEagerInit = true);
    /// The names of beans whose class carries the annotation `annotationType` (merged).
    string[] getBeanNamesForAnnotationErased(string annotationType);

    /// The names of beans injectable as `T`.
    string[] getBeanNamesForType(T)(bool includeNonSingletons = true, bool allowEagerInit = true)
    {
        return getBeanNamesForTypeErased(typeNameOf!T, includeNonSingletons, allowEagerInit);
    }

    /// The beans injectable as `T`, by name, in registration order.
    Map!(string, T) getBeansOfType(T)(bool includeNonSingletons = true, bool allowEagerInit = true)
    {
        Map!(string, T) result = new LinkedHashMap!(string, T)();
        foreach (name; getBeanNamesForTypeErased(typeNameOf!T, includeNonSingletons, allowEagerInit))
        {
            Object bean;
            try
                bean = getBeanErased(name, typeNameOf!T, null);
            catch (BeanCurrentlyInCreationException e)
            {
                if (e.getBeanName() == name)
                    continue; // ignoring a match to the bean currently being created, as Spring does
                throw e;
            }
            if (bean !is null) // a null-supplied bean is left out
                result.put(name, cast(T) bean);
        }
        return result;
    }

    /// The names of beans annotated with `A`.
    string[] getBeanNamesForAnnotation(A)()
    {
        return getBeanNamesForAnnotationErased(typeNameOf!A);
    }

    /// The beans annotated with `A`, by name.
    Map!(string, Object) getBeansWithAnnotation(A)()
    {
        Map!(string, Object) result = new LinkedHashMap!(string, Object)();
        foreach (name; getBeanNamesForAnnotationErased(typeNameOf!A))
            result.put(name, getBeanErased(name, null, null));
        return result;
    }
}

/// A `BeanFactory` that is part of a hierarchy.
interface HierarchicalBeanFactory : BeanFactory
{
    /// The parent factory, or null.
    BeanFactory getParentBeanFactory();
    /// Whether this factory itself (not its ancestors) contains a bean named `name`.
    bool containsLocalBean(string name);
}

/// Defines a factory that returns an object instance on demand.
interface ObjectFactory(T)
{
    /// An instance of the object.
    T getObject();
}

/// A variant of `ObjectFactory` for injection points: optional, unique and streamed access.
interface ObjectProvider(T) : ObjectFactory!T
{
    /// The instance if available (exactly one candidate, or a primary one), else null.
    T getIfAvailable();
    /// The instance if unique (or primary), else null.
    T getIfUnique();
    /// Every matching instance, in registration order.
    Stream!T stream();
    /// Every matching instance, in `@Order`/`Ordered` order.
    Stream!T orderedStream();

    /// The instance if available, else `defaultSupplier()`.
    final T getIfAvailable(T delegate() @safe defaultSupplier)
    {
        auto dependency = getIfAvailable();
        return dependency !is null ? dependency : defaultSupplier();
    }

    /// Call `dependencyConsumer` with the instance if available.
    final void ifAvailable(void delegate(T) @safe dependencyConsumer)
    {
        auto dependency = getIfAvailable();
        if (dependency !is null)
            dependencyConsumer(dependency);
    }

    /// The instance if unique, else `defaultSupplier()`.
    final T getIfUnique(T delegate() @safe defaultSupplier)
    {
        auto dependency = getIfUnique();
        return dependency !is null ? dependency : defaultSupplier();
    }

    /// Call `dependencyConsumer` with the instance if unique.
    final void ifUnique(void delegate(T) @safe dependencyConsumer)
    {
        auto dependency = getIfUnique();
        if (dependency !is null)
            dependencyConsumer(dependency);
    }
}

/// The `ObjectProvider` a `BeanFactory` hands out.
private final class BeanObjectProvider(T) : ObjectProvider!T
{
    private BeanFactory factory;

    this(BeanFactory factory) pure nothrow @nogc
    {
        this.factory = factory;
    }

    T getObject()
    {
        return cast(T) factory.getBeanErased(null, typeNameOf!T, null);
    }

    T getIfAvailable()
    {
        try
            return getObject();
        catch (NoUniqueBeanDefinitionException e)
            throw e;
        catch (NoSuchBeanDefinitionException)
            return null;
    }

    T getIfUnique()
    {
        try
            return getObject();
        catch (NoSuchBeanDefinitionException)
            return null;
    }

    Stream!T stream()
    {
        return Stream!T.ofArray(instances());
    }

    Stream!T orderedStream()
    {
        auto items = instances();
        // Imported here so flint.beans.factory's interfaces do not link the ordering code (S-9).
        auto comparator = imported!"flint.core.annotation.types".AnnotationAwareOrderComparator.INSTANCE();
        imported!"flint.java.util".stableSort(items, (T a, T b) => comparator.compare(cast(Object) a, cast(Object) b));
        return Stream!T.ofArray(items);
    }

    private T[] instances()
    {
        auto listable = cast(ListableBeanFactory) factory;
        if (listable is null)
            return [getObject()];
        T[] result;
        foreach (name; listable.getBeanNamesForTypeErased(typeNameOf!T))
            if (auto bean = listable.getBeanErased(name, typeNameOf!T, null))
                result ~= cast(T) bean;
        return result;
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Callbacks

/// Marker superinterface for beans the container notifies through callback methods.
interface Aware
{
}

/// A bean that wants to know its bean name.
interface BeanNameAware : Aware
{
    /// Called after property population, before initialization callbacks.
    void setBeanName(string name);
}

/// A bean that wants to know its owning `BeanFactory`.
interface BeanFactoryAware : Aware
{
    /// Called after property population, before initialization callbacks.
    void setBeanFactory(BeanFactory beanFactory);
}

/// A bean that reacts once all its properties are set.
interface InitializingBean
{
    /// Called after the container set every property and applied the `Aware` callbacks.
    void afterPropertiesSet();
}

/// A bean that releases resources on destruction.
interface DisposableBean
{
    /// Called when the container destroys the bean.
    void destroy();
}

/// Callback triggered at the end of the singleton pre-instantiation phase.
interface SmartInitializingSingleton
{
    /// Called once every non-lazy singleton has been created.
    void afterSingletonsInstantiated();
}

// ---------------------------------------------------------------------------------------------------------------
// Exceptions

/// Thrown when a `BeanFactory` is asked for a bean it cannot find.
class NoSuchBeanDefinitionException : BeansException
{
    private string beanName;
    private string beanType;

    /// `No bean named 'name' available`.
    this(string name)
    {
        super("No bean named '" ~ name ~ "' available");
        beanName = name;
    }

    /// `No bean named 'name' available: message`.
    this(string name, string message)
    {
        super("No bean named '" ~ name ~ "' available: " ~ message);
        beanName = name;
    }

    /// `No qualifying bean of type 'type' available` (with `: message` when one is given).
    static NoSuchBeanDefinitionException forType(string type, string message = null)
    {
        auto e = new NoSuchBeanDefinitionException(ForType.init,
                "No qualifying bean of type '" ~ type ~ "' available" ~ (message is null ? "" : ": " ~ message));
        e.beanType = type;
        return e;
    }

    private struct ForType
    {
    }

    /// A message built by a subclass or factory.
    protected this(ForType, string message)
    {
        super(message);
    }

    /// The requested bean name, or null for a lookup by type.
    string getBeanName() const pure nothrow @nogc
    {
        return beanName;
    }

    /// The requested type's canonical name, or null for a lookup by name.
    string getBeanType() const pure nothrow @nogc
    {
        return beanType;
    }

    /// How many beans were found: 0 here.
    int getNumberOfBeansFound() const pure nothrow @nogc
    {
        return 0;
    }
}

/// Thrown when a single bean of a type is required but several candidates match.
class NoUniqueBeanDefinitionException : NoSuchBeanDefinitionException
{
    private string[] beanNamesFound;

    /// `No qualifying bean of type 't' available: expected single matching bean but found 2: a,b`.
    this(string type, string[] beanNamesFound)
    {
        string names;
        foreach (i, name; beanNamesFound)
            names ~= (i ? "," : "") ~ name;
        super(ForType.init,
                "No qualifying bean of type '" ~ type ~ "' available: expected single matching bean but found "
                ~ imported!"flint.java.lang".valueOf(cast(int) beanNamesFound.length) ~ ": " ~ names);
        this.beanNamesFound = beanNamesFound;
    }

    /// `No qualifying bean of type 't' available: message`, for the names found.
    this(string type, string[] beanNamesFound, string message)
    {
        super(ForType.init, "No qualifying bean of type '" ~ type ~ "' available: " ~ message);
        this.beanNamesFound = beanNamesFound;
    }

    /// How many beans were found.
    override int getNumberOfBeansFound() const pure nothrow @nogc
    {
        return cast(int) beanNamesFound.length;
    }

    /// The names of the beans found.
    string[] getBeanNamesFound() const
    {
        return beanNamesFound.dup;
    }
}

/// Thrown when a `BeanFactory` encounters an error creating a bean.
class BeanCreationException : FatalBeanException
{
    private string beanName;
    private string resourceDescription;

    /// `msg`, with a cause that can still be initialized (Java's `(String)` constructor).
    this(string msg)
    {
        super(msg);
    }

    /// `msg` and an initialized `cause`, even `null` (Java's `(String, Throwable)` constructor).
    this(string msg, Throwable cause)
    {
        super(msg, cause);
    }

    /// Selects the cause overload for a `null` literal, as Java's overload resolution does.
    this(string msg, typeof(null))
    {
        this(msg, cast(Throwable) null);
    }

    /// `Error creating bean with name 'beanName': msg`, with a cause that can still be initialized.
    this(string beanName, string msg)
    {
        super(named(beanName, msg));
        this.beanName = beanName;
    }

    /// `Error creating bean with name 'beanName': msg` and an initialized `cause`, even `null`.
    this(string beanName, string msg, Throwable cause)
    {
        super(named(beanName, msg), cause);
        this.beanName = beanName;
    }

    /// Selects the cause overload for a `null` literal, as Java's overload resolution does.
    this(string beanName, string msg, typeof(null))
    {
        this(beanName, msg, cast(Throwable) null);
    }

    /// `Error creating bean with name 'beanName' defined in resourceDescription: msg`, with a cause that can still be
    /// initialized.
    this(string resourceDescription, string beanName, string msg)
    {
        super(defined(resourceDescription, beanName, msg));
        this.beanName = beanName;
        this.resourceDescription = resourceDescription;
    }

    /// `Error creating bean with name 'beanName' defined in resourceDescription: msg` and an initialized `cause`.
    this(string resourceDescription, string beanName, string msg, Throwable cause)
    {
        super(defined(resourceDescription, beanName, msg), cause);
        this.beanName = beanName;
        this.resourceDescription = resourceDescription;
    }

    private this(NullableString resourceDescription, NullableString beanName, string msg)
    {
        super(optionalDefined(resourceDescription, beanName, msg));
        this.beanName = beanName.isNull ? null : beanName.get();
        this.resourceDescription = resourceDescription.isNull ? null : resourceDescription.get();
    }

    private this(NullableString resourceDescription, NullableString beanName, string msg, Throwable cause)
    {
        super(optionalDefined(resourceDescription, beanName, msg), cause);
        this.beanName = beanName.isNull ? null : beanName.get();
        this.resourceDescription = resourceDescription.isNull ? null : resourceDescription.get();
    }

    private static string named(string beanName, string msg) pure nothrow
    {
        return "Error creating bean with name '" ~ beanName ~ "': " ~ msg;
    }

    private static string defined(string resourceDescription, string beanName, string msg) pure nothrow
    {
        return "Error creating bean with name '" ~ beanName ~ "'" ~ (resourceDescription is null
                ? "" : " defined in " ~ resourceDescription) ~ ": " ~ msg;
    }

    private static string optionalDefined(NullableString source, NullableString beanName, string msg) pure nothrow
    {
        const name = beanName.isNull ? "null" : beanName.get();
        const resource = source.isNull ? "" : " defined in " ~ source.get();
        return "Error creating bean with name '" ~ name ~ "'" ~ resource ~ ": " ~ msg;
    }

    /// The bean's name, or null.
    string getBeanName() const pure nothrow @nogc
    {
        return beanName;
    }

    /// Where the bean was defined, or null.
    string getResourceDescription() const pure nothrow @nogc
    {
        return resourceDescription;
    }
}

/// Thrown when new bean creation is disallowed, such as during shutdown.
class BeanCreationNotAllowedException : BeanCreationException
{
    /// Describes why the named bean cannot be created.
    this(string beanName, string message)
    {
        super(beanName, message);
    }
}

/// Thrown when creation is requested for an abstract bean definition.
class BeanIsAbstractException : BeanCreationException
{
    /// Reports the requested abstract bean.
    this(string beanName)
    {
        super(beanName, "Bean definition is abstract");
    }
}

/// Thrown when initialization fails before a bean is fully configured.
class BeanInitializationException : FatalBeanException
{
    /// `message`, with a cause that can still be initialized (Java's `(String)` constructor).
    this(string message) pure nothrow
    {
        super(message);
    }

    /// `message` and an initialized `cause`, even `null` (Java's `(String, Throwable)` constructor).
    this(string message, Throwable cause) pure nothrow
    {
        super(message, cause);
    }
}

/// Thrown when a FactoryBean is asked for its object before it is ready.
class FactoryBeanNotInitializedException : FatalBeanException
{
    /// Uses Spring's standard detail message.
    this() pure nothrow
    {
        this("FactoryBean is not fully initialized yet");
    }

    /// Uses the supplied detail message.
    this(string message) pure nothrow
    {
        super(message);
    }
}

/// Thrown when a bean is requested while it is being created: a circular reference.
class BeanCurrentlyInCreationException : BeanCreationException
{
    /// The standard circular-reference message for `beanName`.
    this(string beanName)
    {
        super(beanName, "Requested bean is currently in creation: "
                ~ "Is there an unresolvable circular reference or an asynchronous initialization dependency?");
    }

    /// `Error creating bean with name 'beanName': msg`.
    this(string beanName, string msg)
    {
        super(beanName, msg);
    }
}

/// Thrown when a bean does not match the required type.
class BeanNotOfRequiredTypeException : BeansException
{
    private string beanName, requiredType, actualType;

    /// `Bean named 'n' is expected to be of type 'r' but was actually of type 'a'`.
    this(string beanName, string requiredType, string actualType)
    {
        super("Bean named '" ~ beanName ~ "' is expected to be of type '" ~ requiredType
                ~ "' but was actually of type '" ~ actualType ~ "'");
        this.beanName = beanName;
        this.requiredType = requiredType;
        this.actualType = actualType;
    }

    /// The bean name.
    string getBeanName() const pure nothrow @nogc
    {
        return beanName;
    }

    /// The required type's canonical name.
    string getRequiredType() const pure nothrow @nogc
    {
        return requiredType;
    }

    /// The actual type's canonical name.
    string getActualType() const pure nothrow @nogc
    {
        return actualType;
    }
}

/// Thrown when a bean is not a factory, but `&name` asked for its factory.
class BeanIsNotAFactoryException : BeanNotOfRequiredTypeException
{
    /// `Bean named 'n' is expected to be of type 'flint.beans.factory.FactoryBean' but was actually of type 'a'`.
    this(string name, string actualType)
    {
        super(name, "flint.beans.factory.FactoryBean", actualType);
    }
}

/++
The erased side of `FactoryBean!T` that the bean factory calls (the D-CORE-2 pattern): `mixin
FactoryBean!T.Defaults` implements it from `getObject`.
+/
interface FactoryBeanErased
{
    /// The object, as `getObject` returns it.
    Object getObjectErased();
    /// The type name of the objects this factory creates, or null when unknown in advance.
    string getObjectType();
    /// Whether `getObject` returns the same object every time.
    bool isSingleton();
}

/++
Spring's `FactoryBean<T>`: a bean that is a factory for the object exposed under its name. `getBean("name")`
returns the object, and `getBean("&name")` the factory. Implementations mix in `Defaults` for Java's default
`isSingleton()` (true), `getObjectType()` (`T`'s name, Java's `Class`, R4) and the erased accessor:

---
final class WidgetFactory : FactoryBean!Widget
{
    mixin FactoryBean!Widget.Defaults;

    Widget getObject() { return new Widget; }
}
---
+/
interface FactoryBean(T) : FactoryBeanErased
{
    /// The attribute naming a definition's object type when it cannot be deduced.
    enum OBJECT_TYPE_ATTRIBUTE = "factoryBeanObjectType";

    /// The object this factory manages; may be null.
    T getObject();

    /// Java's default methods, and the erased accessor.
    mixin template Defaults()
    {
        /// `getObject()`, as an `Object`.
        Object getObjectErased()
        {
            return cast(Object) getObject();
        }

        /// `T`'s canonical name.
        string getObjectType()
        {
            return imported!"flint.engine.aot.name".typeNameOf!(typeof(getObject()));
        }

        /// `true`.
        bool isSingleton()
        {
            return true;
        }
    }
}

/// Thrown when a bean depends on other beans or properties that cannot be satisfied.
class UnsatisfiedDependencyException : BeanCreationException
{
    /// `Error creating bean with name 'b': Unsatisfied dependency expressed through bean property 'p': msg`.
    this(string resourceDescription, string beanName, string propertyName, string msg)
    {
        super(resourceDescription, beanName, propertyMessage(propertyName, msg));
    }

    /// The same message with an initialized `cause`.
    this(string resourceDescription, string beanName, string propertyName, string msg, Throwable cause)
    {
        super(resourceDescription, beanName, propertyMessage(propertyName, msg), cause);
    }

    /// The unsatisfied property with an optional resource, bean name and detail message (R5).
    this(NullableString resourceDescription, NullableString beanName, string propertyName, NullableString msg)
    {
        super(resourceDescription, beanName, propertyMessage(propertyName, msg.isNull ? null : msg.get()));
    }

    /// The unsatisfied property with the supplied bean exception as its cause (R5, R7).
    this(NullableString resourceDescription, NullableString beanName, string propertyName, BeansException cause)
    {
        if (cause is null)
            throw new NullPointerException("cause");
        super(resourceDescription, beanName, propertyMessage(propertyName, cause.msg), cause);
    }

    private static string propertyMessage(string propertyName, string detail)
    {
        const suffix = detail.length ? ": " ~ detail : "";
        return "Unsatisfied dependency expressed through bean property '" ~ propertyName ~ "'" ~ suffix;
    }
}

/// Thrown when a `BeanFactory` encounters an invalid bean definition.
class BeanDefinitionStoreException : FatalBeanException
{
    private string beanName;
    private NullableString resourceDescription;

    /// `msg`, with a cause that can still be initialized (Java's `(String)` constructor).
    this(string msg)
    {
        super(msg);
    }

    /// `msg` and an initialized `cause`, even `null` (Java's `(String, Throwable)` constructor).
    this(string msg, Throwable cause)
    {
        super(msg, cause);
    }

    /// A resource reference with the supplied detail message, with a cause that can still be initialized.
    this(NullableString resourceDescription, string msg)
    {
        super(msg);
        this.resourceDescription = resourceDescription;
    }

    /// A resource reference with the supplied detail message and an initialized `cause`.
    this(NullableString resourceDescription, string msg, Throwable cause)
    {
        super(msg, cause);
        this.resourceDescription = resourceDescription;
    }

    /// `Invalid bean definition with name 'beanName' defined in resource: msg`, with a cause that can still be
    /// initialized.
    this(string resourceDescription, string beanName, string msg)
    {
        this(optionalText(resourceDescription), beanName, optionalText(msg));
    }

    /// `Invalid bean definition with name 'beanName' defined in resource: msg` and an initialized `cause`.
    this(string resourceDescription, string beanName, string msg, Throwable cause)
    {
        this(optionalText(resourceDescription), beanName, optionalText(msg), cause);
    }

    /// A named definition with an optional resource description and detail message, with a cause that can still be
    /// initialized.
    this(NullableString resourceDescription, string beanName, NullableString msg)
    {
        super(invalidDefinition(resourceDescription, beanName, msg));
        this.beanName = beanName;
        this.resourceDescription = resourceDescription;
    }

    /// A named definition with an optional resource description and detail message, and an initialized `cause`.
    this(NullableString resourceDescription, string beanName, NullableString msg, Throwable cause)
    {
        super(invalidDefinition(resourceDescription, beanName, msg), cause);
        this.beanName = beanName;
        this.resourceDescription = resourceDescription;
    }

    private static string invalidDefinition(NullableString source, string beanName, NullableString msg) pure nothrow
    {
        const name = beanName is null ? "null" : beanName;
        const resource = source.isNull ? "null" : source.get();
        const detail = msg.isNull ? "" : ": " ~ msg.get();
        return "Invalid bean definition with name '" ~ name ~ "' defined in " ~ resource ~ detail;
    }

    /// The resource description, if available.
    NullableString getResourceDescription() const pure nothrow @nogc
    {
        return resourceDescription;
    }

    /// The bean name, or null.
    string getBeanName() const pure nothrow @nogc
    {
        return beanName;
    }

    private static NullableString optionalText(string text) pure nothrow @nogc
    {
        return text is null ? NullableString.init : NullableString(text);
    }
}

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.BeanClassLoaderAware sha256:d890a7155e1f4e7608b91c7a2e50461abd7186a1e573801ef56c668485a60c31
/// Callback that allows a bean to be aware of the bean `class loader`; that is, the class loader used by the present
/// bean factory to load bean classes. This is mainly intended to be implemented by framework classes which have to pick
/// up application classes by name despite themselves potentially being loaded from a shared class loader. For a list of
/// all bean lifecycle methods, see the `BeanFactory javadocs`.
interface BeanClassLoaderAware : Aware
{
    // port:pending org.springframework.beans.factory.BeanClassLoaderAware#setBeanClassLoader(ClassLoader): type java.lang.ClassLoader is excluded (jvm-runtime)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.BeanExpressionException sha256:4507acefa28216e7b9b5cf8ea07408a7e499f17ea9ea35c6d6bfeb399ad60626
/// Exception that indicates an expression evaluation attempt having failed.
class BeanExpressionException : FatalBeanException
{
    /// Create a new BeanExpressionException with the specified message.
    this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(msg, file, line);
    }

    // port:pending org.springframework.beans.factory.BeanExpressionException#<init>(String,Throwable): type java.lang.Throwable is not mapped to a D symbol
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.BeanFactoryUtils sha256:5e9dc6346feffc126059c436dcaf284eb4cdc6c26b592f9cf26408414eb4b9a9
/// Convenience methods operating on bean factories, in particular on the `ListableBeanFactory` interface. Returns bean
/// counts, bean names or bean instances, taking into account the nesting hierarchy of a bean factory (which the methods
/// defined on the ListableBeanFactory interface don't, in contrast to the methods defined on the BeanFactory
/// interface). NOTE: It is generally preferable to use `ObjectProvider.stream()` via `BeanFactory.getBeanProvider`
/// instead of this utility class.
abstract class BeanFactoryUtils
{
    /// Separator for generated bean names. If a class name or parent name is not unique, "#1", "#2" etc will be
    /// appended, until the name becomes unique.
    enum string GENERATED_BEAN_NAME_SEPARATOR = "#";

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beanNamesForAnnotationIncludingAncestors(ListableBeanFactory,Class): Class<?> needs a plan choice (R4: ClassRef or RuntimeClassRef)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beanNamesForTypeIncludingAncestors(ListableBeanFactory,Class): Class<?> needs a plan choice (R4: ClassRef or RuntimeClassRef)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beanNamesForTypeIncludingAncestors(ListableBeanFactory,Class,boolean,boolean): Class<?> needs a plan choice (R4: ClassRef or RuntimeClassRef)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beanNamesForTypeIncludingAncestors(ListableBeanFactory,ResolvableType): type org.springframework.core.ResolvableType is excluded (runtime-reflection)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beanNamesForTypeIncludingAncestors(ListableBeanFactory,ResolvableType,boolean,boolean): type org.springframework.core.ResolvableType is excluded (runtime-reflection)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beanNamesIncludingAncestors(ListableBeanFactory): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beanOfType(ListableBeanFactory,Class): a generic method

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beanOfType(ListableBeanFactory,Class,boolean,boolean): a generic method

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beanOfTypeIncludingAncestors(ListableBeanFactory,Class): a generic method

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beanOfTypeIncludingAncestors(ListableBeanFactory,Class,boolean,boolean): a generic method

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beansOfTypeIncludingAncestors(ListableBeanFactory,Class): a generic method

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#beansOfTypeIncludingAncestors(ListableBeanFactory,Class,boolean,boolean): a generic method

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#countBeansIncludingAncestors(ListableBeanFactory): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#isFactoryDereference(String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#isGeneratedBeanName(String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#mergeNamesWithParent(String,String,HierarchicalBeanFactory): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#originalBeanName(String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#transformedBeanName(String): the body is not written yet (--strip-pending)

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#transformedBeanNameCache: a constant whose initializer is not a literal

    // port:pending org.springframework.beans.factory.BeanFactoryUtils#uniqueBean(Class,Map): a generic method
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.BeanRegistrar sha256:10390410e36505a2410c89cae1921329cc101f90092c14b53b0399084be1fa74
/// Contract for registering beans programmatically. Implementations use the `BeanRegistry` and `Environment` to
/// register beans: <pre class="code"> class MyBeanRegistrar implements BeanRegistrar { &#064;Override public void
/// register(BeanRegistry registry, Environment env) { registry.registerBean("foo", Foo.class);
/// registry.registerBean("bar", Bar.class, spec -> spec .prototype() .lazyInit() .description("Custom description")
/// .supplier(context -> new Bar(context.bean(Foo.class)))); if (env.matchesProfiles("baz")) {
/// registry.registerBean(Baz.class, spec -> spec .supplier(context -> new Baz("Hello World!"))); } } } `BeanRegistrar`
/// implementations are not Spring components: they must have a no-arg constructor and cannot rely on dependency
/// injection or any other component-model feature. They can be used in two distinct ways depending on the application
/// context setup. <h3>With the `@Configuration` model</h3> A `BeanRegistrar` must be imported via `@Import` on a
/// `@Configuration` class: <pre class="code"> &#064;Configuration &#064;Import(MyBeanRegistrar.class) class
/// MyConfiguration { } This is the only mechanism that triggers bean registration in the annotation-based configuration
/// model. Annotating an implementation with `@Configuration` or `@Component`, or returning an instance from a `@Bean`
/// method, registers it as a bean but does not invoke its `Environment) register` method. When imported, the registrar
/// is invoked in the order it is encountered during configuration class processing. It can therefore check for and
/// build on beans that have already been defined, but has no visibility into beans that will be registered by classes
/// processed later. <h3>Programmatic usage</h3> A `BeanRegistrar` can also be applied directly to a
/// `org.springframework.context.support.GenericApplicationContext`: <pre class="code"> GenericApplicationContext
/// context = new GenericApplicationContext(); context.register(new MyBeanRegistrar()); context.registerBean("myBean",
/// MyBean.class); context.refresh(); This mode is primarily intended for fully programmatic application context setups.
/// Registrars applied this way are invoked before any `@Configuration` class is processed. They can therefore observe
/// beans registered programmatically (e.g., via one of the `GenericApplicationContext#registerBean` methods), but will
/// not see any beans defined in `@Configuration` classes also registered with the context. A `BeanRegistrar`
/// implementing `org.springframework.context.annotation.ImportAware` can optionally introspect import metadata when
/// used in an import scenario; otherwise the `setImportMetadata` method is not called. In Kotlin, it is recommended to
/// use `BeanRegistrarDsl` instead of implementing `BeanRegistrar`.
interface BeanRegistrar
{
    /// Register beans on the given `BeanRegistry` in a programmatic way.
    void register(BeanRegistry registry, Environment env);
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.BeanRegistry sha256:82d5578ebfd245eb071b77c587647826fa3eebcd19c60de0ad96995454f7ec62
/// Used in `Environment)` to expose programmatic bean registration capabilities.
interface BeanRegistry
{
    /// Register beans using the given `BeanRegistrar`.
    void register(BeanRegistrar registrar);

    /// Given a name, register an alias for it.
    void registerAlias(string name, string alias_);

    /// Determine whether a bean of the given name is already registered.
    bool containsBean(string name);

    // port:pending org.springframework.beans.factory.BeanRegistry#containsBean(Class): Class<?> needs a plan choice (R4: ClassRef or RuntimeClassRef)

    // port:pending org.springframework.beans.factory.BeanRegistry#containsBean(ParameterizedTypeReference): a generic method

    // port:pending org.springframework.beans.factory.BeanRegistry#registerBean(Class): a generic method

    // port:pending org.springframework.beans.factory.BeanRegistry#registerBean(Class,Consumer): a generic method

    // port:pending org.springframework.beans.factory.BeanRegistry#registerBean(ParameterizedTypeReference): a generic method

    // port:pending org.springframework.beans.factory.BeanRegistry#registerBean(ParameterizedTypeReference,Consumer): a generic method

    // port:pending org.springframework.beans.factory.BeanRegistry#registerBean(String,Class): a generic method

    // port:pending org.springframework.beans.factory.BeanRegistry#registerBean(String,Class,Consumer): a generic method

    // port:pending org.springframework.beans.factory.BeanRegistry#registerBean(String,ParameterizedTypeReference): a generic method

    // port:pending org.springframework.beans.factory.BeanRegistry#registerBean(String,ParameterizedTypeReference,Consumer): a generic method

    // port:pending org.springframework.beans.factory.BeanRegistry.Spec: a nested interface (R13)

    // port:pending org.springframework.beans.factory.BeanRegistry.SupplierContext: a nested interface (R13)
}
// port:end

// port:generated port-skeleton/1 spring-framework@v7.1.0 org.springframework.beans.factory.NamedBean sha256:879e6fb6b2256ea50e97e556bfc282c2c202d00ce697a367671e34d36617de4c
/// Counterpart of `BeanNameAware`. Returns the bean name of an object. This interface can be introduced to avoid a
/// brittle dependence on bean name in objects used with Spring IoC and Spring AOP.
interface NamedBean
{
    /// Return the name of this bean in a Spring bean factory, if known.
    string getBeanName();
}
// port:end
