// Ported from spring-framework v7.1.0: spring-context/src/test/java/org/springframework/cache/concurrent/ConcurrentMapCacheManagerTests.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.cache.concurrent_map_cache_manager_tests;

import flint.cache.concurrent : ConcurrentMapCache, ConcurrentMapCacheManager;
import flint.engine.aot.any : Any;
import flint.java.lang : NullPointerException, UnsupportedOperationException;
import flint.java.util : List;
import std.exception : assertThrown;

@safe:

@("dynamicMode")
unittest
{
    auto manager = new ConcurrentMapCacheManager();
    auto first = manager.getCache("c1");
    const second = manager.getCache("c2");
    const third = manager.getCache("c3");
    assert(cast(ConcurrentMapCache) first !is null);
    assert(cast(const(ConcurrentMapCache)) second !is null);
    assert(cast(const(ConcurrentMapCache)) third !is null);
    assert(manager.getCache("c1") is first);
    assert(manager.getCache("c2") is second);
    assert(manager.getCache("c3") is third);

    auto key = Any.of("key");
    auto numeric = Any.of("numeric");
    auto nullable = Any.of("nullable");
    first.put(key, Any.of("value"));
    assert(first.get!string(key) == "value");
    first.put(numeric, Any.of(2));
    assert(first.get!int(numeric) == 2);
    first.put(nullable, Any.init);
    assert(first.get(nullable).get().isNull());
    first.put(nullable, Any.init);
    assert(first.get(nullable).get().isNull());
    first.evict(nullable);
    assert(first.get(nullable) is null);

    assert(first.putIfAbsent(key, Any.of("different")).get().get!string() == "value");
    assert(first.get!string(key) == "value");
    assert(first.putIfAbsent(numeric, Any.of(2.1)).get().get!int() == 2);
    assert(first.putIfAbsent(nullable, Any.init) is null);
    assert(first.get(nullable).get().isNull());
    assert(first.putIfAbsent(nullable, Any.init).get().isNull());
    assert(first.get(nullable).get().isNull());
    first.evict(nullable);
    assert(first.get(nullable) is null);

    manager.removeCache("c1");
    assert(manager.getCache("c1") !is first);
    assert(manager.getCache("c2") is second);
    manager.resetCaches();
    assert(manager.getCacheNames().isEmpty());
    assert(manager.getCache("c1") !is first);
    assert(manager.getCache("c2") !is second);
}

@("staticMode")
unittest
{
    auto manager = new ConcurrentMapCacheManager("c1", "c2");
    auto first = manager.getCache("c1");
    const second = manager.getCache("c2");
    assert(cast(ConcurrentMapCache) first !is null && cast(const(ConcurrentMapCache)) second !is null);
    assert(manager.getCache("c1") is first && manager.getCache("c2") is second);
    assert(manager.getCache("c3") is null);
    auto key = Any.of("key");
    auto numeric = Any.of("numeric");
    auto nullable = Any.of("nullable");
    first.put(key, Any.of("value"));
    assert(first.get!string(key) == "value");
    first.put(numeric, Any.of(2));
    assert(first.get!int(numeric) == 2);
    first.put(nullable, Any.init);
    assert(first.get(nullable).get().isNull());
    first.evict(nullable);
    assert(first.get(nullable) is null);

    manager.setAllowNullValues(false);
    auto firstWithoutNulls = cast(ConcurrentMapCache) manager.getCache("c1");
    assert(firstWithoutNulls !is null && !firstWithoutNulls.isAllowNullValues());
    assert(firstWithoutNulls !is first && firstWithoutNulls.get(key) is null);
    const secondWithoutNulls = manager.getCache("c2");
    assert(cast(const(ConcurrentMapCache)) secondWithoutNulls !is null && secondWithoutNulls !is second);
    assert(manager.getCache("c3") is null);
    firstWithoutNulls.put(key, Any.of("value"));
    assert(firstWithoutNulls.get!string(key) == "value");
    firstWithoutNulls.put(numeric, Any.of(2));
    assert(firstWithoutNulls.get!int(numeric) == 2);

    manager.setAllowNullValues(true);
    auto firstWithNulls = manager.getCache("c1");
    auto secondWithNulls = manager.getCache("c2");
    firstWithNulls.put(nullable, Any.init);
    assert(firstWithNulls.get(nullable).get().isNull());
    firstWithNulls.evict(nullable);
    assert(firstWithNulls.get(nullable) is null);
    secondWithNulls.put(key, Any.of("retained"));
    manager.removeCache("c1");
    assert(manager.getCache("c1") is null);
    assert(manager.getCache("c2") is secondWithNulls);
    assert(secondWithNulls.get!string(key) == "retained");
    manager.resetCaches();
    assert(manager.getCache("c1") is null);
    assert(manager.getCache("c2") is secondWithNulls && secondWithNulls.get(key) is null);
}

@("cache name reconfiguration preserves other regions and keeps the live view read-only")
unittest
{
    auto manager = new ConcurrentMapCacheManager();
    const first = manager.getCache("first");
    const second = manager.getCache("second");
    auto names = manager.getCacheNames();

    manager.setCacheNames(List!string.of("first"));
    assert(manager.getCache("first") !is first && manager.getCache("second") is second);
    assert(manager.getCache("third") is null);
    assert(names.size() == 2 && names.contains("first") && names.contains("second"));
    assertThrown!NullPointerException(names.contains(null));
    assertThrown!UnsupportedOperationException(names.clear());

    manager.setCacheNames(null);
    assert(manager.getCache("third") !is null);
    assert(names.size() == 3 && names.contains("third"));
}

@("region registration owns names from reusable storage")
@system unittest
{
    auto manager = new ConcurrentMapCacheManager();
    char[5] scratch = ['f', 'i', 'r', 's', 't'];
    auto region = manager.getCache(cast(string) scratch[]);
    scratch[] = "other";
    assert(region.getName() == "first");
    assert(manager.getCache("first") is region);
    assert(!manager.getCacheNames().contains("other"));
}
