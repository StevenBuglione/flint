// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.inetsocketaddress_test;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException;
import flint.java.net.inetaddress : Inet6Address, InetAddress;
import flint.java.net.inetsocketaddress : InetSocketAddress;
import flint.java.net.socketaddress : SocketAddress;
import std.typecons : Nullable;

@safe:

// Cases and expected rows from pinned Temurin 21.0.13+9 (InetSocketAddressOracle.java over inputs.tsv): case, api
// (port, addr or unresolved), host (<null> for an absent host), address bytes in hex (- for a null InetAddress),
// scope id (-1 for none), port.
private static immutable string inputs = import("inetsocketaddress/inputs.tsv");

private static immutable string expected = import("inetsocketaddress/temurin.tsv");

private string[] split(string text, char separator) pure nothrow
{
    string[] result;
    size_t start;
    foreach (i, c; text)
        if (c == separator)
        {
            result ~= text[start .. i];
            start = i + 1;
        }
    return result ~ text[start .. $];
}

private string[] lines(string text) pure nothrow
{
    auto result = split(text, '\n');
    return result.length > 0 && result[$ - 1].length == 0 ? result[0 .. $ - 1] : result;
}

private int hexDigit(char c) pure nothrow @nogc
{
    return c <= '9' ? c - '0' : c - 'a' + 10;
}

private ubyte[] parseHex(string text) pure nothrow
{
    auto result = new ubyte[text.length / 2];
    foreach (i, ref b; result)
        b = cast(ubyte)(hexDigit(text[2 * i]) << 4 | hexDigit(text[2 * i + 1]));
    return result;
}

private int parseInt(string text) pure nothrow @nogc
{
    const negative = text.length > 0 && text[0] == '-';
    long value;
    foreach (c; text[negative .. $])
        value = value * 10 + (c - '0');
    return cast(int)(negative ? -value : value);
}

private InetSocketAddress build(string[] f)
{
    const host = f[2] == "<null>" ? Nullable!string.init : Nullable!string(f[2]);
    const port = parseInt(f[5]);
    switch (f[1])
    {
    case "port":
        return new InetSocketAddress(port);
    case "unresolved":
        return InetSocketAddress.createUnresolved(f[2], port);
    default:
        InetAddress a;
        if (f[3] != "-")
        {
            const scope_ = parseInt(f[4]);
            a = scope_ >= 0 ? Inet6Address.getByAddress(host, parseHex(f[3]),
                    scope_) : InetAddress.getByAddress(host, parseHex(f[3]));
        }
        return new InetSocketAddress(a, port);
    }
}

private string row(string name, InetSocketAddress s)
{
    auto a = s.getAddress();
    return name ~ "\t" ~ s.toString() ~ "\t" ~ decimal(s.getPort()) ~ "\t" ~ s.getHostString() ~ "\t" ~ (
            s.isUnresolved() ? "1" : "0") ~ "\t" ~ decimal(s.hashCode()) ~ "\t" ~ (a is null ? "-" : a.toString());
}

unittest
{
    // Every row of the Temurin oracle, including the pairwise equality matrix. The one exception is u-null: under
    // R26 a null host string counts as "", so it is checked separately below instead of throwing.
    string[] actual;
    InetSocketAddress[] built;
    string[] names;
    foreach (line; lines(inputs))
    {
        auto f = split(line, '\t');
        if (f[0] == "u-null")
        {
            actual ~= "u-null\tIllegalArgumentException\thostname can't be null";
            continue;
        }
        InetSocketAddress s;
        try
            s = build(f);
        catch (IllegalArgumentException e)
        {
            actual ~= f[0] ~ "\tIllegalArgumentException\t" ~ e.getMessage();
            continue;
        }
        built ~= s;
        names ~= f[0];
        actual ~= row(f[0], s);
    }
    foreach (i; 0 .. built.length)
        foreach (j; i + 1 .. built.length)
            if (built[i].equals(built[j]))
                actual ~= "equal\t" ~ names[i] ~ "\t" ~ names[j] ~ "\t" ~ (built[j].equals(built[i])
                        ? "symmetric" : "asymmetric");
    const want = lines(expected);
    assert(actual.length == want.length);
    foreach (i, line; actual)
        assert(line == want[i], line);
}

unittest
{
    // R26: a null host string is the empty host name, so createUnresolved keeps it instead of throwing.
    auto s = InetSocketAddress.createUnresolved(null, 80);
    assert(s.isUnresolved() && s.getHostString() == "" && s.toString() == "/<unresolved>:80");
    assert(s == InetSocketAddress.createUnresolved("", 80) && s.hashCode() == 80);
}

unittest
{
    // equals and hashCode follow Java through D's ==, Object references and associative arrays.
    auto upper = InetSocketAddress.createUnresolved("Example.COM", 443);
    auto lower = InetSocketAddress.createUnresolved("example.com", 443);
    SocketAddress base = upper;
    assert(lower == upper && lower.equals(base) && !lower.equals(null));
    int[InetSocketAddress] seen;
    seen[lower] = 1;
    assert(upper in seen);
    ubyte[] bytes = [10, 0, 0, 1];
    auto resolved = new InetSocketAddress(InetAddress.getByAddress("example.com", bytes), 443);
    assert(resolved != lower && lower != resolved);
    assert(resolved.getAddress() !is null && lower.getAddress() is null);
    static assert(is(InetSocketAddress : SocketAddress));
}

unittest
{
    // The wildcard address of new InetSocketAddress(port) is a fresh 0.0.0.0 named "0.0.0.0".
    auto a = new InetSocketAddress(8080);
    auto b = new InetSocketAddress(cast(InetAddress) null, 8080);
    assert(a.getAddress() !is b.getAddress() && a == b);
    // As in Java, a bare null matches both the (InetAddress, int) and (String, int) constructors.
    static assert(!__traits(compiles, new InetSocketAddress(null, 8080)));
    assert(a.getAddress().isAnyLocalAddress() && a.getHostString() == "0.0.0.0");
}
