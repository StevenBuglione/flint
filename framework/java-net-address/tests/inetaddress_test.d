// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.inetaddress_test;

import flint.engine.aot.text : decimal;
import flint.java.net.inetaddress : Inet4Address, Inet6Address, InetAddress;
import flint.java.net.unknownhostexception : UnknownHostException;
import flint.java.io : IOException;
import std.typecons : Nullable;

@safe:

// Cases and expected rows from pinned Temurin 21.0.13+9 (InetAddressOracle.java over inputs.tsv): case, api, host
// (<null> for an absent host), address bytes in hex, scope id.
private static immutable string inputs = import("inetaddress/inputs.tsv");

private static immutable string expected = import("inetaddress/temurin.tsv");

private string[] fields(string line) pure nothrow
{
    string[] result;
    size_t start;
    foreach (i, c; line)
        if (c == '\t')
        {
            result ~= line[start .. i];
            start = i + 1;
        }
    return result ~ line[start .. $];
}

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
    if (start < text.length)
        result ~= text[start .. $];
    return result;
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

private string formatHex(scope const(ubyte)[] bytes) pure nothrow
{
    static immutable digits = "0123456789abcdef";
    char[] result;
    foreach (b; bytes)
        result ~= [digits[b >> 4], digits[b & 15]];
    return result.idup;
}

private int parseInt(string text) pure nothrow @nogc
{
    const negative = text.length > 0 && text[0] == '-';
    long value;
    foreach (c; text[negative .. $])
        value = value * 10 + (c - '0');
    return cast(int)(negative ? -value : value);
}

private string row(string name, InetAddress a)
{
    string result = name ~ "\t" ~ (cast(Inet6Address) a !is null ? "Inet6Address" : "Inet4Address");
    result ~= "\t" ~ a.toString() ~ "\t" ~ a.getHostAddress() ~ "\t" ~ formatHex(a.getAddress());
    result ~= "\t" ~ decimal(a.hashCode()) ~ "\t";
    foreach (flag; [
        a.isMulticastAddress(), a.isAnyLocalAddress(), a.isLoopbackAddress(),
        a.isLinkLocalAddress(), a.isSiteLocalAddress(), a.isMCGlobal(), a.isMCNodeLocal(),
        a.isMCLinkLocal(), a.isMCSiteLocal(), a.isMCOrgLocal()
    ])
        result ~= flag ? '1' : '0';
    if (auto v6 = cast(Inet6Address) a)
        result ~= "\t" ~ decimal(v6.getScopeId()) ~ "\t" ~ (v6.isIPv4CompatibleAddress() ? "1" : "0");
    return result;
}

unittest
{
    // Every row of the Temurin oracle, including the pairwise equality matrix.
    string[] actual;
    InetAddress[] built;
    string[] names;
    foreach (line; lines(inputs))
    {
        auto f = fields(line);
        auto addr = parseHex(f[3]);
        const absent = f[2] == "<null>";
        InetAddress a;
        try
        {
            switch (f[1])
            {
            case "addr":
                a = InetAddress.getByAddress(addr);
                break;
            case "host":
                a = absent ? InetAddress.getByAddress(Nullable!string.init,
                        addr) : InetAddress.getByAddress(f[2], addr);
                break;
            case "scoped":
                a = absent ? Inet6Address.getByAddress(Nullable!string.init, addr,
                        parseInt(f[4])) : Inet6Address.getByAddress(f[2], addr, parseInt(f[4]));
                break;
            default:
                a = InetAddress.getLoopbackAddress();
            }
        }
        catch (UnknownHostException e)
        {
            actual ~= f[0] ~ "\tUnknownHostException\t" ~ e.getMessage();
            continue;
        }
        built ~= a;
        names ~= f[0];
        actual ~= row(f[0], a);
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
    // getAddress returns a fresh copy, so callers cannot change the address.
    auto a = InetAddress.getByAddress(cast(ubyte[])[10, 0, 0, 1]);
    auto bytes = a.getAddress();
    bytes[0] = 99;
    assert(a.getHostAddress() == "10.0.0.1");
    ubyte[] v6 = new ubyte[16];
    v6[15] = 1;
    auto b = InetAddress.getByAddress(v6);
    v6[15] = 2;
    assert(b.getHostAddress() == "0:0:0:0:0:0:0:1");
    auto copy = b.getAddress();
    copy[15] = 3;
    assert(b.getHostAddress() == "0:0:0:0:0:0:0:1");
}

unittest
{
    // R26: a null address counts as empty and fails with Java's message; R5: an absent host differs from "".
    try
    {
        InetAddress.getByAddress(null);
        assert(false);
    }
    catch (UnknownHostException e)
        assert(e.getMessage() == "addr is of illegal length");
    static assert(is(UnknownHostException : IOException));
    auto named = InetAddress.getByAddress(cast(string) null, cast(ubyte[])[1, 2, 3, 4]);
    assert(named.toString() == "/1.2.3.4");
}

unittest
{
    // equals and hashCode follow Java through D's ==, Object references and associative arrays.
    auto x = InetAddress.getByAddress("x.test", cast(ubyte[])[192, 168, 1, 1]);
    auto mapped = InetAddress.getByAddress(cast(ubyte[])[
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 192, 168, 1, 1
    ]);
    assert(x == mapped);
    Object o = mapped;
    assert(x.equals(o) && !x.equals(null));
    int[InetAddress] seen;
    seen[x] = 1;
    assert(mapped in seen);
    ubyte[] compat = new ubyte[16];
    compat[12 .. 16] = [192, 168, 1, 1];
    assert(InetAddress.getByAddress(compat) != x);
    static assert(!__traits(compiles, new InetAddress()));
}
