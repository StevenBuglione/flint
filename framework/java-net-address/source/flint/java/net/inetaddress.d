/*
 * Copyright (c) 1995, 2024, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13:
//   src/java.base/share/classes/java/net/InetAddress.java
//   src/java.base/share/classes/java/net/Inet4Address.java
//   src/java.base/share/classes/java/net/Inet6Address.java
//   src/java.base/share/classes/sun/net/util/IPAddressUtil.java (convertFromIPv4MappedAddress)
//   src/java.base/share/classes/java/net/InetAddress.java (getByName, getAllByName, getAddressesFromNameService)
// Modified by the Flint authors.

/++
`java.net.InetAddress` and its `Inet4Address` and `Inet6Address` subclasses: addresses built from raw bytes, the
loopback address, the address-class predicates, text formatting and equality. `getByName` and `getAllByName` parse
IPv4 and IPv6 address literals; Flint has no engine host-name resolver yet, so any other host name fails with
`UnknownHostException`, except Java's own `localhost` fallback to the loopback address. `getLocalHost` and the
reverse lookup in `getHostName` are not part of this leaf.
+/
module flint.java.net.inetaddress;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException;
import flint.java.lang.javaobject : JavaObject;
import flint.java.net.internal.ipaddressutil : checkNumericZone, INADDR16SZ, INADDR4SZ, indexOf,
    isBsdParsableV4, isIPv4MappedAddress, parseAsciiDigit, textToNumericFormatV4, textToNumericFormatV6;
import flint.java.net.unknownhostexception : UnknownHostException;
import std.typecons : Nullable;

@safe:

/// An Internet Protocol (IP) address.
abstract class InetAddress
{
    mixin JavaObject;

    private Nullable!string hostName_;

    package this(Nullable!string hostName) pure nothrow @nogc
    {
        hostName_ = hostName;
    }

    /// Whether this is an IP multicast address.
    bool isMulticastAddress() const pure nothrow @nogc
    {
        return false;
    }

    /// Whether this is a wildcard address.
    bool isAnyLocalAddress() const pure nothrow @nogc
    {
        return false;
    }

    /// Whether this is a loopback address.
    bool isLoopbackAddress() const pure nothrow @nogc
    {
        return false;
    }

    /// Whether this is a link local address.
    bool isLinkLocalAddress() const pure nothrow @nogc
    {
        return false;
    }

    /// Whether this is a site local address.
    bool isSiteLocalAddress() const pure nothrow @nogc
    {
        return false;
    }

    /// Whether this multicast address has global scope.
    bool isMCGlobal() const pure nothrow @nogc
    {
        return false;
    }

    /// Whether this multicast address has node scope.
    bool isMCNodeLocal() const pure nothrow @nogc
    {
        return false;
    }

    /// Whether this multicast address has link scope.
    bool isMCLinkLocal() const pure nothrow @nogc
    {
        return false;
    }

    /// Whether this multicast address has site scope.
    bool isMCSiteLocal() const pure nothrow @nogc
    {
        return false;
    }

    /// Whether this multicast address has organization scope.
    bool isMCOrgLocal() const pure nothrow @nogc
    {
        return false;
    }

    /// The raw IP address in network byte order, as a new array.
    ubyte[] getAddress() const pure nothrow
    {
        return null;
    }

    /// The IP address in textual presentation.
    string getHostAddress() const pure nothrow
    {
        return null;
    }

    /// A hash code for this IP address.
    int hashCode() const pure nothrow @nogc
    {
        return 0;
    }

    /// Whether `obj` is an address of the same family with the same IP address.
    bool equals(scope const Object obj) const pure nothrow @nogc
    {
        return false;
    }

    /// The host name, or the empty string when there is none, then `/` and the IP address.
    override string toString() const pure nothrow
    {
        return (hostName_.isNull ? "" : hostName_.get) ~ "/" ~ getHostAddress();
    }

    /++
    Creates an address from a host name and a raw IP address of 4 or 16 bytes. No name service is consulted. A
    host in square brackets loses them, and an IPv4-mapped IPv6 address becomes an `Inet4Address`.
    +/
    static InetAddress getByAddress(string host, scope const(ubyte)[] addr) pure
    {
        return getByAddress(Nullable!string(host), addr);
    }

    /// ditto
    static InetAddress getByAddress(Nullable!string host, scope const(ubyte)[] addr) pure
    {
        host = stripBrackets(host);
        if (addr.length == Inet4Address.INADDRSZ)
            return new Inet4Address(host, addr);
        if (addr.length == Inet6Address.INADDRSZ)
        {
            if (isIPv4MappedAddress(addr))
                return new Inet4Address(host, addr[12 .. 16]);
            return new Inet6Address(host, addr, -1);
        }
        throw illegalLength();
    }

    /// Creates an address with no host name from a raw IP address of 4 or 16 bytes.
    static InetAddress getByAddress(scope const(ubyte)[] addr) pure
    {
        return getByAddress(Nullable!string.init, addr);
    }

    /++
    The address of `host`: the loopback address when `host` is empty, otherwise the first of `getAllByName(host)`.
    An IPv4 or IPv6 literal is only checked for format.
    +/
    static InetAddress getByName(string host)
    {
        return getAllByName(host)[0];
    }

    /++
    The addresses of `host`, as a new array: the loopback address when `host` is empty, or the one address an IPv4
    literal or an IPv6 literal (optionally in square brackets, with a numeric `%` scope id) denotes. Any other host
    name goes to the name service, which Flint does not have yet: it fails with `UnknownHostException`, except that
    `localhost` (ignoring case) falls back to the loopback address as in Java.
    +/
    static InetAddress[] getAllByName(string host)
    {
        if (host.length == 0)
            return [getLoopbackAddress()];
        if (indexOf(host, '\0') != host.length)
            throw new UnknownHostException("NUL character not allowed in hostname");
        bool ipv6Expected;
        if (host[0] == '[')
        {
            // This is supposed to be an IPv6 literal
            if (host.length > 2 && host[$ - 1] == ']')
            {
                host = host[1 .. $ - 1];
                ipv6Expected = true;
            }
            else
                throw invalidIPv6LiteralException(host, false);
        }
        if (parseAsciiDigit(host[0], 16) != -1 || host[0] == ':')
        {
            if (auto literal = parseLiteral(host, ipv6Expected))
                return [literal];
        }
        else if (ipv6Expected)
            throw invalidIPv6LiteralException(host, true);
        return getAddressesFromNameService(host);
    }

    // The address the IP literal `host` denotes, or null when `host` is no literal and goes to the name service.
    private static InetAddress parseLiteral(string host, bool ipv6Expected)
    {
        // check if it is IPv4 address only if host is not wrapped in '[]'
        if (!ipv6Expected)
            if (auto v4 = parseIPv4Literal(host))
                return v4;
        // Try an IPv6 literal, checking for a numeric or interface-name zone id first
        int numericZone = -1;
        Nullable!string ifname;
        const pos = indexOf(host, '%');
        if (pos != host.length)
        {
            numericZone = checkNumericZone(host);
            if (numericZone == -1)
                ifname = host[pos + 1 .. $];
        }
        ubyte[INADDR16SZ] addr;
        const length = textToNumericFormatV6(host, addr);
        if (length == 0)
        {
            if (indexOf(host, ':') != host.length || ipv6Expected)
                throw invalidIPv6LiteralException(host, ipv6Expected);
            return null;
        }
        if (length == INADDR4SZ)
        {
            // IPv4-mapped address must not contain zone-id
            if (numericZone != -1 || !ifname.isNull)
                throw new UnknownHostException(host ~ ": invalid IPv4-mapped address");
            return new Inet4Address(Nullable!string.init, addr[0 .. INADDR4SZ]);
        }
        // Flint has no NetworkInterface, so no interface name is known.
        if (!ifname.isNull)
            throw new UnknownHostException("no such interface " ~ ifname.get);
        return new Inet6Address(Nullable!string.init, addr[], numericZone);
    }

    // An IPv4 literal, or null. A literal only the BSD rules accept is ambiguous and rejected.
    private static InetAddress parseIPv4Literal(string host)
    {
        ubyte[INADDR4SZ] v4;
        if (textToNumericFormatV4(host, v4))
            return new Inet4Address(Nullable!string.init, v4[]);
        if (isBsdParsableV4(host))
        {
            auto cause = new IllegalArgumentException("Invalid IP address literal: " ~ host);
            throw new UnknownHostException(host, cause);
        }
        return null;
    }

    // Java's getAddressesFromNameService with a resolver that finds no host: Flint has no engine host-name resolver
    // yet. Java's lookup cache only holds resolver results, so it is not needed.
    private static InetAddress[] getAddressesFromNameService(string host)
    {
        if (isLocalhost(host))
            return [getLoopbackAddress()];
        throw new UnknownHostException(host);
    }

    /// The wildcard address `0.0.0.0/0.0.0.0` (Java's IPv4 default; Flint has no `java.net.preferIPv6Addresses`).
    package static InetAddress anyLocalAddress() pure nothrow
    {
        return new Inet4Address(Nullable!string("0.0.0.0"), 0);
    }

    /// The host name this address was created with, without a reverse lookup.
    package Nullable!string holderHostName() const pure nothrow @nogc
    {
        return hostName_;
    }

    /// The loopback address, `localhost/127.0.0.1`.
    static InetAddress getLoopbackAddress() pure nothrow
    {
        return new Inet4Address(Nullable!string("localhost"), 0x7f000001);
    }
}

/// An Internet Protocol version 4 (IPv4) address.
final class Inet4Address : InetAddress
{
    package enum INADDRSZ = 4;

    private immutable int address;

    private this(Nullable!string hostName, scope const(ubyte)[] addr) pure nothrow @nogc
    {
        super(hostName);
        address = addr[0] << 24 | addr[1] << 16 | addr[2] << 8 | addr[3];
    }

    private this(Nullable!string hostName, int address) pure nothrow @nogc
    {
        super(hostName);
        this.address = address;
    }

    private uint octet(int shift) const pure nothrow @nogc
    {
        return (cast(uint) address >> shift) & 0xFF;
    }

    override bool isMulticastAddress() const pure nothrow @nogc
    {
        return (address & 0xf0000000) == 0xe0000000;
    }

    override bool isAnyLocalAddress() const pure nothrow @nogc
    {
        return address == 0;
    }

    override bool isLoopbackAddress() const pure nothrow @nogc
    {
        return octet(24) == 127;
    }

    override bool isLinkLocalAddress() const pure nothrow @nogc
    {
        // 169.254.0.0/16
        return octet(24) == 169 && octet(16) == 254;
    }

    override bool isSiteLocalAddress() const pure nothrow @nogc
    {
        // RFC 1918: 10/8, 172.16/12 and 192.168/16.
        const first = octet(24);
        const second = octet(16);
        return first == 10 || (first == 172 && (second & 0xF0) == 16) || (first == 192 && second == 168);
    }

    override bool isMCGlobal() const pure nothrow @nogc
    {
        // 224.0.1.0 to 238.255.255.255
        return octet(24) >= 224 && octet(24) <= 238 && !(octet(24) == 224 && octet(16) == 0 && octet(8) == 0);
    }

    override bool isMCNodeLocal() const pure nothrow @nogc
    {
        return false;
    }

    override bool isMCLinkLocal() const pure nothrow @nogc
    {
        // 224.0.0/24
        return octet(24) == 224 && octet(16) == 0 && octet(8) == 0;
    }

    override bool isMCSiteLocal() const pure nothrow @nogc
    {
        // 239.255/16
        return octet(24) == 239 && octet(16) == 255;
    }

    override bool isMCOrgLocal() const pure nothrow @nogc
    {
        // 239.192 to 239.195
        return octet(24) == 239 && octet(16) >= 192 && octet(16) <= 195;
    }

    override ubyte[] getAddress() const pure nothrow
    {
        return [
            cast(ubyte) octet(24), cast(ubyte) octet(16), cast(ubyte) octet(8), cast(ubyte) octet(0)
        ];
    }

    override string getHostAddress() const pure nothrow
    {
        return decimal(octet(24)) ~ "." ~ decimal(octet(16)) ~ "." ~ decimal(octet(8)) ~ "." ~ decimal(octet(0));
    }

    override int hashCode() const pure nothrow @nogc
    {
        return address;
    }

    override bool equals(scope const Object obj) const pure nothrow @nogc
    {
        auto that = cast(const Inet4Address) obj;
        return that !is null && that.address == address;
    }
}

/// An Internet Protocol version 6 (IPv6) address.
final class Inet6Address : InetAddress
{
    package enum INADDRSZ = 16;

    private ubyte[INADDRSZ] ipaddress;
    private int scopeId;
    private bool scopeIdSet;

    private this(Nullable!string hostName, scope const(ubyte)[] addr, int scopeId) pure nothrow @nogc
    {
        super(hostName);
        ipaddress[] = addr[];
        if (scopeId >= 0)
        {
            this.scopeId = scopeId;
            scopeIdSet = true;
        }
    }

    /++
    Creates an address from a host name, a raw 16-byte IPv6 address and a numeric scope id. A negative scope id
    leaves the scope unset. No name service is consulted, and a host in square brackets loses them.
    +/
    static Inet6Address getByAddress(string host, scope const(ubyte)[] addr, int scope_id) pure
    {
        return getByAddress(Nullable!string(host), addr, scope_id);
    }

    /// ditto
    static Inet6Address getByAddress(Nullable!string host, scope const(ubyte)[] addr, int scope_id) pure
    {
        host = stripBrackets(host);
        if (addr.length == INADDRSZ)
            return new Inet6Address(host, addr, scope_id);
        throw illegalLength();
    }

    override bool isMulticastAddress() const pure nothrow @nogc
    {
        return ipaddress[0] == 0xff;
    }

    override bool isAnyLocalAddress() const pure nothrow @nogc
    {
        ubyte test;
        foreach (b; ipaddress)
            test |= b;
        return test == 0;
    }

    override bool isLoopbackAddress() const pure nothrow @nogc
    {
        ubyte test;
        foreach (b; ipaddress[0 .. 15])
            test |= b;
        return test == 0 && ipaddress[15] == 0x01;
    }

    override bool isLinkLocalAddress() const pure nothrow @nogc
    {
        return ipaddress[0] == 0xfe && (ipaddress[1] & 0xc0) == 0x80;
    }

    override bool isSiteLocalAddress() const pure nothrow @nogc
    {
        return ipaddress[0] == 0xfe && (ipaddress[1] & 0xc0) == 0xc0;
    }

    override bool isMCGlobal() const pure nothrow @nogc
    {
        return multicastScope(0x0e);
    }

    override bool isMCNodeLocal() const pure nothrow @nogc
    {
        return multicastScope(0x01);
    }

    override bool isMCLinkLocal() const pure nothrow @nogc
    {
        return multicastScope(0x02);
    }

    override bool isMCSiteLocal() const pure nothrow @nogc
    {
        return multicastScope(0x05);
    }

    override bool isMCOrgLocal() const pure nothrow @nogc
    {
        return multicastScope(0x08);
    }

    private bool multicastScope(int value) const pure nothrow @nogc
    {
        return ipaddress[0] == 0xff && (ipaddress[1] & 0x0f) == value;
    }

    override ubyte[] getAddress() const pure nothrow
    {
        return ipaddress.dup;
    }

    /// The numeric scope id, or 0 when the scope is unset.
    int getScopeId() const pure nothrow @nogc
    {
        return scopeId;
    }

    /// Eight colon-separated hexadecimal groups without compression, then `%` and the scope id when it is set.
    override string getHostAddress() const pure nothrow
    {
        static immutable digits = "0123456789abcdef";
        char[39] text;
        size_t length;
        foreach (i; 0 .. INADDRSZ / 2)
        {
            if (i > 0)
                text[length++] = ':';
            const group = ipaddress[2 * i] << 8 | ipaddress[2 * i + 1];
            int shift = 12;
            while (shift > 0 && (group >> shift) == 0)
                shift -= 4;
            for (; shift >= 0; shift -= 4)
                text[length++] = digits[(group >> shift) & 15];
        }
        if (scopeIdSet)
            return text[0 .. length].idup ~ "%" ~ decimal(scopeId);
        return text[0 .. length].idup;
    }

    override int hashCode() const pure nothrow @nogc
    {
        // Java adds four big-endian words built from signed bytes.
        int hash;
        foreach (word; 0 .. 4)
        {
            int component;
            foreach (b; ipaddress[4 * word .. 4 * word + 4])
                component = (component << 8) + cast(byte) b;
            hash += component;
        }
        return hash;
    }

    override bool equals(scope const Object obj) const pure nothrow @nogc
    {
        auto that = cast(const Inet6Address) obj;
        return that !is null && that.ipaddress == ipaddress;
    }

    /// Whether this is an IPv4-compatible IPv6 address: the first 12 bytes are zero.
    bool isIPv4CompatibleAddress() const pure nothrow @nogc
    {
        foreach (b; ipaddress[0 .. 12])
            if (b != 0)
                return false;
        return true;
    }
}

private Nullable!string stripBrackets(Nullable!string host) pure nothrow @nogc
{
    if (!host.isNull)
    {
        auto text = host.get;
        if (text.length > 0 && text[0] == '[' && text[$ - 1] == ']')
            return Nullable!string(text[1 .. $ - 1]);
    }
    return host;
}

// Java's host.equalsIgnoreCase("localhost") without the case tables. Besides ASCII case, the only character that
// matches a letter of "localhost" is U+017F LATIN SMALL LETTER LONG S, whose upper case is 'S'.
private bool isLocalhost(scope const(char)[] host) pure nothrow @nogc
{
    size_t i;
    foreach (wanted; "localhost")
    {
        if (i < host.length && (host[i] | 0x20) == wanted)
            i += 1;
        else if (wanted == 's' && i + 1 < host.length && host[i] == 0xC5 && host[i + 1] == 0xBF)
            i += 2;
        else
            return false;
    }
    return i == host.length;
}

private UnknownHostException invalidIPv6LiteralException(string host, bool wrapInBrackets) pure nothrow
{
    return new UnknownHostException((wrapInBrackets ? "[" ~ host ~ "]" : host) ~ ": invalid IPv6 address literal");
}

private UnknownHostException illegalLength() pure nothrow
{
    return new UnknownHostException("addr is of illegal length");
}
