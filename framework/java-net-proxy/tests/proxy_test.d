// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.proxy_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.net.inetsocketaddress : InetSocketAddress;
import flint.java.net.proxy : Proxy;
import flint.java.net.socketaddress : SocketAddress;

@safe:

// Expected rows from pinned Temurin 21.0.13+9 (ProxyOracle.java): constructor errors, then for each proxy its type,
// toString and address, then the equality matrix. Java's Proxy.hashCode uses the enum's identity hash, so it has no
// oracle row; the test checks the ordinal-based hash below instead.
private static immutable string expected = import("proxy/temurin.tsv");

private string[] lines(string text) pure nothrow
{
    string[] result;
    size_t start;
    foreach (i, c; text)
        if (c == '\n')
        {
            result ~= text[start .. i];
            start = i + 1;
        }
    return start < text.length ? result ~ text[start .. $] : result;
}

private string attempt(Proxy.Type type, SocketAddress sa)
{
    try
        return new Proxy(type, sa).toString();
    catch (IllegalArgumentException e)
        return "IllegalArgumentException: " ~ e.msg;
}

private string typeText(Proxy.Type type) pure nothrow
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

private string digit(size_t value) pure nothrow
{
    immutable string digits = "0123456789";
    return digits[value .. value + 1];
}

private Proxy[] proxies()
{
    auto u = InetSocketAddress.createUnresolved("Proxy.Example", 3128);
    auto u2 = InetSocketAddress.createUnresolved("proxy.example", 3128);
    auto b = new InetSocketAddress("10.0.0.1", 1080);
    auto v6 = new InetSocketAddress("::1", 8080);
    return [
        new Proxy(Proxy.Type.HTTP, u), new Proxy(Proxy.Type.HTTP, u2), new Proxy(Proxy.Type.SOCKS,
                u), new Proxy(Proxy.Type.HTTP, b), new Proxy(Proxy.Type.SOCKS, b),
        new Proxy(Proxy.Type.HTTP, v6)
    ];
}

@("Proxy matches Temurin 21.0.13+9 for construction, toString, address and equals")
unittest
{
    auto u = InetSocketAddress.createUnresolved("Proxy.Example", 3128);
    string[] actual;
    actual ~= "ctor-direct-u\t" ~ attempt(Proxy.Type.DIRECT, u);
    actual ~= "ctor-http-null\t" ~ attempt(Proxy.Type.HTTP, null);
    actual ~= "ctor-socks-null\t" ~ attempt(Proxy.Type.SOCKS, null);
    actual ~= "ctor-direct-null\t" ~ attempt(Proxy.Type.DIRECT, null);
    auto ps = proxies();
    foreach (i, p; ps)
    {
        const address = (cast(InetSocketAddress) p.address()).toString();
        actual ~= "p" ~ digit(i) ~ "\t" ~ typeText(p.type()) ~ "\t" ~ p.toString() ~ "\t" ~ address;
    }
    foreach (i, p; ps)
        foreach (j, q; ps)
            actual ~= "eq\tp" ~ digit(i) ~ "\tp" ~ digit(j) ~ "\t" ~ (p.equals(q) ? "true" : "false");
    actual ~= "eq-null\t" ~ (ps[0].equals(null) ? "true" : "false");
    actual ~= "eq-addr\t" ~ (ps[0].equals(u) ? "true" : "false");

    const rows = lines(expected);
    assert(actual.length == rows.length);
    foreach (i, row; rows)
        assert(actual[i] == row, actual[i]);
}

@("Proxy.hashCode is the type's ordinal plus the address's hash, so equal proxies hash equally")
unittest
{
    auto ps = proxies();
    foreach (p; ps)
        assert(p.hashCode() == p.type() + (cast(InetSocketAddress) p.address()).hashCode());
    assert(ps[0].hashCode() == ps[1].hashCode());
    assert(ps[0] == ps[1]);
    assert(ps[0] != ps[2]);
    int[Object] seen;
    seen[ps[0]] = 1;
    assert(ps[1] in seen);
}

@("Proxy.Type has Java's declaration order")
unittest
{
    static assert(Proxy.Type.DIRECT == 0 && Proxy.Type.HTTP == 1 && Proxy.Type.SOCKS == 2);
    static assert([__traits(allMembers, Proxy.Type)] == ["DIRECT", "HTTP", "SOCKS"]);
}
