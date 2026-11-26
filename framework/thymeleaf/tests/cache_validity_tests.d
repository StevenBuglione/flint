/// Behavioral checks for the stateless Thymeleaf 3.1.7.RELEASE cache-validity policies.
module flint.thymeleaf.cache_validity_tests;

import flint.thymeleaf.cache : AlwaysValidCacheEntryValidity, ICacheEntryValidity,
    NonCacheableCacheEntryValidity, TTLCacheEntryValidity;

@safe:

@("Cache-validity policies preserve both answers through the interface") unittest
{
    ICacheEntryValidity cacheable = AlwaysValidCacheEntryValidity.INSTANCE;
    ICacheEntryValidity uncached = NonCacheableCacheEntryValidity.INSTANCE;
    assert(cacheable.isCacheable() && cacheable.isCacheStillValid());
    assert(!uncached.isCacheable() && !uncached.isCacheStillValid());

    static class Expired : AlwaysValidCacheEntryValidity
    {
        override bool isCacheStillValid() nothrow @nogc
        {
            return false;
        }
    }

    ICacheEntryValidity expired = new Expired;
    assert(expired.isCacheable() && !expired.isCacheStillValid());
}

@("Cache validity has public constructors and an allocation-free shared instance") unittest
{
    auto readAlways = () nothrow @nogc => AlwaysValidCacheEntryValidity.INSTANCE;
    auto readNever = () nothrow @nogc => NonCacheableCacheEntryValidity.INSTANCE;
    assert(readAlways() !is null && readAlways() is readAlways());
    assert(readNever() !is null && readNever() is readNever());
    assert((new AlwaysValidCacheEntryValidity) !is readAlways());
    assert((new NonCacheableCacheEntryValidity) !is readNever());
}

@("Cache-validity instances have the same identity on another thread") @system unittest
{
    import core.thread : Thread;

    auto always = AlwaysValidCacheEntryValidity.INSTANCE;
    auto never = NonCacheableCacheEntryValidity.INSTANCE;
    auto thread = new Thread({
        assert(AlwaysValidCacheEntryValidity.INSTANCE is always);
        assert(NonCacheableCacheEntryValidity.INSTANCE is never);
    });
    thread.start();
    thread.join();
}

@("A TTL cache policy preserves the supplied duration and is cacheable") unittest
{
    foreach (ttl; [long.min, -1L, 0L, 250L, long.max])
    {
        auto policy = new TTLCacheEntryValidity(ttl);
        ICacheEntryValidity validity = policy;
        assert(policy.getCacheTTLMs() == ttl && validity.isCacheable());
    }
}
