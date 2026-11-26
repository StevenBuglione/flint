// Ported from spring-framework v7.1.0: spring-context/src/test/java/org/springframework/cache/concurrent/ConcurrentMapCacheTests.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
// Also exercises the inherited AbstractCacheTests fixture from spring-context/src/testFixtures.
module flint.cache.concurrent_map_cache_tests;

import flint.cache : Cache;
import flint.cache.concurrent : ConcurrentMapCache;
import flint.cache.support : SimpleValueWrapper;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, IllegalStateException, NullPointerException,
    UnsupportedOperationException;
import std.exception : assertThrown, collectException;

@safe:

@("isStoreByReferenceByDefault")
unittest
{
    auto cache = new ConcurrentMapCache("local");
    assert(!cache.isStoreByValue());
    auto key = Any.of("key");
    auto value = new Object();
    cache.put(key, Any.of(value));
    assert(cache.get!Object(key) is value);
}

@("concurrent cache distinguishes misses from cached null and checks typed reads")
unittest
{
    Cache cache = new ConcurrentMapCache("local");
    auto key = Any.of("key");
    assert(cache.get(key) is null);
    assert(cache.get!string(key) is null);

    cache.put(key, Any.of("george"));
    assert(cache.get!string(key) == "george");
    assertThrown!IllegalStateException(cache.get!int(key));

    cache.put(key, Any.init);
    assert(cache.get(key).get().isNull());
    assert(cache.get!string(key) is null);
    assert(cache.evictIfPresent(key));
    assert(!cache.evictIfPresent(key));
}

@("putIfAbsent preserves cached null")
unittest
{
    Cache cache = new ConcurrentMapCache("local");
    auto key = Any.of("key");
    auto alternate = Any.of("alternate");
    assert(cache.putIfAbsent(key, Any.init) is null);
    assert(cache.putIfAbsent(key, alternate).get().isNull());
    assert(cache.get(key).get().isNull());
    assert(cache.invalidate());
    assert(cache.get(key) is null);
    assert(!cache.invalidate());
}

@("value wrappers compare and hash their wrapped values")
unittest
{
    auto first = new SimpleValueWrapper(Any.of("value"));
    auto second = new SimpleValueWrapper(Any.of("val" ~ "ue"));
    auto withoutValue = new SimpleValueWrapper(Any.init);
    auto withTypedNull = new SimpleValueWrapper(Any.of(cast(Object) null));
    assert(first == second && first != withoutValue);
    assert(first.hashCode() == second.hashCode());
    assert(withoutValue == withTypedNull && withoutValue.hashCode() == 0);
    assert(first.toString() == "ValueWrapper for [value]");
}

@("cache writes own text in reusable request storage")
@system unittest
{
    Cache cache = new ConcurrentMapCache("local");
    // Model slices supplied by a request adapter over storage that is reused after a write.
    char[3] keyBytes = ['k', 'e', 'y'];
    char[3] valueBytes = ['o', 'l', 'd'];
    auto key = Any.of(cast(string) keyBytes[]);
    auto value = Any.of(cast(string) valueBytes[]);
    cache.put(key, value);
    keyBytes[] = "new";
    valueBytes[] = "bad";
    assert(cache.get!string(Any.of("key")) == "old");
    assert(cache.get(Any.of("new")) is null);

    assert(cache.putIfAbsent(key, value) is null);
    keyBytes[] = "aaa";
    valueBytes[] = "bbb";
    assert(cache.get!string(Any.of("new")) == "bad");

    auto loaded = cache.get(key, () => value);
    keyBytes[] = "xxx";
    valueBytes[] = "yyy";
    assert(loaded.get!string() == "bbb");
    assert(cache.get!string(Any.of("aaa")) == "bbb");
}

@("a non-null empty string remains a key and a value")
unittest
{
    Cache cache = new ConcurrentMapCache("local", false);
    string text = "source";
    auto empty = Any.of(text[0 .. 0]);
    assert(!empty.isNull());
    assert(!cache.get(empty, () => empty).isNull());
    auto entry = cache.get(empty);
    assert(entry !is null && !entry.get().isNull());
}

@("loader leaves failures uncached and only runs on a miss")
unittest
{
    Cache cache = new ConcurrentMapCache("local");
    auto key = Any.of("key");
    auto failure = new UnsupportedOperationException("Expected exception");
    auto caught = collectException!(Cache.ValueRetrievalException)(cache.get(key, () => failLoad(failure)));
    assert(caught !is null && caught.getCause() is failure);
    assert(cache.get(key) is null);

    int calls;
    Any loadNull()
    {
        ++calls;
        return Any.init;
    }

    assert(cache.get(key, &loadNull).isNull());
    assert(cache.get(key, &loadNull).isNull());
    assert(calls == 1);
}

private Any failLoad(Exception failure)
{
    throw failure;
}

@("recursive same-key loading fails and releases the key for a later load")
unittest
{
    Cache cache = new ConcurrentMapCache("local");
    auto key = Any.of("key");
    auto value = Any.of("value");
    auto caught = collectException!(Cache.ValueRetrievalException)(cache.get(key, () => cache.get(key, () => value)));
    assert(caught !is null && cast(IllegalStateException) caught.getCause() !is null);
    assert(cache.get(key) is null);
    assert(cache.get(key, () => value) == value);
}

@("invalidate makes a running load invisible to subsequent callers")
unittest
{
    Cache cache = new ConcurrentMapCache("local");
    auto key = Any.of("loading");
    auto other = Any.of("present");
    cache.put(other, Any.of("other value"));

    auto loaded = cache.get(key, () { assert(cache.invalidate()); return Any.of("first"); });

    assert(loaded.get!string() == "first");
    assert(cache.get(key) is null && cache.get(other) is null);
    assert(cache.get(key, () => Any.of("second")).get!string() == "second");
    assert(cache.get!string(key) == "second");
}

@("concurrent cache operations reject a null key")
unittest
{
    Cache cache = new ConcurrentMapCache("local");
    auto value = Any.of(1);
    assertThrown!NullPointerException(cache.get(Any.init));
    assertThrown!NullPointerException(cache.get(Any.init, () => value));
    assertThrown!NullPointerException(cache.put(Any.init, value));
    assertThrown!NullPointerException(cache.putIfAbsent(Any.init, value));
    assertThrown!NullPointerException(cache.evict(Any.init));
}

private final class WaitingHashKey
{
    import core.atomic : atomicLoad, atomicStore;
    import flint.conc.park : park, wakeAll;

    private static shared uint hashing;
    private static shared uint releaseHash;

    override bool opEquals(Object other) const nothrow @safe @nogc
    {
        return this is other;
    }

    override size_t toHash() const nothrow @safe @nogc
    {
        atomicStore(hashing, 1u);
        wakeAll(hashing);
        while (atomicLoad(releaseHash) == 0)
            park(releaseHash, 0, 1_000_000_000L);
        return 1;
    }
}

@("a put racing invalidation either contributes to its result or survives it")
@system unittest
{
    import core.atomic : atomicLoad, atomicStore;
    import core.thread : Thread;
    import flint.conc.park : park, wakeAll;

    auto cache = new ConcurrentMapCache("local");
    auto key = Any.of(new WaitingHashKey());
    auto value = Any.of(7);
    auto writer = new Thread({ cache.put(key, value); }).start();
    while (atomicLoad(WaitingHashKey.hashing) == 0)
        park(WaitingHashKey.hashing, 0, 1_000_000_000L);
    const invalidated = cache.invalidate();
    atomicStore(WaitingHashKey.releaseHash, 1u);
    wakeAll(WaitingHashKey.releaseHash);
    writer.join();
    assert(invalidated || cache.get!int(key) == 7);
}

@("warmed concurrent cache hits allocate no memory")
unittest
{
    import core.memory : GC;

    Cache cache = new ConcurrentMapCache("local");
    auto key = Any.of("key");
    auto value = Any.of("value");
    cache.put(key, value);
    const before = GC.stats().allocatedInCurrentThread;
    foreach (_; 0 .. 1_000)
    {
        assert(cache.get(key).get() == value);
        assert(cache.get!string(key) == "value");
        assert(cache.get(key, () => Any.init) == value);
        assert(cache.putIfAbsent(key, value).get() == value);
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("null-disabled cache rejects a null mapping and permits another load")
unittest
{
    Cache cache = new ConcurrentMapCache("local", false);
    auto key = Any.of("key");
    assertThrown!IllegalArgumentException(cache.put(key, Any.init));
    assertThrown!(Cache.ValueRetrievalException)(cache.get(key, () => Any.init));
    assert(cache.get(key) is null);
    assert(cache.get(key, () => Any.of("value")) == Any.of("value"));
}

@("concurrent callers coalesce a load and return the value")
@system unittest
{
    import core.atomic : atomicLoad, atomicOp, atomicStore;
    import core.thread : Thread;
    import flint.conc.park : park, wakeAll;

    Cache cache = new ConcurrentMapCache("local");
    auto key = Any.of("key");
    shared uint allowCompletion;
    shared uint waiting;
    shared int calls;
    int[8] results;

    Any load() @safe
    {
        if (atomicOp!"+="(calls, 1) == 1)
        {
            while (atomicLoad(allowCompletion) == 0)
                park(allowCompletion, 0, 1_000_000_000L);
        }
        return Any.of(atomicLoad(calls));
    }

    Thread start(size_t index)
    {
        return new Thread({
            if (index != 0)
                atomicOp!"+="(waiting, 1u);
            results[index] = cache.get(key, &load).get!int();
        }).start();
    }

    Thread[results.length] threads;
    threads[0] = start(0);
    while (atomicLoad(calls) == 0)
        Thread.yield();
    foreach (index; 1 .. threads.length)
        threads[index] = start(index);
    while (atomicLoad(waiting) + 1 != threads.length)
        Thread.yield();
    atomicStore(allowCompletion, 1u);
    wakeAll(allowCompletion);
    foreach (thread; threads)
        thread.join();
    assert(atomicLoad(calls) == 1);
    assert(results[] == [1, 1, 1, 1, 1, 1, 1, 1]);
}
