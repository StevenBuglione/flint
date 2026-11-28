// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.interfaceaddress_test;

import flint.engine.aot.text : decimal;
import flint.java.lang : NullPointerException;
import flint.java.net.inetaddress : Inet4Address, InetAddress;
import flint.java.net.interfaceaddress : InterfaceAddress;

@safe:

// Rows from pinned Temurin 21.0.13+9 (InterfaceAddressOracle.java): key, tab, value.
private static immutable string expected = import("interfaceaddress/temurin.tsv");

private string flag(bool value) pure nothrow @nogc
{
    return value ? "true" : "false";
}

private void appendRow(ref string rows, string key, string value) pure nothrow
{
    rows ~= key ~ "\t" ~ value ~ "\n";
}

private string hashOrEx(const InterfaceAddress ia) pure
{
    try
        return decimal(ia.hashCode());
    catch (NullPointerException)
        return "NullPointerException";
}

private struct Fixtures
{
    InetAddress lo;
    InetAddress v4;
    InetAddress v4Named;
    InetAddress v4Other;
    Inet4Address bcast24;
    Inet4Address bcast16;
    Inet4Address bcastNamed;
    InetAddress v6;
    InetAddress v6Lo;
    InterfaceAddress def;
    InterfaceAddress iaV4;
    InterfaceAddress iaV4Same;
    InterfaceAddress iaV4DiffBcast;
    InterfaceAddress iaV4NoBcast;
    InterfaceAddress iaV4DiffMask;
    InterfaceAddress iaV4Other;
    InterfaceAddress iaLo;
    InterfaceAddress iaLoSame;
    InterfaceAddress iaLoBcast;
    InterfaceAddress iaV6;
    InterfaceAddress iaV6Lo;
    InterfaceAddress iaNullAddrWithBcast;
    InterfaceAddress iaNullAddrSame;
    InterfaceAddress iaNegMask;
    InterfaceAddress iaMinMask;
    InterfaceAddress iaMaxMask;
}

private Fixtures buildFixtures()
{
    Fixtures f;
    f.lo = InetAddress.getLoopbackAddress();
    const ubyte[4] v4Bytes = [192, 168, 1, 5];
    const ubyte[4] v4OtherBytes = [10, 0, 0, 1];
    const ubyte[4] bcast24Bytes = [192, 168, 1, 255];
    const ubyte[4] bcast16Bytes = [192, 168, 255, 255];
    f.v4 = InetAddress.getByAddress(v4Bytes[]);
    f.v4Named = InetAddress.getByAddress("host.example", v4Bytes[]);
    f.v4Other = InetAddress.getByAddress(v4OtherBytes[]);
    f.bcast24 = cast(Inet4Address) InetAddress.getByAddress(bcast24Bytes[]);
    f.bcast16 = cast(Inet4Address) InetAddress.getByAddress(bcast16Bytes[]);
    f.bcastNamed = cast(Inet4Address) InetAddress.getByAddress("bcast.example", bcast24Bytes[]);
    assert(f.bcast24 !is null && f.bcast16 !is null && f.bcastNamed !is null);
    f.v6 = InetAddress.getByName("2001:db8::1");
    f.v6Lo = InetAddress.getByName("::1");

    f.def = new InterfaceAddress();
    f.iaV4 = new InterfaceAddress(f.v4, f.bcast24, 24);
    f.iaV4Same = new InterfaceAddress(f.v4Named, f.bcastNamed, 24);
    f.iaV4DiffBcast = new InterfaceAddress(f.v4, f.bcast16, 24);
    f.iaV4NoBcast = new InterfaceAddress(f.v4, null, 24);
    f.iaV4DiffMask = new InterfaceAddress(f.v4, f.bcast24, 16);
    f.iaV4Other = new InterfaceAddress(f.v4Other, f.bcast24, 24);
    f.iaLo = new InterfaceAddress(f.lo, null, 8);
    f.iaLoSame = new InterfaceAddress(f.lo, null, 8);
    f.iaLoBcast = new InterfaceAddress(f.lo, f.bcast24, 8);
    f.iaV6 = new InterfaceAddress(f.v6, null, 64);
    f.iaV6Lo = new InterfaceAddress(f.v6Lo, null, 128);
    f.iaNullAddrWithBcast = new InterfaceAddress(null, f.bcast24, 24);
    f.iaNullAddrSame = new InterfaceAddress(null, f.bcast24, 24);
    f.iaNegMask = new InterfaceAddress(f.v4, f.bcast24, cast(short)-1);
    f.iaMinMask = new InterfaceAddress(f.v4, null, short.min);
    f.iaMaxMask = new InterfaceAddress(f.v4, f.bcast24, short.max);
    return f;
}

private void observedAccessors(ref string rows, ref const Fixtures f) pure nothrow
{
    appendRow(rows, "def-addr-null", flag(f.def.getAddress() is null));
    appendRow(rows, "def-bcast-null", flag(f.def.getBroadcast() is null));
    appendRow(rows, "def-mask", decimal(cast(int) f.def.getNetworkPrefixLength()));
    appendRow(rows, "v4-addr", f.iaV4.getAddress().getHostAddress());
    appendRow(rows, "v4-bcast", f.iaV4.getBroadcast().getHostAddress());
    appendRow(rows, "v4-mask", decimal(cast(int) f.iaV4.getNetworkPrefixLength()));
    appendRow(rows, "v4-same-ref", flag(f.iaV4.getAddress() is f.v4 && f.iaV4.getBroadcast() is f.bcast24));
    appendRow(rows, "v6-addr", f.iaV6.getAddress().getHostAddress());
    appendRow(rows, "v6-bcast-null", flag(f.iaV6.getBroadcast() is null));
    appendRow(rows, "v6-mask", decimal(cast(int) f.iaV6.getNetworkPrefixLength()));
    appendRow(rows, "v6lo-mask", decimal(cast(int) f.iaV6Lo.getNetworkPrefixLength()));
    appendRow(rows, "neg-mask", decimal(cast(int) f.iaNegMask.getNetworkPrefixLength()));
    appendRow(rows, "min-mask", decimal(cast(int) f.iaMinMask.getNetworkPrefixLength()));
    appendRow(rows, "max-mask", decimal(cast(int) f.iaMaxMask.getNetworkPrefixLength()));
}

private void observedToString(ref string rows, ref const Fixtures f) pure nothrow
{
    appendRow(rows, "str-def", f.def.toString());
    appendRow(rows, "str-v4", f.iaV4.toString());
    appendRow(rows, "str-v4-named", f.iaV4Same.toString());
    appendRow(rows, "str-v4-nobcast", f.iaV4NoBcast.toString());
    appendRow(rows, "str-lo", f.iaLo.toString());
    appendRow(rows, "str-v6", f.iaV6.toString());
    appendRow(rows, "str-v6lo", f.iaV6Lo.toString());
    appendRow(rows, "str-null-addr-bcast", f.iaNullAddrWithBcast.toString());
    appendRow(rows, "str-neg-mask", f.iaNegMask.toString());
    appendRow(rows, "str-min-mask", f.iaMinMask.toString());
    appendRow(rows, "str-max-mask", f.iaMaxMask.toString());
}

private void observedHashCode(ref string rows, ref const Fixtures f) pure
{
    appendRow(rows, "hash-def", hashOrEx(f.def));
    appendRow(rows, "hash-null-addr-bcast", hashOrEx(f.iaNullAddrWithBcast));
    appendRow(rows, "hash-v4", hashOrEx(f.iaV4));
    appendRow(rows, "hash-v4-same", hashOrEx(f.iaV4Same));
    appendRow(rows, "hash-v4-diff-bcast", hashOrEx(f.iaV4DiffBcast));
    appendRow(rows, "hash-v4-nobcast", hashOrEx(f.iaV4NoBcast));
    appendRow(rows, "hash-v4-diff-mask", hashOrEx(f.iaV4DiffMask));
    appendRow(rows, "hash-lo", hashOrEx(f.iaLo));
    appendRow(rows, "hash-v6", hashOrEx(f.iaV6));
    appendRow(rows, "hash-v6lo", hashOrEx(f.iaV6Lo));
    appendRow(rows, "hash-neg-mask", hashOrEx(f.iaNegMask));
    appendRow(rows, "hash-min-mask", hashOrEx(f.iaMinMask));
    appendRow(rows, "hash-max-mask", hashOrEx(f.iaMaxMask));
}

private void observedEquals(ref string rows, ref Fixtures f) pure nothrow
{
    appendRow(rows, "eq-self-v4", flag(f.iaV4.equals(f.iaV4)));
    appendRow(rows, "eq-self-def", flag(f.def.equals(f.def)));
    appendRow(rows, "eq-null", flag(f.iaV4.equals(null)));
    appendRow(rows, "eq-other-type", flag(f.iaV4.equals(f.v4)));
    appendRow(rows, "eq-v4-named", flag(f.iaV4.equals(f.iaV4Same) && f.iaV4Same.equals(f.iaV4)));
    appendRow(rows, "eq-v4-diff-bcast", flag(f.iaV4.equals(f.iaV4DiffBcast) || f.iaV4DiffBcast.equals(f.iaV4)));
    appendRow(rows, "eq-v4-nobcast", flag(f.iaV4.equals(f.iaV4NoBcast) || f.iaV4NoBcast.equals(f.iaV4)));
    appendRow(rows, "eq-v4-diff-mask", flag(f.iaV4.equals(f.iaV4DiffMask) || f.iaV4DiffMask.equals(f.iaV4)));
    appendRow(rows, "eq-v4-diff-addr", flag(f.iaV4.equals(f.iaV4Other) || f.iaV4Other.equals(f.iaV4)));
    appendRow(rows, "eq-lo-nobcast", flag(f.iaLo.equals(f.iaLoSame) && f.iaLoSame.equals(f.iaLo)));
    appendRow(rows, "eq-lo-vs-bcast", flag(f.iaLo.equals(f.iaLoBcast) || f.iaLoBcast.equals(f.iaLo)));
    appendRow(rows, "eq-v4-vs-null-addr", flag(f.iaV4.equals(f.iaNullAddrWithBcast)
            || f.iaNullAddrWithBcast.equals(f.iaV4)));
    appendRow(rows, "eq-null-addr-both", flag(f.iaNullAddrWithBcast.equals(f.iaNullAddrSame)
            && f.iaNullAddrSame.equals(f.iaNullAddrWithBcast)));
    appendRow(rows, "eq-def-vs-null-addr-bcast", flag(f.def.equals(f.iaNullAddrWithBcast)
            || f.iaNullAddrWithBcast.equals(f.def)));
    appendRow(rows, "eq-def-vs-def", flag(f.def.equals(new InterfaceAddress())));
    appendRow(rows, "eq-v6-vs-v4", flag(f.iaV6.equals(f.iaV4) || f.iaV4.equals(f.iaV6)));
    appendRow(rows, "eq-v6-self-copy", flag(f.iaV6.equals(new InterfaceAddress(f.v6, null, 64))));
}

unittest
{
    auto f = buildFixtures();
    string rows;
    observedAccessors(rows, f);
    observedToString(rows, f);
    observedHashCode(rows, f);
    observedEquals(rows, f);
    assert(rows == expected);
}

unittest
{
    // JavaObject bridges == and associative arrays; a null address hashes to 0 through toHash().
    auto f = buildFixtures();
    assert(f.iaV4 == f.iaV4Same);
    assert(f.iaV4 != f.iaV4NoBcast);
    assert(f.def.toHash() == 0);

    int[InterfaceAddress] table;
    table[f.iaV4] = 42;
    assert(table[f.iaV4Same] == 42);
}

unittest
{
    // Accessors and equals allocate nothing (@nogc).
    auto f = buildFixtures();

    void checkNoGc() @safe @nogc
    {
        assert(f.iaV4.getAddress() is f.v4);
        assert(f.iaV4.getBroadcast() is f.bcast24);
        assert(f.iaV4.getNetworkPrefixLength() == 24);
        assert(f.iaV4.equals(f.iaV4Same));
        assert(!f.iaV4.equals(f.iaV4DiffBcast));
        assert(!f.iaV4.equals(null));
    }

    checkNoGc();
}
