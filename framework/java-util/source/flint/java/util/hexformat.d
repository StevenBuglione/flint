/// Java SE 21 hexadecimal conversions.
module flint.java.util.hexformat;

@safe:

/// An immutable hexadecimal formatter.
final class HexFormat
{
    private immutable bool upper;
    private immutable string separator;
    private immutable string beforeByte;
    private immutable string afterByte;

    private this(bool upper, string delimiter, string prefix, string suffix) pure nothrow @nogc
    {
        this.upper = upper;
        separator = delimiter;
        beforeByte = prefix;
        afterByte = suffix;
    }

    /// Create a lowercase formatter.
    static HexFormat of() pure nothrow
    {
        return new HexFormat(false, null, null, null);
    }

    /// Create a lowercase formatter with a delimiter between adjacent bytes.
    static HexFormat ofDelimiter(string delimiter) pure nothrow
    {
        return new HexFormat(false, delimiter, null, null);
    }

    /// Select the delimiter between adjacent bytes.
    HexFormat withDelimiter(string delimiter) pure nothrow
    {
        return new HexFormat(upper, delimiter, beforeByte, afterByte);
    }

    /// Select the prefix attached to each byte.
    HexFormat withPrefix(string prefix) pure nothrow
    {
        return new HexFormat(upper, separator, prefix, afterByte);
    }

    /// Select the suffix attached to each byte.
    HexFormat withSuffix(string suffix) pure nothrow
    {
        return new HexFormat(upper, separator, beforeByte, suffix);
    }

    /// Select uppercase hexadecimal letters.
    HexFormat withUpperCase() pure nothrow
    {
        return withCase(true);
    }

    /// Select lowercase hexadecimal letters.
    HexFormat withLowerCase() pure nothrow
    {
        return withCase(false);
    }

    pragma(inline, false) private HexFormat withCase(bool uppercase) pure nothrow
    {
        return upper == uppercase ? this : new HexFormat(uppercase, separator, beforeByte, afterByte);
    }

    /// Return the delimiter between adjacent bytes.
    string delimiter() const pure nothrow @nogc
    {
        return separator;
    }

    /// Return the prefix attached to each byte.
    string prefix() const pure nothrow @nogc
    {
        return beforeByte;
    }

    /// Return the suffix attached to each byte.
    string suffix() const pure nothrow @nogc
    {
        return afterByte;
    }

    /// Format each byte with the selected alphabet and decorations.
    string formatHex(scope const(byte)[] bytes) const pure nothrow
    {
        return renderBytes(bytes, alphabet(), separator, beforeByte, afterByte);
    }

    /// Format the bytes in the range [fromIndex, toIndex).
    string formatHex(scope const(byte)[] bytes, int fromIndex, int toIndex) const pure
    {
        import flint.java.lang : IndexOutOfBoundsException;

        if (fromIndex < 0 || toIndex < fromIndex || toIndex > bytes.length)
            throw new IndexOutOfBoundsException("Hexadecimal byte range is out of bounds");
        return formatHex(bytes[fromIndex .. toIndex]);
    }

    /// Report the output case.
    bool isUpperCase() const pure nothrow @nogc
    {
        return upper;
    }

    /// Render the low nibble.
    wchar toLowHexDigit(int value) const pure nothrow @nogc
    {
        return alphabet()[value & 15];
    }

    /// Render bits four through seven.
    wchar toHighHexDigit(int value) const pure nothrow @nogc
    {
        return alphabet()[(value >> 4) & 15];
    }

    /// Render the eight bits of a signed Java byte.
    string toHexDigits(byte value) const pure nothrow
    {
        return render(cast(ubyte) value, 2);
    }

    /// Render the sixteen bits of a Java UTF-16 code unit.
    string toHexDigits(wchar value) const pure nothrow
    {
        return render(cast(ushort) value, 4);
    }

    /// Render the sixteen bits of a signed integer.
    string toHexDigits(short value) const pure nothrow
    {
        return render(cast(ushort) value, 4);
    }

    /// Render the thirty-two bits of a signed integer.
    string toHexDigits(int value) const pure nothrow
    {
        return render(cast(uint) value, 8);
    }

    /// Render the sixty-four bits of a signed integer.
    string toHexDigits(long value) const pure nothrow
    {
        return render(cast(ulong) value, 16);
    }

    /// Render a requested number of low hexadecimal digits.
    string toHexDigits(long value, int digits) const pure
    {
        import flint.java.lang : IllegalArgumentException;

        if (cast(uint) digits > 16)
            throw new IllegalArgumentException("Hexadecimal digit count must be between 0 and 16");
        return render(cast(ulong) value, cast(uint) digits);
    }

    /// Check whether the code point names an ASCII hexadecimal digit.
    static bool isHexDigit(int codePoint) pure nothrow @nogc
    {
        return digitValue(codePoint) >= 0;
    }

    /// Return the value of one ASCII hexadecimal digit.
    static int fromHexDigit(int codePoint) pure
    {
        import flint.java.lang : NumberFormatException;

        const int value = digitValue(codePoint);
        if (value < 0)
            throw new NumberFormatException("Invalid hexadecimal digit");
        return value;
    }

    /// Decode up to eight hexadecimal digits into the bits of a Java int.
    static int fromHexDigits(scope const(char)[] text) pure
    {
        return cast(int) parseDigits(text, 8);
    }

    /// Decode up to sixteen hexadecimal digits into the bits of a Java long.
    static long fromHexDigitsToLong(scope const(char)[] text) pure
    {
        return cast(long) parseDigits(text, 16);
    }

    private string alphabet() const pure nothrow @nogc
    {
        return upper ? "0123456789ABCDEF" : "0123456789abcdef";
    }

    private string render(ulong value, uint digits) const pure nothrow
    {
        return renderDigits(value, digits, upper);
    }
}

private:

char[] renderBytes(scope const(byte)[] bytes, string table, string delimiter, string prefix, string suffix) pure nothrow
{
    import core.checkedint : addu, mulu;
    import core.exception : onOutOfMemoryError;

    const count = bytes.length;
    if (count == 0)
        return null;

    bool overflow;
    const width = addu(addu(prefix.length, suffix.length, overflow), cast(size_t) 2, overflow);
    const decorated = mulu(width, count, overflow);
    const separators = mulu(delimiter.length, count - 1, overflow);
    const size = addu(decorated, separators, overflow);
    if (overflow)
        onOutOfMemoryError();

    auto text = new char[size];
    size_t at;
    foreach (index, value; bytes)
    {
        if (index != 0)
        {
            text[at .. at + delimiter.length] = delimiter;
            at += delimiter.length;
        }
        text[at .. at + prefix.length] = prefix;
        at += prefix.length;
        const uint octet = cast(ubyte) value;
        text[at++] = table[octet >> 4];
        text[at++] = table[octet & 15];
        text[at .. at + suffix.length] = suffix;
        at += suffix.length;
    }
    return text;
}

ulong parseDigits(scope const(char)[] text, uint limit) pure
{
    import flint.java.lang : IllegalArgumentException;

    if (text.length > limit)
    {
        // Legal UTF-8 uses at most three bytes per UTF-16 code unit.
        uint units = limit + 1;
        if (text.length <= 3 * limit)
        {
            units = 0;
            for (size_t index; index < text.length && units <= limit; ++index)
            {
                const ubyte octet = text[index];
                units += ((octet & 0xc0) != 0x80) + (octet >= 0xf0);
            }
        }
        if (units > limit)
            throw new IllegalArgumentException("Too many hexadecimal digits");
    }

    ulong result;
    foreach (char digit; text)
        result = (result << 4) | cast(uint) HexFormat.fromHexDigit(digit);
    return result;
}

pragma(inline, false) char[] renderDigits(ulong value, uint digits, bool upper) pure nothrow
{
    auto text = new char[digits];
    const table = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    foreach_reverse (ref digit; text)
    {
        digit = table[value & 15];
        value >>= 4;
    }
    return text;
}

int digitValue(int codePoint) pure nothrow @nogc
{
    const uint code = cast(uint) codePoint;
    const uint decimal = code - '0';
    if (decimal < 10)
        return cast(int) decimal;
    const uint letter = (code | 0x20) - 'a';
    return letter < 6 ? cast(int)(letter + 10) : -1;
}
