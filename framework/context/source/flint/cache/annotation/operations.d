// Ported from spring-framework v7.1.0: spring-context/src/main/java/org/springframework/cache/annotation/SpringCacheAnnotationParser.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.cache.annotation.operations;

import flint.cache.annotation : Cacheable, CacheConfig, CacheEvict, CachePut, Caching;
import flint.core.annotation.types : AnnotationConfigurationException;
import flint.engine.aot.descriptor : Descriptor, MergedAnnotation;
import flint.engine.aot.name : typeNameOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import flint.util : StringUtils;

@safe:

package(flint.cache):

/// The three cache operations recognized by the advisor.
enum CacheOperationKind
{
    cacheable,
    evict,
    put,
}

/// The normalized attributes consumed when building a method's cache advice.
struct CacheOperationMetadata
{
    /// The operation selected by the annotation.
    CacheOperationKind kind;
    /// Cache names in declaration order with duplicates removed.
    string[] cacheNames;
    /// The SpEL key source.
    string key;
    /// The configured key generator bean name.
    string keyGenerator;
    /// The configured cache manager bean name.
    string cacheManager;
    /// The configured cache resolver bean name.
    string cacheResolver;
    /// The SpEL condition source.
    string condition;
    /// The SpEL veto evaluated against the result.
    string unless;
    /// Whether same-key cache misses share a synchronous load.
    bool sync;
    /// Whether to evict every entry in each resolved cache.
    bool allEntries;
    /// Whether to evict before invoking the target.
    bool beforeInvocation;
}

private immutable string[4] operationAnnotations = [
    typeNameOf!Cacheable, typeNameOf!CacheEvict, typeNameOf!CachePut, typeNameOf!Caching
];

/// The source distinguishes an explicit empty group from no cache declarations.
struct ParsedCacheOperations
{
    /// Whether the source found a cache annotation.
    bool declared;
    /// Resolved operations in Spring's order.
    CacheOperationMetadata[] values;
}

/// Read the first matching aggregate of AOT metadata during advisor configuration.
ParsedCacheOperations parseCacheOperations(scope const(MergedAnnotation)[] annotations, scope const Descriptor target)
{
    const aggregate = firstOperationAggregate(annotations);
    if (aggregate == uint.max)
        return ParsedCacheOperations.init;

    auto defaults = cacheConfig(target);
    CacheOperationMetadata[] result;
    foreach (type; operationAnnotations)
        foreach (ref annotation; annotations)
            if (annotation.aggregateIndex == aggregate && annotation.type == type)
                appendOperations(result, annotation, defaults);
    return ParsedCacheOperations(true, result);
}

/// Whether an annotation table has a cache operation or group.
bool hasCacheAnnotations(scope const(MergedAnnotation)[] annotations) nothrow @nogc
{
    return firstOperationAggregate(annotations) != uint.max;
}

private uint firstOperationAggregate(scope const(MergedAnnotation)[] annotations) nothrow @nogc
{
    uint nearest = uint.max;
    foreach (ref annotation; annotations)
        foreach (type; operationAnnotations)
            if (annotation.type == type && annotation.aggregateIndex < nearest)
                nearest = annotation.aggregateIndex;
    return nearest;
}

private const(CacheConfig) cacheConfig(scope const Descriptor target)
{
    if (target !is null)
        foreach (ref annotation; target.annotations)
            if (annotation.type == typeNameOf!CacheConfig)
            {
                requireMerged(annotation);
                const value = annotation.value;
                return value.get!CacheConfig();
            }
    return CacheConfig.init;
}

private void requireMerged(const MergedAnnotation annotation)
{
    if (annotation.error.length)
        throw new AnnotationConfigurationException(annotation.error);
}

private void appendOperations(ref CacheOperationMetadata[] operations, const MergedAnnotation entry,
        const CacheConfig defaults)
{
    requireMerged(entry);
    switch (entry.type)
    {
    case typeNameOf!Cacheable:
        operations ~= parseOperation(entry.value.get!Cacheable(), defaults);
        break;
    case typeNameOf!CacheEvict:
        operations ~= parseOperation(entry.value.get!CacheEvict(), defaults);
        break;
    case typeNameOf!CachePut:
        operations ~= parseOperation(entry.value.get!CachePut(), defaults);
        break;
    case typeNameOf!Caching:
        const group = entry.value.get!Caching();
        foreach (ref annotation; group.cacheable)
            operations ~= parseOperation(annotation, defaults);
        foreach (ref annotation; group.evict)
            operations ~= parseOperation(annotation, defaults);
        foreach (ref annotation; group.put)
            operations ~= parseOperation(annotation, defaults);
        break;
    default:
        break;
    }
}

private CacheOperationMetadata parseOperation(T)(const T annotation, const CacheConfig defaults)
{
    CacheOperationMetadata result;
    static if (is(T == Cacheable))
    {
        result.kind = CacheOperationKind.cacheable;
        result.sync = annotation.sync;
        result.unless = annotation.unless;
    }
    else static if (is(T == CacheEvict))
    {
        result.kind = CacheOperationKind.evict;
        result.allEntries = annotation.allEntries;
        result.beforeInvocation = annotation.beforeInvocation;
    }
    else static if (is(T == CachePut))
    {
        result.kind = CacheOperationKind.put;
        result.unless = annotation.unless;
    }

    const(string)[] names = annotation.cacheNames.length ? annotation.cacheNames : annotation.value;
    if (names.length == 0)
        names = defaults.cacheNames.length ? defaults.cacheNames : defaults.value;
    foreach (name; names)
    {
        if (!StringUtils.hasText(name))
            throw new IllegalArgumentException("Cache name must be non-empty if specified");
        if (!containsName(result.cacheNames, name))
            result.cacheNames ~= name;
    }

    result.key = annotation.key;
    result.keyGenerator = annotation.keyGenerator;
    result.cacheManager = annotation.cacheManager;
    result.cacheResolver = annotation.cacheResolver;
    result.condition = annotation.condition;
    applyQualifierDefaults(result, defaults);
    return result;
}

private void applyQualifierDefaults(ref CacheOperationMetadata operation, const CacheConfig defaults)
{
    const hasKey = StringUtils.hasText(operation.key);
    const hasGenerator = StringUtils.hasText(operation.keyGenerator);
    if (hasKey && hasGenerator)
        throw new IllegalStateException("Cache annotation 'key' and 'keyGenerator' are mutually exclusive");
    if (!hasKey && !hasGenerator && StringUtils.hasText(defaults.keyGenerator))
        operation.keyGenerator = defaults.keyGenerator;

    const hasManager = StringUtils.hasText(operation.cacheManager);
    const hasResolver = StringUtils.hasText(operation.cacheResolver);
    if (hasManager && hasResolver)
        throw new IllegalStateException("Cache annotation 'cacheManager' and 'cacheResolver' are mutually exclusive");
    if (!hasManager && !hasResolver)
    {
        if (StringUtils.hasText(defaults.cacheResolver))
            operation.cacheResolver = defaults.cacheResolver;
        else if (StringUtils.hasText(defaults.cacheManager))
            operation.cacheManager = defaults.cacheManager;
    }
}

private bool containsName(scope const(string)[] names, string name) nothrow @nogc
{
    foreach (existing; names)
        if (existing == name)
            return true;
    return false;
}
