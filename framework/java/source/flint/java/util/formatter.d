/++
`java.util.Formatter`'s format strings (clean room, from the Java SE specification), as `String.format` uses them:
one non-template engine over erased arguments (`Any[]`), so a call site instantiates nothing but its `Any.of`
boxing (rulebook R7) and never `std.format`.

Specifiers are `%[argument_index$][flags][width][.precision]conversion`, with `<` for the previous argument.
Conversions: `b B s S c d o x X f n %`; flags `- # + space 0 , (`. Arguments format as Java's would: `%s` as
`String.valueOf` (null, `true`, `Double.toString`, an object's `toString`), `%d`/`%o`/`%x` for integral types (`%x`
of a negative `int` is its 32-bit two's complement, of a `long` its 64-bit one), `%c` for a character or code
point, `%f` for floating point (precision 6 by default, rounded half up).

Deviations: no `Locale` (the root locale's `.` and `,`); `%e`, `%g`, `%a`, `%h` and the date/time conversions throw
`UnknownFormatConversionException`; `%f` rounds through `double` arithmetic, so it can differ from Java's exact
decimal rounding beyond 15 significant digits.
+/
module flint.java.util.formatter;

import flint.engine.aot.any : Any;
import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : IllegalArgumentException;

@safe:

/// Java's `IllegalFormatException`: a format string with illegal syntax or an argument it cannot format.
class IllegalFormatException : IllegalArgumentException
{
    /// With `message`.
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, null, file, line);
    }
}

/// Java's `DuplicateFormatFlagsException`: a flag occurs more than once in a specifier.
class DuplicateFormatFlagsException : IllegalFormatException
{
    private string flags;

    /// The repeated flags. A null slice counts as empty (R26).
    this(string flags, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super("Flags = '" ~ flags ~ "'", file, line);
        this.flags = flags;
    }

    /// The repeated flags.
    string getFlags() const pure nothrow @nogc
    {
        return flags;
    }
}

private class IllegalFormatArgumentIndexException : IllegalFormatException
{
    this(string message) pure nothrow
    {
        super(message);
    }
}

/// Java's `MissingFormatArgumentException`: a specifier without an argument.
class MissingFormatArgumentException : IllegalFormatException
{
    private string specifier;

    /// For `specifier`, such as `%s`.
    this(string specifier, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super("Format specifier '" ~ specifier ~ "'", file, line);
        this.specifier = specifier;
    }

    /// The specifier.
    string getFormatSpecifier() const pure nothrow @nogc
    {
        return specifier;
    }
}

/// Java's `UnknownFormatConversionException`: an unknown (or unsupported) conversion.
class UnknownFormatConversionException : IllegalFormatException
{
    private string conversion;

    /// For `conversion`.
    this(string conversion, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super("Conversion = '" ~ conversion ~ "'", file, line);
        this.conversion = conversion;
    }

    /// The conversion.
    string getConversion() const pure nothrow @nogc
    {
        return conversion;
    }
}

/// Java's `IllegalFormatConversionException`: a conversion that does not apply to the argument's type.
class IllegalFormatConversionException : IllegalFormatException
{
    /// `conversion` given an argument of type `argumentType` (its Java name).
    this(char conversion, string argumentType, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super([conversion].idup ~ " != " ~ argumentType, file, line);
    }
}

/// `format` with `arguments` substituted, as `java.util.Formatter.format(format, args).toString()`.
string formatJava(string format, scope Any[] arguments)
{
    // Validate every specifier before resolving arguments, as Formatter does.
    Spec[4] specs;
    Spec extra;
    size_t count;
    for (size_t start = nextSpecifier(format, 0); start < format.length;)
    {
        const end = count < specs.length ? parseSpec(format, start, specs[count]) : parseSpec(format, start, extra);
        ++count;
        start = nextSpecifier(format, end);
    }

    Pieces result;
    size_t next; // the next ordinary index
    ptrdiff_t previous = -1;
    size_t end;
    foreach (i; 0 .. count)
    {
        // For longer formats, reparse only the validated suffix beyond the stack slots.
        Spec spec;
        if (i < specs.length)
            spec = specs[i];
        else
            parseSpec(format, nextSpecifier(format, end), spec);
        result.put(format[end .. spec.start]);
        result.put(render(spec, arguments, next, previous));
        end = spec.start + spec.text.length;
    }
    result.put(format[end .. $]);
    return result.text();
}

private size_t nextSpecifier(scope const(char)[] format, size_t start) pure nothrow @nogc
{
    while (start < format.length && format[start] != '%')
        ++start;
    return start;
}

/++
Flint: the formatted pieces, gathered in a stack buffer and copied to the heap once at the end, instead of appended
one by one to a growing string (an array append per piece). The result is the same string; a text longer than the
buffer continues on the heap.
+/
private struct Pieces
{
    private char[256] stack = void;
    private size_t used;
    private char[] heap;

    void put(scope const(char)[] piece) pure nothrow
    {
        if (heap is null && used + piece.length <= stack.length)
        {
            stack[used .. used + piece.length] = piece;
            used += piece.length;
            return;
        }
        if (heap is null)
            heap = stack[0 .. used].dup;
        heap ~= piece;
    }

    // The text; null when nothing was written, as the empty result was before.
    string text() const pure nothrow
    {
        if (heap !is null)
            return heap.idup;
        return used == 0 ? null : stack[0 .. used].idup;
    }
}

private struct Spec
{
    string text; // the specifier as written, for messages
    size_t start;
    ptrdiff_t index = -1; // explicit 1-based index, 0 for `<`, -1 for ordinary
    bool leftJustify, alternate, plus, space, zeroPad, group, parentheses;
    int width = -1;
    int precision = -1;
    char conversion;
}

/// Parse the specifier at `format[start]` (a `%`); returns the index after it.
private size_t parseSpec(string format, size_t start, out Spec spec)
{
    const indexStart = start + 1;
    if (indexStart < format.length && validConversion(format[indexStart]))
    {
        spec.start = start;
        spec.text = format[start .. indexStart + 1];
        spec.conversion = format[indexStart];
        return indexStart + 1;
    }
    const indexEnd = digitsEnd(format, indexStart);
    const hasIndex = indexEnd > indexStart && indexEnd < format.length && format[indexEnd] == '$';
    const flagsStart = hasIndex ? indexEnd + 1 : indexStart;
    size_t widthStart = flagsStart;
    while (widthStart < format.length && includes("-#+ 0,(<", format[widthStart]))
        ++widthStart;
    const widthEnd = digitsEnd(format, widthStart);
    size_t i = widthEnd;
    size_t precisionStart = widthEnd;
    if (i < format.length && format[i] == '.')
    {
        precisionStart = ++i;
        i = digitsEnd(format, i);
        if (i == precisionStart)
            invalidSpecifier(format, indexStart);
    }
    const conversionStart = i;
    const end = conversionEnd(format, conversionStart, indexStart);

    if (hasIndex)
        spec.index = argumentIndex(format[indexStart .. indexEnd]);
    parseFlags(format[flagsStart .. widthStart], spec);
    if (widthEnd > widthStart)
        spec.width = cast(int) number(format[widthStart .. widthEnd]);
    if (precisionStart != widthEnd)
        spec.precision = cast(int) number(format[precisionStart .. conversionStart]);

    spec.conversion = checkedConversion(format[conversionStart .. end]);
    spec.start = start;
    spec.text = format[start .. end];
    return end;
}

private size_t conversionEnd(string format, size_t end, size_t indexStart)
{
    if (end + 1 < format.length && (format[end] == 't' || format[end] == 'T') && conversionCharacter(format[end + 1]))
        ++end;
    if (end >= format.length || !conversionCharacter(format[end]))
        invalidSpecifier(format, indexStart);
    return end + 1;
}

private char checkedConversion(string conversion)
{
    if (conversion.length == 1)
    {
        if (!validConversion(conversion[0]))
            throw new UnknownFormatConversionException(conversion);
    }
    else if (!includes("HIklMSLNpzZsQBbhAaCYyjmdeRTrDFc", conversion[1]))
        throw new UnknownFormatConversionException("t" ~ conversion[1 .. $]);
    return conversion[0];
}

private size_t digitsEnd(scope const(char)[] format, size_t i) pure nothrow @nogc
{
    while (i < format.length && format[i] >= '0' && format[i] <= '9')
        ++i;
    return i;
}

private bool conversionCharacter(char c) pure nothrow @nogc
{
    return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '%';
}

private bool validConversion(char c) pure nothrow @nogc
{
    switch (c)
    {
    case 'b', 'B', 'h', 'H', 's', 'S', 'c', 'C', 'd', 'o', 'x', 'X', 'e', 'E', 'f', 'g', 'G', 'a',
            'A', '%', 'n':
            return true;
    default:
        return false;
    }
}

private bool includes(scope const(char)[] choices, char c) pure nothrow @nogc
{
    foreach (choice; choices)
        if (choice == c)
            return true;
    return false;
}

private void invalidSpecifier(string format, size_t index)
{
    if (index == format.length)
        throw new UnknownFormatConversionException("%");
    size_t end = index;
    const first = decodeUtf8(format, end);
    // Report the first UTF-16 unit. Invalid UTF-8 and lone surrogates become U+FFFD (R14).
    throw new UnknownFormatConversionException(first == 0xFFFD || first > 0xFFFF ? "\uFFFD" : format[index .. end]);
}

private int argumentIndex(scope const(char)[] digits)
{
    int value;
    foreach (c; digits)
    {
        const digit = c - '0';
        if (value > (int.max - digit) / 10)
            throw new IllegalFormatArgumentIndexException("Format argument index: (not representable as int)");
        value = value * 10 + digit;
    }
    if (value == 0)
        throw new IllegalFormatArgumentIndexException("Illegal format argument index = 0");
    return value;
}

private void parseFlags(string flags, ref Spec spec)
{
    foreach (i, flag; flags)
    {
        const text = flags[i .. i + 1];
        switch (flag)
        {
        case '-':
            setFlag(spec.leftJustify, text);
            break;
        case '#':
            setFlag(spec.alternate, text);
            break;
        case '+':
            setFlag(spec.plus, text);
            break;
        case ' ':
            setFlag(spec.space, text);
            break;
        case '0':
            setFlag(spec.zeroPad, text);
            break;
        case ',':
            setFlag(spec.group, text);
            break;
        case '(':
            setFlag(spec.parentheses, text);
            break;
        case '<':
            if (spec.index == 0)
                throw new DuplicateFormatFlagsException(text);
            spec.index = 0;
            break;
        default:
            assert(0, "parseFlags requires a validated flag");
        }
    }
}

private void setFlag(ref bool present, string flag)
{
    if (present)
        throw new DuplicateFormatFlagsException(flag);
    present = true;
}

private long number(string digits) pure nothrow @nogc
{
    long value;
    foreach (c; digits)
        value = value * 10 + (c - '0');
    return value;
}

/// The text of one specifier, taking its argument from `arguments`.
private string render(const ref Spec spec, scope Any[] arguments, ref size_t next, ref ptrdiff_t previous)
{
    switch (spec.conversion)
    {
    case 'n':
        return "\n";
    case '%':
        return pad(spec, "%");
    default:
        break;
    }
    size_t index;
    if (spec.index > 0)
        index = spec.index - 1;
    else if (spec.index == 0)
    {
        if (previous < 0)
            throw new MissingFormatArgumentException(spec.text);
        index = previous;
    }
    else
        index = next++;
    if (index >= arguments.length)
        throw new MissingFormatArgumentException(spec.text);
    previous = index;
    return pad(spec, convert(spec, arguments[index]));
}

private string convert(const ref Spec spec, Any argument)
{
    switch (spec.conversion)
    {
    case 'b', 'B':
        return cased(spec, truncate(spec, booleanText(argument)));
    case 's', 'S':
        return cased(spec, truncate(spec, stringText(argument)));
    case 'c':
        return argument.isNull ? "null" : characterText(argument);
    case 'd':
        return integralText(spec, argument);
    case 'o', 'x', 'X':
        return radixText(spec, argument);
    case 'f':
        return fixedText(spec, argument);
    default:
        throw new UnknownFormatConversionException([spec.conversion]);
    }
}

private string truncate(const ref Spec spec, string text) pure nothrow
{
    if (spec.precision < 0 || spec.precision >= text.length)
        return text;
    const prefix = utf16Prefix(text, spec.precision);
    if (prefix.end < text.length && prefix.units < spec.precision)
        return text[0 .. prefix.end] ~ "\uFFFD"; // R14 covers the high half of a split surrogate pair.
    return text[0 .. prefix.end];
}

private string cased(const ref Spec spec, string text) pure nothrow
{
    if (spec.conversion != 'S' && spec.conversion != 'B' && spec.conversion != 'X')
        return text;
    auto upper = text.dup;
    foreach (ref c; upper)
        if (c >= 'a' && c <= 'z')
            c = cast(char)(c - 32);
    return upper.idup;
}

/// Pad to the UTF-16 width with spaces on the left, or on the right with `-`.
private string pad(const ref Spec spec, string text) pure nothrow
{
    if (spec.width <= 0)
        return text;
    const prefix = utf16Prefix(text, spec.width);
    if (prefix.end < text.length || prefix.units == spec.width)
        return text;
    auto spaces = new char[](spec.width - prefix.units);
    spaces[] = ' ';
    return spec.leftJustify ? text ~ spaces : spaces ~ text;
}

private struct TextPrefix
{
    size_t end;
    size_t units;
}

// Find the last complete UTF-8 boundary within the UTF-16 limit.
private TextPrefix utf16Prefix(scope const(char)[] text, size_t limit) pure nothrow @nogc
{
    import flint.engine.aot.text : decodeUtf8;

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

private string booleanText(Any argument)
{
    if (argument.isNull)
        return "false";
    if (argument.typeName == "bool")
        return argument.get!bool ? "true" : "false";
    return "true";
}

/// `String.valueOf` of the argument.
private string stringText(Any argument)
{
    import flint.java.lang : doubleToString, floatToString;

    if (argument.isNull)
        return "null";
    switch (argument.typeName)
    {
    case "double":
        return doubleToString(argument.get!double);
    case "float":
        return floatToString(cast(float) argument.get!double);
    default:
        break;
    }
    if (auto object = argument.asObject())
    {
        import flint.engine.aot.objects : objectToString;

        return objectToString(object);
    }
    return argument.toString();
}

private bool isIntegral(string typeName) pure nothrow @nogc
{
    switch (typeName)
    {
    case "byte", "short", "int", "long", "ubyte", "ushort", "uint", "ulong":
        return true;
    default:
        return false;
    }
}

private string javaTypeName(Any argument) pure nothrow
{
    switch (argument.typeName)
    {
    case "string":
        return "java.lang.String";
    case "bool":
        return "java.lang.Boolean";
    case "double":
        return "java.lang.Double";
    case "float":
        return "java.lang.Float";
    case "char", "wchar", "dchar":
        return "java.lang.Character";
    default:
        return argument.typeName;
    }
}

private string characterText(Any argument)
{
    import flint.engine.aot.text : utf8;

    const character = argument.typeName == "char" || argument.typeName == "wchar" || argument.typeName == "dchar";
    if (!character && !isIntegral(argument.typeName))
        throw new IllegalFormatConversionException('c', javaTypeName(argument));
    const code = character ? cast(long) argument.get!dchar : argument.get!long;
    const text = code < 0 || code > 0x10FFFF ? null : utf8(cast(dchar) code);
    if (text is null)
        throw new IllegalFormatException("Code point = 0x" ~ hex(cast(ulong) code));
    return text;
}

private string integralText(const ref Spec spec, Any argument)
{
    if (argument.isNull)
        return "null";
    if (!isIntegral(argument.typeName))
        throw new IllegalFormatConversionException('d', javaTypeName(argument));
    const unsigned = argument.typeName == "ulong";
    const value = argument.get!long;
    const negative = !unsigned && value < 0;
    const magnitude = negative ? -cast(ulong) value : cast(ulong) value;
    return signed(spec, digits(magnitude, 10, spec.group), negative);
}

/// Apply the sign flags and zero padding to `body`, the magnitude's digits.
private string signed(const ref Spec spec, string body, bool negative) pure nothrow
{
    string prefix = negative ? (spec.parentheses ? "(" : "-") : spec.plus ? "+" : spec.space ? " " : "";
    const suffix = negative && spec.parentheses ? ")" : "";
    if (spec.zeroPad && spec.width > 0)
    {
        const used = prefix.length + body.length + suffix.length;
        if (used < spec.width)
        {
            auto zeros = new char[](spec.width - used);
            zeros[] = '0';
            body = zeros.idup ~ body;
        }
    }
    return prefix ~ body ~ suffix;
}

private string radixText(const ref Spec spec, Any argument)
{
    if (argument.isNull)
        return "null";
    if (!isIntegral(argument.typeName))
        throw new IllegalFormatConversionException(spec.conversion, javaTypeName(argument));
    ulong bits = cast(ulong) argument.get!long;
    switch (argument.typeName)
    {
    case "byte":
        bits &= 0xFF;
        break;
    case "short":
        bits &= 0xFFFF;
        break;
    case "int":
        bits &= 0xFFFF_FFFF;
        break;
    default:
        break;
    }
    const octal = spec.conversion == 'o';
    auto body = digits(bits, octal ? 8 : 16, false);
    if (spec.alternate)
        body = (octal ? "0" : "0x") ~ body;
    return cased(spec, signed(spec, body, false));
}

private string fixedText(const ref Spec spec, Any argument)
{
    if (argument.isNull)
        return "null";
    if (argument.typeName != "double" && argument.typeName != "float")
        throw new IllegalFormatConversionException('f', javaTypeName(argument));
    const value = argument.get!double;
    const negative = value < 0 || (value == 0 && 1 / value < 0);
    if (value != value || value == double.infinity || value == -double.infinity)
        return pad(spec, nonFinite(spec, value, negative));
    const precision = spec.precision < 0 ? 6 : spec.precision;
    string whole, fraction;
    decimalDigits(negative ? -value : value, whole, fraction);
    roundHalfUp(whole, fraction, precision);
    auto body = spec.group ? grouped(whole) : whole;
    if (precision > 0 || spec.alternate)
        body ~= "." ~ fraction;
    return signed(spec, body, negative);
}

/// `NaN` and the infinities, with Java's sign flags.
private string nonFinite(const ref Spec spec, double value, bool negative) pure nothrow @nogc
{
    if (value != value)
        return "NaN";
    if (negative)
        return spec.parentheses ? "(Infinity)" : "-Infinity";
    return spec.plus ? "+Infinity" : "Infinity";
}

/// The whole and fraction digits of `magnitude` from Java's shortest representation (`Double.toString`), which
/// Java's `Formatter` rounds from (a `float` is widened to `double` first, as Java does).
private void decimalDigits(double magnitude, out string whole, out string fraction)
{
    import flint.java.lang : doubleToString;

    const text = doubleToString(magnitude);
    size_t e;
    while (e < text.length && text[e] != 'E')
        e++;
    long exponent;
    if (e < text.length)
    {
        const negativeExponent = text[e + 1] == '-';
        exponent = number(text[e + (negativeExponent ? 2 : 1) .. $]);
        if (negativeExponent)
            exponent = -exponent;
    }
    string digitText;
    ptrdiff_t point = -1;
    foreach (i, c; text[0 .. e])
    {
        if (c == '.')
            point = cast(ptrdiff_t) digitText.length;
        else
            digitText ~= c;
    }
    ptrdiff_t position = (point < 0 ? cast(ptrdiff_t) digitText.length : point) + exponent;
    while (position <= 0)
    {
        digitText = "0" ~ digitText;
        position++;
    }
    while (position > digitText.length)
        digitText ~= '0';
    whole = digitText[0 .. position];
    fraction = digitText[position .. $];
    while (whole.length > 1 && whole[0] == '0')
        whole = whole[1 .. $];
}

/// Round `whole.fraction` to `precision` fraction digits, half up, as Java's `RoundingMode.HALF_UP`.
private void roundHalfUp(ref string whole, ref string fraction, int precision) pure nothrow
{
    if (fraction.length <= precision)
    {
        while (fraction.length < precision)
            fraction ~= '0';
        return;
    }
    const up = fraction[precision] >= '5';
    auto digits = (whole ~ fraction[0 .. precision]).dup;
    if (up)
    {
        size_t i = digits.length;
        while (i > 0 && digits[i - 1] == '9')
            digits[--i] = '0';
        if (i == 0)
            digits = "1".dup ~ digits;
        else
            digits[i - 1]++;
    }
    whole = digits[0 .. $ - precision].idup;
    fraction = digits[$ - precision .. $].idup;
}

/// Decimal digits with `,` every three from the right.
private string grouped(string digitText) pure nothrow
{
    string result;
    foreach (i, c; digitText)
    {
        if (i && (digitText.length - i) % 3 == 0)
            result ~= ',';
        result ~= c;
    }
    return result;
}

/// `value` in `radix`, with `,` every three digits when `group` (decimal only).
private string digits(ulong value, uint radix, bool group) pure nothrow
{
    char[66] buffer;
    size_t at = buffer.length;
    size_t count;
    do
    {
        if (group && count && count % 3 == 0)
            buffer[--at] = ',';
        const digit = cast(uint)(value % radix);
        buffer[--at] = cast(char)(digit < 10 ? '0' + digit : 'a' + digit - 10);
        value /= radix;
        count++;
    }
    while (value);
    return buffer[at .. $].idup;
}

private string hex(ulong value) pure nothrow
{
    return digits(value, 16, false);
}
