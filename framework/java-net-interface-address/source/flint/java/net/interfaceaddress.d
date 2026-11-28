/*
 * Copyright (c) 2005, 2021, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/InterfaceAddress.java
// Modified by the Flint authors.

/++
`java.net.InterfaceAddress`: a network interface IP address, optional IPv4 broadcast address and subnet prefix length.
Instances are constructed package-internally (for `NetworkInterface`).
+/
module flint.java.net.interfaceaddress;

import flint.engine.aot.text : decimal;
import flint.java.lang : NullPointerException;
import flint.java.lang.javaobject : JavaObject;
import flint.java.net.inetaddress : Inet4Address, InetAddress;

@safe:

/// Represents a network interface address: an IP address, a subnet prefix length and an optional IPv4 broadcast.
final class InterfaceAddress
{
    mixin JavaObject;

    package(flint.java.net) InetAddress address;
    package(flint.java.net) Inet4Address broadcast;
    package(flint.java.net) short maskLength;

    package(flint.java.net) this() pure nothrow @nogc
    {
    }

    package(flint.java.net) this(InetAddress address, Inet4Address broadcast, short maskLength) pure nothrow @nogc
    {
        this.address = address;
        this.broadcast = broadcast;
        this.maskLength = maskLength;
    }

    /// The `InetAddress` for this interface address.
    inout(InetAddress) getAddress() inout pure nothrow @nogc
    {
        return address;
    }

    /// The IPv4 broadcast address, or `null` if none applies (for example on IPv6 or loopback).
    inout(InetAddress) getBroadcast() inout pure nothrow @nogc
    {
        return broadcast;
    }

    /// The subnet prefix length (for example 8, 16 or 24 for IPv4; 64 or 128 for IPv6).
    short getNetworkPrefixLength() const pure nothrow @nogc
    {
        return maskLength;
    }

    /// Whether `obj` is an `InterfaceAddress` with equal address, broadcast and network prefix length.
    bool equals(scope const Object obj) const pure nothrow @nogc
    {
        auto cmp = cast(const InterfaceAddress) obj;
        if (cmp is null)
            return false;
        return addrEquals(address, cmp.address) && addrEquals(broadcast, cmp.broadcast) && maskLength == cmp.maskLength;
    }

    /// The sum of the address hash code, optional broadcast hash code and network prefix length.
    int hashCode() const pure
    {
        if (address is null)
            throwNullAddress();
        return address.hashCode() + (broadcast !is null ? broadcast.hashCode() : 0) + maskLength;
    }

    /// Formats as `<address>/<prefixLength> [<broadcast>]`.
    override string toString() const pure nothrow
    {
        const addrStr = address is null ? "null" : address.toString();
        const bcastStr = broadcast is null ? "null" : broadcast.toString();
        return addrStr ~ "/" ~ decimal(cast(int) maskLength) ~ " [" ~ bcastStr ~ "]";
    }
}

private bool addrEquals(const InetAddress a, scope const InetAddress b) pure nothrow @nogc
{
    return a is b || (a !is null && a.equals(b));
}

pragma(inline, false) private void throwNullAddress() pure
{
    throw new NullPointerException();
}
