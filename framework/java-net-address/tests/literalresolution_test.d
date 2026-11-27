// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.literalresolution_test;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException;
import flint.java.net.inetaddress : Inet6Address, InetAddress;
import flint.java.net.unknownhostexception : UnknownHostException;
import std.utf : encode;

@safe:

// Cases and expected rows from pinned Temurin 21.0.13+9 (LiteralResolutionOracle.java over inputs.tsv): case,
// kind (all = getAllByName, one = getByName, sock = InetSocketAddress(String, int), lookup = getAllByName of a host
// that reaches the name service), host with backslash-u escapes (<null> for null), port.
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

private string failure(string kind, string message, Throwable cause) pure nothrow
{
    string causeText = "-";
    if (auto iae = cast(IllegalArgumentException) cause)
        causeText = "IllegalArgumentException: " ~ iae.getMessage();
    return "ex\t" ~ kind ~ "\t" ~ message ~ "\t" ~ causeText;
}

private string run(string kind, string host)
{
    try
    {
        switch (kind)
        {
        case "one":
            return "ok\t1\t" ~ describe(InetAddress.getByName(host));
        default:
            auto all = InetAddress.getAllByName(host);
            string result = "ok\t" ~ decimal(cast(int) all.length);
            foreach (a; all)
                result ~= "\t" ~ describe(a);
            return result;
        }
    }
    catch (UnknownHostException e)
        return failure("UnknownHostException", e.getMessage(), e.getCause());
    catch (IllegalArgumentException e)
        return failure("IllegalArgumentException", e.getMessage(), null);
}

unittest
{
    // Every InetAddress row of the Temurin oracle; the sock rows (InetSocketAddress) wait for its package. A lookup
    // row reaches the name service, which Flint does not have yet: both sides throw UnknownHostException, and
    // Flint's message is the host name.
    static immutable string[] lookupFailure = ["ex", "UnknownHostException"];
    const want = lines(expected);
    const cases = lines(inputs);
    assert(cases.length == want.length);
    foreach (i, line; cases)
    {
        auto f = split(line, '\t');
        if (f[1] == "sock")
            continue;
        const host = f[2] == "<null>" ? null : unescape(f[2]);
        auto actual = f[0] ~ "\t" ~ run(f[1], host);
        if (f[1] == "lookup")
        {
            assert(actual == f[0] ~ "\tex\tUnknownHostException\t" ~ host ~ "\t-", actual);
            assert(split(want[i], '	')[1 .. 3] == lookupFailure, want[i]);
        }
        else
            assert(actual == want[i], actual ~ "\n" ~ want[i]);
    }
}

unittest
{
    // Each call returns a new array, and literal addresses carry no host name.
    auto first = InetAddress.getAllByName("10.1.2.3");
    first[0] = null;
    auto second = InetAddress.getAllByName("10.1.2.3");
    assert(second.length == 1 && second[0].toString() == "/10.1.2.3");
}

unittest
{
    // Upstream's fallback when the resolver fails for localhost, ignoring case. With a real resolver Java keeps the
    // queried spelling ("LOCALHOST/127.0.0.1") and also returns ::1 when /etc/hosts lists it; these rows wait for
    // the engine host-name resolver.
    auto all = InetAddress.getAllByName("LocalHost");
    assert(all.length == 1 && all[0].toString() == "localhost/127.0.0.1");
    // U+017F (long s) upper-cases to 'S', so it matches; nothing else beyond ASCII case does.
    foreach (spelling; ["LOCALHO\u017FT", "localho\u017ft"])
        assert(InetAddress.getByName(spelling).isLoopbackAddress());
    static immutable string[] unknown = [
        "localhost.", "localhos", "localhosts", "\u0131ocalhost", "localho\u017f", "lOcAlHoSt\0"
    ];
    foreach (spelling; unknown)
    {
        try
        {
            InetAddress.getByName(spelling);
            assert(false, spelling);
        }
        catch (UnknownHostException e)
            assert(e.getMessage() == (spelling[$ - 1] ? spelling : "NUL character not allowed in hostname"));
    }
    // An interface-name scope needs NetworkInterface, which Flint lacks, so every name is unknown.
    try
    {
        InetAddress.getByName("fe80::1%lo");
        assert(false);
    }
    catch (UnknownHostException e)
        assert(e.getMessage() == "no such interface lo");
}

unittest
{
    // Random IPv6 literals hash across the int range: fewer than 85% fall in the short range (as JDK's HashSpread
    // checks). A fixed linear congruential generator keeps the run deterministic.
    static immutable digits = "0123456789ABCDEF";
    uint state = 12_345;
    int narrow;
    enum iterations = 10_000;
    foreach (_; 0 .. iterations)
    {
        char[39] text;
        size_t length;
        foreach (group; 0 .. 8)
        {
            if (group > 0)
                text[length++] = ':';
            foreach (__; 0 .. 4)
            {
                state = state * 1_103_515_245 + 12_345;
                text[length++] = digits[(state >> 16) & 15];
            }
        }
        const hash = InetAddress.getByName(text[0 .. length].idup).hashCode();
        narrow += hash >= short.min && hash <= short.max;
    }
    assert(narrow * 100 < iterations * 85);
}

unittest
{
    // The message of a failed lookup names the host once (JDK B6246242 rejects "foo.bar: foo.bar").
    try
    {
        InetAddress.getByName("foo.bar");
        assert(false);
    }
    catch (UnknownHostException e)
        assert(e.getMessage() == "foo.bar");
}
