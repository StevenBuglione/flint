/// Shared formatter options, width and precision, and scalar rendering.
module flint.java.util.internal.formatter_support;

import flint.engine.aot.text : decodeUtf8;

@safe:
package(flint.java):

enum Flag : uint
{
    left = 1 << 0,
    uppercase = 1 << 1,
    alternate = 1 << 2,
    plus = 1 << 3,
    space = 1 << 4,
    zero = 1 << 5,
    group = 1 << 6,
    parentheses = 1 << 7,
    previous = 1 << 8,
}

/// Width, precision and flags shared by the erased and specialised renderers.
struct FormatOptions
{
    uint flags;
    int width = -1;
    int precision = -1;
    char conversion;
    ubyte datePattern;

    bool has(Flag flag) const pure nothrow @nogc
    {
        return (flags & flag) != 0;
    }
}

char asciiLower(char c) pure nothrow @nogc
{
    return c >= 'A' && c <= 'Z' ? cast(char)(c + 'a' - 'A') : c;
}

char asciiUpper(char c) pure nothrow @nogc
{
    return c >= 'a' && c <= 'z' ? cast(char)(c + 'A' - 'a') : c;
}

/// Apply ASCII uppercase to a renderer's output.
string asciiUppercase(string text) pure nothrow
{
    auto upper = text.dup;
    foreach (ref c; upper)
        c = asciiUpper(c);
    return upper.idup;
}

string truncate(const ref FormatOptions spec, string text) pure nothrow
{
    if (spec.precision < 0 || spec.precision >= text.length)
        return text;
    const prefix = utf16Prefix(text, spec.precision);
    if (prefix.end < text.length && prefix.units < spec.precision)
        return text[0 .. prefix.end] ~ "\uFFFD"; // R14 covers the high half of a split surrogate pair.
    return text[0 .. prefix.end];
}

/// Pad to the UTF-16 width with spaces on the left, or on the right with `-`.
string pad(const ref FormatOptions spec, string text) pure nothrow
{
    if (spec.width <= 0)
        return text;
    const prefix = utf16Prefix(text, spec.width);
    if (prefix.end < text.length || prefix.units == spec.width)
        return text;
    auto spaces = new char[](spec.width - prefix.units);
    spaces[] = ' ';
    return spec.has(Flag.left) ? text ~ spaces : spaces ~ text;
}

private struct TextPrefix
{
    size_t end;
    size_t units;
}

// Find the last complete UTF-8 boundary within the UTF-16 limit.
private TextPrefix utf16Prefix(scope const(char)[] text, size_t limit) pure nothrow @nogc
{
    TextPrefix prefix;
    while (prefix.end < text.length && prefix.units < limit)
    {
        if (text[prefix.end] < 0x80)
        {
            prefix.end++;
            prefix.units++;
            continue;
        }
        auto next = prefix.end;
        const units = decodeUtf8(text, next) > 0xffff ? 2u : 1u;
        if (units > limit - prefix.units)
            break;
        prefix.end = next;
        prefix.units += units;
    }
    return prefix;
}
