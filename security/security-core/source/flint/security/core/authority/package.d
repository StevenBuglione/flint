// Ported from spring-security 7.2.0: core/src/main/java/org/springframework/security/core/authority/FactorGrantedAuthority.java
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

/// Spring Security's time-stamped authentication factors.
module flint.security.core.authority;

import flint.java.lang : IllegalArgumentException, JavaObject, stringHashCode;
import flint.java.time : Instant;
import flint.security.core : GrantedAuthority;
import flint.util : StringUtils;

@safe:

/// Indicates the factor used for authentication and the time when it was granted.
final class FactorGrantedAuthority : GrantedAuthority
{
    enum AUTHORIZATION_CODE_AUTHORITY = "FACTOR_AUTHORIZATION_CODE";
    enum BEARER_AUTHORITY = "FACTOR_BEARER";
    enum CAS_AUTHORITY = "FACTOR_CAS";
    enum OTT_AUTHORITY = "FACTOR_OTT";
    enum PASSWORD_AUTHORITY = "FACTOR_PASSWORD";
    enum SAML_RESPONSE_AUTHORITY = "FACTOR_SAML_RESPONSE";
    enum WEBAUTHN_AUTHORITY = "FACTOR_WEBAUTHN";
    enum X509_AUTHORITY = "FACTOR_X509";

    private string authority;
    private Instant issuedAt;

    private this(string authority, Instant issuedAt)
    {
        if (authority is null)
            throw new IllegalArgumentException("authority cannot be null");
        this.authority = authority;
        this.issuedAt = issuedAt;
    }

    /// Start building a factor authority with the supplied authority text.
    static Builder withAuthority(string authority)
    {
        return Builder(authority);
    }

    /// Start building an authority with the FACTOR_ prefix added to the supplied factor.
    static Builder withFactor(string factor)
    {
        if (!StringUtils.hasText(factor))
            throw new IllegalArgumentException("factor cannot be empty");
        if (factor.length >= 7 && factor[0 .. 7] == "FACTOR_")
            throw new IllegalArgumentException("factor cannot start with 'FACTOR_' got '" ~ factor ~ "'");
        return withAuthority("FACTOR_" ~ factor);
    }

    /// Create the factor authority using the current instant.
    static FactorGrantedAuthority fromAuthority(string authority)
    {
        return withAuthority(authority).build();
    }

    /// Create the prefixed factor authority using the current instant.
    static FactorGrantedAuthority fromFactor(string factor)
    {
        return withFactor(factor).build();
    }

    /// The factor's authority text.
    string getAuthority()
    {
        return authority;
    }

    /// When the factor was granted.
    Instant getIssuedAt()
    {
        return issuedAt;
    }

    /// Equal authority and issuance instant.
    bool equals(Object other)
    {
        auto factor = cast(FactorGrantedAuthority) other;
        return factor !is null && factor.authority == authority && factor.issuedAt == issuedAt;
    }

    /// Combine the factor and its issuance instant.
    int hashCode() pure nothrow @nogc
    {
        return 31 * (31 + stringHashCode(authority)) + issuedAt.hashCode();
    }

    mixin JavaObject;

    override string toString()
    {
        return "FactorGrantedAuthority [authority=" ~ authority ~ ", issuedAt=" ~ issuedAt.toString() ~ "]";
    }

    /// Builds a factor authority, defaulting its time to the first build's instant.
    static struct Builder
    {
        private string authority;
        private Instant issuedAt_;
        private bool hasIssuedAt;

        private this(string authority)
        {
            if (!StringUtils.hasText(authority))
                throw new IllegalArgumentException("A granted authority textual representation is required");
            this.authority = authority;
        }

        /// Set the issuance time explicitly.
        ref Builder issuedAt(Instant value) return
        {
            issuedAt_ = value;
            hasIssuedAt = true;
            return this;
        }

        /// Create the authority.
        FactorGrantedAuthority build()
        {
            if (!hasIssuedAt)
            {
                issuedAt_ = Instant.now();
                hasIssuedAt = true;
            }
            return new FactorGrantedAuthority(authority, issuedAt_);
        }
    }
}
