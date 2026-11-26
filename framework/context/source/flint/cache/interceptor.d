// Ported from spring-framework v7.1.0: spring-context/src/main/java/org/springframework/cache/interceptor/CacheOperation.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
// Also ported from BasicOperation.java, CacheableOperation.java, CacheEvictOperation.java and CachePutOperation.java.
module flint.cache.interceptor;

import flint.java.lang : JavaObject, stringHashCode;
import flint.java.util : Collections, LinkedHashSet, Set;
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
