// Ported from spring-security 7.2.0: core/src/test/java/org/springframework/security/core/authority/FactorGrantedAuthorityTests.java
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
module flint.security.factor_granted_authority_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.time : Instant;
import flint.security.core.authority : FactorGrantedAuthority;
import std.exception : collectException;

@safe:

@("buildWhenOnlyAuthorityThenDefaultsIssuedAtToNow")
unittest
{
    const before = Instant.now();
    auto authority = FactorGrantedAuthority.withAuthority("profile:read").build();
    const after = Instant.now();
    assert(authority.getAuthority() == "profile:read");
    assert(authority.getIssuedAt().compareTo(before) >= 0 && authority.getIssuedAt().compareTo(after) <= 0);
}

@("buildWhenAllFieldsSetThenCreatesCorrectly")
unittest
{
    const issuedAt = Instant.ofEpochSecond(42);
    auto authority = FactorGrantedAuthority.withAuthority("admin:write").issuedAt(issuedAt).build();
    assert(authority.getAuthority() == "admin:write" && authority.getIssuedAt() == issuedAt);
}

@("buildWhenNullAuthorityThenThrowsException")
unittest
{
    const failure = collectException!IllegalArgumentException(FactorGrantedAuthority.withAuthority(null));
    assert(failure !is null && failure.msg == "A granted authority textual representation is required");
}

@("buildWhenEmptyAuthorityThenThrowsException")
unittest
{
    const failure = collectException!IllegalArgumentException(FactorGrantedAuthority.withAuthority(""));
    assert(failure !is null && failure.msg == "A granted authority textual representation is required");
}

@("FactorGrantedAuthority compares both the authority and the issued-at instant")
unittest
{
    auto builder = FactorGrantedAuthority.withFactor("PASSWORD").issuedAt(Instant.EPOCH);
    auto authority = builder.build();
    auto equal = builder.build();
    assert(authority.getAuthority() == FactorGrantedAuthority.PASSWORD_AUTHORITY);
    assert(authority == equal && authority.toHash() == equal.toHash());
    assert(authority.hashCode() == 96_238_998);
    assert(authority != builder.issuedAt(Instant.ofEpochSecond(1)).build());
    assert(authority.toString() == "FactorGrantedAuthority [authority=FACTOR_PASSWORD, issuedAt=1970-01-01T00:00:00Z]");
}

@("FactorGrantedAuthority validates the unprefixed factor")
unittest
{
    const failure = collectException!IllegalArgumentException(FactorGrantedAuthority.withFactor("FACTOR_PASSWORD"));
    assert(failure !is null && failure.msg == "factor cannot start with 'FACTOR_' got 'FACTOR_PASSWORD'");
    assert(collectException!IllegalArgumentException(FactorGrantedAuthority.withFactor(" ")) !is null);
}
