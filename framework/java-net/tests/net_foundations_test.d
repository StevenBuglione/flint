// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.net_foundations_test;

import flint.java.net.protocolfamily : ProtocolFamily;
import flint.java.net.socketaddress : SocketAddress;
import flint.java.net.standardprotocolfamily : StandardProtocolFamily, name;

@safe:

private final class DummySocketAddress : SocketAddress
{
    immutable string label;

    this(string label) pure nothrow @nogc
    {
        super();
        this.label = label;
    }
}

private final class CustomProtocolFamily : ProtocolFamily
{
    private immutable string familyName;

    this(string familyName) pure nothrow @nogc
    {
        this.familyName = familyName;
    }

    override string name()
    {
        return familyName;
    }
}

unittest
{
    // SocketAddress is abstract and meant to be subclassed via its public no-arg constructor.
    static assert(__traits(isAbstractClass, SocketAddress));
    static assert(!__traits(compiles, new SocketAddress()));
    SocketAddress addr = new DummySocketAddress("local");
    assert(addr !is null);
    auto concrete = cast(DummySocketAddress) addr;
    assert(concrete !is null && concrete.label == "local");
}

unittest
{
    // ProtocolFamily interface and StandardProtocolFamily enum (R18 + R20).
    ProtocolFamily custom = new CustomProtocolFamily("CUSTOM");
    assert(custom.name() == "CUSTOM");

    assert(cast(int) StandardProtocolFamily.INET == 0);
    assert(cast(int) StandardProtocolFamily.INET6 == 1);
    assert(cast(int) StandardProtocolFamily.UNIX == 2);
    assert(StandardProtocolFamily.INET.name() == "INET");
    assert(StandardProtocolFamily.INET6.name() == "INET6");
    assert(StandardProtocolFamily.UNIX.name() == "UNIX");
}
