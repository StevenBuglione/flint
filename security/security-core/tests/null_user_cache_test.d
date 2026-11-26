// Ported from spring-security 7.2.0: core/src/test/java/org/springframework/security/core/userdetails/cache/NullUserCacheTests.java
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
module flint.security.null_user_cache_test;

import flint.security.core : AuthorityUtils;
import flint.security.core.userdetails : User, UserCache;
import flint.security.core.userdetails.cache : NullUserCache;

@safe:

@("testCacheOperation")
unittest
{
    UserCache cache = new NullUserCache;
    auto user = new User("john", "password", true, true, true, true,
            AuthorityUtils.createAuthorityList("ROLE_ONE", "ROLE_TWO"));
    cache.putUserInCache(user);
    assert(cache.getUserFromCache(user.getUsername()) is null);
    assert(cache.getUserFromCache(null) is null);
    cache.removeUserFromCache(null);
}
