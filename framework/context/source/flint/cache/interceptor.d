// Ported from spring-framework v7.1.0: spring-context/src/main/java/org/springframework/cache/interceptor/SimpleKey.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
// Also ported from SimpleKeyGenerator.java, KeyGenerator.java, BasicOperation.java,
// CacheOperation.java, CacheableOperation.java, CacheEvictOperation.java, CachePutOperation.java
// CacheOperationSource.java and AbstractFallbackCacheOperationSource.java.
module flint.cache.interceptor;

import flint.cache.support : cacheValueEquals, cacheValueHash, cacheValueText;
import flint.conc.slot : ProcessSlot;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, DescriptorTable, MemberDescriptorRef, MemberKind,
    MethodDescriptor, TypeKind;
import flint.engine.aot.name : typeNameOf;
import flint.java.lang : IllegalArgumentException, JavaObject, NullPointerException, javaHashCode, stringHashCode;
import flint.java.util : Collection, Collections, LinkedHashSet, Set;
import flint.util : Assert;
import std.typecons : Nullable;

@safe:

/// An operation that names the caches on which it acts (R10).
interface BasicOperation
{
    /// Cache names in declaration order.
    Set!string getCacheNames();
}

private struct CacheOperationValues
{
    string name = "";
    Set!string cacheNames;
    string key = "";
    string keyGenerator = "";
    string cacheManager = "";
    string cacheResolver = "";
    string condition = "";
}

/// Common settings and identity for a cache operation.
abstract class CacheOperation : BasicOperation
{
    private CacheOperationValues values;
    private string description;
    private int hash;

    /// Capture the builder's settings and identifying description.
    protected this(Builder builder)
    {
        values = builder.values;
        values.cacheNames = builder.getCacheNames();
        description = builder.operationDescription().idup;
        hash = stringHashCode(description);
    }

    /// The operation name.
    string getName() nothrow @nogc
    {
        return values.name;
    }

    /// Cache names in declaration order (R10).
    override Set!string getCacheNames() nothrow @nogc
    {
        return values.cacheNames;
    }

    /// The SpEL key expression.
    string getKey() nothrow @nogc
    {
        return values.key;
    }

    /// The key generator bean name.
    string getKeyGenerator() nothrow @nogc
    {
        return values.keyGenerator;
    }

    /// The cache manager bean name.
    string getCacheManager() nothrow @nogc
    {
        return values.cacheManager;
    }

    /// The cache resolver bean name.
    string getCacheResolver() nothrow @nogc
    {
        return values.cacheResolver;
    }

    /// The SpEL condition expression.
    string getCondition() nothrow @nogc
    {
        return values.condition;
    }

    /// Compare operations by their identifying descriptions (R11).
    bool equals(Object other)
    {
        auto operation = cast(CacheOperation) other;
        return operation !is null && description == operation.description;
    }

    /// The Java hash of the identifying description (R11).
    int hashCode() nothrow @nogc
    {
        return hash;
    }

    /// The description built when the operation was constructed.
    override final string toString() nothrow @nogc
    {
        return description;
    }

    mixin JavaObject;

    /// Base class for operation builders (R3, R12, R13).
    static abstract class Builder
    {
        private CacheOperationValues values;

        /// Set the operation name.
        void setName(string name)
        {
            Assert.hasText(name, "Name must not be empty");
            values.name = name;
        }

        /// Set one cache name.
        void setCacheName(string name)
        {
            Assert.hasText(name, "Cache name must not be empty");
            values.cacheNames = Collections.singleton(name);
        }

        /// Set the ordered cache names (R7).
        void setCacheNames(scope const(string)[] names...)
        {
            auto cacheNames = new LinkedHashSet!string();
            foreach (name; names)
            {
                Assert.hasText(name, "Cache name must be non-empty if specified");
                cacheNames.add(name);
            }
            values.cacheNames = cacheNames;
        }

        /// Return the assigned cache names (R10).
        Set!string getCacheNames()
        {
            if (values.cacheNames is null)
                values.cacheNames = Collections.emptySet!string();
            return values.cacheNames;
        }

        /// Set the SpEL key expression.
        void setKey(string key)
        {
            Assert.notNull(key, "Key must not be null");
            values.key = key;
        }

        /// The SpEL key expression.
        string getKey() nothrow @nogc
        {
            return values.key;
        }

        /// The key generator bean name.
        string getKeyGenerator() nothrow @nogc
        {
            return values.keyGenerator;
        }

        /// The cache manager bean name.
        string getCacheManager() nothrow @nogc
        {
            return values.cacheManager;
        }

        /// The cache resolver bean name.
        string getCacheResolver() nothrow @nogc
        {
            return values.cacheResolver;
        }

        /// Set the key generator bean name.
        void setKeyGenerator(string keyGenerator)
        {
            Assert.notNull(keyGenerator, "KeyGenerator name must not be null");
            values.keyGenerator = keyGenerator;
        }

        /// Set the cache manager bean name.
        void setCacheManager(string cacheManager)
        {
            Assert.notNull(cacheManager, "CacheManager name must not be null");
            values.cacheManager = cacheManager;
        }

        /// Set the cache resolver bean name.
        void setCacheResolver(string cacheResolver)
        {
            Assert.notNull(cacheResolver, "CacheResolver name must not be null");
            values.cacheResolver = cacheResolver;
        }

        /// Set the SpEL condition expression.
        void setCondition(string condition)
        {
            Assert.notNull(condition, "Condition must not be null");
            values.condition = condition;
        }

        private char[] operationDescription()
        {
            const name = typeid(this).name;
            size_t simple = name.length;
            while (simple && name[simple - 1] != '.')
                --simple;
            // A D nested class uses the same dotted qualification as a package name.
            auto text = name[simple .. $].dup;
            text ~= '[';
            text ~= values.name;
            text ~= "] caches=[";
            auto names = getCacheNames().iterator();
            if (names.hasNext())
                text ~= names.next();
            while (names.hasNext())
            {
                text ~= ", ";
                text ~= names.next();
            }
            text ~= "] | key='";
            text ~= values.key;
            text ~= "' | keyGenerator='";
            text ~= values.keyGenerator;
            text ~= "' | cacheManager='";
            text ~= values.cacheManager;
            text ~= "' | cacheResolver='";
            text ~= values.cacheResolver;
            text ~= "' | condition='";
            text ~= values.condition;
            text ~= '\'';
            appendOperationDetails(text);
            return text;
        }

        private void appendOperationDetails(ref char[] text)
        {
            if (auto cacheable = cast(CacheableOperation.Builder) this)
            {
                appendUnless(text, cacheable.unless_);
                text ~= " | sync='";
                text ~= cacheable.sync_ ? "true" : "false";
                text ~= '\'';
            }
            else if (auto eviction = cast(CacheEvictOperation.Builder) this)
            {
                text ~= eviction.cacheWide ? ",true" : ",false";
                text ~= eviction.beforeInvocation ? ",true" : ",false";
            }
            else if (auto put = cast(CachePutOperation.Builder) this)
                appendUnless(text, put.unless_);
        }

        /// Create the operation described by this builder.
        abstract CacheOperation build();
    }
}

/// An operation that looks up a value before invoking the method.
class CacheableOperation : CacheOperation
{
    private Nullable!string unless_;
    private bool sync_;

    /// Capture a cacheable operation from its builder.
    this(Builder builder)
    {
        super(builder);
        unless_ = builder.unless_;
        sync_ = builder.sync_;
    }

    /// The result veto, which distinguishes null from empty (R5).
    Nullable!string getUnless() nothrow @nogc
    {
        return unless_;
    }

    /// Whether to coalesce same-key loads.
    bool isSync() nothrow @nogc
    {
        return sync_;
    }

    /// Builder for a cacheable operation.
    static class Builder : CacheOperation.Builder
    {
        private Nullable!string unless_;
        private bool sync_;

        /// Set the result veto.
        void setUnless(string unless)
        {
            setUnless(nullableUnless(unless));
        }

        /// Set the result veto while preserving explicit absence (R5).
        void setUnless(Nullable!string unless)
        {
            unless_ = unless;
        }

        /// Whether to coalesce same-key loads.
        void setSync(bool sync)
        {
            sync_ = sync;
        }

        /// Create the cacheable operation.
        override CacheableOperation build()
        {
            return new CacheableOperation(this);
        }
    }
}

/// An operation that evicts entries before or after the method call.
class CacheEvictOperation : CacheOperation
{
    private bool cacheWide;
    private bool beforeInvocation;

    /// Capture an eviction operation from its builder.
    this(Builder builder)
    {
        super(builder);
        cacheWide = builder.cacheWide;
        beforeInvocation = builder.beforeInvocation;
    }

    /// Whether to evict every entry in each cache.
    bool isCacheWide() nothrow @nogc
    {
        return cacheWide;
    }

    /// Whether eviction runs before the target method.
    bool isBeforeInvocation() nothrow @nogc
    {
        return beforeInvocation;
    }

    /// Builder for an eviction operation.
    static class Builder : CacheOperation.Builder
    {
        private bool cacheWide;
        private bool beforeInvocation;

        /// Whether to evict every entry.
        void setCacheWide(bool value)
        {
            cacheWide = value;
        }

        /// Whether eviction runs before the target method.
        void setBeforeInvocation(bool value)
        {
            beforeInvocation = value;
        }

        /// Create the eviction operation.
        override CacheEvictOperation build()
        {
            return new CacheEvictOperation(this);
        }
    }
}

/// An operation that stores the method result.
class CachePutOperation : CacheOperation
{
    private Nullable!string unless_;

    /// Capture a put operation from its builder.
    this(Builder builder)
    {
        super(builder);
        unless_ = builder.unless_;
    }

    /// The result veto, which distinguishes null from empty (R5).
    Nullable!string getUnless() nothrow @nogc
    {
        return unless_;
    }

    /// Builder for a put operation.
    static class Builder : CacheOperation.Builder
    {
        private Nullable!string unless_;

        /// Set the result veto.
        void setUnless(string unless)
        {
            setUnless(nullableUnless(unless));
        }

        /// Set the result veto while preserving explicit absence (R5).
        void setUnless(Nullable!string unless)
        {
            unless_ = unless;
        }

        /// Create the put operation.
        override CachePutOperation build()
        {
            return new CachePutOperation(this);
        }
    }
}

private Nullable!string nullableUnless(string unless)
{
    return unless is null ? Nullable!string.init : Nullable!string(unless);
}

private void appendUnless(ref char[] text, Nullable!string unless)
{
    text ~= " | unless='";
    text ~= unless.isNull ? "null" : unless.get();
    text ~= '\'';
}

/// Supplies cache operation metadata for an advised method (R4, R10).
interface CacheOperationSource
{
    /// Whether the target can carry cache operation metadata.
    bool isCandidateClass(scope const Descriptor target);

    /// Whether there is a cache operation for the method and target.
    bool hasCacheOperations(MemberDescriptorRef method, const Descriptor target);

    /// The declared operations, or null when there is no caching metadata.
    /// The source may retain these descriptors, which must be stable after registration.
    Collection!CacheOperation getCacheOperations(MemberDescriptorRef method, const Descriptor target);

    /// Spring's default candidate and operation checks (R3).
    mixin template Defaults()
    {
        override bool isCandidateClass(scope const Descriptor)
        {
            return true;
        }

        override bool hasCacheOperations(MemberDescriptorRef method, const Descriptor target)
        {
            auto operations = getCacheOperations(method, target);
            return operations !is null && !operations.isEmpty();
        }
    }
}

/// Resolves cache metadata from specific methods and types, and memoizes the results.
abstract class AbstractFallbackCacheOperationSource : CacheOperationSource
{
    private shared ProcessSlot!OperationSnapshot operations;

    /// Whether the type can carry cache operation metadata.
    override bool isCandidateClass(scope const Descriptor)
    {
        return true;
    }

    /// Test for operations without publishing a new miss.
    override bool hasCacheOperations(MemberDescriptorRef method, const Descriptor target)
    {
        auto found = operationsFor(method, target, false);
        return found !is null && !found.isEmpty();
    }

    /// Read the metadata for this registered method and target.
    override Collection!CacheOperation getCacheOperations(MemberDescriptorRef method, const Descriptor target)
    {
        return operationsFor(method, target, true);
    }

    /// Find caching metadata on the given type.
    protected abstract Collection!CacheOperation findCacheOperations(scope const Descriptor type);

    /// Find caching metadata on the given method with its declaring type when available.
    protected abstract Collection!CacheOperation findCacheOperations(MemberDescriptorRef method);

    /// Choose the operation metadata cache key for a method and concrete target.
    protected Any getCacheKey(MemberDescriptorRef method, const Descriptor target)
    {
        return Any.of(MethodOperationKey(cast(const(void)*) method.owner, cast(const(void)*) target, method.index));
    }

    private Collection!CacheOperation operationsFor(MemberDescriptorRef method, const Descriptor target,
            bool cacheMissing)
    {
        if (method.method() is null)
            return null;
        OperationEntry entry;
        entry.key = getCacheKey(method, target);
        entry.order = operationKeyOrder(entry.key);
        auto current = operations.get();
        if (current !is null && current.find(entry, entry.value))
            return entry.value;

        entry.value = build(method, target);
        if (entry.value is null && !cacheMissing)
            return null;
        return publish(current, entry);
    }

    private Collection!CacheOperation publish(OperationSnapshot current, OperationEntry entry)
    {
        for (;;)
        {
            auto replacement = new OperationSnapshot(current, entry);
            synchronized (this)
            {
                if (operations.get() is current)
                {
                    operations.set(replacement);
                    return entry.value;
                }
            }
            // A custom key may invoke application equality. Compare against the newer snapshot outside the monitor.
            current = operations.get();
            Collection!CacheOperation published;
            if (current.find(entry, published))
                return published;
        }
    }

    private Collection!CacheOperation build(MemberDescriptorRef method, const Descriptor target)
    {
        auto specific = mostSpecificMethod(method, target);
        auto found = findCacheOperations(specific);
        if (found !is null)
            return found;
        found = findCacheOperations(specific.declaringType());
        if (found !is null || specific == method)
            return found;

        found = findCacheOperations(method);
        return found is null ? findCacheOperations(method.declaringType()) : found;
    }
}

private MemberDescriptorRef mostSpecificMethod(MemberDescriptorRef method, const Descriptor target) nothrow @nogc
{
    if (target !is null && target !is method.owner)
    {
        auto original = method.method();
        foreach (index, ref candidate; target.methods)
            if (sameSignature(candidate, *original))
                return MemberDescriptorRef(target, cast(uint) index, MemberKind.method);
    }
    return method;
}

private bool sameSignature(scope ref const MethodDescriptor left, scope ref const MethodDescriptor right) nothrow @nogc
{
    if (left.name != right.name || left.parameters.length != right.parameters.length)
        return false;
    foreach (i, ref parameter; left.parameters)
        if (parameter.type != right.parameters[i].type)
            return false;
    return true;
}

// Any stores this key inline. The pointer fields keep registered descriptors alive.
private struct MethodOperationKey
{
    const(void)* owner;
    const(void)* target;
    size_t memberIndex;
}

static assert(!Any.boxes!MethodOperationKey);

private size_t[3] operationKeyOrder(Any key)
{
    MethodOperationKey method;
    if (key.tryGet(method))
        return [cast(size_t) method.owner, method.memberIndex, cast(size_t) method.target];
    if (key.isNull())
        throw new NullPointerException("Cache operation metadata key must not be null");
    return [0, cast(size_t) cacheValueHash(key), 0];
}

private struct OperationEntry
{
    Any key;
    size_t[3] order;
    Collection!CacheOperation value;
}

// Once published, the sorted entries are read-only. A cold insert copies one array.
private final class OperationSnapshot
{
    private OperationEntry[] entries;

    this(OperationSnapshot previous, OperationEntry addition)
    {
        auto old = previous is null ? null : previous.entries;
        const at = previous is null ? 0 : previous.lowerBound(addition.order);
        entries = new OperationEntry[old.length + 1];
        entries[0 .. at] = old[0 .. at];
        entries[at] = addition;
        entries[at + 1 .. $] = old[at .. $];
    }

    bool find(ref OperationEntry sought, out Collection!CacheOperation value)
    {
        for (size_t at = lowerBound(sought.order); at < entries.length && entries[at].order == sought.order;
                ++at)
        {
            if (cacheValueEquals(entries[at].key, sought.key))
            {
                value = entries[at].value;
                return true;
            }
        }
        return false;
    }

    private size_t lowerBound(size_t[3] key) const pure nothrow @nogc
    {
        size_t low, high = entries.length;
        while (low < high)
        {
            const middle = low + (high - low) / 2;
            if (entries[middle].order < key)
                low = middle + 1;
            else
                high = middle;
        }
        return low;
    }
}

/// Generate a key from the advised target, its method descriptor and the erased parameters.
interface KeyGenerator
{
    /// Return the key for the borrowed receiver, method and argument sequence.
    Any generate(scope Any target, MemberDescriptorRef method, scope Any[] params...);
}

/// Generate keys directly for scalar parameters and use SimpleKey when they must be grouped.
class SimpleKeyGenerator : KeyGenerator
{
    private const DescriptorTable descriptors;

    /// Create a generator for scalar and compound keys without array descriptors.
    this()
    {
        this(null);
    }

    /// Use the context's startup-registered descriptors to snapshot array parameters.
    package(flint.cache) this(const DescriptorTable descriptors)
    {
        this.descriptors = descriptors;
    }

    override Any generate(scope Any target, MemberDescriptorRef method, scope Any[] params...)
    {
        return generateErasedKey(descriptors, params);
    }

    /// Generate the default key from its method arguments.
    static Any generateKey(scope Any[] params...)
    {
        return generateErasedKey(null, params);
    }

    /// Generate a key from typed arguments, including array components known at compile time (R7).
    static Any generateKey(Args...)(Args args) if (typedKeyArguments!Args)
    {
        static if (Args.length == 1 && !isTypedKeyArray!(Args[0]))
        {
            auto key = Any.of(args[0]);
            if (!key.isNull() && !isArray(key.typeName()))
                return key;
        }
        return Any.of(new SimpleKey(args));
    }

    private static Any generateErasedKey(const DescriptorTable descriptors, scope Any[] params)
    {
        if (params.length == 0)
            return Any.of(SimpleKey.EMPTY);
        if (params.length == 1 && !params[0].isNull() && !isArray(params[0].typeName()))
            return params[0];
        return Any.of(new SimpleKey(descriptors, params));
    }
}

/// An ordered tuple of method arguments. String elements are copied when the key is created.
class SimpleKey
{
    private static shared ProcessSlot!SimpleKey empty;
    private Any[] params;
    private int hash;

    /// The common key for methods with no arguments.
    static @property SimpleKey EMPTY()
    {
        auto current = empty.get();
        return current is null ? empty.setIfAbsent(new SimpleKey()) : current;
    }

    /// Snapshot the supplied key elements.
    this(scope Any[] elements...)
    {
        this(cast(const(DescriptorTable)) null, elements);
    }

    /// Snapshot typed arguments using their declared array component types (R7).
    this(Args...)(Args elements) if (typedKeyArguments!Args)
    {
        params = new Any[elements.length];
        static foreach (i; 0 .. elements.length)
            params[i] = ownTypedElement(elements[i]);
        calculateHash();
    }

    private this(const DescriptorTable descriptors, scope Any[] elements)
    {
        params = new Any[elements.length];
        foreach (i, element; elements)
            params[i] = ownElement(element, descriptors);
        calculateHash();
    }

    private void calculateHash()
    {
        uint combined = elementsHash(params);
        combined = (combined ^ (combined >>> 16)) * 0x85ebca6b;
        combined = (combined ^ (combined >>> 13)) * 0xc2b2ae35;
        hash = cast(int)(combined ^ (combined >>> 16));
    }

    /// Compare the elements of the two keys in order.
    bool equals(Object other)
    {
        auto that = cast(SimpleKey) other;
        if (this is that)
            return true;
        return that !is null && hash == that.hash && elementsEqual(params, that.params);
    }

    /// The hash computed when the key was created.
    final int hashCode() nothrow @nogc
    {
        return hash;
    }

    /// The Spring SimpleKey representation.
    override string toString()
    {
        return "SimpleKey " ~ elementsText(params);
    }

    mixin JavaObject;
}

private bool isArray(string name) pure nothrow @nogc
{
    return name.length > 2 && name[$ - 2 .. $] == "[]";
}

private enum typedKeyArguments(Args...) = Args.length != 0 && !(Args.length == 1
            && (is(Args[0] : const(Any)[]) || is(Args[0] == typeof(null))));

private enum isTypedKeyArray(T) = is(T == E[], E) && !is(T : const(char)[]);

private Any ownTypedElement(T)(T value)
{
    static if (is(T == typeof(null)))
        return Any.init;
    else static if (isTypedKeyArray!T && is(T == E[], E))
    {
        if (value is null)
            return Any.init;
        static if (is(const E == const Any))
            throw new IllegalArgumentException("Cache key arrays require a concrete element type: " ~ typeNameOf!T);
        else
        {
            auto elements = new Any[value.length];
            foreach (i, element; value)
                elements[i] = ownTypedElement(element);
            return Any.of(new ArrayKey(elements, typeNameOf!E));
        }
    }
    else
        return ownElement(Any.of(value), null);
}

private Any ownElement(Any value, const DescriptorTable descriptors)
{
    if (value.isNull())
        return Any.init;
    if (isArray(value.typeName()))
    {
        auto descriptor = descriptors is null ? null : descriptors.find(value.typeName());
        if (descriptor is null || descriptor.kind != TypeKind.array || descriptor.length is null
                || descriptor.element is null)
            throw new IllegalArgumentException("Missing AOT array descriptor for cache key type: " ~ value.typeName());
        // An erased Any[] can contain itself. A typed array's declared nesting depth is finite.
        if (descriptor.elementType == typeNameOf!Any)
            throw new IllegalArgumentException("Cache key arrays require a concrete element type: " ~ value.typeName());
        auto elements = new Any[descriptor.length(value)];
        foreach (i; 0 .. elements.length)
            elements[i] = ownElement(descriptor.element(value, i), descriptors);
        return Any.of(new ArrayKey(elements, descriptor.elementType));
    }
    if (value.typeName() != "string")
        return value;
    auto text = value.get!string();
    return Any.of(text.length == 0 ? "" : text.idup);
}

// Keep array contents out of the application's mutable storage. Java deep equality
// distinguishes primitive array types and compares reference arrays element by element.
private final class ArrayKey
{
    private Any[] elements;
    private string primitiveType;
    private int hash;

    this(Any[] elements, string elementType)
    {
        this.elements = elements;
        primitiveType = primitiveArrayType(elementType);
        hash = elementsHash(elements);
    }

    bool equals(Object other)
    {
        auto that = cast(ArrayKey) other;
        return that !is null && primitiveType == that.primitiveType && hash == that.hash
            && elementsEqual(elements, that.elements);
    }

    int hashCode() nothrow @nogc
    {
        return hash;
    }

    override string toString()
    {
        return elementsText(elements);
    }

    mixin JavaObject;
}

private string primitiveArrayType(string type) pure nothrow @nogc
{
    static immutable string[4] qualifiers = ["const(", "immutable(", "inout(", "shared("];
    foreach (qualifier; qualifiers)
        if (type.length > qualifier.length && type[0 .. qualifier.length] == qualifier && type[$ - 1] == ')')
            return primitiveArrayType(type[qualifier.length .. $ - 1]);

    switch (type)
    {
    case "bool":
    case "byte", "ubyte":
    case "short", "ushort":
    case "int", "uint":
    case "long",
            "ulong":
    case "char", "wchar", "dchar":
    case "float", "double":
        return type;
    default:
        return null;
    }
}

private bool elementsEqual(scope Any[] left, scope Any[] right)
{
    if (left.length != right.length)
        return false;
    foreach (i, element; left)
    {
        auto other = right[i];
        const type = element.typeName();
        if (type == "float" && other.typeName() == type)
        {
            if (floatingBits(element.get!float()) != floatingBits(other.get!float()))
                return false;
        }
        else if (type == "double" && other.typeName() == type)
        {
            if (floatingBits(element.get!double()) != floatingBits(other.get!double()))
                return false;
        }
        else if (!cacheValueEquals(element, other))
            return false;
    }
    return true;
}

private int elementsHash(scope Any[] elements)
{
    uint hash = 1;
    foreach (element; elements)
        hash = 31 * hash + elementHash(element);
    return cast(int) hash;
}

private int elementHash(Any value)
{
    switch (value.typeName())
    {
    case "bool":
        return javaHashCode(value.get!bool());
    case "byte", "ubyte", "short", "ushort", "int", "uint":
        return cast(int) value.get!long();
    case "long":
        return javaHashCode(value.get!long());
    case "ulong":
        return javaHashCode(value.get!ulong());
    case "char", "wchar", "dchar":
        return cast(int) value.get!dchar();
    case "float":
        return cast(int) floatingBits(value.get!float());
    case "double":
        return javaHashCode(value.get!double());
    default:
        return cacheValueHash(value);
    }
}

private auto floatingBits(T)(T value) pure nothrow @nogc
{
    static if (is(T == float))
    {
        alias Word = uint;
        enum canonicalNaN = 0x7fc00000U;
    }
    else
    {
        alias Word = ulong;
        enum canonicalNaN = 0x7ff8000000000000UL;
    }
    union Bits
    {
        T number;
        Word bits;
    }

    Bits data;
    data.number = value;
    return value != value ? canonicalNaN : data.bits;
}

private string elementsText(scope Any[] elements)
{
    auto text = "[".dup;
    foreach (i, element; elements)
    {
        if (i != 0)
            text ~= ", ";
        text ~= cacheValueText(element);
    }
    text ~= ']';
    return text.idup;
}
