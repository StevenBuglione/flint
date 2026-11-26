// Ported from spring-framework v7.1.0: spring-context/src/main/java/org/springframework/cache/annotation/Cacheable.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
// Also ported from CacheConfig.java, CacheEvict.java, CachePut.java, and Caching.java.
module flint.cache.annotation;

import flint.core.annotation : AliasFor;

@safe:

/// Cache a method's result, returning a cached hit without invoking the method.
struct Cacheable
{
    /// Alias of cacheNames.
    @AliasFor("cacheNames")
    string[] value;
    /// The cache regions to consult.
    @AliasFor("value")
    string[] cacheNames;
    /// The SpEL expression that supplies the key.
    string key;
    /// The bean name of the key generator.
    string keyGenerator;
    /// The bean name of the cache manager.
    string cacheManager;
    /// The bean name of the cache resolver.
    string cacheResolver;
    /// The SpEL condition that enables caching for the call.
    string condition;
    /// The SpEL condition that vetoes storing the result.
    string unless;
    /// Coalesce concurrent loads of the same key.
    bool sync;

    /// The single-name annotation form.
    static Cacheable opCall(string value, string[] cacheNames = null, string key = null,
            string keyGenerator = null, string cacheManager = null, string cacheResolver = null,
            string condition = null, string unless = null, bool sync = false)
    {
        return opCall([value], cacheNames, key, keyGenerator, cacheManager, cacheResolver, condition, unless, sync);
    }

    /// The named-attribute or multi-region annotation form.
    static Cacheable opCall(string[] value = null, string[] cacheNames = null, string key = null,
            string keyGenerator = null, string cacheManager = null, string cacheResolver = null,
            string condition = null, string unless = null, bool sync = false)
    {
        Cacheable result = {
            value, cacheNames, key, keyGenerator, cacheManager, cacheResolver, condition, unless, sync
        };
        return result;
    }
}

/// Invoke the method and put its result in the cache.
struct CachePut
{
    /// Alias of cacheNames.
    @AliasFor("cacheNames")
    string[] value;
    /// The cache regions to update.
    @AliasFor("value")
    string[] cacheNames;
    /// The SpEL expression that supplies the key.
    string key;
    /// The bean name of the key generator.
    string keyGenerator;
    /// The bean name of the cache manager.
    string cacheManager;
    /// The bean name of the cache resolver.
    string cacheResolver;
    /// The SpEL condition that enables the put.
    string condition;
    /// The SpEL condition that vetoes storing the result.
    string unless;

    /// The single-name annotation form.
    static CachePut opCall(string value, string[] cacheNames = null, string key = null,
            string keyGenerator = null, string cacheManager = null, string cacheResolver = null,
            string condition = null, string unless = null)
    {
        return opCall([value], cacheNames, key, keyGenerator, cacheManager, cacheResolver, condition, unless);
    }

    /// The named-attribute or multi-region annotation form.
    static CachePut opCall(string[] value = null, string[] cacheNames = null, string key = null,
            string keyGenerator = null, string cacheManager = null, string cacheResolver = null,
            string condition = null, string unless = null)
    {
        CachePut result = {
            value, cacheNames, key, keyGenerator, cacheManager, cacheResolver, condition, unless
        };
        return result;
    }
}

/// Evict an entry or a whole region before or after a method call.
struct CacheEvict
{
    /// Alias of cacheNames.
    @AliasFor("cacheNames")
    string[] value;
    /// The cache regions from which to evict.
    @AliasFor("value")
    string[] cacheNames;
    /// The SpEL expression that supplies the key.
    string key;
    /// The bean name of the key generator.
    string keyGenerator;
    /// The bean name of the cache manager.
    string cacheManager;
    /// The bean name of the cache resolver.
    string cacheResolver;
    /// The SpEL condition that enables eviction.
    string condition;
    /// Evict all entries in each region.
    bool allEntries;
    /// Evict before calling the method.
    bool beforeInvocation;

    /// The single-name annotation form.
    static CacheEvict opCall(string value, string[] cacheNames = null, string key = null,
            string keyGenerator = null, string cacheManager = null, string cacheResolver = null,
            string condition = null, bool allEntries = false, bool beforeInvocation = false)
    {
        return opCall([value], cacheNames, key, keyGenerator, cacheManager, cacheResolver,
                condition, allEntries, beforeInvocation);
    }

    /// The named-attribute or multi-region annotation form.
    static CacheEvict opCall(string[] value = null, string[] cacheNames = null, string key = null,
            string keyGenerator = null, string cacheManager = null, string cacheResolver = null,
            string condition = null, bool allEntries = false, bool beforeInvocation = false)
    {
        CacheEvict result = {
            value, cacheNames, key, keyGenerator, cacheManager, cacheResolver, condition,
                allEntries, beforeInvocation
        };
        return result;
    }
}

/// Groups several cache operations on the same element.
struct Caching
{
    /// Cacheable operations.
    Cacheable[] cacheable;
    /// Put operations.
    CachePut[] put;
    /// Eviction operations.
    CacheEvict[] evict;
}

/// Shared defaults for all cache operations on a class.
struct CacheConfig
{
    /// Alias of cacheNames.
    @AliasFor("cacheNames")
    string[] value;
    /// The default cache regions.
    @AliasFor("value")
    string[] cacheNames;
    /// The default key generator's bean name.
    string keyGenerator;
    /// The default cache manager's bean name.
    string cacheManager;
    /// The default cache resolver's bean name.
    string cacheResolver;

    /// The single-name annotation form.
    static CacheConfig opCall(string value, string[] cacheNames = null, string keyGenerator = null,
            string cacheManager = null, string cacheResolver = null)
    {
        return opCall([value], cacheNames, keyGenerator, cacheManager, cacheResolver);
    }

    /// The named-attribute or multi-region annotation form.
    static CacheConfig opCall(string[] value = null, string[] cacheNames = null,
            string keyGenerator = null, string cacheManager = null, string cacheResolver = null)
    {
        CacheConfig result = {value, cacheNames, keyGenerator, cacheManager, cacheResolver};
        return result;
    }
}
