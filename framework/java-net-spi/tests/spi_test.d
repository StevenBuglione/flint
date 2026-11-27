// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.spi_test;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException;
import flint.java.net.inetaddress : InetAddress;
import flint.java.net.spi.inetaddressresolver : InetAddressResolver;
import flint.java.net.spi.inetaddressresolverprovider : InetAddressResolverProvider;
import flint.java.net.unknownhostexception : UnknownHostException;
import flint.java.util.stream : Stream;

@safe:

alias LookupPolicy = InetAddressResolver.LookupPolicy;

// Rows from pinned Temurin 21.0.13+9 (LookupPolicyOracle.java): characteristics, then "ok" with characteristics()
// or "iae" with the IllegalArgumentException message. Covers every 5-bit mask and sign-bit and custom-flag values.
private static immutable string expected = import("spi/lookuppolicy-temurin.tsv");

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

private int parseInt(string text) pure nothrow @nogc
{
    const negative = text.length > 0 && text[0] == '-';
    long value;
    foreach (c; text[negative .. $])
        value = value * 10 + (c - '0');
    return cast(int)(negative ? -value : value);
}

private string describe(int characteristics)
{
    try
        return "ok\t" ~ decimal(LookupPolicy.of(characteristics).characteristics());
    catch (IllegalArgumentException e)
        return "iae\t" ~ e.msg;
}

unittest
{
    // The constants are Java's bit values.
    static assert(LookupPolicy.IPV4 == 1 && LookupPolicy.IPV6 == 2);
    static assert(LookupPolicy.IPV4_FIRST == 4 && LookupPolicy.IPV6_FIRST == 8);
    // The constructor is private; LookupPolicy.of is the only factory.
    static assert(!__traits(compiles, new LookupPolicy(1)));
    static assert(__traits(isFinalClass, LookupPolicy));
}

unittest
{
    // LookupPolicy.of accepts and rejects exactly the masks Temurin does, with its messages.
    size_t rows;
    foreach (line; split(expected, '\n'))
    {
        if (line.length == 0)
            continue;
        auto fields = split(line, '\t');
        assert(fields.length == 3, line);
        assert(describe(parseInt(fields[0])) == fields[1] ~ "\t" ~ fields[2], line);
        ++rows;
    }
    assert(rows == 41);
}

unittest
{
    // Valid and invalid combinations named in the specification: one address type is required, at most one order
    // flag, and an order flag needs its address type. Bits other than the four flags are kept for custom providers.
    with (LookupPolicy)
    {
        foreach (valid; [
            IPV4, IPV4 | IPV4_FIRST, IPV6, IPV6 | IPV6_FIRST, IPV4 | IPV6, IPV4 | IPV6 | IPV4_FIRST,
            IPV4 | IPV6 | IPV6_FIRST, IPV4 | IPV6 | 0x10, IPV4 | IPV6 | 0x20
        ])
            assert(of(valid).characteristics() == valid);
        foreach (invalid; [
            0, IPV4_FIRST, IPV6_FIRST, IPV4_FIRST | IPV6_FIRST, IPV4 | IPV6_FIRST, IPV6 | IPV4_FIRST,
            IPV4 | IPV6 | IPV4_FIRST | IPV6_FIRST
        ])
        {
            bool thrown;
            try
                of(invalid);
            catch (IllegalArgumentException)
                thrown = true;
            assert(thrown);
        }
    }
}

private final class FixedResolver : InetAddressResolver
{
    override Stream!InetAddress lookupByName(string host, LookupPolicy lookupPolicy)
    {
        if (host != "example.test" || (lookupPolicy.characteristics() & LookupPolicy.IPV4) == 0)
            throw new UnknownHostException(host);
        immutable ubyte[4] address = [192, 0, 2, 1];
        return Stream!InetAddress.of(InetAddress.getByAddress(host, address[]));
    }

    override string lookupByAddress(scope const(ubyte)[] addr)
    {
        if (addr.length != 4)
            throw new UnknownHostException("bad address");
        return "example.test";
    }
}

private final class FixedProvider : InetAddressResolverProvider
{
    override InetAddressResolver get(Configuration configuration)
    {
        return configuration is null ? new FixedResolver : configuration.builtinResolver();
    }

    override string name()
    {
        return "fixed";
    }
}

unittest
{
    // A provider subclass supplies a resolver; the resolver contract streams addresses and reports failures with
    // UnknownHostException.
    static assert(__traits(isAbstractClass, InetAddressResolverProvider));
    InetAddressResolverProvider provider = new FixedProvider;
    assert(provider.name() == "fixed");
    auto resolver = provider.get(null);
    auto found = resolver.lookupByName("example.test", LookupPolicy.of(LookupPolicy.IPV4)).toArray();
    assert(found.length == 1);
    assert(found[0].toString() == "example.test/192.0.2.1");
    immutable ubyte[4] address = [192, 0, 2, 1];
    assert(resolver.lookupByAddress(address[]) == "example.test");
    bool thrown;
    try
        resolver.lookupByName("example.test", LookupPolicy.of(LookupPolicy.IPV6));
    catch (UnknownHostException e)
        thrown = e.msg == "example.test";
    assert(thrown);
}
