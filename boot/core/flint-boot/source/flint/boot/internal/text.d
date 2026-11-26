/++
Boot's own string helpers (Flint addition), in place of std.conv, std.uni, std.string, std.array and std.algorithm.
Each of those links a Phobos object whose references reach std.socket and std.net.curl, and through them the
loggers, std.regex, std.zip and std.json, into every app (playbook S-9, S-21).

Case mapping is per code point, as `flint.java.character` maps it (JDK 21, simple mappings): the same as std.uni's
for every character without a multi-character mapping (`ß`, ligatures), which property names and values Boot
compares never hold.
+/
module flint.boot.internal.text;

@safe:

/// `text` with every code point upper-cased.
string upperCase(string text) pure nothrow
{
    return mapped!true(text);
}

/// `text` with every code point lower-cased.
string lowerCase(string text) pure nothrow
{
    return mapped!false(text);
}

private string mapped(bool upper)(string text) pure nothrow
{
    import flint.engine.aot.text : decodeUtf8, utf8;
    import flint.java.character : toLowerCase, toUpperCase;

    foreach (i, c; text)
    {
        if (c >= 0x80 || (upper ? c >= 'a' && c <= 'z' : c >= 'A' && c <= 'Z'))
        {
            // Something changes, or might: copy the unchanged prefix, then map the rest.
            string result = text[0 .. i];
            size_t index = i;
            while (index < text.length)
            {
                const unit = text[index];
                if (unit < 0x80)
                {
                    result ~= upper ? (unit >= 'a' && unit <= 'z' ? cast(char)(unit - 32) : unit) : (unit >= 'A'
                            && unit <= 'Z' ? cast(char)(unit + 32) : unit);
                    index++;
                    continue;
                }
                const start = index;
                const code = decodeUtf8(text, index);
                const changed = upper ? toUpperCase(code) : toLowerCase(code);
                result ~= changed == code ? text[start .. index] : utf8(changed);
            }
            return result;
        }
    }
    return text;
}

/// Whether `a` and `b` are equal ignoring case, as std.uni's `sicmp(a, b) == 0` for text without multi-character
/// mappings.
bool equalsIgnoreCase(string a, string b) pure nothrow
{
    return (a.length == b.length && a == b) || lowerCase(a) == lowerCase(b);
}

/// `text` with every `from` replaced by `to`, left to right, as std.array's `replace`.
string replaced(string text, scope const(char)[] from, scope const(char)[] to) pure nothrow
{
    if (from.length == 0 || text.length < from.length)
        return text;
    string result;
    size_t start, i;
    while (i + from.length <= text.length)
    {
        if (text[i .. i + from.length] == from)
        {
            result ~= text[start .. i];
            result ~= to;
            i += from.length;
            start = i;
        }
        else
            i++;
    }
    return start == 0 ? text : result ~ text[start .. $];
}

/// `values` joined by `separator`, as std.array's `join`.
string joined(scope const string[] values, scope const(char)[] separator) pure nothrow
{
    string result;
    foreach (i, value; values)
    {
        if (i != 0)
            result ~= separator;
        result ~= value;
    }
    return result;
}

/// The pieces of `text` between `separator`s, empty ones included, as std.array's `split(text, separator)`: none
/// for an empty text.
string[] pieces(string text, char separator) pure nothrow
{
    if (text.length == 0)
        return null;
    string[] result;
    size_t start;
    foreach (i, c; text)
    {
        if (c != separator)
            continue;
        result ~= text[start .. i];
        start = i + 1;
    }
    return result ~ text[start .. $];
}

/// The index of the first `needle` in `text`, or -1, as std.string's `indexOf`.
ptrdiff_t indexOf(scope const(char)[] text, scope const(char)[] needle) pure nothrow @nogc
{
    if (needle.length > text.length)
        return -1;
    foreach (i; 0 .. text.length - needle.length + 1)
        if (text[i .. i + needle.length] == needle)
            return i;
    return -1;
}

/// The index of the first `c` in `text`, or -1.
ptrdiff_t indexOf(scope const(char)[] text, char c) pure nothrow @nogc
{
    foreach (i, d; text)
        if (d == c)
            return i;
    return -1;
}

/// Whether `text` starts with `prefix`.
bool startsWith(scope const(char)[] text, scope const(char)[] prefix) pure nothrow @nogc
{
    return text.length >= prefix.length && text[0 .. prefix.length] == prefix;
}

/// Whether `text` ends with `suffix`.
bool endsWith(scope const(char)[] text, scope const(char)[] suffix) pure nothrow @nogc
{
    return text.length >= suffix.length && text[$ - suffix.length .. $] == suffix;
}

/// Whether `text` contains `fragment`.
bool contains(scope const(char)[] text, scope const(char)[] fragment) pure nothrow @nogc
{
    return indexOf(text, fragment) >= 0;
}

/// `text` without trailing white space, as std.string's `stripRight` (the characters std.uni's isWhite accepts).
string stripTrailing(string text) pure nothrow
{
    import flint.engine.aot.text : stripWhite;

    // stripWhite strips both ends: the leading white space is what it strips when the end cannot be stripped.
    const both = stripWhite(text);
    if (both.length == 0)
        return text[0 .. 0];
    const lead = text.length + 1 - stripWhite(text ~ 'x').length;
    return text[0 .. lead + both.length];
}

/// `values` sorted in place by code unit, as std.algorithm's `sort` orders strings (insertion sort: Boot sorts
/// short lists).
string[] sortStrings(string[] values) pure nothrow @nogc
{
    foreach (i; 1 .. values.length)
    {
        auto value = values[i];
        size_t j = i;
        for (; j > 0 && values[j - 1] > value; j--)
            values[j] = values[j - 1];
        values[j] = value;
    }
    return values;
}

/// `chars` as UTF-8, as std.conv's `to!string` of a `dchar[]`.
string utf8Text(scope const(dchar)[] chars) pure nothrow
{
    import flint.engine.aot.text : utf8;

    string result;
    foreach (c; chars)
        result ~= c < 0x80 ? [cast(char) c] : utf8(c);
    return result;
}

/// The code points of valid UTF-8 `text`, as std.conv's `to!dstring`; null when `text` is not valid UTF-8.
dstring utf32Text(scope const(char)[] text) pure nothrow
{
    import flint.engine.aot.text : decodeUtf8, isValidUtf8;

    if (!isValidUtf8(text))
        return null;
    dchar[] result;
    size_t index;
    while (index < text.length)
        result ~= decodeUtf8(text, index);
    return result.idup;
}

/// Reads digits in `radix` (2 to 16, no sign or prefix), at most `max`; false for anything else.
bool parseUnsigned(scope const(char)[] digits, uint radix, ulong max, out ulong value) pure nothrow @nogc
{
    if (digits.length == 0 || radix < 2 || radix > 16)
        return false;
    ulong result;
    foreach (c; digits)
    {
        uint digit = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A'
            && c <= 'F' ? c - 'A' + 10 : 16;
        if (digit >= radix || result > (max - digit) / radix)
            return false;
        result = result * radix + digit;
    }
    value = result;
    return true;
}

/// Reads a hexadecimal integer of digits only, at most `long.max`; false for anything else.
bool parseHex(scope const(char)[] digits, out long value) pure nothrow @nogc
{
    if (digits.length == 0)
        return false;
    ulong result;
    foreach (c; digits)
    {
        uint digit;
        if (c >= '0' && c <= '9')
            digit = c - '0';
        else if (c >= 'a' && c <= 'f')
            digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F')
            digit = c - 'A' + 10;
        else
            return false;
        if (result > (long.max - digit) / 16)
            return false;
        result = result * 16 + digit;
    }
    value = cast(long) result;
    return true;
}

unittest
{
    import std.uni : sicmp, toLower, toUpper;

    // Case: std.uni's, for ASCII and for characters with one-character mappings.
    static immutable string[] texts = [
        "", "abc", "ABC", "server.port", "Été", "çaÇA", "x-y_Z9", "ΑβΓ", "İ"
    ];
    foreach (text; texts ~ "日本")
    {
        assert(upperCase(text) == text.toUpper, text);
        assert(lowerCase(text) == text.toLower, text);
    }
    assert(upperCase("abc") == "ABC" && lowerCase("ABC") == "abc");
    const same = "ABC";
    assert(upperCase(same) is same); // nothing to change: no copy
    foreach (pair; [
            ["PostgreSQL", "postgresql"], ["H2", "h2"], ["a", "b"], ["été", "ÉTÉ"], [
                "ab", "abc"
            ]
        ])
        assert(equalsIgnoreCase(pair[0], pair[1]) == (sicmp(pair[0], pair[1]) == 0), pair[0]);

}

unittest
{
    import std.array : join, replace, split;
    import std.string : indexOf, stripRight;

    // Replace, join, split, indexOf, stripRight: std's.
    foreach (text; ["", "a.b.c", "...", "a\\${b}\\${", "no dots", "a..b"])
        foreach (pair; [[".", "_"], ["\\${", "${"], ["..", "-"]])
            assert(replaced(text, pair[0], pair[1]) == text.replace(pair[0], pair[1]), text);
    assert(joined(["a", "b", "c"], ",") == ["a", "b", "c"].join(",") && joined(null, ",") == "");
    foreach (text; ["a,b", ",a,,b,", "", ",", "abc"])
        assert(pieces(text, ',') == text.split(","), text);
    foreach (text; ["abc", "", "a.b", "..", "x"])
    {
        assert(indexOf(text, ".") == text.indexOf("."), text);
        assert(indexOf(text, '.') == text.indexOf('.'), text);
    }
    foreach (text; ["", "  ", "a  ", "  a", " a \t\n", "a ", "a"])
        assert(stripTrailing(text) == text.stripRight, text);
    assert(startsWith("abc", "ab") && !startsWith("a", "ab") && endsWith("abc", "bc") && !endsWith("c", "bc"));
    assert(contains("abc", "b") && !contains("abc", "d") && contains("abc", ""));

}

unittest
{
    // Sorting: std.algorithm's order.
    import std.algorithm.sorting : sort;

    foreach (list; [["b", "a", "c"], [], ["x"], ["B", "a", "A", "b", "a"]])
    {
        auto mine = list.dup, theirs = list.dup;
        assert(sortStrings(mine) == theirs.sort.release);
    }

}

unittest
{
    // UTF-8 and UTF-32: std.conv's.
    import std.conv : to;

    foreach (text; ["", "abc", "é日😀", "a b"])
    {
        assert(utf32Text(text) == text.to!dstring, text);
        assert(utf8Text(text.to!dstring) == text, text);
    }
    assert(utf32Text("\xFF") is null && utf32Text("a\xC3") is null);

}

unittest
{
    import std.conv : to;

    // Radixes: std.conv's for values in range.
    ulong unsigned;
    foreach (text; ["0", "1", "777", "ff", "1010", "18446744073709551615"])
        foreach (radix; [2u, 8, 10, 16])
        {
            bool theirs = true;
            ulong expected;
            try
                expected = text.to!ulong(radix);
            catch (Exception)
                theirs = false;
            const mine = parseUnsigned(text, radix, ulong.max, unsigned);
            assert(mine == theirs && (!theirs || unsigned == expected), text);
        }
    assert(!parseUnsigned("", 10, ulong.max, unsigned) && !parseUnsigned("100", 10, 99, unsigned));
    assert(parseUnsigned("99", 10, 99, unsigned) && unsigned == 99 && !parseUnsigned("-1", 10, 9, unsigned));

}

unittest
{
    // Hex: digits only, within long.
    long value;
    assert(parseHex("ff", value) && value == 255 && parseHex("7FFFFFFFFFFFFFFF", value) && value == long.max);
    assert(!parseHex("", value) && !parseHex("8000000000000000", value) && !parseHex("-1", value));
    assert(!parseHex("0x1", value) && !parseHex("g", value));
}
