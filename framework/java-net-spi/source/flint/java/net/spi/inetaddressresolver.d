/*
 * Copyright (c) 2021, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/spi/InetAddressResolver.java
// Modified by the Flint authors.

/++
`java.net.spi.InetAddressResolver`, the service contract for host-name and address resolution, and its
`LookupPolicy`. Flint has no engine resolver yet, so nothing in java.net calls a resolver (D-JDK-8).
+/
module flint.java.net.spi.inetaddressresolver;

import flint.java.lang : IllegalArgumentException;
import flint.java.net.inetaddress : InetAddress;
import flint.java.util.stream : Stream;

@safe:

/// Resolves host names to IP addresses and IP addresses to host names.
interface InetAddressResolver
{
    /// The IP addresses of `host` that match `lookupPolicy`; throws `UnknownHostException` when none are found.
    Stream!InetAddress lookupByName(string host, LookupPolicy lookupPolicy);

    /// The host name of the raw IP address `addr`; throws `UnknownHostException` when it cannot be found.
    string lookupByAddress(scope const(ubyte)[] addr);

    /// The type and order of addresses a resolver's `lookupByName` returns.
    static final class LookupPolicy
    {
        /// Requests IPv4 addresses.
        enum int IPV4 = 1 << 0;
        /// Requests IPv6 addresses.
        enum int IPV6 = 1 << 1;
        /// Requests IPv4 addresses before IPv6 addresses.
        enum int IPV4_FIRST = 1 << 2;
        /// Requests IPv6 addresses before IPv4 addresses.
        enum int IPV6_FIRST = 1 << 3;

        private immutable int characteristics_;

        private this(int characteristics) pure nothrow @nogc
        {
            characteristics_ = characteristics;
        }

        /// A policy with the `characteristics` bit mask; throws `IllegalArgumentException` for an invalid mask.
        static LookupPolicy of(int characteristics) pure
        {
            if (string problem = checkCharacteristics(characteristics))
                throw new IllegalArgumentException(problem);
            return new LookupPolicy(characteristics);
        }

        /// The characteristics bit mask.
        int characteristics() const pure nothrow @nogc
        {
            return characteristics_;
        }
    }
}

// The message of the IllegalArgumentException that LookupPolicy.of throws for `characteristics`, or null.
private string checkCharacteristics(int characteristics) pure nothrow @nogc
{
    alias P = InetAddressResolver.LookupPolicy;
    // At least one type of addresses should be requested
    if ((characteristics & P.IPV4) == 0 && (characteristics & P.IPV6) == 0)
        return "No address type specified";
    // Requested order of addresses couldn't be determined
    if ((characteristics & P.IPV4_FIRST) != 0 && (characteristics & P.IPV6_FIRST) != 0)
        return "Addresses order cannot be determined";
    // If IPv4 addresses requested to be returned first then they should be requested too
    if ((characteristics & P.IPV4_FIRST) != 0 && (characteristics & P.IPV4) == 0)
        return "Addresses order and type do not match";
    // If IPv6 addresses requested to be returned first then they should be requested too
    if ((characteristics & P.IPV6_FIRST) != 0 && (characteristics & P.IPV6) == 0)
        return "Addresses order and type do not match";
    return null;
}
