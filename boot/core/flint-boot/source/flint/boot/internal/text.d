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
    foreach (i, c; text)
    {
        // Something changes, or might: one copy from here on.
        if (c >= 0x80 || (upper ? c >= 'a' && c <= 'z' : c >= 'A' && c <= 'Z'))
            return remapped!upper(text, i);
    }
    return text;
}

// `text` mapped from `from` on, into one buffer of the text's length (an ASCII mapping keeps it), grown only when a
// non-ASCII mapping is longer: no append per character (each is a druntime call), and no garbage when nothing grows.
private char[] remapped(bool upper)(scope const(char)[] text, size_t from) pure nothrow
{
    import flint.engine.aot.text : decodeUtf8, utf8;
    import flint.java.character : toLowerCase, toUpperCase;

    auto result = new char[text.length];
    result[0 .. from] = text[0 .. from];
    size_t length = from, index = from;
    while (index < text.length)
    {
        const unit = text[index];
        if (unit < 0x80)
        {
            const lower = upper ? unit >= 'a' && unit <= 'z' : unit >= 'A' && unit <= 'Z';
            result[length++] = lower ? cast(char)(upper ? unit - 32 : unit + 32) : unit;
            index++;
            continue;
        }
        const start = index;
        const code = decodeUtf8(text, index);
        const changed = upper ? toUpperCase(code) : toLowerCase(code);
        const piece = changed == code ? text[start .. index] : utf8(changed);
        if (length + piece.length + (text.length - index) > result.length)
            result.length = length + piece.length + (text.length - index);
        result[length .. length + piece.length] = piece;
        length += piece.length;
    }
    return result[0 .. length];
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
    const count = occurrences(text, from);
    if (count == 0)
        return text;
    return substituted(text, from, to, count);
}

// The non-overlapping `from`s in `text`, left to right.
private size_t occurrences(scope const(char)[] text, scope const(char)[] from) pure nothrow @nogc
{
    size_t count, i;
    while (i + from.length <= text.length)
    {
        if (text[i .. i + from.length] == from)
        {
            count++;
            i += from.length;
        }
        else
            i++;
    }
    return count;
}

private alias Text = const(char)[];

// `text` with its `n` `from`s replaced, into one buffer of the exact length.
private char[] substituted(scope Text text, scope Text from, scope Text to, size_t n) pure nothrow
{
    auto result = new char[text.length - n * from.length + n * to.length];
    size_t length, start, i;
    while (i + from.length <= text.length)
    {
        if (text[i .. i + from.length] != from)
        {
            i++;
            continue;
        }
        result[length .. length + (i - start)] = text[start .. i];
        length += i - start;
        result[length .. length + to.length] = to;
        length += to.length;
        i += from.length;
        start = i;
    }
    result[length .. $] = text[start .. $];
    return result;
}

/// `values` joined by `separator`, as std.array's `join`.
string joined(scope const string[] values, scope const(char)[] separator) pure nothrow
{
    if (values.length == 0)
        return "";
    if (values.length == 1)
        return values[0];
    return joinedCopy(values, separator);
}

// `values` and their separators, copied into one buffer of the exact length.
private char[] joinedCopy(scope const string[] values, scope const(char)[] separator) pure nothrow
{
    size_t total;
    foreach (i, value; values)
        total += (i == 0 ? 0 : separator.length) + value.length;
    auto result = new char[total];
    size_t length;
    foreach (i, value; values)
    {
        if (i != 0)
        {
            result[length .. length + separator.length] = separator;
            length += separator.length;
        }
        result[length .. length + value.length] = value;
        length += value.length;
    }
    return result;
}

/// The pieces of `text` between `separator`s, empty ones included, as std.array's `split(text, separator)`: none
/// for an empty text. The pieces are slices of `text`, in one array of the exact length.
string[] pieces(string text, char separator) pure nothrow
{
    if (text.length == 0)
        return null;
    size_t count = 1;
    foreach (c; text)
        count += c == separator;
    auto result = new string[count];
    size_t start, n;
    foreach (i, c; text)
    {
        if (c != separator)
            continue;
        result[n++] = text[start .. i];
        start = i + 1;
    }
    result[n] = text[start .. $];
    return result;
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
    return utf8Copy(chars);
}

// `chars` encoded into one buffer of the exact length.
private char[] utf8Copy(scope const(dchar)[] chars) pure nothrow
{
    import flint.engine.aot.text : utf8;

    size_t total;
    foreach (c; chars)
        total += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
    auto result = new char[total];
    size_t length;
    foreach (c; chars)
    {
        if (c < 0x80)
        {
            result[length++] = cast(char) c;
            continue;
        }
        const piece = utf8(c);
        result[length .. length + piece.length] = piece;
        length += piece.length;
    }
    return result[0 .. length];
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
