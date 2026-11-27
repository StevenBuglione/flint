// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.inetsocketaddress_literal_test;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException;
import flint.java.net.inetaddress : Inet6Address, InetAddress;
import flint.java.net.inetsocketaddress : InetSocketAddress;
import std.utf : encode;

@safe:

// The InetSocketAddress(String, int) rows of pinned Temurin 21.0.13+9's literal-resolution oracle
// (LiteralResolutionOracle.java; its InetAddress rows are in framework/java-net-address): case, kind (sock), host
// with backslash-u escapes (<null> for null), port.
private static immutable string inputs = import("literalresolution/inputs.tsv");

private static immutable string expected = import("literalresolution/temurin.tsv");

private string[] split(string line, char separator) pure nothrow
{
    string[] result;
    size_t start;
    foreach (i, c; line)
        if (c == separator)
        {
            result ~= line[start .. i];
            start = i + 1;
        }
    return result ~ line[start .. $];
}

private string[] lines(string text) pure nothrow
{
    auto result = split(text, '\n');
    return result.length > 0 && result[$ - 1].length == 0 ? result[0 .. $ - 1] : result;
}

private int hexValue(string digits) pure nothrow @nogc
{
    int value;
    foreach (c; digits)
        value = value << 4 | (c <= '9' ? c - '0' : (c | 0x20) - 'a' + 10);
    return value;
}

private string unescape(string text) pure
{
    char[] result;
    for (size_t i = 0; i < text.length; ++i)
    {
        if (text[i] == '\\' && i + 6 <= text.length && text[i + 1] == 'u')
        {
            encode(result, cast(dchar) hexValue(text[i + 2 .. i + 6]));
            i += 5;
        }
        else
            result ~= text[i];
    }
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

private string describe(const InetAddress a) pure nothrow
{
    static immutable string kinds = "Inet4Address|Inet6Address|";
    auto v6 = cast(const Inet6Address) a;
    string result = (v6 is null ? kinds[0 .. 13] : kinds[13 .. $]) ~ a.toString() ~ "|";
    result ~= (v6 is null ? "-" : decimal(v6.getScopeId())) ~ "|";
    const bool[10] flags = [
        a.isMulticastAddress(), a.isAnyLocalAddress(), a.isLoopbackAddress(),
        a.isLinkLocalAddress(), a.isSiteLocalAddress(), a.isMCGlobal(), a.isMCNodeLocal(),
        a.isMCLinkLocal(), a.isMCSiteLocal(), a.isMCOrgLocal()
    ];
    foreach (flag; flags)
        result ~= flag ? '1' : '0';
    return result;
}

private string run(string host, int port)
{
    try
    {
        auto s = new InetSocketAddress(host, port);
        return "ok\t" ~ s.toString() ~ "\t" ~ (s.isUnresolved()
                ? "true" : "false") ~ "\t" ~ s.getHostString() ~ "\t" ~ decimal(s.hashCode()) ~ "\t" ~ (
                s.getAddress() is null ? "-" : describe(s.getAddress()));
    }
    catch (IllegalArgumentException e)
        return "ex\tIllegalArgumentException\t" ~ e.getMessage() ~ "\t-";
}

unittest
{
    // Every row of the oracle. A host name stays unresolved, as in Java when the name service finds nothing
    // (D-JDK-8). sock-null differs by R26 (a null host string is "", so the address is the loopback address
    // instead of IllegalArgumentException).
    const want = lines(expected);
    const cases = lines(inputs);
    assert(cases.length == want.length && cases.length == 28);
    foreach (i, line; cases)
    {
        auto f = split(line, '\t');
        assert(f[1] == "sock");
        const host = f[2] == "<null>" ? null : unescape(f[2]);
        auto actual = f[0] ~ "\t" ~ run(host, parseInt(f[3]));
        if (f[0] == "sock-null")
        {
            assert(actual == "sock-null\tok\tlocalhost/127.0.0.1:80\tfalse\tlocalhost\t2130706513\t"
                    ~ "Inet4Address|localhost/127.0.0.1|-|0010000000", actual);
            assert(want[i] == "sock-null\tex\tIllegalArgumentException\thostname can't be null\t-");
        }
        else
            assert(actual == want[i], actual ~ "\n" ~ want[i]);
    }
}

unittest
{
    // An interface-name scope needs NetworkInterface, which Flint lacks, so the address stays unresolved.
    auto unresolved = new InetSocketAddress("fe80::1%lo", 7);
    assert(unresolved.isUnresolved() && unresolved.getHostString() == "fe80::1%lo");
}
