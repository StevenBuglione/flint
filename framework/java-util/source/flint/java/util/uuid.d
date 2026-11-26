/// Java SE 21 UUID values (R1, R5, R8, R11). Import this leaf directly from flint:java-util.
module flint.java.util.uuid;

import flint.java.lang : Comparable, JavaObject, NullPointerException;

@safe:

/// An immutable 128-bit universally unique identifier.
final class UUID : Comparable!UUID
{
    mixin JavaObject;

    private immutable ulong most;
    private immutable ulong least;

    /// Construct a UUID from the two signed words carrying its bits.
    this(long mostSigBits, long leastSigBits) pure nothrow @nogc
    {
        most = cast(ulong) mostSigBits;
        least = cast(ulong) leastSigBits;
    }

    /// Generate a version 4 UUID using the operating system's secure random source.
    static UUID randomUUID()
    {
        import flint.conc : fillSecureRandom;
        import flint.java.lang : IllegalStateException;

        ubyte[16] entropy;
        const result = fillSecureRandom(entropy[]);
        if (result.code)
            throw new IllegalStateException(result.message);
        const ulong mostBits = (loadWord(entropy[0 .. 8]) & ~0xf000UL) | 0x4000UL;
        const ulong leastBits = (loadWord(entropy[8 .. 16]) & 0x3fff_ffff_ffff_ffffUL) | (1UL << 63);
        return new UUID(cast(long) mostBits, cast(long) leastBits);
    }

    /// The upper 64 bits as a signed long.
    long getMostSignificantBits() const pure nothrow @nogc
    {
        return cast(long) most;
    }

    /// The lower 64 bits as a signed long.
    long getLeastSignificantBits() const pure nothrow @nogc
    {
        return cast(long) least;
    }

    /// The version nibble. Java's method name is a D keyword.
    int version_() const pure nothrow @nogc
    {
        return cast(int)((most >> 12) & 0xf);
    }

    /// The UUID variant encoded in the high bits of the lower word.
    int variant() const pure nothrow @nogc
    {
        if ((least >> 63) == 0)
            return 0;
        if ((least >> 62) == 2)
            return 2;
        return cast(int)(least >> 61);
    }

    /// Return the version-1 timestamp in 100-nanosecond ticks since 1582-10-15 UTC.
    long timestamp() const pure
    {
        requireTimeBased();
        const ulong low = most >> 32;
        const ulong middle = (most >> 16) & 0xffff;
        const ulong high = most & 0xfff;
        return cast(long)((high << 48) | (middle << 32) | low);
    }

    /// Return the 14-bit version-1 clock sequence.
    int clockSequence() const pure
    {
        requireTimeBased();
        return cast(int)((least >> 48) & 0x3fff);
    }

    /// Return the 48-bit version-1 node identifier.
    long node() const pure
    {
        requireTimeBased();
        return cast(long)(least & 0xffff_ffff_ffffUL);
    }

    private void requireTimeBased() const pure
    {
        import flint.java.lang : UnsupportedOperationException;

        if (version_() != 1)
            throw new UnsupportedOperationException("Not a time-based UUID");
    }

    /// Compare the two signed words, starting with the most significant word.
    override int compareTo(UUID other) pure
    {
        if (other is null)
            throw new NullPointerException();
        if (most != other.most)
            return cast(long) most < cast(long) other.most ? -1 : 1;
        return (cast(long) least > cast(long) other.least) - (cast(long) least < cast(long) other.least);
    }

    /// Compare the UUID's complete bit pattern.
    bool equals(scope const Object other) const pure nothrow @nogc
    {
        const value = cast(const UUID) other;
        return value !is null && most == value.most && least == value.least;
    }

    /// Fold the four 32-bit words with XOR.
    int hashCode() const pure nothrow @nogc
    {
        const ulong folded = most ^ least;
        return cast(int)(folded ^ (folded >> 32));
    }

    /// Render the standard 8-4-4-4-12 layout in lowercase hexadecimal.
    override string toString() const pure nothrow
    {
        return renderUuid(most, least);
    }
}

private char[] renderUuid(ulong most, ulong least) pure nothrow
{
    auto text = new char[36];
    text[8] = text[13] = text[18] = text[23] = '-';
    writeHex(text[0 .. 8], most >> 32);
    writeHex(text[9 .. 13], most >> 16);
    writeHex(text[14 .. 18], most);
    writeHex(text[19 .. 23], least >> 48);
    writeHex(text[24 .. 36], least);
    return text;
}

private ulong loadWord(scope const(ubyte)[] bytes) pure nothrow @nogc
{
    ulong bits;
    foreach (value; bytes)
        bits = (bits << 8) | value;
    return bits;
}

private void writeHex(scope char[] output, ulong value) pure nothrow @nogc
{
    enum digits = "0123456789abcdef";
    foreach_reverse (ref ch; output)
    {
        ch = digits[value & 0xf];
        value >>= 4;
    }
}
