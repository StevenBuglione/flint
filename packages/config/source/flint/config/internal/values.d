module flint.config.internal.values;

import core.lifetime : move;
import flint.config.internal.sources : InputValue, validUtf8;
import flint.serde.owned : deserialize;

@safe:

private struct Box(T)
{
    T value;
}

/// Bind a field; decoder instantiations happen in the module that instantiates load.
package(flint.config) bool coerce(T)(InputValue source, ref T value)
{
    return coerceValue(source, value);
}

private bool coerceValue(T)(InputValue source, ref T value)
{
    if (source.json)
    {
        auto decoded = deserialize!(Box!T)("{\"value\":" ~ source.text ~ "}");
        if (!decoded.ok)
            return false;
        value = move(decoded.value.value);
        return true;
    }
    return fromText(source.text, value);
}

private bool digits(string input, ref size_t index) pure nothrow @nogc
{
    const original = index;
    while (index < input.length && input[index] >= '0' && input[index] <= '9')
        ++index;
    return index != original;
}

private bool decimal(string input, bool fractional, bool signed) pure nothrow @nogc
{
    size_t index;
    if (input.length != 0 && (input[0] == '+' || input[0] == '-'))
    {
        if (!signed && input[0] == '-')
            return false;
        ++index;
    }
    if (!digits(input, index))
        return false;
    if (fractional && index < input.length && input[index] == '.')
    {
        ++index;
        if (!digits(input, index))
            return false;
    }
    if (index == input.length)
        return true;
    return fractional && exponent(input, index);
}

private bool exponent(string input, size_t index) pure nothrow @nogc
{
    if (input[index] != 'e' && input[index] != 'E')
        return false;
    ++index;
    if (index < input.length && (input[index] == '+' || input[index] == '-'))
        ++index;
    return digits(input, index) && index == input.length;
}

private bool arrayValues(Element)(string input, ref Element[] values)
{
    if (input.length == 0)
        return true;
    char[] part;
    bool escaped;
    foreach (ch; input)
    {
        if (escaped)
        {
            if (ch != ',' && ch != '\\')
                return false;
            part ~= ch;
            escaped = false;
        }
        else if (ch == '\\')
            escaped = true;
        else if (ch == ',')
        {
            Element item;
            if (!fromText(part.idup, item))
                return false;
            values ~= item;
            part.length = 0;
        }
        else
            part ~= ch;
    }
    Element last;
    if (escaped || !fromText(part.idup, last))
        return false;
    values ~= last;
    return true;
}

// Rewrite accepted decimal text in JSON number syntax: no plus sign or redundant leading zeros.
private string jsonNumber(string input)
{
    size_t index;
    string sign;
    if (input[0] == '+' || input[0] == '-')
    {
        sign = input[0] == '-' ? "-" : "";
        index = 1;
    }
    while (index + 1 < input.length && input[index] == '0' && input[index + 1] >= '0' && input[index + 1] <= '9')
        ++index;
    return sign ~ input[index .. $];
}

// std.traits.isFloatingPoint, isIntegral and isUnsigned without their instantiations per field type.
private enum bool floating(T) = __traits(isFloating, T) && is(T : real);

private template integral(T)
{
    static if (!__traits(isIntegral, T))
        enum integral = false;
    else static if (is(T Base == enum))
        enum integral = integral!Base;
    else
        enum integral = __traits(isZeroInit, T) && !is(immutable T == immutable bool) && !is(T == __vector);
}

private template unsigned(T)
{
    static if (!__traits(isUnsigned, T))
        enum unsigned = false;
    else static if (is(T Base == enum))
        enum unsigned = unsigned!Base;
    else
        enum unsigned = __traits(isZeroInit, T) && !is(immutable T == immutable bool) && !is(T == __vector);
}

private bool number(T)(string input, ref T value)
{
    if (!decimal(input, floating!T, !unsigned!T))
        return false;
    static if (floating!T)
    {
        // Use the same correctly rounded conversion as JSON and TOML file values.
        return coerceValue(InputValue(jsonNumber(input), InputValue.init.origin, true), value);
    }
    else
        return integer(input, value);
}

private struct Magnitude
{
    bool valid;
    bool negative;
    bool signed;
    ulong value;
}

// Sign and magnitude of `[+-]?[0-9]+` text; not valid when the magnitude exceeds ulong.
private Magnitude magnitudeOf(string input) pure nothrow @nogc
{
    Magnitude result;
    size_t index;
    if (input.length != 0 && (input[0] == '+' || input[0] == '-'))
    {
        result.negative = input[0] == '-';
        result.signed = true;
        index = 1;
    }
    if (index == input.length)
        return result;
    for (; index < input.length; ++index)
    {
        const ch = input[index];
        if (ch < '0' || ch > '9')
            return result;
        const digit = ch - '0';
        if (result.value > (ulong.max - digit) / 10)
            return result;
        result.value = result.value * 10 + digit;
    }
    result.valid = true;
    return result;
}

// The values std.conv.to!T accepts for validated decimal text: in-range integers, a sign only on signed types,
// and nothing for enums, whose conversion from text matches member names.
private bool integer(T)(string input, ref T value)
{
    static if (is(T == enum))
        return false;
    else
    {
        const parsed = magnitudeOf(input);
        if (!parsed.valid)
            return false;
        static if (__traits(isUnsigned, T))
        {
            if (parsed.signed || parsed.value > T.max)
                return false;
            value = cast(T) parsed.value;
        }
        else
        {
            if (parsed.value > (parsed.negative ? cast(ulong) T.max + 1 : cast(ulong) T.max))
                return false;
            value = cast(T)(parsed.negative ? 0 - parsed.value : parsed.value);
        }
        return true;
    }
}

private bool fromText(T)(string input, ref T value)
{
    static if (is(T == string))
    {
        if (!validUtf8(input))
            return false;
        value = input;
        return true;
    }
    else static if (is(T == bool))
    {
        if (input != "true" && input != "false")
            return false;
        value = input == "true";
        return true;
    }
    else static if (integral!T || floating!T)
        return number(input, value);
    else static if (is(T == Element[extent], Element, size_t extent))
    {
        Element[] parsed;
        if (!arrayValues(input, parsed) || parsed.length != extent)
            return false;
        value[] = parsed[];
        return true;
    }
    else static if (is(T == Element[], Element))
    {
        Element[] parsed;
        if (!arrayValues(input, parsed))
            return false;
        value = parsed;
        return true;
    }
    else
        static assert(false, "unsupported configuration field type " ~ T.stringof);
}

version (unittest)
{
    @("decimal integer fields accept exactly what std.conv.to accepts")
    unittest
    {
        import std.conv : to;
        import std.meta : AliasSeq;

        enum Small : byte
        {
            low = -1,
            high = 1
        }

        enum Wide : ulong
        {
            one = 1
        }

        static immutable string[] corpus = [
            "0", "1", "+0", "-0", "+1", "-1", "007", "-007", "+007", "127", "128", "-128", "-129",
            "255", "256", "+255", "32767", "32768", "-32768", "-32769", "65535", "65536", "2147483647",
            "2147483648", "-2147483648", "-2147483649", "4294967295", "4294967296",
            "9223372036854775807", "9223372036854775808", "-9223372036854775808",
            "-9223372036854775809", "18446744073709551615", "18446744073709551616",
            "-18446744073709551615", "99999999999999999999", "0000000000000000000000000000001",
            "+18446744073709551615"
        ];
        static foreach (T; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, Small, Wide))
        {
            foreach (text; corpus)
            {
                T expected = T.max;
                bool converted = true;
                try
                    expected = to!T(text);
                catch (Exception)
                    converted = false;
                T actual = T.max;
                assert(integer(text, actual) == converted, T.stringof ~ " " ~ text);
                assert(actual == expected, T.stringof ~ " " ~ text);
            }
        }
    }
}
