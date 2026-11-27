/*
 * Copyright (c) 2003, 2021, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/Proxy.java
// Modified by the Flint authors.

/++
`java.net.Proxy`: a proxy type and the address of the proxy server. This leaf covers `Proxy.Type`, the
`(Type, SocketAddress)` constructor, `type`, `address`, `toString`, `equals` and `hashCode`. `NO_PROXY` is deferred:
it needs one shared object, and engine-aot's `constantInstance` accepts only classes whose fields are all
`immutable`, which `address` (a caller's `SocketAddress`) cannot be.
+/
module flint.java.net.proxy;

import flint.java.lang : IllegalArgumentException;
import flint.java.lang.javaobject : JavaObject;
import flint.java.net.inetsocketaddress : InetSocketAddress;
import flint.java.net.socketaddress : SocketAddress;

@safe:

/// A proxy setting: a type (`HTTP` or `SOCKS`) and the socket address of the proxy server.
class Proxy
{
    mixin JavaObject;

    /// The type of a proxy.
    enum Type : ubyte
    {
        /// A direct connection, or the absence of a proxy.
        DIRECT,
        /// A proxy for high-level protocols such as HTTP or FTP.
        HTTP,
        /// A SOCKS (V4 or V5) proxy.
        SOCKS,
    }

    private Type type_;
    private SocketAddress sa;

    /++
    A proxy of `type` at `sa`. Throws `IllegalArgumentException` when `type` is `DIRECT` or `sa` is not an
    `InetSocketAddress` (including `null`).
    +/
    this(Type type, SocketAddress sa) pure
    {
        if (type == Type.DIRECT || cast(InetSocketAddress) sa is null)
            throw new IllegalArgumentException(incompatibleMessage(type, sa));
        type_ = type;
        this.sa = sa;
    }

    /// The proxy type.
    final Type type() const pure nothrow @nogc
    {
        return type_;
    }

    /// The socket address of the proxy, or `null` for a direct connection.
    final inout(SocketAddress) address() inout pure nothrow @nogc
    {
        return sa;
    }

    /// `DIRECT`, or the type's name, ` @ ` and the address's `toString`.
    override string toString() const pure nothrow
    {
        if (type_ == Type.DIRECT)
            return "DIRECT";
        return typeName(type_) ~ " @ " ~ inetAddress().toString();
    }

    /// Whether `obj` is a `Proxy` of the same type with an equal address (or both addresses `null`).
    final bool equals(scope const Object obj) const pure nothrow @nogc
    {
        auto that = cast(const Proxy) obj;
        if (that is null || that.type_ != type_)
            return false;
        return sa is null ? that.sa is null : inetAddress().equals(that.sa);
    }

    /// The type's hash code plus the address's (R11: the type contributes its ordinal, not Java's identity hash).
    final int hashCode() const pure nothrow @nogc
    {
        return sa is null ? type_ : type_ + inetAddress().hashCode();
    }

    // The address of a proxy that is not DIRECT, which the constructor checked is an InetSocketAddress.
    private const(InetSocketAddress) inetAddress() const pure nothrow @nogc
    {
        return cast(const InetSocketAddress) sa;
    }
}

private string typeName(Proxy.Type type) pure nothrow @nogc
{
    final switch (type)
    {
    case Proxy.Type.DIRECT:
        return "DIRECT";
    case Proxy.Type.HTTP:
        return "HTTP";
    case Proxy.Type.SOCKS:
        return "SOCKS";
    }
}

// Java appends String.valueOf(sa). Object.toString is not @safe in D, so an address that is neither null nor an
// InetSocketAddress (only a caller's own SocketAddress subclass) shows its D class name instead.
private string incompatibleMessage(Proxy.Type type, const SocketAddress sa) pure nothrow
{
    string shown;
    if (sa is null)
        shown = "null";
    else if (auto inet = cast(const InetSocketAddress) sa)
        shown = inet.toString();
    else
        shown = typeid(sa).name;
    return "type " ~ typeName(type) ~ " is not compatible with address " ~ shown;
}
