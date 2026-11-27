/// Java's `Double.toString` and `Float.toString` renderings (JDK 19 and later) over the
/// shortest round-trip digits that JSON encoding already uses.
///
/// Spring-layer APIs print numbers the way the JDK does: Jackson's default
/// `NumberOutput.toString(double)` and SLF4J's `String.valueOf` both call
/// `Double.toString`. The JDK picks the shortest decimal that rounds back to the
/// value, the closest among those, ties to an even last digit, which is exactly
/// `shortest`. Only the layout differs from JSON's: at least one digit after the
/// point, plain notation for 10^-3 <= |v| < 10^7 and `d.dddE<n>` otherwise. The JDK
/// renders the smallest subnormals (a significand below `C_TINY`) with two digits.
module flint.serde.java_number;

import flint.serde.internal.shortest : shortest;
import flint.serde.sys.text : copyText;

@safe:

/// Longest rendering: a sign, 17 digits, the point, `E-` and three exponent digits.
enum size_t javaNumberCapacity = 32;

private union DoubleView
{
    ulong raw;
    double value;
}

private union FloatView
{
    uint raw;
    float value;
}

/// Write `Double.toString(value)` into `output` and return its length.
size_t formatJavaDouble(double value, ref char[javaNumberCapacity] output) pure nothrow @nogc
{
    DoubleView view;
    view.value = value;
    // DoubleToDecimal.C_TINY = 3: Float.MIN_VALUE * {1, 2} keep a second digit.
    static immutable ulong[3] tinyDigits = [0, 49, 99];
    return render(view.raw, 52, 1023, tinyDigits[], -325, output);
}

/// Write `Float.toString(value)` into `output` and return its length.
size_t formatJavaFloat(float value, ref char[javaNumberCapacity] output) pure nothrow @nogc
{
    FloatView view;
    view.value = value;
    // FloatToDecimal.C_TINY = 8: the seven smallest subnormals keep a second digit.
    static immutable ulong[8] tinyDigits = [0, 14, 28, 42, 56, 70, 84, 98];
    return render(view.raw, 23, 127, tinyDigits[], -46, output);
}

version (D_BetterC)
{
}
else
{
    /// `Double.toString(value)` as a GC string.
    string javaDoubleString(double value) pure nothrow
    {
        // Out of line: inlined, the formatter call and the copy grow every caller (Formatter.convert, Jackson).
        pragma(inline, false);
        char[javaNumberCapacity] text;
        // Not .idup: its template instance lives in serde's first archive object (see flint.serde.sys.text).
        return copyText(text[0 .. formatJavaDouble(value, text)]);
    }

    /// `Float.toString(value)` as a GC string.
    string javaFloatString(float value) pure nothrow
    {
        pragma(inline, false);
        char[javaNumberCapacity] text;
        return copyText(text[0 .. formatJavaFloat(value, text)]);
    }
}

private struct Text
{
    char[javaNumberCapacity]* output;
    size_t length;

    void put(scope const(char)[] text) scope pure nothrow @nogc
    {
        (*output)[length .. length + text.length] = text;
        length += text.length;
    }
}

private size_t render(ulong raw, uint fractionBits, int bias, scope const(ulong)[] tinyDigits,
        int tinyExponent, return ref char[javaNumberCapacity] output) pure nothrow @nogc
{
    auto text = Text(&output);
    immutable exponentMask = cast(uint)(bias * 2 + 1);
    immutable exponentBits = cast(uint)((raw >> fractionBits) & exponentMask);
    immutable fraction = raw & ((1UL << fractionBits) - 1);
    immutable negative = ((raw >> (fractionBits + bitsOf(exponentMask))) & 1) != 0;
    if (exponentBits == exponentMask)
    {
        text.put(fraction != 0 ? "NaN" : negative ? "-Infinity" : "Infinity");
        return text.length;
    }
    if (negative)
        text.put("-");
    if (exponentBits == 0 && fraction == 0)
    {
        text.put("0.0");
        return text.length;
    }

    ulong digits;
    int exponent;
    if (exponentBits == 0 && fraction < tinyDigits.length)
    {
        digits = tinyDigits[cast(size_t) fraction];
        exponent = tinyExponent;
        while (digits % 10 == 0)
        {
            digits /= 10;
            ++exponent;
        }
    }
    else
    {
        const decimal = shortest(fraction, exponentBits, fractionBits, bias);
        digits = decimal.digits;
        exponent = decimal.exponent;
    }
    layout(text, digits, exponent);
    return text.length;
}

// Lay out digits * 10^exponent as Double.toString does.
private void layout(ref scope Text text, ulong digits, int exponent) pure nothrow @nogc
{
    char[20] buffer;
    size_t first = buffer.length;
    do
    {
        buffer[--first] = cast(char)('0' + digits % 10);
        digits /= 10;
    }
    while (digits != 0);
    const significand = buffer[first .. $];
    // The value is 0.d1d2...dn * 10^e.
    immutable e = cast(int) significand.length + exponent;
    if (0 < e && e <= 7)
    {
        foreach (index; 0 .. e)
            text.put(index < significand.length ? significand[index .. index + 1] : "0");
        text.put(".");
        text.put(e < significand.length ? significand[e .. $] : "0");
    }
    else if (-3 < e && e <= 0)
    {
        text.put("0.");
        foreach (_; e .. 0)
            text.put("0");
        text.put(significand);
    }
    else
    {
        text.put(significand[0 .. 1]);
        text.put(".");
        text.put(significand.length > 1 ? significand[1 .. $] : "0");
        text.put(e - 1 < 0 ? "E-" : "E");
        uint shown = e - 1 < 0 ? 1 - e : e - 1;
        char[4] power;
        size_t start = power.length;
        do
        {
            power[--start] = cast(char)('0' + shown % 10);
            shown /= 10;
        }
        while (shown != 0);
        text.put(power[start .. $]);
    }
}

private uint bitsOf(uint mask) pure nothrow @nogc
{
    uint count;
    while (mask != 0)
    {
        ++count;
        mask >>= 1;
    }
    return count;
}

@("Java Double.toString layout: plain between 10^-3 and 10^7, scientific outside")
unittest
{
    static string text(double value)
    {
        char[javaNumberCapacity] buffer;
        return buffer[0 .. formatJavaDouble(value, buffer)].idup;
    }

    assert(text(0.0) == "0.0" && text(-0.0) == "-0.0");
    assert(text(1.0) == "1.0" && text(100.0) == "100.0" && text(1.5) == "1.5");
    assert(text(1_234_567.0) == "1234567.0" && text(1e7) == "1.0E7" && text(12_345_678.0) == "1.2345678E7");
    assert(text(0.001) == "0.001" && text(0.0001) == "1.0E-4" && text(0.1) == "0.1");
    assert(text(double.max) == "1.7976931348623157E308");
    assert(text(double.min_normal) == "2.2250738585072014E-308");
    DoubleView tiny;
    static immutable ulong[4] doubleBits = [1, 2, 3, 0x8000_0000_0000_0001];
    static immutable string[4] doubleTexts = ["4.9E-324", "9.9E-324", "1.5E-323", "-4.9E-324"];
    foreach (index, bits; doubleBits)
    {
        tiny.raw = bits;
        assert(text(tiny.value) == doubleTexts[index]);
    }
    assert(text(double.nan) == "NaN" && text(double.infinity) == "Infinity" && text(-double.infinity) == "-Infinity");
}

@("Java Float.toString keeps float precision and the C_TINY subnormals")
unittest
{
    static string text(float value)
    {
        char[javaNumberCapacity] buffer;
        return buffer[0 .. formatJavaFloat(value, buffer)].idup;
    }

    assert(text(0.1f) == "0.1" && text(1.0f) == "1.0" && text(3.4028235e38f) == "3.4028235E38");
    assert(text(float.min_normal) == "1.1754944E-38");
    FloatView tiny;
    static immutable uint[4] floatBits = [1, 5, 7, 8];
    static immutable string[4] floatTexts = ["1.4E-45", "7.0E-45", "9.8E-45", "1.1E-44"];
    foreach (index, bits; floatBits)
    {
        tiny.raw = bits;
        assert(text(tiny.value) == floatTexts[index]);
    }
}
