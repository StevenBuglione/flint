/** Lexical IPv6 checks shared by URI and URL. */
module flint.java.net.internal.ipv6literal;

@safe:

package(flint.java.net):

bool isScopeCharacter(char byte_) pure nothrow @nogc
{
    const lower = byte_ | 0x20;
    return (lower >= 'a' && lower <= 'z') || asciiDigit(byte_) >= 0 || byte_ == '_' || byte_ == '.';
}

bool validIpv6(scope const(char)[] input) pure nothrow @nogc
{
    const scopeStart = delimiter(input, '%');
    if (scopeStart < input.length && scopeStart + 1 == input.length)
        return false;

    const numeric = input[0 .. scopeStart];
    const compression = compressionStart(numeric);
    if (compression == numeric.length)
        return countIpv6Groups(numeric, true) == 8;

    const before = countIpv6Groups(numeric[0 .. compression], false);
    const after = countIpv6Groups(numeric[compression + 2 .. $], true);
    return before >= 0 && after >= 0 && before + after < 8;
}

private size_t compressionStart(scope const(char)[] text) pure nothrow @nogc
{
    foreach (index, byte_; text)
        if (byte_ == ':' && index + 1 < text.length && text[index + 1] == ':')
            return index;
    return text.length;
}

// An embedded IPv4 address occupies the last two groups of the full literal.
private int countIpv6Groups(scope const(char)[] text, bool acceptsIpv4) pure nothrow @nogc
{
    if (text.length == 0)
        return 0;

    int groups;
    while (text.length != 0)
    {
        const end = delimiter(text, ':');
        const group = text[0 .. end];
        if (acceptsIpv4 && end == text.length && delimiter(group, '.') < group.length)
            return validIpv4(group) ? groups + 2 : -1;
        if (!validHexGroup(group) || ++groups > 8)
            return -1;
        if (end == text.length)
            return groups;
        text = text[end + 1 .. $];
    }
    return -1;
}

private bool validHexGroup(scope const(char)[] text) pure nothrow @nogc
{
    if (text.length == 0 || text.length > 4)
        return false;
    foreach (byte_; text)
    {
        const lower = byte_ | 0x20;
        if (asciiDigit(byte_) < 0 && (lower < 'a' || lower > 'f'))
            return false;
    }
    return true;
}

private bool validIpv4(scope const(char)[] text) pure nothrow @nogc
{
    foreach (section; 0 .. 4)
    {
        const end = delimiter(text, '.');
        if (end == 0 || (end == text.length) != (section == 3))
            return false;
        int value;
        foreach (byte_; text[0 .. end])
        {
            const digit = asciiDigit(byte_);
            if (digit < 0 || (value = 10 * value + digit) > 255)
                return false;
        }
        if (section != 3)
            text = text[end + 1 .. $];
    }
    return true;
}

private size_t delimiter(scope const(char)[] text, char wanted) pure nothrow @nogc
{
    foreach (position, byte_; text)
        if (byte_ == wanted)
            return position;
    return text.length;
}

private int asciiDigit(char value) pure nothrow @nogc
{
    return value >= '0' && value <= '9' ? value - '0' : -1;
}
