/*
 * Copyright (c) 2021, 2023, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/spi/InetAddressResolverProvider.java
// Modified by the Flint authors.

/++
`java.net.spi.InetAddressResolverProvider`, the factory for an `InetAddressResolver`, and its `Configuration`.
Java finds providers with `ServiceLoader`; Flint wires services at build time and has no engine resolver yet, so
nothing in java.net consults a provider (D-JDK-8). Java's `SecurityManager` permission check is not ported.
+/
module flint.java.net.spi.inetaddressresolverprovider;

import flint.java.net.spi.inetaddressresolver : InetAddressResolver;

@safe:

/// A service provider for an `InetAddressResolver`.
abstract class InetAddressResolverProvider
{
    /// Initializes a new provider.
    protected this() pure nothrow @nogc
    {
    }

    /// The resolver this provider supplies, built with `configuration`.
    abstract InetAddressResolver get(Configuration configuration);

    /// The name of this provider.
    abstract string name();

    /++
    The platform configuration a provider receives. Java's interface is sealed and permits only the JDK's
    internal `ResolverProviderConfiguration` (R16).
    +/
    interface Configuration
    {
        /// The platform's built-in resolver.
        InetAddressResolver builtinResolver();

        /// The local host name.
        string lookupLocalHostName();
    }
}
