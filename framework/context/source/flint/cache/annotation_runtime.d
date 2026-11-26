// Ported from spring-framework v7.1.0: spring-context/src/main/java/org/springframework/cache/annotation/AnnotationCacheOperationSource.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
// Also ported from CacheAnnotationParser.java and SpringCacheAnnotationParser.java.
module flint.cache.annotation_runtime;

import flint.cache.annotation.operations : CacheOperationKind, CacheOperationMetadata,
    hasCacheAnnotations, parseCacheOperations;
import flint.cache.interceptor : AbstractFallbackCacheOperationSource, CacheableOperation,
    CacheEvictOperation, CacheOperation, CachePutOperation;
import flint.engine.aot.descriptor : Descriptor, MemberDescriptorRef, MethodDescriptor;
import flint.java.lang : IllegalArgumentException, JavaObject, NullPointerException, stringHashCode;
import flint.java.util : ArrayList, Collection, LinkedHashSet, Set;

@safe:

/// Reads cache operation metadata from an annotation system.
interface CacheAnnotationParser
{
    /// Whether this type can carry annotations read by the parser.
    bool isCandidateClass(scope const Descriptor target);

    /// Read cache operation annotations on this type.
    Collection!CacheOperation parseCacheAnnotations(scope const Descriptor type);

    /// Read cache operation annotations on this method and apply the declaring type's defaults.
    Collection!CacheOperation parseCacheAnnotations(MemberDescriptorRef method);

    /// Default candidate check (R3).
    mixin template Defaults()
    {
        override bool isCandidateClass(scope const Descriptor)
        {
            return true;
        }
    }
}

/// Reads Flint cache operation annotations from the registered AOT descriptors.
class FlintCacheAnnotationParser : CacheAnnotationParser
{
    /// Whether the descriptor has operations at type or method level.
    override bool isCandidateClass(scope const Descriptor target) nothrow @nogc
    {
        if (target is null)
            return false;
        if (hasCacheAnnotations(target.annotations))
            return true;
        foreach (ref method; target.methods)
            if (hasCacheAnnotations(method.annotations))
                return true;
        return false;
    }

    /// Read the given type's cache operation annotations.
    override Collection!CacheOperation parseCacheAnnotations(scope const Descriptor type)
    {
        if (type is null)
            return null;
        auto parsed = parseCacheOperations(type.annotations, type);
        return parsed.declared ? operationCollection(type.name, parsed.values) : null;
    }

    /// Read the given method's cache operation annotations and class defaults.
    override Collection!CacheOperation parseCacheAnnotations(MemberDescriptorRef member)
    {
        auto method = member.method();
        if (method is null)
            return null;
        auto declaringType = member.declaringType();
        auto parsed = parseCacheOperations(method.annotations, declaringType);
        return parsed.declared ? operationCollection(operationName(method, declaringType), parsed.values) : null;
    }

    /// Built-in parsers have no configuration and compare equal (R11).
    bool equals(Object other) nothrow @nogc
    {
        return cast(FlintCacheAnnotationParser) other !is null;
    }

    /// The common hash for built-in parsers.
    int hashCode() nothrow @nogc
    {
        return stringHashCode("flint.cache.annotation_runtime.FlintCacheAnnotationParser");
    }

    mixin JavaObject;
}

/// Supplies cache operations from configured annotation parsers.
class AnnotationCacheOperationSource : AbstractFallbackCacheOperationSource
{
    private LinkedHashSet!CacheAnnotationParser parsers;

    /// Use Flint's cache annotations.
    this()
    {
        this(new FlintCacheAnnotationParser());
    }

    /// Use a single custom parser.
    this(CacheAnnotationParser parser)
    {
        if (parser is null)
            throw new IllegalArgumentException("CacheAnnotationParser must not be null");
        parsers = new LinkedHashSet!CacheAnnotationParser([parser]);
    }

    /// Use the given custom parsers in registration order.
    this(scope CacheAnnotationParser[] parsers...)
    {
        if (parsers.length == 0)
            throw new IllegalArgumentException("At least one CacheAnnotationParser needs to be specified");
        auto distinct = new LinkedHashSet!CacheAnnotationParser();
        foreach (parser; parsers)
        {
            if (parser is null)
                throw new NullPointerException();
            if (!distinct.add(parser))
                throw new IllegalArgumentException("Duplicate CacheAnnotationParser");
        }
        this.parsers = distinct;
    }

    /// Use a set of custom parsers in its iteration order.
    this(Set!CacheAnnotationParser parsers)
    {
        if (parsers is null || parsers.isEmpty())
            throw new IllegalArgumentException("At least one CacheAnnotationParser needs to be specified");
        this.parsers = new LinkedHashSet!CacheAnnotationParser(parsers);
    }

    /// Whether a parser recognizes this target as a candidate.
    override bool isCandidateClass(scope const Descriptor target)
    {
        foreach (parser; parsers)
            if (parser.isCandidateClass(target))
                return true;
        return false;
    }

    /// Find caching operations declared on the given type.
    protected override Collection!CacheOperation findCacheOperations(scope const Descriptor type)
    {
        return determineCacheOperations(parser => parser.parseCacheAnnotations(type));
    }

    /// Find caching operations declared on the given method.
    protected override Collection!CacheOperation findCacheOperations(MemberDescriptorRef method)
    {
        return determineCacheOperations(parser => parser.parseCacheAnnotations(method));
    }

    /// The callback used to ask a parser for operations (R9).
    protected static interface CacheOperationProvider
    {
        /// Ask the parser for operations on the current element.
        Collection!CacheOperation getCacheOperations(CacheAnnotationParser parser);
    }

    /// Combine the configured parsers' operations (R9).
    protected Collection!CacheOperation determineCacheOperations(CacheOperationProvider provider)
    {
        return determineCacheOperations(parser => provider.getCacheOperations(parser));
    }

    /// Scoped delegate form of the parser callback (R9).
    protected Collection!CacheOperation determineCacheOperations(
            scope Collection!CacheOperation delegate(CacheAnnotationParser) @safe provider)
    {
        Collection!CacheOperation result;
        ArrayList!CacheOperation combined;
        foreach (parser; parsers)
        {
            auto found = provider(parser);
            if (found is null)
                continue;
            if (result is null)
                result = found;
            else
            {
                if (combined is null)
                {
                    combined = new ArrayList!CacheOperation(result.size() + found.size());
                    combined.addAll(result);
                    result = combined;
                }
                combined.addAll(found);
            }
        }
        return result;
    }

    /// Compare the configured parser sets by value (R11).
    bool equals(Object other)
    {
        if (this is other)
            return true;
        auto that = cast(AnnotationCacheOperationSource) other;
        return that !is null && parsers.equals(that.parsers);
    }

    /// The parser set's order-independent hash.
    int hashCode()
    {
        return parsers.hashCode();
    }

    mixin JavaObject;
}

private Collection!CacheOperation operationCollection(string name, scope const(CacheOperationMetadata)[] values)
{
    auto result = new ArrayList!CacheOperation();
    foreach (ref metadata; values)
        result.add(buildOperation(name, metadata));
    return result;
}

private CacheOperation buildOperation(string name, ref const CacheOperationMetadata metadata)
{
    auto builder = operationBuilder(metadata);
    builder.setName(name);
    builder.setCacheNames(metadata.cacheNames);
    builder.setKey(annotationText(metadata.key));
    builder.setKeyGenerator(annotationText(metadata.keyGenerator));
    builder.setCacheManager(annotationText(metadata.cacheManager));
    builder.setCacheResolver(annotationText(metadata.cacheResolver));
    builder.setCondition(annotationText(metadata.condition));
    return builder.build();
}

private CacheOperation.Builder operationBuilder(ref const CacheOperationMetadata metadata)
{
    final switch (metadata.kind)
    {
    case CacheOperationKind.cacheable:
        auto cacheable = new CacheableOperation.Builder();
        cacheable.setUnless(annotationText(metadata.unless));
        cacheable.setSync(metadata.sync);
        return cacheable;
    case CacheOperationKind.evict:
        auto evict = new CacheEvictOperation.Builder();
        evict.setCacheWide(metadata.allEntries);
        evict.setBeforeInvocation(metadata.beforeInvocation);
        return evict;
    case CacheOperationKind.put:
        auto put = new CachePutOperation.Builder();
        put.setUnless(annotationText(metadata.unless));
        return put;
    }
}

private string annotationText(string value) nothrow @nogc
{
    return value is null ? "" : value;
}

private string operationName(scope const(MethodDescriptor)* method, scope const Descriptor target)
{
    char[] name;
    if (target !is null)
    {
        name ~= target.name;
        name ~= '.';
    }
    name ~= method.name;
    name ~= '(';
    foreach (index, ref parameter; method.parameters)
    {
        if (index != 0)
            name ~= ',';
        name ~= parameter.type;
    }
    name ~= ')';
    return name.idup;
}
