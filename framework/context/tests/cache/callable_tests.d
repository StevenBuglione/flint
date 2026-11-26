module flint.cache.callable_tests;

import flint.cache : Cache;
import flint.cache.concurrent : ConcurrentMapCache;
import flint.cache.support : NoOpCache;
import flint.engine.aot.any : Any;
import flint.java.lang : ClassCastException, IllegalStateException, NullPointerException;
import flint.java.util.concurrent.callable : Callable;
import std.exception : collectException;

@safe:

private final class TextLoader : Callable!string
{
    int calls;
    Exception failure;

    override string call()
    {
        ++calls;
        if (failure !is null)
            throw failure;
        return "loaded";
    }
}

@("Callable overload uses the provider's synchronous loading semantics")
unittest
{
    auto key = Any.of("name");
    auto loader = new TextLoader;
    Cache cache = new ConcurrentMapCache("test");
    assert(cache.get(key, loader) == "loaded");
    assert(cache.get(key, loader) == "loaded");
    assert(loader.calls == 1);

    auto concrete = new NoOpCache("test");
    assert(concrete.get(key, loader) == "loaded");
    assert(concrete.get(key, loader) == "loaded");
    assert(loader.calls == 3);
}

@("Callable preserves a loader's failure and the cache key")
unittest
{
    auto cache = new ConcurrentMapCache("test");
    auto key = Any.of("name");
    auto loader = new TextLoader;
    loader.failure = new IllegalStateException("unable to load");
    auto failure = collectException!(Cache.ValueRetrievalException)(cache.get(key, loader));
    assert(failure !is null && failure.getKey() == key && failure.getCause() is loader.failure);
    assert(cache.get(key) is null);
    loader.failure = null;
    assert(cache.get(key, loader) == "loaded");
}

@("a null Callable is only needed if the key is missing")
unittest
{
    Cache cache = new ConcurrentMapCache("test");
    auto key = Any.of("name");
    Callable!string absent;
    auto failure = collectException!(Cache.ValueRetrievalException)(cache.get(key, absent));
    assert(failure !is null && cast(NullPointerException) failure.getCause() !is null);

    cache.put(key, Any.of("cached"));
    assert(cache.get(key, absent) == "cached");
}

@("the Callable overload checks the cached type before returning it")
unittest
{
    auto cache = new ConcurrentMapCache("test");
    auto key = Any.of("name");
    auto loader = new TextLoader;
    cache.put(key, Any.of(17));
    assert(collectException!ClassCastException(cache.get(key, loader)) !is null);
    assert(loader.calls == 0);
}

@("Callable cache hits allocate no memory after startup")
unittest
{
    import core.memory : GC;

    Cache cache = new ConcurrentMapCache("test");
    auto key = Any.of("name");
    auto loader = new TextLoader;
    assert(cache.get(key, loader) == "loaded");
    const before = GC.stats().allocatedInCurrentThread;
    foreach (i; 0 .. 1_000)
        assert(cache.get(key, loader) == "loaded");
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(loader.calls == 1);
}
