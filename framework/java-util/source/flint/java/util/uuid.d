/// Java SE 21 UUID values (R1, R5, R8, R11). Import this leaf directly from flint:java-util.
module flint.java.util.uuid;

import flint.engine.aot.objects : assumeClass;
import flint.java.lang : Comparable, NullPointerException;

@safe:

/// An immutable 128-bit universally unique identifier.
final class UUID : Comparable!UUID
{
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
        import flint.conc.random : fillSecureRandom;
        import flint.java.lang : IllegalStateException;

        ubyte[16] entropy;
        const result = fillSecureRandom(entropy[]);
        if (result.code)
            throw new IllegalStateException(result.message);
        const ulong mostBits = (loadWord(entropy[0 .. 8]) & ~0xf000UL) | 0x4000UL;
        const ulong leastBits = (loadWord(entropy[8 .. 16]) & 0x3fff_ffff_ffff_ffffUL) | (1UL << 63);
        return new UUID(cast(long) mostBits, cast(long) leastBits);
    }

    /++
    Java's `UUID.fromString(name)`: four hyphen-separated hexadecimal fields, shifted into the two words. Java
    accepts fields shorter or longer than the canonical 8-4-4-4-12 layout, a leading `+` in a field, and the
    digits of `Character.digit` in radix 16, and rejects a field beyond Java's signed `long` range; this port
    keeps those rules, including the `NumberFormatException` and `IllegalArgumentException` messages. A D null
    string is Java's `""` (R26).
    +/
    static UUID fromString(string name)
    {
        import flint.java.lang : IllegalArgumentException;

        if (utf16Length(name) > 36)
            throw new IllegalArgumentException("UUID string too large");

        size_t[4] dashes;
        size_t found;
        foreach (index, char codeUnit; name)
        {
            if (codeUnit != '-')
                continue;
            if (found == dashes.length)
                invalidUuidString(name);
            dashes[found++] = index;
        }
        if (found != dashes.length)
            invalidUuidString(name);

        const first = parseHexField(name[0 .. dashes[0]]);
        const second = parseHexField(name[dashes[0] + 1 .. dashes[1]]);
        const third = parseHexField(name[dashes[1] + 1 .. dashes[2]]);
        const fourth = parseHexField(name[dashes[2] + 1 .. dashes[3]]);
        const fifth = parseHexField(name[dashes[3] + 1 .. $]);

        const long mostBits = (first & 0xffff_ffffL) << 32 | (second & 0xffffL) << 16 | (third & 0xffffL);
        const long leastBits = (fourth & 0xffffL) << 48 | (fifth & 0xffff_ffff_ffffL);
        return new UUID(mostBits, leastBits);
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
        return compareWords(other);
    }

    override int opCmp(Object other)
    {
        const value = checkedUuid(other);
        return value is null ? 0 : compareWords(value);
    }

    private int compareWords(scope const UUID other) const pure nothrow @nogc
    {
        if (most != other.most)
            return cast(long) most < cast(long) other.most ? -1 : 1;
        return (cast(long) least > cast(long) other.least) - (cast(long) least < cast(long) other.least);
    }

    private static const(UUID) checkedUuid(return scope const Object other) pure nothrow @nogc
    {
        // UUID is final. An exact type check permits the cast without a shared runtime cast thunk.
        if (other is null || typeid(other) !is typeid(UUID))
            return null;
        return assumeClass!UUID(other);
    }

    /// Compare the UUID's complete bit pattern.
    bool equals(scope const Object other) const pure nothrow @nogc
    {
        const value = checkedUuid(other);
        return value !is null && most == value.most && least == value.least;
    }

    override bool opEquals(Object other) pure nothrow @nogc
    {
        return equals(other);
    }

    bool opEquals(UUID other) const pure nothrow @nogc
    {
        return other !is null && most == other.most && least == other.least;
    }

    override size_t toHash() pure nothrow @nogc
    {
        return cast(uint) hashCode();
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

// Java's length in UTF-16 code units; a four-byte sequence is a surrogate pair.
private size_t utf16Length(scope const(char)[] text) pure nothrow @nogc
{
    size_t units;
    foreach (char codeUnit; text)
    {
        if ((codeUnit & 0xC0) == 0x80)
            continue;
        units += codeUnit >= 0xF0 ? 2 : 1;
    }
    return units;
}

// Java's `Long.parseLong(field, 16)` for one UUID field. `+` is the only sign a field can hold, because `-`
// splits fields; the value must fit Java's signed `long` before the masks in `fromString` apply.
private long parseHexField(string field)
{
    import flint.java.lang : NumberFormatException;
    import flint.java.lang.character : digit;

    if (field.length == 0)
        throw new NumberFormatException("");
    size_t byteIndex;
    size_t unitIndex;
    if (field[0] == '+')
    {
        byteIndex = 1;
        unitIndex = 1;
        if (byteIndex == field.length)
            fieldError(field, 1);
    }
    enum long limit = -long.max;
    enum long multmin = limit / 16;
    long result;
    while (byteIndex < field.length)
    {
        const start = unitIndex;
        uint unit;
        if (!nextBmpUnit(field, byteIndex, unit))
            fieldError(field, start);
        const value = digit(cast(wchar) unit, 16);
        if (value < 0 || result < multmin)
            fieldError(field, start);
        result *= 16;
        if (result < limit + value)
            fieldError(field, start);
        result -= value;
        ++unitIndex;
    }
    return -result;
}

// The next BMP code unit of UTF-8 text; false for a malformed sequence or a supplementary character, whose Java
// code units have no digit value.
private bool nextBmpUnit(scope const(char)[] text, ref size_t index, out uint unit) pure nothrow @nogc
{
    const uint lead = cast(ubyte) text[index++];
    if (lead < 0x80)
    {
        unit = lead;
        return true;
    }
    uint value;
    size_t extra;
    if ((lead & 0xE0) == 0xC0)
    {
        extra = 1;
        value = lead & 0x1F;
    }
    else if ((lead & 0xF0) == 0xE0)
    {
        extra = 2;
        value = lead & 0x0F;
    }
    else
        return false;
    foreach (_; 0 .. extra)
    {
        if (index == text.length || (cast(ubyte) text[index] & 0xC0) != 0x80)
            return false;
        value = (value << 6) | (cast(ubyte) text[index++] & 0x3F);
    }
    if (extra == 1 ? value < 0x80 : value < 0x800)
        return false;
    unit = value;
    return true;
}

// Java's `NumberFormatException.forCharSequence` for one field.
private noreturn fieldError(string field, size_t index)
{
    import flint.java.lang : NumberFormatException;

    throw new NumberFormatException(fieldErrorMessage(field, index));
}

// The message in one exact-sized buffer, with no shared append instantiations in the leaf.
private string fieldErrorMessage(string field, size_t index) pure nothrow
{
    enum prefix = "Error at index ";
    enum separator = " in: \"";
    char[20] digits = void;
    size_t at = digits.length;
    size_t value = index;
    do
    {
        digits[--at] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value);

    const separatorStart = prefix.length + digits.length - at;
    const fieldStart = separatorStart + separator.length;
    auto message = new char[fieldStart + field.length + 1];
    message[0 .. prefix.length] = prefix;
    message[prefix.length .. separatorStart] = digits[at .. $];
    message[separatorStart .. fieldStart] = separator;
    message[fieldStart .. $ - 1] = field;
    message[$ - 1] = '"';
    return message;
}

// Java's `IllegalArgumentException("Invalid UUID string: " + name)`.
private noreturn invalidUuidString(string name)
{
    import flint.java.lang : IllegalArgumentException;

    throw new IllegalArgumentException(invalidUuidMessage(name));
}

// The message in one exact-sized buffer, with no shared append instantiations in the leaf.
private string invalidUuidMessage(string name) pure nothrow
{
    enum prefix = "Invalid UUID string: ";
    auto message = new char[prefix.length + name.length];
    message[0 .. prefix.length] = prefix;
    message[prefix.length .. $] = name;
    return message;
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
