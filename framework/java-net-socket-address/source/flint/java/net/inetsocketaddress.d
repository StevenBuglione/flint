/*
 * Copyright (c) 2000, 2023, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/InetSocketAddress.java
// Modified by the Flint authors.

/++
`java.net.InetSocketAddress`: an IP address or an unresolved host name, plus a port. This leaf covers the
constructors (`(String, int)` resolves through `InetAddress.getByName`, so only address literals and `localhost`
resolve until Flint has an engine host-name resolver), `createUnresolved`, the accessors, `toString`, `equals` and
`hashCode`. `getHostName` may reverse-resolve and is not part of this leaf.
+/
module flint.java.net.inetsocketaddress;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException;
import flint.java.lang.javaobject : JavaObject;
import flint.java.net.inetaddress : Inet6Address, InetAddress;
import flint.java.net.internal.hostcase : equalsIgnoreCase, lowerRootHashCode;
import flint.java.net.socketaddress : SocketAddress;
import flint.java.net.unknownhostexception : UnknownHostException;

@safe:

/// An IP socket address: an IP address and a port, or an unresolved host name and a port.
class InetSocketAddress : SocketAddress
{
    mixin JavaObject;

    // Java's InetSocketAddressHolder fields: exactly one of hostname and addr is set.
    private string hostname;
    private InetAddress addr;
    private int port;

    /// A socket address with the wildcard address `0.0.0.0` and `port`, which must be from 0 to 65535.
    this(int port) pure
    {
        this(cast(InetAddress) null, port);
    }

    /// A socket address with `addr` (the wildcard address when `null`) and `port`, which must be from 0 to 65535.
    this(InetAddress addr, int port) pure
    {
        this.addr = addr is null ? InetAddress.anyLocalAddress() : addr;
        this.port = checkPort(port);
    }

    /++
    A socket address for `hostname` and `port`, which must be from 0 to 65535. The address is
    `InetAddress.getByName(hostname)`; when that fails, the address is unresolved and keeps `hostname`. An empty
    `hostname` gives the loopback address.
    +/
    this(string hostname, int port)
    {
        try
            addr = InetAddress.getByName(hostname);
        catch (UnknownHostException e)
            this.hostname = hostname;
        this.port = checkPort(port);
    }

    private this(int port, string hostname) pure nothrow @nogc
    {
        this.hostname = hostname;
        this.port = port;
    }

    /++
    An unresolved socket address with host name `host` and `port`, which must be from 0 to 65535. No name service
    is consulted, and `host` is kept as given, even when it is an address literal.
    +/
    static InetSocketAddress createUnresolved(string host, int port) pure
    {
        return new InetSocketAddress(checkPort(port), host);
    }

    /// The port number.
    final int getPort() const pure nothrow @nogc
    {
        return port;
    }

    /// The IP address, or `null` when this address is unresolved.
    final inout(InetAddress) getAddress() inout pure nothrow @nogc
    {
        return addr;
    }

    /// The host name of an unresolved address, otherwise the address's own host name or, when it has none, its
    /// textual IP address. Never a reverse lookup.
    final string getHostString() const pure nothrow
    {
        if (addr is null)
            return hostname;
        const name = addr.holderHostName();
        return name.isNull ? addr.getHostAddress() : name.get;
    }

    /// Whether this address has no IP address.
    final bool isUnresolved() const pure nothrow @nogc
    {
        return addr is null;
    }

    /// `host/<unresolved>:port`, or the address's `toString` with an IPv6 address in square brackets, then `:port`.
    override string toString() const pure nothrow
    {
        string formatted;
        if (addr is null)
            formatted = hostname ~ "/<unresolved>";
        else
        {
            formatted = addr.toString();
            if (cast(const Inet6Address) addr !is null)
            {
                size_t slash = formatted.length;
                while (formatted[slash - 1] != '/')
                    --slash;
                formatted = formatted[0 .. slash] ~ "[" ~ formatted[slash .. $] ~ "]";
            }
        }
        return formatted ~ ":" ~ decimal(port);
    }

    /// Whether `obj` has the same port and an equal IP address, or, both unresolved, a host name equal ignoring case.
    final bool equals(scope const Object obj) const pure nothrow @nogc
    {
        auto that = cast(const InetSocketAddress) obj;
        if (that is null)
            return false;
        const sameIP = addr !is null ? addr.equals(that.addr) : (that.addr is null
                && equalsIgnoreCase(hostname, that.hostname));
        return sameIP && port == that.port;
    }

    /// The address's hash code, or the lower-cased host name's, plus the port.
    final int hashCode() const pure nothrow @nogc
    {
        return (addr !is null ? addr.hashCode() : lowerRootHashCode(hostname)) + port;
    }
}

private int checkPort(int port) pure
{
    if (port < 0 || port > 0xFFFF)
        throw new IllegalArgumentException("port out of range:" ~ decimal(port));
    return port;
}
