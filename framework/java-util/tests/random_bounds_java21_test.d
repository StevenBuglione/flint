module random_bounds_java21_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.util.random.random : Random;
import std.conv : to;
import std.exception : assertThrown;
import std.string : split, splitLines;

@safe:

private ulong doubleBits(double value) pure nothrow @nogc
{
    union Bits
    {
        double d;
        ulong u;
    }

    Bits bits = Bits(value);
    return bits.u;
}

private double fromDoubleBits(ulong value) pure nothrow @nogc
{
    union Bits
    {
        double d;
        ulong u;
    }

    Bits bits;
    bits.u = value;
    return bits.d;
}

private void checkIntBound(long seed, int bound, string row, string[] encoded)
{
    auto random = new Random(seed);
    foreach (hex; encoded)
        assert(cast(uint) random.nextInt(bound) == to!uint(hex, 16), row);
}

private void checkIntRange(long seed, int origin, int bound, string row, string[] encoded)
{
    auto random = new Random(seed);
    foreach (hex; encoded)
        assert(cast(uint) random.nextInt(origin, bound) == to!uint(hex, 16), row);
}

private void checkLongBound(long seed, long bound, string row, string[] encoded)
{
    auto random = new Random(seed);
    foreach (hex; encoded)
        assert(cast(ulong) random.nextLong(bound) == to!ulong(hex, 16), row);
}

private void checkLongRange(long seed, long origin, long bound, string row, string[] encoded)
{
    auto random = new Random(seed);
    foreach (hex; encoded)
        assert(cast(ulong) random.nextLong(origin, bound) == to!ulong(hex, 16), row);
}

private void checkDoubleBound(long seed, ulong boundBits, string row, string[] encoded)
{
    auto random = new Random(seed);
    const double bound = fromDoubleBits(boundBits);
    foreach (hex; encoded)
        assert(doubleBits(random.nextDouble(bound)) == to!ulong(hex, 16), row);
}

private void checkDoubleRange(long seed, ulong originBits, ulong boundBits, string row, string[] encoded)
{
    auto random = new Random(seed);
    const double origin = fromDoubleBits(originBits);
    const double bound = fromDoubleBits(boundBits);
    foreach (hex; encoded)
        assert(doubleBits(random.nextDouble(origin, bound)) == to!ulong(hex, 16), row);
}

@("Random bounded draws agree bit for bit with Java SE 21")
unittest
{
    size_t rows;
    foreach (line; import("random-bounds-java21.tsv").splitLines())
    {
        auto fields = line.split("\t");
        const kind = fields[0];
        const long seed = fields[1].to!long;
        const string row = line;
        auto encoded = fields[4].split(",");
        final switch (kind)
        {
        case "intBound":
            checkIntBound(seed, fields[2].to!int, row, encoded);
            break;
        case "intRange":
            checkIntRange(seed, fields[2].to!int, fields[3].to!int, row, encoded);
            break;
        case "longBound":
            checkLongBound(seed, fields[2].to!long, row, encoded);
            break;
        case "longRange":
            checkLongRange(seed, fields[2].to!long, fields[3].to!long, row, encoded);
            break;
        case "doubleBound":
            checkDoubleBound(seed, fields[2].to!ulong(16), row, encoded);
            break;
        case "doubleRange":
            checkDoubleRange(seed, fields[2].to!ulong(16), fields[3].to!ulong(16), row, encoded);
            break;
        }
        ++rows;
    }
    assert(rows == 630);
}

@("Random rejects invalid bounds and ranges as Java does")
unittest
{
    auto random = new Random(42);
    assertThrown!IllegalArgumentException(random.nextInt(0));
    assertThrown!IllegalArgumentException(random.nextInt(-1));
    assertThrown!IllegalArgumentException(random.nextInt(5, 5));
    assertThrown!IllegalArgumentException(random.nextInt(6, 5));
    assertThrown!IllegalArgumentException(random.nextLong(0));
    assertThrown!IllegalArgumentException(random.nextLong(-5));
    assertThrown!IllegalArgumentException(random.nextLong(5, 5));
    assertThrown!IllegalArgumentException(random.nextLong(6, 5));
    assertThrown!IllegalArgumentException(random.nextDouble(0.0));
    assertThrown!IllegalArgumentException(random.nextDouble(-1.0));
    assertThrown!IllegalArgumentException(random.nextDouble(double.infinity));
    assertThrown!IllegalArgumentException(random.nextDouble(double.nan));
    assertThrown!IllegalArgumentException(random.nextDouble(1.0, 1.0));
    assertThrown!IllegalArgumentException(random.nextDouble(2.0, 1.0));
    assertThrown!IllegalArgumentException(random.nextDouble(double.nan, 1.0));
    assertThrown!IllegalArgumentException(random.nextDouble(0.0, double.infinity));
}

@("Random bounded draws advance the same state as Java's shared sequence")
unittest
{
    auto a = new Random(123_456_789);
    auto b = new Random(123_456_789);
    assert(a.nextInt(1000) == b.nextInt(1000));
    assert(a.nextLong(1L << 40) == b.nextLong(1L << 40));
    assert(doubleBits(a.nextDouble(3.5)) == doubleBits(b.nextDouble(3.5)));
    assert(a.nextInt() == b.nextInt());
}
