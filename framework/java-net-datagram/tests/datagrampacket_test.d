// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.datagrampacket_test;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException;
import flint.java.net.datagrampacket : DatagramPacket;
import flint.java.net.inetaddress : InetAddress;
import flint.java.net.inetsocketaddress : InetSocketAddress;
import flint.java.net.socketaddress : SocketAddress;

@safe:

// Rows from pinned Temurin 21.0.13+9 (DatagramPacketOracle.java): key, tab, value.
// Every non-R26 row is computed below and matched byte-for-byte; the 5 trailing r26-* rows
// document Java's NullPointerException on null byte[] and are verified separately under R26.
private static immutable string expected = import("datagrampacket/temurin.tsv");

private final class CustomSocketAddress : SocketAddress
{
    this() pure nothrow @nogc
    {
        super();
    }
}

private string flag(bool value) pure nothrow @nogc
{
    return value ? "true" : "false";
}

private string catchEx(scope void delegate() @safe action)
{
    try
    {
        action();
        return "OK";
    }
    catch (IllegalArgumentException e)
    {
        return "IllegalArgumentException:" ~ (e.msg is null ? "null" : e.msg);
    }
}

private void appendRow(ref string rows, string key, string value) pure nothrow
{
    rows ~= key ~ "\t" ~ value ~ "\n";
}

private void observedConstructors(ref string rows, byte[] b10, InetAddress lo, InetAddress v4,
        InetAddress v6, out DatagramPacket p2, out DatagramPacket p3)
{
    auto p1 = new DatagramPacket(b10, 6);
    appendRow(rows, "ctor-2-same-buf", flag(p1.getData() is b10));
    appendRow(rows, "ctor-2-offset", decimal(p1.getOffset()));
    appendRow(rows, "ctor-2-length", decimal(p1.getLength()));
    appendRow(rows, "ctor-2-addr-null", flag(p1.getAddress() is null));
    appendRow(rows, "ctor-2-port", decimal(p1.getPort()));
    auto sa1 = cast(InetSocketAddress) p1.getSocketAddress();
    assert(sa1 !is null);
    appendRow(rows, "ctor-2-sa-anylocal", flag(sa1.getAddress().isAnyLocalAddress()));
    appendRow(rows, "ctor-2-sa-str", sa1.toString());

    p2 = new DatagramPacket(b10, 3, 5);
    appendRow(rows, "ctor-3-offset", decimal(p2.getOffset()));
    appendRow(rows, "ctor-3-length", decimal(p2.getLength()));
    appendRow(rows, "ctor-3-addr-null", flag(p2.getAddress() is null));
    appendRow(rows, "ctor-3-port", decimal(p2.getPort()));

    p3 = new DatagramPacket(b10, 2, 4, v4, 5353);
    appendRow(rows, "ctor-5-offset", decimal(p3.getOffset()));
    appendRow(rows, "ctor-5-length", decimal(p3.getLength()));
    appendRow(rows, "ctor-5-addr", p3.getAddress().getHostAddress());
    appendRow(rows, "ctor-5-port", decimal(p3.getPort()));
    auto p3sa = cast(InetSocketAddress) p3.getSocketAddress();
    assert(p3sa !is null);
    appendRow(rows, "ctor-5-sa", p3sa.toString());

    auto p4 = new DatagramPacket(b10, 7, v6, 65_535);
    appendRow(rows, "ctor-4-ip-offset", decimal(p4.getOffset()));
    appendRow(rows, "ctor-4-ip-length", decimal(p4.getLength()));
    appendRow(rows, "ctor-4-ip-addr", p4.getAddress().getHostAddress());
    appendRow(rows, "ctor-4-ip-port", decimal(p4.getPort()));
    auto p4sa = cast(InetSocketAddress) p4.getSocketAddress();
    assert(p4sa !is null);
    appendRow(rows, "ctor-4-ip-sa", p4sa.toString());

    auto p4null = new DatagramPacket(b10, 2, 3, cast(InetAddress) null, 0);
    appendRow(rows, "ctor-5-null-addr", flag(p4null.getAddress() is null));
    appendRow(rows, "ctor-5-null-port", decimal(p4null.getPort()));

    auto isa = new InetSocketAddress(v4, 8080);
    auto p5 = new DatagramPacket(b10, 1, 8, isa);
    appendRow(rows, "ctor-4-sa-offset", decimal(p5.getOffset()));
    appendRow(rows, "ctor-4-sa-length", decimal(p5.getLength()));
    appendRow(rows, "ctor-4-sa-addr", p5.getAddress().getHostAddress());
    appendRow(rows, "ctor-4-sa-port", decimal(p5.getPort()));

    auto p6 = new DatagramPacket(b10, 10, new InetSocketAddress(lo, 0));
    appendRow(rows, "ctor-3-sa-offset", decimal(p6.getOffset()));
    appendRow(rows, "ctor-3-sa-length", decimal(p6.getLength()));
    appendRow(rows, "ctor-3-sa-addr", p6.getAddress().getHostAddress());
    appendRow(rows, "ctor-3-sa-port", decimal(p6.getPort()));

    p1.getData()[0] = 42;
    appendRow(rows, "buf-write-through", decimal(cast(int) b10[0]));
    auto idA = new DatagramPacket(b10, 0);
    auto idB = new DatagramPacket(b10, 0);
    appendRow(rows, "identity-neq", flag(idA is idB));
}

private void observedSetters(ref string rows, byte[] b10, InetAddress v6, DatagramPacket p2, DatagramPacket p3)
{
    byte[] b20 = new byte[20];
    p2.setData(b20);
    appendRow(rows, "setData1-same", flag(p2.getData() is b20));
    appendRow(rows, "setData1-offset", decimal(p2.getOffset()));
    appendRow(rows, "setData1-length", decimal(p2.getLength()));

    p2.setData(b10, 4, 6);
    appendRow(rows, "setData3-offset", decimal(p2.getOffset()));
    appendRow(rows, "setData3-length", decimal(p2.getLength()));
    p2.setLength(2);
    appendRow(rows, "setLength-ok-len", decimal(p2.getLength()));
    appendRow(rows, "setLength-ok-off", decimal(p2.getOffset()));
    p2.setLength(6);
    appendRow(rows, "setLength-max-ok", decimal(p2.getLength()));
    p2.setLength(0);
    appendRow(rows, "setLength-zero-ok", decimal(p2.getLength()));

    p3.setAddress(null);
    appendRow(rows, "setAddress-null", flag(p3.getAddress() is null));
    p3.setPort(0);
    appendRow(rows, "setPort-0", decimal(p3.getPort()));
    p3.setPort(65_535);
    appendRow(rows, "setPort-65535", decimal(p3.getPort()));
    p3.setSocketAddress(new InetSocketAddress(v6, 443));
    appendRow(rows, "setSA-addr", p3.getAddress().getHostAddress());
    appendRow(rows, "setSA-port", decimal(p3.getPort()));

    byte[] empty = [];
    auto pe = new DatagramPacket(empty, 0, 0);
    appendRow(rows, "empty-len", decimal(pe.getLength()));
    appendRow(rows, "empty-off", decimal(pe.getOffset()));
    pe.setData(empty);
    appendRow(rows, "empty-setData1-len", decimal(pe.getLength()));
}

private void observedBufferExceptions(ref string rows, byte[] b10, DatagramPacket p2)
{
    appendRow(rows, "ex-neg-len", catchEx(() { new DatagramPacket(b10, -1); }));
    appendRow(rows, "ex-len-too-big", catchEx(() { new DatagramPacket(b10, 11); }));
    appendRow(rows, "ex-neg-off", catchEx(() { new DatagramPacket(b10, -1, 1); }));
    appendRow(rows, "ex-off-plus-len", catchEx(() { new DatagramPacket(b10, 6, 5); }));
    appendRow(rows, "ex-overflow", catchEx(() { new DatagramPacket(b10, int.max, 1); }));
    appendRow(rows, "ex-overflow-2", catchEx(() { new DatagramPacket(b10, 1, int.max); }));
    appendRow(rows, "ex-setLength-neg", catchEx(() { p2.setLength(-1); }));
    appendRow(rows, "ex-setLength-too-big", catchEx(() { p2.setLength(7); }));
    appendRow(rows, "ex-setLength-overflow", catchEx(() { p2.setLength(int.max); }));
}

private void observedAddressExceptions(ref string rows, byte[] b10, InetAddress lo, DatagramPacket p3)
{
    appendRow(rows, "ex-port-neg", catchEx(() { p3.setPort(-1); }));
    appendRow(rows, "ex-port-neg-666", catchEx(() { p3.setPort(-666); }));
    appendRow(rows, "ex-port-65536", catchEx(() { p3.setPort(65_536); }));
    appendRow(rows, "ex-port-max", catchEx(() { p3.setPort(int.max); }));
    appendRow(rows, "ex-ctor-port-neg", catchEx(() { new DatagramPacket(b10, 10, lo, -1); }));
    appendRow(rows, "ex-ctor-port-high", catchEx(() { new DatagramPacket(b10, 10, lo, 65_536); }));
    appendRow(rows, "ex-sa-null", catchEx(() { p3.setSocketAddress(null); }));
    appendRow(rows, "ex-sa-custom", catchEx(() { p3.setSocketAddress(new CustomSocketAddress()); }));
    appendRow(rows, "ex-sa-unresolved", catchEx(() {
            p3.setSocketAddress(InetSocketAddress.createUnresolved("foo.bar", 161));
        }));
    appendRow(rows, "ex-ctor-sa-null", catchEx(() {
            new DatagramPacket(b10, 10, cast(SocketAddress) null);
        }));
    appendRow(rows, "ex-ctor-sa-unresolved", catchEx(() {
            new DatagramPacket(b10, 10, InetSocketAddress.createUnresolved("foo.bar", 161));
        }));
    appendRow(rows, "ex-order-buf-before-port", catchEx(() { new DatagramPacket(b10, 11, lo, -1); }));
    appendRow(rows, "ex-order-buf-before-sa", catchEx(() {
            new DatagramPacket(b10, 11, cast(SocketAddress) null);
        }));
}

private string observed()
{
    string rows;
    byte[] b10 = new byte[10];
    foreach (i; 0 .. b10.length)
        b10[i] = cast(byte)(cast(int) i - 5);
    auto lo = InetAddress.getLoopbackAddress();
    const ubyte[4] v4Bytes = [10, 0, 0, 1];
    auto v4 = InetAddress.getByAddress(v4Bytes[]);
    auto v6 = InetAddress.getByName("2001:db8::1");

    DatagramPacket p2;
    DatagramPacket p3;
    observedConstructors(rows, b10, lo, v4, v6, p2, p3);
    observedSetters(rows, b10, v6, p2, p3);
    observedBufferExceptions(rows, b10, p2);
    observedAddressExceptions(rows, b10, lo, p3);
    return rows;
}

unittest
{
    enum r26Tail = "r26-ctor-null-0\tNullPointerException:null\n" ~ "r26-ctor-null-10\tNullPointerException:null\n"
        ~ "r26-setData1-null\tNullPointerException:null packet buffer\n"
        ~ "r26-setData3-null-0-0\tNullPointerException:null\n" ~ "r26-setData3-null-0-1\tNullPointerException:null\n";
    assert(expected.length > r26Tail.length && expected[$ - r26Tail.length .. $] == r26Tail);
    assert(observed() == expected[0 .. $ - r26Tail.length]);
}

unittest
{
    // R26: null byte[] counts as empty [] where Java throws NullPointerException.
    auto p0 = new DatagramPacket(null, 0);
    assert(p0.getData().length == 0 && p0.getOffset() == 0 && p0.getLength() == 0);

    auto p3 = new DatagramPacket(null, 0, 0);
    assert(p3.getData().length == 0 && p3.getOffset() == 0 && p3.getLength() == 0);

    // Nonzero length on null buffer fails bounds check with IllegalArgumentException.
    enum oob10 = "IllegalArgumentException:Range [0, 0 + 10) out of bounds for length 0";
    assert(catchEx(() { new DatagramPacket(null, 10); }) == oob10);
    assert(catchEx(() { new DatagramPacket(null, 0, 10); }) == oob10);

    // setData(null) resets to empty buffer with offset 0 and length 0.
    byte[] buf = new byte[8];
    auto p = new DatagramPacket(buf, 2, 4);
    p.setData(null);
    assert(p.getData().length == 0 && p.getOffset() == 0 && p.getLength() == 0);

    p.setData(null, 0, 0);
    assert(p.getData().length == 0 && p.getOffset() == 0 && p.getLength() == 0);
    enum oob1 = "IllegalArgumentException:Range [0, 0 + 1) out of bounds for length 0";
    assert(catchEx(() { p.setData(null, 0, 1); }) == oob1);
}

unittest
{
    // Request-path getters and simple setters allocate nothing (@nogc).
    byte[] buf = new byte[16];
    auto lo = InetAddress.getLoopbackAddress();
    auto p = new DatagramPacket(buf, 2, 6, lo, 1234);

    void checkNoGc() @safe @nogc
    {
        assert(p.getData() is buf);
        assert(p.getOffset() == 2);
        assert(p.getLength() == 6);
        assert(p.getAddress() is lo);
        assert(p.getPort() == 1234);
        p.setAddress(null);
        assert(p.getAddress() is null);
        p.setAddress(lo);
        p.setData(buf);
        assert(p.getOffset() == 0 && p.getLength() == 16);
    }

    checkNoGc();
}
