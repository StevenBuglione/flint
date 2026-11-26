// Ported from spring-security 7.2.0: core/src/test/java/org/springframework/security/core/userdetails/cache/SpringCacheBasedUserCacheTests.java
/*
 * Copyright 2004, 2005, 2006 Acegi Technology Pty Limited
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
module flint.security.flint_cache_based_user_cache_test;

import flint.cache : Cache;
import flint.cache.concurrent : ConcurrentMapCacheManager;
import flint.engine.aot.any : Any;
import flint.java.lang : ClassCastException, IllegalArgumentException, NullPointerException;
import flint.security.core : AuthorityUtils;
import flint.security.core.userdetails : User, UserDetails;
import flint.security.core.userdetails.cache : FlintCacheBasedUserCache;
import std.exception : collectException;

@safe:

private Cache region()
{
    return new ConcurrentMapCacheManager().getCache("springbasedusercachetests");
}

private User testUser()
{
    return new User("john", "password", true, true, true, true,
            AuthorityUtils.createAuthorityList("ROLE_ONE", "ROLE_TWO"));
}

@("cacheOperationsAreSuccessful")
unittest
{
    auto cache = new FlintCacheBasedUserCache(region());
    auto user = testUser();
    cache.putUserInCache(user);
    auto found = cache.getUserFromCache(user.getUsername());
    assert(found is user && found.getPassword() == user.getPassword());

    cache.removeUserFromCache(user);
    assert(cache.getUserFromCache(user.getUsername()) is null);
    assert(cache.getUserFromCache(null) is null);
    assert(cache.getUserFromCache("UNKNOWN_USER") is null);
}

@("startupDetectsMissingCache")
unittest
{
    const invalid = collectException!IllegalArgumentException(new FlintCacheBasedUserCache(null));
    assert(invalid !is null && invalid.msg == "cache mandatory");
}

@("FlintCacheBasedUserCache preserves cached null and type checking")
unittest
{
    auto storage = region();
    auto cache = new FlintCacheBasedUserCache(storage);
    const key = "john";
    storage.put(Any.of(key), Any.of(cast(Object) null));
    assert(cache.getUserFromCache(key) is null);

    storage.put(Any.of(key), Any.of("other value"));
    assert(collectException!ClassCastException(cache.getUserFromCache(key)) !is null);

    cache.removeUserFromCache(key);
    assert(storage.get(Any.of(key)) is null);
}

@("FlintCacheBasedUserCache skips null lookups and preserves an empty key")
unittest
{
    auto storage = region();
    auto cache = new FlintCacheBasedUserCache(storage);
    auto user = testUser();
    storage.put(Any.of(""), Any.of(cast(Object) user));
    assert(cache.getUserFromCache("") is user);
    assert(cache.getUserFromCache(null) is null);
    assert(collectException!NullPointerException(cache.removeUserFromCache(cast(string) null)) !is null);
    assert(collectException!NullPointerException(cache.removeUserFromCache(cast(UserDetails) null)) !is null);
}
