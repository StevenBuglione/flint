// Ported from spring-framework v7.1.0: spring-context/src/main/java/org/springframework/cache/support/NoOpCache.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
// Also ported from NoOpCacheManager.java and SimpleValueWrapper.java.
module flint.cache.support;

import core.atomic : atomicLoad, atomicStore, cas;
import flint.cache : Cache, CacheManager;
import flint.engine.aot.any : Any;
import flint.engine.aot.objects : objectEquals, objectToHash, objectToString;
import flint.java.lang : IllegalArgumentException, JavaObject, javaHashCode, NullPointerException,
    UnsupportedOperationException;
import flint.java.util : AbstractCollection, Collection, Iterator, NoSuchElementException, Set;

@safe:

/// A cache region that accepts operations without storing any mappings.
class NoOpCache : Cache
{
    private string name_;

    /// Create the named cache region.
    this(string name)
    {
        if (name is null)
            throw new IllegalArgumentException("Cache name must not be null");
        name_ = name;
    }

    override string getName() nothrow @nogc
    {
        return name_;
    }

    override Object getNativeCache() nothrow @nogc
    {
        return this;
    }

    /// The cached value as the requested type.
    T get(T)(Any key)
    {
        return (cast(Cache) this).get!T(key);
    }

    override ValueWrapper get(Any key) nothrow @nogc
    {
        return null;
    }

    override Any get(Any key, scope Any delegate() @safe valueLoader)
    {
        try
        {
            if (valueLoader is null)
                throw new NullPointerException();
            return valueLoader();
        }
        catch (Exception failure)
        {
            throw new ValueRetrievalException(key, valueLoader, failure);
        }
    }

    override void put(Any key, Any value) nothrow @nogc
    {
    }

    override ValueWrapper putIfAbsent(Any key, Any value) nothrow @nogc
    {
        return null;
    }

    override void evict(Any key) nothrow @nogc
    {
    }

    override bool evictIfPresent(Any key) nothrow @nogc
    {
        return false;
    }

    override void clear() nothrow @nogc
    {
    }

    override bool invalidate() nothrow @nogc
    {
        return false;
    }
}

/// Resolve a stable no-op cache for each requested name until the manager resets.
class NoOpCacheManager : CacheManager
{
    // Read-only after atomic publication. Cache objects and the name view can outlive a reset.
    private Snapshot regions;
    private CacheNames names;

    /// Construct an empty manager with a live view of its registered names.
    this()
    {
        names = new CacheNames(&registeredCaches);
    }

    override Cache getCache(string name)
    {
        if (name is null)
            throw new NullPointerException();
        NoOpCache created;
        for (;;)
        {
            auto observed = atomicLoad(regions);
            auto found = find(observed, name);
            if (found !is null)
                return found;
            if (created is null)
                created = new NoOpCache(name);
            auto updated = new Snapshot(entries(observed) ~ created);
            if (cas(&regions, observed, updated))
                return created;
        }
    }

    override Collection!string getCacheNames() nothrow @nogc
    {
        return names;
    }

    override void resetCaches() nothrow @nogc
    {
        atomicStore(regions, cast(Snapshot) null);
    }

    private Cache[] registeredCaches() nothrow @nogc
    {
        return entries(atomicLoad(regions));
    }

    private static Cache[] entries(Snapshot snapshot) nothrow @nogc
    {
        return snapshot is null ? null : snapshot.caches;
    }

    private static Cache find(Snapshot snapshot, string name)
    {
        if (name is null)
            return null;
        foreach (cache; entries(snapshot))
            if (cache.getName() == name)
                return cache;
        return null;
    }

    private static final class Snapshot
    {
        private Cache[] caches;

        this(Cache[] caches) nothrow @nogc
        {
            this.caches = caches;
        }
    }

}

/// Read-only names backed by the manager's latest list of registered caches.
package(flint.cache) final class CacheNames : AbstractCollection!string, Set!string
{
    private Cache[]delegate() @safe nothrow @nogc registered;
    private bool rejectsNullName;

    this(Cache[]delegate() @safe nothrow @nogc registered, bool rejectsNullName = false) nothrow @nogc
    {
        this.registered = registered;
        this.rejectsNullName = rejectsNullName;
    }

    override int size() nothrow @nogc
    {
        return cast(int) registered().length;
    }

    override bool contains(string name)
    {
        if (name is null)
        {
            if (rejectsNullName)
                throw new NullPointerException();
            return false;
        }
        foreach (cache; registered())
            if (cache.getName() == name)
                return true;
        return false;
    }

    override Iterator!string iterator()
    {
        return new NameIterator(registered());
    }

    override bool isSet() nothrow @nogc
    {
        return true;
    }

    override bool equals(Object other)
    {
        if (other is this)
            return true;
        auto that = cast(Set!string) other;
        auto caches = registered();
        if (that is null || that.size() != caches.length)
            return false;
        foreach (cache; caches)
            if (!that.contains(cache.getName()))
                return false;
        return true;
    }

    override int hashCode()
    {
        int result;
        foreach (cache; registered())
            result += javaHashCode(cache.getName());
        return result;
    }

    override bool remove(string name)
    {
        throw new UnsupportedOperationException();
    }

    override bool addAll(Collection!string other)
    {
        throw new UnsupportedOperationException();
    }

    override bool removeAll(Collection!string other)
    {
        throw new UnsupportedOperationException();
    }

    override bool retainAll(Collection!string other)
    {
        throw new UnsupportedOperationException();
    }

    override bool removeIf(bool delegate(string) @safe filter)
    {
        throw new UnsupportedOperationException();
    }

    override void clear()
    {
        throw new UnsupportedOperationException();
    }
}

private final class NameIterator : Iterator!string
{
    private Cache[] caches;
    private size_t index;

    this(Cache[] caches) nothrow @nogc
    {
        this.caches = caches;
    }

    override bool hasNext() nothrow @nogc
    {
        return index < caches.length;
    }

    override string next()
    {
        if (!hasNext())
            throw new NoSuchElementException();
        return caches[index++].getName();
    }

    override void remove()
    {
        throw new UnsupportedOperationException();
    }
}

/// An immutable wrapper around a cache value, which may be null.
class SimpleValueWrapper : Cache.ValueWrapper
{
    private Any value;

    /// Wrap the value to expose through `get`.
    this(Any value) nothrow @nogc
    {
        this.value = value;
    }

    override Any get() nothrow @nogc
    {
        return value;
    }

    /// Compare with another wrapper by its contained value.
    bool equals(Object other)
    {
        if (other is this)
            return true;
        auto wrapper = cast(Cache.ValueWrapper) other;
        return wrapper !is null && cacheValueEquals(get(), wrapper.get());
    }

    /// The wrapped value's hash, or zero for null.
    int hashCode()
    {
        return cacheValueHash(value);
    }

    override string toString()
    {
        return "ValueWrapper for [" ~ cacheValueText(value) ~ "]";
    }

    mixin JavaObject;
}

package(flint.cache) bool cacheValueEquals(Any value, Any other)
{
    if (value.isNull())
        return other.isNull();
    auto object = value.asObject();
    return object is null ? value == other : objectEquals(object, other.asObject());
}

package(flint.cache) int cacheValueHash(Any value)
{
    if (value.isNull())
        return 0;
    if (auto object = value.asObject())
        return cast(int) objectToHash(object);
    if (value.typeName() == "string")
        return javaHashCode(value.get!string());
    if (value.typeName() == "int")
        return value.get!int();
    return cast(int) value.toHash();
}

package(flint.cache) string cacheValueText(Any value)
{
    auto object = value.asObject();
    return object is null ? value.toString() : objectToString(object);
}
