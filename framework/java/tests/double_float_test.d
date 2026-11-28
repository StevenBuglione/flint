// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.lang.double_float_test;

import flint.java.lang : NumberFormatException;
import flint.java.lang.double_ : Double;
import flint.java.lang.float_ : Float;

@safe:

// The message of the NumberFormatException `fn` throws, or null when it returns.
private string failure(scope void delegate() @safe fn)
{
    try
        fn();
    catch (NumberFormatException e)
        return e.msg.length ? e.msg : "(empty)";
    return null;
}

@("Double and Float constants match Java")
unittest
{
    static assert(Double.MIN_VALUE == double.min_normal * double.epsilon);
    static assert(Double.MAX_VALUE == double.max && Double.MIN_NORMAL == double.min_normal);
    static assert(Double.PRECISION == 53 && Double.MAX_EXPONENT == 1023 && Double.MIN_EXPONENT == -1022);
    static assert(Double.SIZE == 64 && Double.BYTES == 8);
    static assert(Double.NaN != Double.NaN && Double.POSITIVE_INFINITY == double.infinity);
    static assert(Double.NEGATIVE_INFINITY == -double.infinity);

    static assert(Float.MIN_VALUE == float.min_normal * float.epsilon);
    static assert(Float.MAX_VALUE == float.max && Float.MIN_NORMAL == float.min_normal);
    static assert(Float.PRECISION == 24 && Float.MAX_EXPONENT == 127 && Float.MIN_EXPONENT == -126);
    static assert(Float.SIZE == 32 && Float.BYTES == 4);
    static assert(Float.NaN != Float.NaN && Float.POSITIVE_INFINITY == float.infinity);
    static assert(Float.NEGATIVE_INFINITY == -float.infinity);
}

@("Double.toString and Float.toString match Java's shortest round-trip text")
unittest
{
    assert(Double.toString(1.5) == "1.5");
    assert(Double.toString(0.0) == "0.0");
    assert(Double.toString(-0.0) == "-0.0");
    assert(Double.toString(1.0) == "1.0");
    assert(Double.toString(1.0e20) == "1.0E20");
    assert(Double.toString(Double.NaN) == "NaN");
    assert(Double.toString(Double.POSITIVE_INFINITY) == "Infinity");
    assert(Double.toString(Double.NEGATIVE_INFINITY) == "-Infinity");

    assert(Float.toString(1.5f) == "1.5");
    assert(Float.toString(0.0f) == "0.0");
    assert(Float.toString(-0.0f) == "-0.0");
    assert(Float.toString(1.0f) == "1.0");
    assert(Float.toString(1.0e20f) == "1.0E20");
    assert(Float.toString(Float.NaN) == "NaN");
    assert(Float.toString(Float.POSITIVE_INFINITY) == "Infinity");
    assert(Float.toString(Float.NEGATIVE_INFINITY) == "-Infinity");
}

@("Double.toHexString and Float.toHexString match Java's C99 text")
unittest
{
    assert(Double.toHexString(1.0) == "0x1.0p0");
    assert(Double.toHexString(0.0) == "0x0.0p0");
    assert(Double.toHexString(-0.0) == "-0x0.0p0");
    assert(Double.toHexString(2.0) == "0x1.0p1");
    assert(Double.toHexString(0.5) == "0x1.0p-1");
    assert(Double.toHexString(-1.0) == "-0x1.0p0");
    assert(Double.toHexString(Double.MIN_VALUE) == "0x0.0000000000001p-1022");
    assert(Double.toHexString(Double.MIN_NORMAL) == "0x1.0p-1022");
    assert(Double.toHexString(Double.MAX_VALUE) == "0x1.fffffffffffffp1023");
    assert(Double.toHexString(Double.NaN) == "NaN");
    assert(Double.toHexString(Double.POSITIVE_INFINITY) == "Infinity");
    assert(Double.toHexString(Double.NEGATIVE_INFINITY) == "-Infinity");

    assert(Float.toHexString(1.0f) == "0x1.0p0");
    assert(Float.toHexString(0.0f) == "0x0.0p0");
    assert(Float.toHexString(-0.0f) == "-0x0.0p0");
    assert(Float.toHexString(2.0f) == "0x1.0p1");
    assert(Float.toHexString(0.5f) == "0x1.0p-1");
    assert(Float.toHexString(-1.0f) == "-0x1.0p0");
    assert(Float.toHexString(Float.MIN_VALUE) == "0x0.000002p-126");
    assert(Float.toHexString(Float.MIN_NORMAL) == "0x1.0p-126");
    assert(Float.toHexString(Float.MAX_VALUE) == "0x1.fffffep127");
    assert(Float.toHexString(Float.NaN) == "NaN");
    assert(Float.toHexString(Float.POSITIVE_INFINITY) == "Infinity");
    assert(Float.toHexString(Float.NEGATIVE_INFINITY) == "-Infinity");
}

@("parseDouble and parseFloat accept Java's decimal and hexadecimal forms")
unittest
{
    assert(Double.parseDouble("1.5") == 1.5);
    assert(Double.parseDouble("1.0f") == 1.0);
    assert(Double.parseDouble("1.0d") == 1.0);
    assert(Double.parseDouble("0x1.8p1") == 3.0);
    assert(Double.parseDouble("0x1.8p+1") == 3.0);
    assert(Double.parseDouble("0x1.8p-1") == 0.75);
    assert(Double.parseDouble("NaN") != Double.parseDouble("NaN"));
    assert(Double.parseDouble("Infinity") == double.infinity);
    assert(Double.parseDouble("-Infinity") == -double.infinity);
    assert(Double.parseDouble("1e400") == double.infinity);
    assert(Double.parseDouble("1e-400") == 0.0);
    assert(Double.parseDouble("-0.0") == 0.0);

    assert(Float.parseFloat("1.5") == 1.5f);
    assert(Float.parseFloat("1.0f") == 1.0f);
    assert(Float.parseFloat("1.0d") == 1.0f);
    assert(Float.parseFloat("0x1.8p1") == 3.0f);
    assert(Float.parseFloat("NaN") != Float.parseFloat("NaN"));
    assert(Float.parseFloat("Infinity") == float.infinity);
    assert(Float.parseFloat("-Infinity") == -float.infinity);
    assert(Float.parseFloat("1e40") == float.infinity);
    assert(Float.parseFloat("1e-50") == 0.0f);
}

@("parseDouble and parseFloat report Java's messages")
unittest
{
    assert(failure({ Double.parseDouble(""); }) == "empty String");
    assert(failure({ Double.parseDouble("1.0x"); }) == `For input string: "1.0x"`);
    assert(failure({ Float.parseFloat(""); }) == "empty String");
    assert(failure({ Float.parseFloat("1.0x"); }) == `For input string: "1.0x"`);
}

@("valueOf returns the primitive and parses strings")
unittest
{
    assert(Double.valueOf(1.5) == 1.5);
    assert(Double.valueOf("1.5") == 1.5);
    assert(Float.valueOf(1.5f) == 1.5f);
    assert(Float.valueOf("1.5") == 1.5f);
}

@("isNaN, isInfinite and isFinite match Java's classification")
unittest
{
    assert(Double.isNaN(Double.NaN) && !Double.isNaN(1.0));
    assert(Double.isInfinite(Double.POSITIVE_INFINITY) && Double.isInfinite(Double.NEGATIVE_INFINITY));
    assert(!Double.isInfinite(1.0) && !Double.isInfinite(Double.NaN));
    assert(Double.isFinite(1.0) && !Double.isFinite(Double.NaN) && !Double.isFinite(Double.POSITIVE_INFINITY));

    assert(Float.isNaN(Float.NaN) && !Float.isNaN(1.0f));
    assert(Float.isInfinite(Float.POSITIVE_INFINITY) && Float.isInfinite(Float.NEGATIVE_INFINITY));
    assert(!Float.isInfinite(1.0f) && !Float.isInfinite(Float.NaN));
    assert(Float.isFinite(1.0f) && !Float.isFinite(Float.NaN) && !Float.isFinite(Float.POSITIVE_INFINITY));
}

@("bit conversions round-trip and canonicalise NaN")
unittest
{
    assert(Double.longBitsToDouble(Double.doubleToRawLongBits(1.5)) == 1.5);
    assert(Double.longBitsToDouble(Double.doubleToLongBits(1.5)) == 1.5);
    assert(Double.doubleToLongBits(Double.NaN) == 0x7ff8_0000_0000_0000L);
    assert(Double.doubleToLongBits(Double.NaN) == Double.doubleToLongBits(-Double.NaN));

    assert(Float.intBitsToFloat(Float.floatToRawIntBits(1.5f)) == 1.5f);
    assert(Float.intBitsToFloat(Float.floatToIntBits(1.5f)) == 1.5f);
    assert(Float.floatToIntBits(Float.NaN) == 0x7fc0_0000);
    assert(Float.floatToIntBits(Float.NaN) == Float.floatToIntBits(-Float.NaN));
}

@("hashCode and compare match Java's total order")
unittest
{
    assert(Double.hashCode(1.5) == cast(int)(Double.doubleToLongBits(1.5) ^ (Double.doubleToLongBits(1.5) >>> 32)));
    assert(Double.compare(1.0, 2.0) < 0 && Double.compare(2.0, 1.0) > 0 && Double.compare(1.0, 1.0) == 0);
    assert(Double.compare(Double.NaN, Double.NaN) == 0);
    assert(Double.compare(Double.NaN, Double.POSITIVE_INFINITY) > 0);
    assert(Double.compare(-0.0, 0.0) < 0);

    assert(Float.hashCode(1.5f) == Float.floatToIntBits(1.5f));
    assert(Float.compare(1.0f, 2.0f) < 0 && Float.compare(2.0f, 1.0f) > 0 && Float.compare(1.0f, 1.0f) == 0);
    assert(Float.compare(Float.NaN, Float.NaN) == 0);
    assert(Float.compare(Float.NaN, Float.POSITIVE_INFINITY) > 0);
    assert(Float.compare(-0.0f, 0.0f) < 0);
}

@("sum, max and min follow Java's signed-zero and NaN rules")
unittest
{
    assert(Double.sum(1.5, 2.5) == 4.0);
    assert(Double.max(1.0, 2.0) == 2.0 && Double.min(1.0, 2.0) == 1.0);
    assert(Double.max(Double.NaN, 1.0) != Double.max(Double.NaN, 1.0));
    assert(Double.min(Double.NaN, 1.0) != Double.min(Double.NaN, 1.0));
    assert(Double.max(-0.0, 0.0) == 0.0 && Double.min(-0.0, 0.0) == -0.0);

    assert(Float.sum(1.5f, 2.5f) == 4.0f);
    assert(Float.max(1.0f, 2.0f) == 2.0f && Float.min(1.0f, 2.0f) == 1.0f);
    assert(Float.max(Float.NaN, 1.0f) != Float.max(Float.NaN, 1.0f));
    assert(Float.min(Float.NaN, 1.0f) != Float.min(Float.NaN, 1.0f));
    assert(Float.max(-0.0f, 0.0f) == 0.0f && Float.min(-0.0f, 0.0f) == -0.0f);
}

@("float16ToFloat and floatToFloat16 match Java's binary16 conversions")
unittest
{
    assert(Float.float16ToFloat(cast(short) 0x0000) == 0.0f);
    assert(Float.float16ToFloat(cast(short) 0x8000) == -0.0f);
    assert(Float.float16ToFloat(cast(short) 0x3c00) == 1.0f);
    assert(Float.float16ToFloat(cast(short) 0xbc00) == -1.0f);
    assert(Float.float16ToFloat(cast(short) 0x7bff) == 65_504.0f);
    assert(Float.float16ToFloat(cast(short) 0x7c00) == float.infinity);
    assert(Float.float16ToFloat(cast(short) 0xfc00) == -float.infinity);
    assert(Float.float16ToFloat(cast(short) 0x0001) == 0x1p-24f);

    assert(Float.floatToFloat16(0.0f) == cast(short) 0x0000);
    assert(Float.floatToFloat16(-0.0f) == cast(short) 0x8000);
    assert(Float.floatToFloat16(1.0f) == cast(short) 0x3c00);
    assert(Float.floatToFloat16(-1.0f) == cast(short) 0xbc00);
    assert(Float.floatToFloat16(65_504.0f) == cast(short) 0x7bff);
    assert(Float.floatToFloat16(65_536.0f) == cast(short) 0x7c00);
    assert(Float.floatToFloat16(0.5f) == cast(short) 0x3800);
    assert(Float.floatToFloat16(0x1p-24f) == cast(short) 0x0001);
    assert(Float.floatToFloat16(0x1p-25f) == cast(short) 0x0000);

    // NaN stays NaN with its sign, and a rounding tie goes to the even significand.
    assert(Float.float16ToFloat(cast(short) 0x7e00) != Float.float16ToFloat(cast(short) 0x7e00));
    assert(Float.floatToFloat16(Float.NaN) == cast(short) 0x7e00);
    assert(Float.floatToFloat16(1.0f + 0x1p-11f) == cast(short) 0x3c00);
    assert(Float.floatToFloat16(1.0f + 0x3p-11f) == cast(short) 0x3c02);
}
