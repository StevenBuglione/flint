/// Java SE 21 hexadecimal primitive conversions.
module flint.java.util.hexformat;

@safe:

/// A formatter whose case setting applies only to output.
final class HexFormat
{
    private immutable bool upper;

    private this(bool upper) pure nothrow @nogc
    {
        this.upper = upper;
    }

    /// Create a lowercase formatter.
    static HexFormat of() pure nothrow
    {
        return new HexFormat(false);
    }

    /// Select uppercase hexadecimal letters.
    HexFormat withUpperCase() pure nothrow
    {
        return upper ? this : new HexFormat(true);
    }

    /// Select lowercase hexadecimal letters.
    HexFormat withLowerCase() pure nothrow
    {
        return upper ? new HexFormat(false) : this;
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

    private string alphabet() const pure nothrow @nogc
    {
        return upper ? "0123456789ABCDEF" : "0123456789abcdef";
    }

    private string render(ulong value, uint digits) const pure nothrow
    {
        return renderDigits(value, digits, upper);
    }
}

private char[] renderDigits(ulong value, uint digits, bool upper) pure nothrow
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

private int digitValue(int codePoint) pure nothrow @nogc
{
    const uint code = cast(uint) codePoint;
    const uint decimal = code - '0';
    if (decimal < 10)
        return cast(int) decimal;
    const uint letter = (code | 0x20) - 'a';
    return letter < 6 ? cast(int)(letter + 10) : -1;
}
