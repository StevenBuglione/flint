/// Numeric sign and zero padding for Java Formatter.
module flint.java.util.internal.formatter_number_padding;

import flint.java.util.internal.formatter_support : Flag, FormatOptions;

@safe:
package(flint.java):

/// Apply the sign flags and zero padding to `body`, the magnitude's digits.
string signed(const ref FormatOptions spec, string body, bool negative) pure nothrow
{
    const suffix = negative && spec.has(Flag.parentheses) ? ")" : "";
    return paddedNumber(spec, numberSign(spec, negative), body, suffix);
}

string numberSign(const ref FormatOptions spec, bool negative) pure nothrow @nogc
{
    return negative ? (spec.has(Flag.parentheses) ? "(" : "-") : spec.has(Flag.plus)
        ? "+" : spec.has(Flag.space) ? " " : "";
}

string numberZeros(size_t count) pure nothrow
{
    if (count == 0)
        return "";
    auto zeros = new char[count];
    zeros[] = '0';
    return zeros.idup;
}

/// Zero padding follows a sign or radix indicator and precedes the digits.
string paddedNumber(const ref FormatOptions spec, string prefix, string body, string suffix) pure nothrow
{
    if (spec.has(Flag.zero) && spec.width > 0)
    {
        const used = prefix.length + body.length + suffix.length;
        if (used < spec.width)
            body = numberZeros(spec.width - used) ~ body;
    }
    return prefix ~ body ~ suffix;
}
