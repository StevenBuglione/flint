// Ported from spring-security 7.2.0: core/src/main/java/org/springframework/security/core/userdetails/cache/NullUserCache.java
// Also ported from SpringCacheBasedUserCache.java in the same upstream package.
/*
 * Copyright 2004, 2005, 2006 Acegi Technology Pty Limited
 * Copyright 2004-present the original author or authors.
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
module flint.security.core.userdetails.cache;

import flint.cache : Cache;
import flint.engine.aot.any : Any;
import flint.java.lang : ClassCastException, IllegalArgumentException, NullPointerException;
import flint.security.core.userdetails : UserCache, UserDetails;

@safe:

/// A user cache that discards all entries.
class NullUserCache : UserCache
{
    /// Always report a cache miss.
    UserDetails getUserFromCache(string username)
    {
        return null;
    }

    /// Discard the user.
    void putUserInCache(UserDetails user)
    {
    }

    /// Accept the removal without storing state.
    void removeUserFromCache(string username)
    {
    }
}

/// Stores user details in an application cache region.
class FlintCacheBasedUserCache : UserCache
{
    private Cache cache;

    /// Select the cache region used for user details.
    this(Cache cache)
    {
        if (cache is null)
            throw new IllegalArgumentException("cache mandatory");
        this.cache = cache;
    }

    /// Look up the user using their user name.
    UserDetails getUserFromCache(string username)
    {
        if (username is null)
            return null;
        auto entry = cache.get(Any.of(username));
        if (entry is null)
            return null;
        auto value = entry.get();
        if (value.isNull())
            return null;
        if (auto user = cast(UserDetails) value.asObject())
            return user;
        throw new ClassCastException();
    }

    /// Store the user under their user name.
    void putUserInCache(UserDetails user)
    {
        if (user is null)
            throw new NullPointerException();
        cache.put(Any.of(user.getUsername()), Any.of(cast(Object) user));
    }

    /// Remove the entry for the supplied user.
    void removeUserFromCache(UserDetails user)
    {
        if (user is null)
            throw new NullPointerException();
        removeUserFromCache(user.getUsername());
    }

    /// Remove the entry for the supplied user name.
    void removeUserFromCache(string username)
    {
        cache.evict(Any.of(username));
    }
}
