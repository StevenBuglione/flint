// Ported from spring-security 7.2.0: core/src/main/java/org/springframework/security/core/authority/mapping
/*
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

/// Spring Security's granted-authority mapping contracts.
module flint.security.core.authority.mapping;

import flint.security.core : GrantedAuthority;

@safe:

/// Maps the authorities loaded for a user to the authorities granted to their authentication token.
interface GrantedAuthoritiesMapper
{
    /// The authorities granted to the token.
    GrantedAuthority[] mapAuthorities(GrantedAuthority[] authorities);
}

/// A mapper that returns the supplied authorities.
class NullAuthoritiesMapper : GrantedAuthoritiesMapper
{
    /// Return the same authorities.
    GrantedAuthority[] mapAuthorities(GrantedAuthority[] authorities)
    {
        return authorities;
    }
}
