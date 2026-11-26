// Ported from spring-framework v7.1.0: spring-context/src/main/java/org/springframework/cache/Cache.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
// Also ported from CacheManager.java.
module flint.cache;

import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.java.lang : IllegalStateException, RuntimeException;
import flint.java.util : Collection;

@safe:

/// A named cache region. Object-typed keys and values use Flint's erased Any.
interface Cache
{
    /// The name of this cache region.
    string getName();

    /// The underlying cache provider.
    Object getNativeCache();

    /// Null on a miss. A non-null wrapper can hold a cached null.
    ValueWrapper get(Any key);

    /// Read a value with a type check (R4). A miss or cached null yields T.init.
    T get(T)(Any key)
    {
        auto entry = get(key);
        if (entry is null)
            return T.init;

        auto value = entry.get();
        if (value.isNull())
            return T.init;
        static if (!is(T == class) && !is(T == interface) && !is(T == Any))
        {
            if (value.typeName() != typeNameOf!T)
                throw new IllegalStateException("Cached value is not of required type " ~ typeNameOf!T);
        }
        if (!value.holds!T())
            throw new IllegalStateException("Cached value is not of required type " ~ typeNameOf!T);
        return value.get!T();
    }

    /// Read a value or obtain it by invoking the loader (R9).
    Any get(Any key, scope Any delegate() @safe valueLoader);

    /// Associate the key with the given value.
    void put(Any key, Any value);

    /// Associate the key with the value when absent, otherwise return the existing entry.
    ValueWrapper putIfAbsent(Any key, Any value);

    /// Remove the mapping for this key.
    void evict(Any key);

    /// Immediately remove the mapping and report whether one was known to exist.
    bool evictIfPresent(Any key);

    /// Remove all mappings.
    void clear();

    /// Immediately remove all mappings and report whether any were known to exist.
    bool invalidate();

    /// Default methods for providers without atomic or immediate operations (R3).
    mixin template Defaults()
    {
        override ValueWrapper putIfAbsent(Any key, Any value)
        {
            auto entry = get(key);
            if (entry is null)
                put(key, value);
            return entry;
        }

        override bool evictIfPresent(Any key)
        {
            evict(key);
            return false;
        }

        override bool invalidate()
        {
            clear();
            return false;
        }
    }

    /// A cached value, which may itself be null.
    static interface ValueWrapper
    {
        /// The value stored in the cache.
        Any get();
    }

    /// Wraps a loader failure and retains the cache key and original cause (R8, R13).
    static class ValueRetrievalException : RuntimeException
    {
        private Any key_;

        /// Wrap the exception thrown while loading this key.
        this(Any key, scope Any delegate() @safe loader, Throwable cause)
        {
            super("Value for key '" ~ key.toString() ~ "' could not be loaded using '" ~ (loader is null
                    ? "null" : "valueLoader") ~ "'", cause);
            key_ = key;
        }

        /// The key whose loader failed.
        Any getKey() nothrow @nogc
        {
            return key_;
        }
    }
}

/// The central SPI for resolving named cache regions.
interface CacheManager
{
    /// The named cache, or null when this manager cannot supply it.
    Cache getCache(string name);

    /// The names of the regions the manager knows about (R10).
    Collection!string getCacheNames();

    /// Reset the regions or clear their entries.
    void resetCaches();

    /// Retain the registered regions and clear each one's entries (R3).
    mixin template Defaults()
    {
        override void resetCaches()
        {
            foreach (name; getCacheNames())
            {
                auto cache = getCache(name);
                if (cache !is null)
                    cache.clear();
            }
        }
    }
}
