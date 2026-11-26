// Ported from spring-security 7.2.0: core/src/main/java/org/springframework/security/core/userdetails/cache/NullUserCache.java
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
module flint.security.core.userdetails.cache;

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
