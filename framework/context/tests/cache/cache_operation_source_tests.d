// Ported from spring-framework v7.1.0: spring-context/src/test/java/org/springframework/cache/annotation/AnnotationCacheOperationSourceTests.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.cache.cache_operation_source_tests;

import core.memory : GC;
import core.sync.barrier : Barrier;
import core.thread : Thread;
import flint.cache.annotation : Cacheable, CacheConfig, CacheEvict, Caching;
import flint.cache.annotation_runtime : AnnotationCacheOperationSource, CacheAnnotationParser,
    FlintCacheAnnotationParser;
import flint.cache.interceptor : CacheableOperation, CacheEvictOperation, CacheOperation, CacheOperationSource;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MemberDescriptorRef, MemberKind, MergedAnnotation,
    MethodDescriptor, ParameterDescriptor, TypeKind, descriptorOf;
import flint.engine.aot.name : typeNameOf;
import flint.engine.aot.objects : objectEquals, objectToHash;
import flint.java.lang : IllegalStateException, JavaObject;
import flint.java.util : ArrayList, Collection;
import std.exception : assertThrown;

@safe:

@CacheConfig(["catalog"], null, "sharedKeys")
private class Catalog
{
}

@CacheConfig("interfaceCatalog", null, null, null, "interfaceResolver")
private interface CatalogDefaults
{
}

@CacheConfig("baseCatalog", null, null, "baseManager")
private class BaseCatalog
{
}

private class InheritedCatalog : BaseCatalog, CatalogDefaults
{
}

private MergedAnnotation annotation(T)(T value)
{
    return MergedAnnotation(typeNameOf!T, Any.of(value));
}

private MemberDescriptorRef member(const Descriptor owner, uint index = 0) nothrow @nogc
{
    return MemberDescriptorRef(owner, index, MemberKind.method);
}

private CacheOperation[] operationsFor(MergedAnnotation[] annotations)
{
    auto target = new Descriptor("AnnotatedClass", TypeKind.class_);
    target.methods = [findMethod("int", annotations)];
    auto source = new AnnotationCacheOperationSource();
    return source.getCacheOperations(member(target), target).toArray();
}

@("singularAnnotation")
unittest
{
    auto operations = operationsFor([annotation(Cacheable("test"))]);
    assert(operations.length == 1 && cast(CacheableOperation) operations[0]!is null);
    assert(operations[0].getCacheNames().toArray() == ["test"]);
}

@("multipleAnnotation")
unittest
{
    auto operations = operationsFor([annotation(CacheEvict("test")), annotation(Cacheable("test"))]);
    assert(operations.length == 2);
    assert(cast(CacheableOperation) operations[0]!is null && cast(CacheEvictOperation) operations[1]!is null);
    foreach (operation; operations)
        assert(operation.getCacheNames().toArray() == ["test"]);
}

@("validateNoCacheIsValid")
unittest
{
    auto operations = operationsFor([annotation(Cacheable())]);
    assert(operations.length == 1 && operations[0].getCacheNames().isEmpty());
}

@("keyAndKeyGeneratorCannotBeSetTogether")
unittest
{
    assertThrown!IllegalStateException(operationsFor([
        annotation(Cacheable("test", key: "#root.methodName", keyGenerator: "custom"))
    ]));
}

@("cacheResolverAndCacheManagerCannotBeSetTogether")
unittest
{
    assertThrown!IllegalStateException(operationsFor([
        annotation(Cacheable("test", cacheManager: "manager", cacheResolver: "resolver"))
    ]));
}

@("caching")
unittest
{
    CacheOperationSource source = new AnnotationCacheOperationSource();
    auto configured = descriptorOf!Catalog;
    auto catalog = new Descriptor(configured.name, configured.kind);
    catalog.annotations = configured.annotations;
    auto method = new MethodDescriptor;
    method.name = "find";
    method.parameters = [ParameterDescriptor("id", "int")];
    method.annotations = [
        annotation(Caching([Cacheable()], [], [CacheEvict("oldCatalog", allEntries: true)]))
    ];
    catalog.methods = [*method];

    assert(source.isCandidateClass(catalog));
    assert(source.hasCacheOperations(member(catalog), catalog));

    auto operations = source.getCacheOperations(member(catalog), catalog).toArray();
    assert(operations.length == 2);
    auto read = cast(CacheableOperation) operations[0];
    auto evict = cast(CacheEvictOperation) operations[1];
    assert(read !is null && evict !is null);
    assert(read.getName() == catalog.name ~ ".find(int)");
    assert(read.getCacheNames().contains("catalog") && read.getKeyGenerator() == "sharedKeys");
    assert(!read.getUnless().isNull && read.getUnless().get() == "");
    assert(evict.isCacheWide() && evict.getCacheNames().contains("oldCatalog"));
}

@("emptyCaching")
unittest
{
    auto annotationSource = new AnnotationCacheOperationSource();
    CacheOperationSource source = annotationSource;
    auto catalog = descriptorOf!Catalog;
    assert(!annotationSource.isCandidateClass(catalog), "a CacheConfig alone does not declare a cache operation");
    assert(!source.isCandidateClass(catalog), "interface dispatch uses the annotation source candidate check");
    catalog.methods = [findMethod("int"), findMethod("long", [annotation(Caching.init)])];
    assert(source.getCacheOperations(member(catalog), catalog) is null);
    assert(source.getCacheOperations(MemberDescriptorRef.init, catalog) is null);
    assert(source.getCacheOperations(member(catalog, 7), catalog) is null);
    assert(!source.hasCacheOperations(member(catalog), catalog));

    auto empty = member(catalog, 1);
    auto operations = source.getCacheOperations(empty, catalog);
    assert(operations !is null && operations.isEmpty());
    assert(!source.hasCacheOperations(empty, catalog));
}

private MethodDescriptor findMethod(string parameterType, MergedAnnotation[] annotations = null)
{
    MethodDescriptor method;
    method.name = "find";
    method.parameters = [ParameterDescriptor("id", parameterType)];
    method.annotations = annotations;
    return method;
}

@("the concrete method and class take precedence over the original interface method")
unittest
{
    CacheOperationSource source = new AnnotationCacheOperationSource();
    auto declared = new Descriptor("Declared", TypeKind.interface_);
    declared.methods = [findMethod("int", [annotation(Cacheable.init)]), findMethod("long")];
    declared.annotations = [
        annotation(Cacheable("declaredType")), annotation(CacheConfig("interface"))
    ];
    auto original = member(declared);
    auto concrete = new Descriptor("Concrete", TypeKind.class_);
    concrete.methods = [
        findMethod("long", [annotation(Cacheable("wrongOverload"))]),
        findMethod("int", [annotation(Cacheable("concrete"))]),
    ];
    concrete.annotations = [annotation(Cacheable("type"))];
    auto operations = source.getCacheOperations(original, concrete).toArray();
    assert(operations.length == 1 && operations[0].getCacheNames().contains("concrete"));

    auto classFallback = new Descriptor("ClassFallback", TypeKind.class_);
    classFallback.methods = [findMethod("int")];
    classFallback.annotations = [annotation(Cacheable("type"))];
    operations = source.getCacheOperations(original, classFallback).toArray();
    assert(operations.length == 1 && operations[0].getCacheNames().contains("type"));

    auto methodFallback = new Descriptor("MethodFallback", TypeKind.class_);
    methodFallback.methods = [findMethod("int")];
    operations = source.getCacheOperations(original, methodFallback).toArray();
    assert(operations.length == 1 && operations[0].getCacheNames().contains("interface"));

    auto declaringTypeFallback = new Descriptor("DeclaringTypeFallback", TypeKind.class_);
    declaringTypeFallback.methods = [findMethod("long")];
    operations = source.getCacheOperations(member(declared, 1), declaringTypeFallback).toArray();
    assert(operations.length == 1 && operations[0].getCacheNames().contains("declaredType"));
}

@("the operation source reuses precomputed metadata for the same method and target")
unittest
{
    CacheOperationSource source = new AnnotationCacheOperationSource();
    auto first = descriptorOf!Catalog;
    auto second = new Descriptor("OtherCatalog", first.kind);
    second.annotations = [annotation(CacheConfig("otherCatalog"))];
    first.methods = [findMethod("int", [annotation(Cacheable.init)]), findMethod("long")];
    second.methods = [findMethod("int", [annotation(Cacheable.init)])];
    auto method = member(first);

    auto firstOperations = source.getCacheOperations(method, first);
    auto secondOperations = source.getCacheOperations(method, second);
    assert(firstOperations is source.getCacheOperations(method, first));
    assert(secondOperations is source.getCacheOperations(method, second));
    assert(firstOperations.toArray()[0].getCacheNames().contains("catalog"));
    assert(secondOperations.toArray()[0].getCacheNames().contains("otherCatalog"));

    auto miss = member(first, 1);
    assert(source.getCacheOperations(miss, first) is null);
    const before = GC.stats().allocatedInCurrentThread;
    foreach (i; 0 .. 1_000)
    {
        assert(source.getCacheOperations(method, first) is firstOperations);
        assert(source.hasCacheOperations(method, second));
        assert(source.getCacheOperations(miss, first) is null);
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("cacheConfigFromInterface")
unittest
{
    auto catalog = descriptorOf!InheritedCatalog;
    catalog.methods = [findMethod("int", [annotation(Cacheable.init)])];
    auto source = new AnnotationCacheOperationSource();
    auto operations = source.getCacheOperations(member(catalog), catalog).toArray();
    assert(operations.length == 1 && operations[0].getCacheNames().contains("interfaceCatalog"));
    assert(operations[0].getCacheResolver() == "interfaceResolver");
    assert(operations[0].getCacheManager().length == 0);
}

@("concurrent first metadata reads converge on the published operation collection")
@system unittest
{
    enum readers = 8;
    CacheOperationSource source = new AnnotationCacheOperationSource();
    auto target = descriptorOf!Catalog;
    target.methods = [findMethod("int", [annotation(Cacheable.init)])];
    auto method = member(target);
    auto start = new Barrier(readers);
    auto results = new Collection!CacheOperation[readers];
    Thread[readers] threads;
    Thread reader(size_t index)
    {
        return new Thread({ start.wait(); results[index] = source.getCacheOperations(method, target); });
    }

    foreach (index, ref thread; threads)
        thread = reader(index);
    foreach (thread; threads)
        thread.start();
    foreach (thread; threads)
        thread.join();
    assert(results[0]!is null);
    foreach (result; results)
        assert(result is results[0]);
}

private final class NamedParser : CacheAnnotationParser
{
    private string cacheName;
    uint calls;

    this(string cacheName)
    {
        this.cacheName = cacheName;
    }

    override bool isCandidateClass(scope const Descriptor target)
    {
        return target !is null && target.name == "Rules";
    }

    override Collection!CacheOperation parseCacheAnnotations(scope const Descriptor)
    {
        return null;
    }

    override Collection!CacheOperation parseCacheAnnotations(MemberDescriptorRef method)
    {
        ++calls;
        assert(method.name() == "find");
        assert(method.declaringType().name == "Rules");
        auto builder = new CacheableOperation.Builder();
        builder.setName(method.name());
        builder.setCacheName(cacheName);
        auto operations = new ArrayList!CacheOperation();
        operations.add(builder.build());
        return operations;
    }
}

@("custom parsers contribute ordered operations and run only on cold lookup")
unittest
{
    auto first = new NamedParser("first");
    auto second = new NamedParser("second");
    CacheOperationSource source = new AnnotationCacheOperationSource(first, second);
    auto target = new Descriptor("Rules", TypeKind.class_);
    target.methods = [findMethod("int")];
    auto method = member(target);
    assert(source.isCandidateClass(target));
    auto operations = source.getCacheOperations(method, target);
    auto values = operations.toArray();
    assert(values.length == 2);
    assert(values[0].getCacheNames().contains("first") && values[1].getCacheNames().contains("second"));
    assert(source.getCacheOperations(method, target) is operations);
    assert(first.calls == 1 && second.calls == 1);
}

@("built-in parsers and default operation sources compare by their configuration")
unittest
{
    auto first = new FlintCacheAnnotationParser();
    auto second = new FlintCacheAnnotationParser();
    assert(objectEquals(first, second));
    assert(objectToHash(first) == objectToHash(second));

    auto defaultSource = new AnnotationCacheOperationSource();
    auto same = new AnnotationCacheOperationSource(second);
    auto different = new AnnotationCacheOperationSource(new NamedParser("custom"));
    assert(objectEquals(defaultSource, same));
    assert(objectToHash(defaultSource) == objectToHash(same));
    assert(!objectEquals(defaultSource, different));
}

@("custom parser sets compare independently of registration order")
unittest
{
    import flint.java.lang : IllegalArgumentException;
    import std.exception : assertThrown;

    auto first = new NamedParser("first");
    auto second = new NamedParser("second");
    auto ordered = new AnnotationCacheOperationSource(first, second);
    auto reversed = new AnnotationCacheOperationSource(second, first);
    auto other = new AnnotationCacheOperationSource(first, new NamedParser("second"));
    assert(objectEquals(ordered, reversed));
    assert(objectToHash(ordered) == objectToHash(reversed));
    assert(!objectEquals(ordered, other));
    assertThrown!IllegalArgumentException(new AnnotationCacheOperationSource(new FlintCacheAnnotationParser(),
            new FlintCacheAnnotationParser()));
}

private final class CollidingCacheKey
{
    private string name;

    this(string name)
    {
        this.name = name;
    }

    bool equals(Object other) nothrow @nogc
    {
        auto that = cast(CollidingCacheKey) other;
        return that !is null && name == that.name;
    }

    int hashCode() nothrow @nogc
    {
        return 1;
    }

    mixin JavaObject;
}

private final class GroupedCacheOperationSource : AnnotationCacheOperationSource
{
    protected override Any getCacheKey(MemberDescriptorRef method, const Descriptor)
    {
        return Any.of(new CollidingCacheKey(method.name()));
    }
}

@("custom operation cache keys use value equality and resolve hash collisions")
unittest
{
    CacheOperationSource source = new GroupedCacheOperationSource();
    auto first = new Descriptor("First", TypeKind.class_);
    first.methods = [findMethod("int", [annotation(Cacheable("first"))])];
    auto second = new Descriptor("Second", TypeKind.class_);
    second.methods = [findMethod("int", [annotation(Cacheable("second"))])];
    auto other = new Descriptor("Other", TypeKind.class_);
    other.methods = [MethodDescriptor("other", "int", null, [annotation(Cacheable("other"))])];

    auto firstOperations = source.getCacheOperations(member(first), first);
    auto otherOperations = source.getCacheOperations(member(other), other);
    assert(firstOperations.toArray()[0].getCacheNames().contains("first"));
    assert(otherOperations.toArray()[0].getCacheNames().contains("other"));
    assert(source.getCacheOperations(member(second), second) is firstOperations);
    assert(source.getCacheOperations(member(other), other) is otherOperations);
}
