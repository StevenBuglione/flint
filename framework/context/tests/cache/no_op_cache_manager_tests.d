// Ported from spring-framework v7.1.0: spring-context/src/test/java/org/springframework/cache/NoOpCacheManagerTests.java
/*
 * Copyright 2002-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Modified by the Flint authors.
 */
module flint.cache.no_op_cache_manager_tests;

import flint.cache : Cache, CacheManager;
import flint.cache.support : NoOpCacheManager;
import flint.engine.aot.any : Any;
import flint.java.lang : NullPointerException, UnsupportedOperationException;
import std.exception : assertThrown, collectException;

@safe:

@("getCache")
unittest
{
    CacheManager manager = new NoOpCacheManager();
    const cache = manager.getCache("bucket");
    assert(cache !is null);
    assert(manager.getCache("bucket") is cache);
}

@("noOpCache")
unittest
{
    CacheManager manager = new NoOpCacheManager();
    auto cache = manager.getCache("bucket");
    auto key = Any.of(new Object());
    assert(cache.getName() == "bucket");
    cache.put(key, Any.of(new Object()));
    assert(cache.get(key) is null);
    assert(cache.get!Object(key) is null);
    assert(cache.getNativeCache() is cast(Object) cache);
}

@("cacheName")
unittest
{
    CacheManager manager = new NoOpCacheManager();
    assert(!manager.getCacheNames().contains("bucket"));
    manager.getCache("bucket");
    assert(manager.getCacheNames().contains("bucket"));
}

@("cacheCallable")
unittest
{
    CacheManager manager = new NoOpCacheManager();
    auto cache = manager.getCache("bucket");
    auto key = Any.of(new Object());
    auto value = Any.of(new Object());
    assert(cache.get(key, () => value) == value);
}

@("cacheGetCallableFail")
unittest
{
    CacheManager manager = new NoOpCacheManager();
    auto cache = manager.getCache("bucket");
    auto key = Any.of("key");
    auto failure = new UnsupportedOperationException("Expected exception");
    auto caught = collectException!(Cache.ValueRetrievalException)(cache.get(key, () => throwFailure(failure)));
    assert(caught !is null);
    assert(caught.getCause() is failure);
    assert(caught.getKey() == key);
}

private Any throwFailure(Exception failure)
{
    throw failure;
}

@("reset removes cache registrations from the live read-only name view")
unittest
{
    CacheManager manager = new NoOpCacheManager();
    auto names = manager.getCacheNames();
    const old = manager.getCache("bucket");
    assert(names.contains("bucket"));
    assertThrown!UnsupportedOperationException(names.remove("bucket"));
    assertThrown!NullPointerException(manager.getCache(null));
    manager.resetCaches();
    assert(names.isEmpty());
    assert(manager.getCache("bucket") !is old);
}

@("first lookup of a cache name publishes exactly one cache")
@system unittest
{
    import core.atomic : atomicLoad, atomicStore;
    import core.thread : Thread;

    auto manager = new NoOpCacheManager();
    shared bool start;
    Cache[8] caches;
    Thread[8] threads;
    Thread lookup(size_t index)
    {
        return new Thread({
            while (!atomicLoad(start))
                Thread.yield();
            caches[index] = manager.getCache("same");
        });
    }

    foreach (i, ref thread; threads)
    {
        thread = lookup(i);
        thread.start();
    }
    atomicStore(start, true);
    foreach (thread; threads)
        thread.join();
    assert(caches[0]!is null);
    foreach (cache; caches)
        assert(cache is caches[0]);
    assert(manager.getCacheNames().size() == 1);
}

@("warmed cache lookup allocates no memory")
unittest
{
    import core.memory : GC;

    CacheManager manager = new NoOpCacheManager();
    auto cache = manager.getCache("bucket");
    auto names = manager.getCacheNames();
    auto key = Any.of("key");
    const before = GC.stats().allocatedInCurrentThread;
    foreach (_; 0 .. 1_000)
    {
        assert(manager.getCache("bucket") is cache);
        assert(manager.getCacheNames() is names);
        assert(names.contains("bucket"));
        assert(cache.get(key) is null);
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}
