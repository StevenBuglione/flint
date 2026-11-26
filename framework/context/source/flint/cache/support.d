// Ported from spring-framework v7.1.0: spring-context/src/main/java/org/springframework/cache/support/NoOpCache.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
// Also ported from NoOpCacheManager.java.
module flint.cache.support;

import core.atomic : atomicLoad, atomicStore, cas;
import flint.cache : Cache, CacheManager;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, javaHashCode, NullPointerException, UnsupportedOperationException;
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
    private NameView names;

    /// Construct an empty manager with a live view of its registered names.
    this()
    {
        names = new NameView(this);
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

    private static NoOpCache[] entries(Snapshot snapshot) nothrow @nogc
    {
        return snapshot is null ? null : snapshot.caches;
    }

    private static NoOpCache find(Snapshot snapshot, string name) nothrow @nogc
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
        private NoOpCache[] caches;

        this(NoOpCache[] caches) nothrow @nogc
        {
            this.caches = caches;
        }
    }

    private static final class NameView : AbstractCollection!string, Set!string
    {
        private NoOpCacheManager manager;

        this(NoOpCacheManager manager) nothrow @nogc
        {
            this.manager = manager;
        }

        override int size() nothrow @nogc
        {
            return cast(int) entries(atomicLoad(manager.regions)).length;
        }

        override bool contains(string name) nothrow @nogc
        {
            return find(atomicLoad(manager.regions), name) !is null;
        }

        override Iterator!string iterator()
        {
            return new NameIterator(entries(atomicLoad(manager.regions)));
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
            auto caches = entries(atomicLoad(manager.regions));
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
            foreach (cache; entries(atomicLoad(manager.regions)))
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

    private static final class NameIterator : Iterator!string
    {
        private NoOpCache[] caches;
        private size_t index;

        this(NoOpCache[] caches) nothrow @nogc
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
}
