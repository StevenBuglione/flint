module flint.config.internal.values;

import core.lifetime : move;
import flint.config.internal.sources : InputValue;
import flint.serde.owned : deserialize;
import std.conv : to;
import std.traits : isFloatingPoint, isIntegral, isUnsigned;
import std.utf : validate;

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

private bool number(T)(string input, ref T value)
{
    if (!decimal(input, isFloatingPoint!T, !isUnsigned!T))
        return false;
    static if (isFloatingPoint!T)
    {
        // Use the same correctly rounded conversion as JSON and TOML file values.
        return coerceValue(InputValue(jsonNumber(input), InputValue.init.origin, true), value);
    }
    else
        return integer(input, value);
}

private bool integer(T)(string input, ref T value)
{
    T parsed;
    try
        parsed = to!T(input);
    catch (Exception)
        return false;
    value = parsed;
    return true;
}

private bool fromText(T)(string input, ref T value)
{
    static if (is(T == string))
    {
        try
            validate(input);
        catch (Exception)
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
    else static if (isIntegral!T || isFloatingPoint!T)
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
