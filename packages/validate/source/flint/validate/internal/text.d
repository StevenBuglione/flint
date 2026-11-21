module flint.validate.internal.text;

@safe:

package(flint.validate) int decodeScalar(scope const(ubyte)[] bytes, ref size_t offset) pure nothrow @nogc
{
    immutable first = bytes[offset++];
    if (first < 0x80)
        return first;

    uint codepoint;
    uint remaining;
    uint limit;
    if (first >= 0xC2 && first <= 0xDF)
    {
        remaining = 1;
        limit = 0x80;
        codepoint = first & 0x1F;
    }
    else if (first >= 0xE0 && first <= 0xEF)
    {
        remaining = 2;
        limit = 0x800;
        codepoint = first & 0x0F;
    }
    else if (first >= 0xF0 && first <= 0xF4)
    {
        remaining = 3;
        limit = 0x1_0000;
        codepoint = first & 0x07;
    }
    else
    {
        return -1;
    }

    if (remaining > bytes.length - offset)
        return -1;
    foreach (_; 0 .. remaining)
    {
        immutable next = bytes[offset++];
        if ((next & 0xC0) != 0x80)
            return -1;
        codepoint = (codepoint << 6) | (next & 0x3F);
    }

    return codepoint >= limit && codepoint <= 0x10_FFFF && (codepoint < 0xD800 || codepoint > 0xDFFF)
        ? cast(int) codepoint : -1;
}

private bool whiteSpace(uint codepoint) pure nothrow @nogc
{
    switch (codepoint)
    {
    case 0x0009: .. case 0x000D:
    case 0x2000:
            .. case 0x200A:
    case 0x0020:
    case 0x0085:
    case 0x00A0:
    case 0x1680:
    case 0x2028:
    case 0x2029:
    case 0x202F:
    case 0x205F:
    case 0x3000:
        return true;
    default:
        return false;
    }
}

package(flint.validate) bool nonBlank(scope const(ubyte)[] bytes) pure nothrow @nogc
{
    bool found;
    for (size_t offset; offset < bytes.length;)
    {
        immutable codepoint = decodeScalar(bytes, offset);
        if (codepoint < 0)
            return false;
        found = found || !whiteSpace(cast(uint) codepoint);
    }
    return found;
}

package(flint.validate) bool scalarSize(scope const(ubyte)[] bytes, size_t minimum, size_t maximum) pure nothrow @nogc
{
    size_t count;
    for (size_t offset; offset < bytes.length;)
    {
        if (count == maximum || decodeScalar(bytes, offset) < 0)
            return false;
        ++count;
    }
    return count >= minimum;
}

package(flint.validate) bool asciiEmail(scope const(ubyte)[] bytes) pure nothrow @nogc
{
    if (bytes.length < 3 || bytes.length > 254)
        return false;

    size_t separator;
    while (separator < bytes.length && bytes[separator] != '@')
        ++separator;
    return separator <= 64 && separator < bytes.length && validDotAtom(bytes[0 .. separator])
        && validDomain(bytes[separator + 1 .. $]);
}

private bool asciiLetterOrDigit(ubyte ch) pure nothrow @nogc
{
    return (ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
}

private bool validDotAtom(scope const(ubyte)[] part) pure nothrow @nogc
{
    bool lastDot = true;
    foreach (ch; part)
    {
        if (ch == '.')
        {
            if (lastDot)
                return false;
            lastDot = true;
        }
        else
        {
            if (!asciiLetterOrDigit(ch) && !localPunctuation(ch))
                return false;
            lastDot = false;
        }
    }
    return !lastDot;
}

private bool localPunctuation(ubyte ch) pure nothrow @nogc
{
    foreach (candidate; "!#$%&'*+-/=?^_`{|}~")
    {
        if (ch == candidate)
            return true;
    }
    return false;
}

private bool validDomain(scope const(ubyte)[] domain) pure nothrow @nogc
{
    size_t labelLength;
    bool hyphen;
    foreach (ch; domain)
    {
        if (ch == '.')
        {
            if (labelLength == 0 || hyphen)
                return false;
            labelLength = 0;
            continue;
        }
        if (++labelLength > 63)
            return false;
        hyphen = ch == '-';
        if (hyphen ? labelLength == 1 : !asciiLetterOrDigit(ch))
            return false;
    }
    return labelLength > 0 && !hyphen;
}
