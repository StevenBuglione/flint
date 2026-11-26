module flint.cache.cache_operation_builder_tests;

import core.memory : GC;
import flint.cache.interceptor : BasicOperation, CacheableOperation, CacheEvictOperation,
    CacheOperation, CachePutOperation;
import flint.java.lang : IllegalArgumentException, stringHashCode;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

@("cacheable builders preserve ordered names and operation identity")
unittest
{
    auto builder = new CacheableOperation.Builder();
    builder.setName("find");
    builder.setCacheNames("books", "authors", "books");
    builder.setKey("#p0");
    builder.setKeyGenerator("");
    builder.setCacheManager("regions");
    builder.setCacheResolver("");
    builder.setCondition("#enabled");
    builder.setUnless("");
    builder.setSync(true);

    auto operation = builder.build();
    BasicOperation basic = operation;
    assert(basic.getCacheNames().toArray() == ["books", "authors"]);
    assert(operation.getName() == "find" && operation.getKey() == "#p0");
    assert(operation.getCacheManager() == "regions" && operation.getCondition() == "#enabled");
    assert(!operation.getUnless().isNull && operation.getUnless().get() == "" && operation.isSync());

    enum description = "Builder[find] caches=[books, authors] | key='#p0' | keyGenerator=''"
        ~ " | cacheManager='regions' | cacheResolver='' | condition='#enabled' | unless='' | sync='true'";
    assert(operation.toString() == description && operation.hashCode() == stringHashCode(description));
    assert(operation.equals(builder.build()) && operation == builder.build());

    builder.setCacheName("changed");
    assert(!operation.equals(builder.build()));
    assert(operation.getCacheNames().toArray() == ["books", "authors"]);
}

@("eviction and put preserve their specific flags and nullable state")
unittest
{
    auto eviction = new CacheEvictOperation.Builder();
    eviction.setCacheWide(true);
    eviction.setBeforeInvocation(true);
    auto evict = eviction.build();
    assert(evict.isCacheWide() && evict.isBeforeInvocation());
    assert(evict.toString()[$ - 10 .. $] == ",true,true");

    auto writer = new CachePutOperation.Builder();
    auto absent = writer.build();
    assert(absent.getUnless().isNull);
    writer.setUnless(Nullable!string(""));
    auto empty = writer.build();
    assert(!empty.getUnless().isNull && empty.getUnless().get() == "");
    assert(!absent.equals(empty));
    writer.setUnless(null);
    assert(writer.build().equals(absent));
}

@("base builder validates names and explicit null selectors")
unittest
{
    CacheOperation.Builder builder = new CacheableOperation.Builder();
    assertThrown!IllegalArgumentException(builder.setName(" "));
    assertThrown!IllegalArgumentException(builder.setCacheName("\u2003"));
    assertThrown!IllegalArgumentException(builder.setCacheNames("valid", ""));
    assertThrown!IllegalArgumentException(builder.setKey(null));
    assertThrown!IllegalArgumentException(builder.setKeyGenerator(null));
    assertThrown!IllegalArgumentException(builder.setCacheManager(null));
    assertThrown!IllegalArgumentException(builder.setCacheResolver(null));
    assertThrown!IllegalArgumentException(builder.setCondition(null));
}

private final class NamedBuilder : CachePutOperation.Builder
{
}

@("a derived builder's name participates in operation identity")
unittest
{
    auto plain = new CachePutOperation.Builder();
    plain.setName("write");
    auto named = new NamedBuilder();
    named.setName("write");
    auto operation = named.build();
    enum description = "NamedBuilder[write] caches=[] | key='' | keyGenerator='' | cacheManager=''"
        ~ " | cacheResolver='' | condition='' | unless='null'";
    assert(operation.toString() == description);
    assert(operation.hashCode() == stringHashCode(description));
    assert(!operation.equals(plain.build()));
}

@("reading constructed cache metadata allocates no GC memory")
unittest
{
    auto builder = new CacheableOperation.Builder();
    builder.setName("find");
    builder.setCacheName("books");
    builder.setUnless("#result == null");
    builder.setSync(true);
    auto operation = builder.build();
    auto identical = builder.build();
    const hash = operation.hashCode();
    assert(operation.equals(identical) && operation.getCacheNames().contains("books"));

    const before = GC.stats().allocatedInCurrentThread;
    foreach (i; 0 .. 1_000)
    {
        assert(operation.equals(identical));
        assert(operation.hashCode() == hash && operation.toString().length);
        assert(operation.getName() == "find" && operation.getCacheNames().contains("books"));
        assert(operation.getUnless().get() == "#result == null" && operation.isSync());
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}
