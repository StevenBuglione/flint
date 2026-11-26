/*
 * Copyright (c) 2011-2026 Thymeleaf (http://www.thymeleaf.org)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Ported from thymeleaf 3.1.7.RELEASE:
 * lib/thymeleaf/src/main/java/org/thymeleaf/cache/ICacheEntryValidity.java,
 * AlwaysValidCacheEntryValidity.java, NonCacheableCacheEntryValidity.java and TTLCacheEntryValidity.java
 * in the same directory.
 * Modified by the Flint authors.
 */
module flint.thymeleaf.cache;

import flint.engine.aot.clock : currentTimeMillis;
import flint.engine.aot.objects : statelessInstance;

@safe:

/// Controls whether a template resolution can be cached and when it expires.
interface ICacheEntryValidity
{
    /// Whether the resolved template can be cached.
    bool isCacheable();

    /// Whether a cached resolution remains valid. Caches call this for cacheable entries.
    bool isCacheStillValid();
}

/// A cacheable resolution whose validity never expires.
class AlwaysValidCacheEntryValidity : ICacheEntryValidity
{
    /// The single shared instance (R17).
    static AlwaysValidCacheEntryValidity INSTANCE() nothrow @nogc
    {
        return statelessInstance!AlwaysValidCacheEntryValidity();
    }

    /// Create a separate always-valid policy.
    this() pure nothrow @nogc
    {
    }

    /// This policy allows caching.
    override bool isCacheable() nothrow @nogc
    {
        return true;
    }

    /// An entry using this policy remains valid.
    override bool isCacheStillValid() nothrow @nogc
    {
        return true;
    }
}

/// A resolution that cannot be cached.
class NonCacheableCacheEntryValidity : ICacheEntryValidity
{
    /// The single shared instance (R17).
    static NonCacheableCacheEntryValidity INSTANCE() nothrow @nogc
    {
        return statelessInstance!NonCacheableCacheEntryValidity();
    }

    /// Create a separate non-cacheable policy.
    this() pure nothrow @nogc
    {
    }

    /// This policy disallows caching.
    override bool isCacheable() nothrow @nogc
    {
        return false;
    }

    /// An entry using this policy is never valid.
    override bool isCacheStillValid() nothrow @nogc
    {
        return false;
    }
}

/// A cacheable resolution that expires after a wall-clock duration in milliseconds.
class TTLCacheEntryValidity : ICacheEntryValidity
{
    private const long ttlMillis;
    private const long expiresAtMillis;

    /// Start the validity period at the current wall-clock time.
    this(long cacheTTLMs) nothrow @nogc
    {
        this(cacheTTLMs, currentTimeMillis());
    }

    private this(long cacheTTLMs, long createdAtMillis) pure nothrow @nogc
    {
        ttlMillis = cacheTTLMs;
        // Java's signed long addition wraps at the end of its range.
        expiresAtMillis = cast(long)(cast(ulong) createdAtMillis + cast(ulong) cacheTTLMs);
    }

    /// The configured duration in milliseconds.
    long getCacheTTLMs() const pure nothrow @nogc
    {
        return ttlMillis;
    }

    /// This policy allows caching.
    override bool isCacheable() nothrow @nogc
    {
        return true;
    }

    /// Whether the current wall-clock time precedes the expiration deadline.
    override bool isCacheStillValid() nothrow @nogc
    {
        return validAt(currentTimeMillis());
    }

    private bool validAt(long wallTimeMillis) const pure nothrow @nogc
    {
        return wallTimeMillis < expiresAtMillis;
    }
}

@("TTL expires at the exact wall-clock deadline and preserves Java wrapping") unittest
{
    auto before = new TTLCacheEntryValidity(150, 1_000);
    assert(before.validAt(1_149) && !before.validAt(1_150) && !before.validAt(1_151));

    auto zero = new TTLCacheEntryValidity(0, 1_000);
    assert(zero.validAt(999) && !zero.validAt(1_000));

    auto negative = new TTLCacheEntryValidity(-10, 1_000);
    assert(negative.validAt(989) && !negative.validAt(990));

    auto wrapped = new TTLCacheEntryValidity(long.max, 2);
    assert(wrapped.validAt(long.min) && !wrapped.validAt(long.min + 1));
}
