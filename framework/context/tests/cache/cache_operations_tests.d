module flint.cache.cache_operations_tests;

import flint.cache.annotation : Cacheable, CacheConfig, CacheEvict, CachePut, Caching;
import flint.cache.annotation.operations : CacheOperationKind, parseCacheOperations;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MergedAnnotation, MethodDescriptor, TypeKind, descriptorOf;
import flint.engine.aot.name : typeNameOf;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import std.exception : assertThrown;

@safe:

private MergedAnnotation merged(T)(T value, ubyte aggregate = 0)
{
    return MergedAnnotation(typeNameOf!T, Any.of(value), 0, aggregate);
}

@CacheConfig(["catalog", "catalog", "edition"], null, "classKey", "classManager", "classResolver")
private class Catalog
{
}

@("operation settings override class defaults in Spring's precedence")
unittest
{
    auto descriptor = descriptorOf!Catalog;
    MethodDescriptor method;
    method.annotations = [merged(Cacheable(key: "#p0", unless: "#result == null"))];

    auto operations = parseCacheOperations(method.annotations, descriptor).values;
    assert(operations.length == 1);
    assert(operations[0].cacheNames == ["catalog", "edition"]);
    assert(operations[0].key == "#p0" && operations[0].keyGenerator.length == 0);
    assert(operations[0].cacheResolver == "classResolver" && operations[0].cacheManager.length == 0);
    assert(operations[0].unless == "#result == null");

    method.annotations = [merged(Cacheable("secondary", cacheManager: "localManager"))];
    operations = parseCacheOperations(method.annotations, descriptor).values;
    assert(operations[0].cacheNames == ["secondary"] && operations[0].keyGenerator == "classKey");
    assert(operations[0].cacheManager == "localManager" && operations[0].cacheResolver.length == 0);
}

@("descriptor operations use local metadata before inherited metadata")
unittest
{
    MethodDescriptor method;
    method.annotations = [merged(Cacheable("result")), merged(CacheEvict("obsolete"), 1),];
    auto operations = parseCacheOperations(method.annotations, null).values;
    assert(operations.length == 1 && operations[0].cacheNames == ["result"]);

    method.annotations = [merged(CacheEvict("obsolete"), 1)];
    operations = parseCacheOperations(method.annotations, null).values;
    assert(operations.length == 1 && operations[0].kind == CacheOperationKind.evict);
    assert(operations[0].cacheNames == ["obsolete"]);

    method.annotations = [merged(Caching.init)];
    assert(parseCacheOperations(method.annotations, null).values.length == 0);
}

@("class-level operations provide a fallback and CacheConfig may be inherited")
unittest
{
    auto catalog = new Descriptor("Catalog", TypeKind.class_);
    catalog.annotations = [
        merged(Cacheable(sync: true), 1),
        merged(CacheConfig("inherited", keyGenerator: "inheritedKey"), 2),
    ];
    auto operations = parseCacheOperations(catalog.annotations, catalog).values;
    assert(operations.length == 1 && operations[0].sync);
    assert(operations[0].cacheNames == ["inherited"] && operations[0].keyGenerator == "inheritedKey");
}

@("group operations keep Spring's cacheable, evict and put order")
unittest
{
    MethodDescriptor method;
    method.annotations = [
        merged(CachePut("directPut")), merged(Cacheable("directRead")),
        merged(Caching([Cacheable("one"), Cacheable("two", condition: "#p0")],
                [CachePut("groupPut")], [
                    CacheEvict("groupEvict", allEntries: true, beforeInvocation: true)
        ])), merged(CacheEvict("directEvict")),
    ];

    auto operations = parseCacheOperations(method.annotations, null).values;
    assert(operations.length == 7);
    assert(operations[0].cacheNames == ["directRead"] && operations[1].cacheNames == ["directEvict"]);
    assert(operations[2].cacheNames == ["directPut"] && operations[3].cacheNames == ["one"]);
    assert(operations[4].cacheNames == ["two"] && operations[4].condition == "#p0");
    assert(operations[5].kind == CacheOperationKind.evict);
    assert(operations[5].allEntries && operations[5].beforeInvocation);
    assert(operations[6].cacheNames == ["groupPut"] && operations[6].kind == CacheOperationKind.put);
}

@("conflicting cache selectors and blank cache names are rejected")
unittest
{
    MethodDescriptor method;
    method.annotations = [merged(Cacheable(key: "#p0", keyGenerator: "otherKey"))];
    assertThrown!IllegalStateException(parseCacheOperations(method.annotations, null));

    method.annotations = [merged(CachePut(cacheManager: "manager", cacheResolver: "resolver"))];
    assertThrown!IllegalStateException(parseCacheOperations(method.annotations, null));

    method.annotations = [merged(CacheEvict(["valid", "\u2003"]))];
    assertThrown!IllegalArgumentException(parseCacheOperations(method.annotations, null));
}

@("blank CacheConfig qualifiers leave operation values alone")
unittest
{
    auto catalog = new Descriptor("Catalog", TypeKind.class_);
    catalog.annotations = [merged(CacheConfig(keyGenerator: " ", cacheManager: " "))];
    MethodDescriptor method;
    method.annotations = [merged(Cacheable("catalog", keyGenerator: "\t", cacheManager: "\n"))];
    auto operations = parseCacheOperations(method.annotations, catalog).values;
    assert(operations[0].keyGenerator == "\t");
    assert(operations[0].cacheManager == "\n");
}
