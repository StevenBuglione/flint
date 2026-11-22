module flint.cli.internal.convert;

import std.traits : Unqual, isDynamicArray, isIntegral, isUnsigned;

@safe:

package(flint.cli) template Element(T)
{
    static if (is(T : Item[], Item))
        alias Element = Item;
    else
        alias Element = void;
}

package(flint.cli) enum IsText(T) = isDynamicArray!T && is(Unqual!(Element!T) == char);
private enum IsFloat(T) = is(T == float) || is(T == double) || is(T == real);
private enum Scalar(T) = IsText!T || is(T == bool) || is(T == enum) || isIntegral!T || IsFloat!T;
package(flint.cli) enum IsRepeated(T) = isDynamicArray!T && !IsText!T;
package(flint.cli) enum Supported(T) = Scalar!T || (IsRepeated!T && Scalar!(Element!T));

package(flint.cli) string typeName(T)() pure nothrow @nogc
{
    static if (IsText!T)
        return "text";
    else static if (is(T == bool))
        return "boolean";
    else static if (IsRepeated!T)
        return typeName!(Element!T)();
    else
        return T.stringof;
}

package(flint.cli) void ownDefault(T)(ref T output)
{
    static if (IsRepeated!T || is(T == char[]))
        output = output.dup;
    static if (IsRepeated!T && is(Element!T == char[]))
    {
        foreach (ref item; output)
            item = item.dup;
    }
}

package(flint.cli) string apply(T)(ref T output, scope const(char)[] text, bool first) if (Supported!T)
{
    static if (IsRepeated!T)
    {
        Element!T value;
        const reason = convert(value, text);
        if (reason is null)
        {
            if (first)
                output = null;
            output ~= value;
        }
        return reason;
    }
    else
    {
        return convert(output, text);
    }
}

private string convert(T)(ref T output, scope const(char)[] text)
{
    static if (IsText!T)
    {
        static if (is(T == char[]))
            output = text.dup;
        else
            output = text.idup;
        return null;
    }
    else static if (is(T == bool))
    {
        if (text == "true" || text == "1")
            output = true;
        else if (text == "false" || text == "0")
            output = false;
        else
            return "expected true or false";
        return null;
    }
    else static if (is(T == enum))
    {
        static foreach (member; __traits(allMembers, T))
        {
            if (text == member)
            {
                output = __traits(getMember, T, member);
                return null;
            }
        }
        return "unknown enumerator";
    }
    else static if (isIntegral!T)
    {
        return convertInteger(output, text);
    }
    else
    {
        return convertFloat(output, text);
    }
}

private string convertInteger(T)(ref T output, scope const(char)[] text) pure nothrow @nogc
{
    static if (isUnsigned!T)
    {
        const parsed = readInteger(text, IntegerBounds(T.max));
        if (parsed.problem is null)
            output = cast(T) parsed.magnitude;
    }
    else
    {
        enum limit = cast(ulong)(-(T.min + 1)) + 1;
        const parsed = readInteger(text, IntegerBounds(T.max, limit));
        if (parsed.problem is null)
        {
            if (parsed.negative)
                output = parsed.magnitude == limit ? T.min : cast(T)-cast(long) parsed.magnitude;
            else
                output = cast(T) parsed.magnitude;
        }
    }
    return parsed.problem;
}

private struct Integer
{
    ulong magnitude;
    bool negative;
    string problem;
}

private struct IntegerBounds
{
    ulong positive;
    ulong negative;
}

private Integer readInteger(scope const(char)[] text, IntegerBounds limits) pure nothrow @nogc
{
    if (text.length == 0)
        return Integer(0, false, "expected a decimal integer");
    const negative = text[0] == '-';
    if (negative && limits.negative == 0)
        return Integer(0, false, "unsigned integer cannot be negative");
    if (negative || text[0] == '+')
        text = text[1 .. $];
    if (text.length == 0)
        return Integer(0, negative, "expected decimal digits");

    const bound = negative ? limits.negative : limits.positive;
    ulong magnitude;
    foreach (digit; text)
    {
        if (digit < '0' || digit > '9')
            return Integer(0, negative, "expected only decimal digits after the sign");
        const value = cast(ulong)(digit - '0');
        if (value > bound || magnitude > (bound - value) / 10)
            return Integer(0, negative, "integer is out of range");
        magnitude = magnitude * 10 + value;
    }
    return Integer(magnitude, negative);
}

private string convertFloat(T)(ref T output, scope const(char)[] text)
{
    import std.conv : ConvException, to;

    if (!isDecimal(text))
        return "expected a finite decimal number";
    try
    {
        const value = text.to!T;
        if (!(value > -T.infinity && value < T.infinity))
            return "number is not finite";
        output = value;
        return null;
    }
    catch (ConvException)
    {
        return "number is out of range";
    }
}

private size_t digits(scope const(char)[] text, size_t index) pure nothrow @nogc
{
    while (index < text.length && text[index] >= '0' && text[index] <= '9')
        ++index;
    return index;
}

private bool isDecimal(scope const(char)[] text) pure nothrow @nogc
{
    size_t start;
    if (text.length != 0 && (text[0] == '-' || text[0] == '+'))
        start = 1;
    size_t index = digits(text, start);
    bool mantissa = index != start;
    if (index < text.length && text[index] == '.')
    {
        ++index;
        const end = digits(text, index);
        mantissa = mantissa || end != index;
        index = end;
    }
    return mantissa && hasOnlyExponent(text[index .. $]);
}

private bool hasOnlyExponent(scope const(char)[] tail) pure nothrow @nogc
{
    if (tail.length == 0)
        return true;
    if (tail[0] != 'e' && tail[0] != 'E')
        return false;
    size_t exponent = 1;
    if (tail.length > exponent && (tail[exponent] == '-' || tail[exponent] == '+'))
        ++exponent;
    return tail.length > exponent && digits(tail, exponent) == tail.length;
}
