/*
 * Copyright (c) 1995, 2022, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/DatagramPacket.java
// Modified by the Flint authors.

/++
`java.net.DatagramPacket`: a datagram buffer, offset, length and remote IP endpoint. Equality and hashing stay by
identity, as in Java, which does not override `equals` or `hashCode`. Under R26, a `null` buffer slice counts as an
empty `byte[]` where Java throws `NullPointerException`.
+/
module flint.java.net.datagrampacket;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException;
import flint.java.net.inetaddress : InetAddress;
import flint.java.net.inetsocketaddress : InetSocketAddress;
import flint.java.net.socketaddress : SocketAddress;

@safe:

/// Represents a connectionless datagram packet.
final class DatagramPacket
{
    package(flint.java.net) byte[] buf;
    package(flint.java.net) int offset;
    package(flint.java.net) int length;
    package(flint.java.net) int bufLength;
    package(flint.java.net) InetAddress address;
    package(flint.java.net) int port;

    /++
    Constructs a packet for receiving `length` bytes into `buf` starting at `offset`. A `null` `buf` counts as empty
    under R26.
    +/
    this(byte[] buf, int offset, int length)
    {
        setData(buf, offset, length);
    }

    /++
    Constructs a packet for receiving `length` bytes into `buf` starting at offset 0. A `null` `buf` counts as empty
    under R26.
    +/
    this(byte[] buf, int length)
    {
        this(buf, 0, length);
    }

    /++
    Constructs a packet for sending `length` bytes from `buf` at `offset` to `address` and `port` (0 to 65535).
    A `null` `buf` counts as empty under R26.
    +/
    this(byte[] buf, int offset, int length, InetAddress address, int port)
    {
        setData(buf, offset, length);
        setAddress(address);
        setPort(port);
    }

    /++
    Constructs a packet for sending `length` bytes from `buf` at `offset` to the resolved `InetSocketAddress`
    `address`. A `null` `buf` counts as empty under R26.
    +/
    this(byte[] buf, int offset, int length, SocketAddress address)
    {
        setData(buf, offset, length);
        setSocketAddress(address);
    }

    /++
    Constructs a packet for sending `length` bytes from `buf` at offset 0 to `address` and `port` (0 to 65535).
    A `null` `buf` counts as empty under R26.
    +/
    this(byte[] buf, int length, InetAddress address, int port)
    {
        this(buf, 0, length, address, port);
    }

    /++
    Constructs a packet for sending `length` bytes from `buf` at offset 0 to the resolved `InetSocketAddress`
    `address`. A `null` `buf` counts as empty under R26.
    +/
    this(byte[] buf, int length, SocketAddress address)
    {
        this(buf, 0, length, address);
    }

    /// The remote IP address, or `null` if not set.
    InetAddress getAddress() @nogc
    {
        synchronized (this)
            return address;
    }

    /// The remote port number, or 0 if not set.
    int getPort() @nogc
    {
        synchronized (this)
            return port;
    }

    /// The backing data buffer (the same slice, not a copy).
    byte[] getData() @nogc
    {
        synchronized (this)
            return buf;
    }

    /// The starting offset of the packet data within the buffer.
    int getOffset() @nogc
    {
        synchronized (this)
            return offset;
    }

    /// The length of the packet data to send or receive.
    int getLength() @nogc
    {
        synchronized (this)
            return length;
    }

    /++
    Sets the backing buffer, `offset` and `length`. A `null` `buf` counts as empty under R26.
    +/
    void setData(byte[] buf, int offset, int length)
    {
        synchronized (this)
        {
            checkFromIndexSize(offset, length, buf.length);
            this.buf = buf;
            this.length = length;
            this.bufLength = length;
            this.offset = offset;
        }
    }

    /// Sets the remote IP address (`null` is permitted).
    void setAddress(InetAddress iaddr) @nogc
    {
        synchronized (this)
            address = iaddr;
    }

    /// Sets the remote port number, which must be from 0 to 65535.
    void setPort(int iport)
    {
        synchronized (this)
        {
            if (iport < 0 || iport > 0xFFFF)
                throwPortOutOfRange(iport);
            port = iport;
        }
    }

    /// Sets the remote address and port from a resolved `InetSocketAddress`.
    void setSocketAddress(SocketAddress address)
    {
        synchronized (this)
        {
            auto addr = cast(InetSocketAddress) address;
            if (addr is null)
                throwUnsupportedAddress();
            if (addr.isUnresolved())
                throwUnresolvedAddress();
            this.address = addr.getAddress();
            this.port = addr.getPort();
        }
    }

    /// Returns a new `InetSocketAddress` with this packet's IP address (or the wildcard address if `null`) and port.
    SocketAddress getSocketAddress()
    {
        synchronized (this)
            return new InetSocketAddress(address, port);
    }

    /++
    Sets the backing buffer, resetting `offset` to 0 and `length` to `buf.length`. A `null` `buf` counts as empty
    under R26.
    +/
    void setData(byte[] buf) @nogc
    {
        synchronized (this)
        {
            this.buf = buf;
            this.offset = 0;
            this.length = cast(int) buf.length;
            this.bufLength = cast(int) buf.length;
        }
    }

    /// Sets the length of the packet data, which must fit within `buf.length - offset`.
    void setLength(int length)
    {
        synchronized (this)
        {
            checkFromIndexSize(offset, length, buf.length);
            this.length = length;
            this.bufLength = length;
        }
    }
}

private void checkFromIndexSize(int offset, int length, size_t bufLength) pure
{
    if (offset < 0 || length < 0 || cast(long) offset + cast(long) length > cast(long) bufLength)
        throwOutOfBounds(offset, length, bufLength);
}

pragma(inline, false) private void throwOutOfBounds(int offset, int length, size_t bufLength) pure
{
    throw new IllegalArgumentException("Range [" ~ decimal(offset) ~ ", " ~ decimal(
            offset) ~ " + " ~ decimal(length) ~ ") out of bounds for length " ~ decimal(cast(ulong) bufLength));
}

pragma(inline, false) private void throwPortOutOfRange(int iport) pure
{
    throw new IllegalArgumentException("Port out of range:" ~ decimal(iport));
}

pragma(inline, false) private void throwUnsupportedAddress() pure
{
    throw new IllegalArgumentException("unsupported address type");
}

pragma(inline, false) private void throwUnresolvedAddress() pure
{
    throw new IllegalArgumentException("unresolved address");
}
