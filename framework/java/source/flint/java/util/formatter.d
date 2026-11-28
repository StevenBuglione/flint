/++
`java.util.Formatter`'s format strings (clean room, from the Java SE specification), as `String.format` uses them:
one non-template engine over erased arguments (`Any[]`), so a call site instantiates nothing but its `Any.of`
boxing (rulebook R7) and never `std.format`.

Specifiers are `%[argument_index$][flags][width][.precision]conversion`, with `<` for the previous argument.
Conversions: `b B h H s S c C d o x X f e E g G a A n %`; flags `- # + space 0 , (`. Arguments format as Java's would: `%s` as
`String.valueOf` (null, `true`, `Double.toString`, an object's `toString`), `%d`/`%o`/`%x` for integral types (`%x`
of a negative `int` is its 32-bit two's complement, of a `long` its 64-bit one), `%c` for a character or code
point, and `%f`, `%e`/`%E`, `%g`/`%G` and `%a`/`%A` for floating point. Decimal conversions round half up
with a default precision of six digits. Hexadecimal formatting uses exact digits by default and rounds ties to even
at reduced precision.

The renderer uses the root locale's `.` and `,`. `%h` uses the Java boxed scalar hash. For object references it
uses virtual `toHash` (R11). A `JavaObject` mixin calls `hashCode` and returns zero for an exception. A class
without the mixin uses its D `toHash`. Erased native aggregates have no Java object to hash.
The date/time conversions accept a boxed `long` in Flint's default UTC zone. Calendar, Date and temporal
objects require their own projections.
+/
module flint.java.util.formatter;

import flint.engine.aot.any : Any;
import flint.engine.aot.text : decimal, decodeUtf8, utf8;
import flint.java.lang : IllegalArgumentException;
import flint.java.util.internal.formatter_support : Flag, FormatOptions, asciiLower, asciiUpper,
    asciiUppercase, pad, truncate;
import flint.java.util.internal.formatter_digits : hex;
import flint.java.util.internal.formatter_pieces : Pieces;

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

/// Java's `FormatFlagsConversionMismatchException`: flags that a conversion does not accept.
class FormatFlagsConversionMismatchException : IllegalFormatException
{
    private string flags;
    private wchar conversion;

    /// The rejected flags and the UTF-16 conversion unit (R14). Null flags count as empty (R26).
    this(string flags, wchar conversion, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        const text = utf8(conversion);
        super("Conversion = " ~ (text is null ? "\uFFFD" : text) ~ ", Flags = " ~ flags, file, line);
        this.flags = flags;
        this.conversion = conversion;
    }

    /// The rejected flags.
    string getFlags() const pure nothrow @nogc
    {
        return flags;
    }

    /// The UTF-16 conversion unit.
    wchar getConversion() const pure nothrow @nogc
    {
        return conversion;
    }
}

/// Java's `IllegalFormatCodePointException`: an invalid Unicode code point.
class IllegalFormatCodePointException : IllegalFormatException
{
    private int codePoint;

    /// The invalid code point.
    this(int codePoint, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super("Code point = 0x" ~ hex(cast(uint) codePoint), file, line);
        this.codePoint = codePoint;
    }

    /// The invalid code point.
    int getCodePoint() const pure nothrow @nogc
    {
        return codePoint;
    }
}

/// Java's `IllegalFormatFlagsException`: incompatible formatting flags.
class IllegalFormatFlagsException : IllegalFormatException
{
    private string flags;

    /// The incompatible flags. A null slice counts as empty (R26).
    this(string flags, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super("Flags = '" ~ flags ~ "'", file, line);
        this.flags = flags;
    }

    /// The incompatible flags.
    string getFlags() const pure nothrow @nogc
    {
        return flags;
    }
}

/// Java's `IllegalFormatPrecisionException`: a precision that is out of range or disallowed.
class IllegalFormatPrecisionException : IllegalFormatException
{
    private int precision;

    /// The invalid precision.
    this(int precision, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(decimal(precision), file, line);
        this.precision = precision;
    }

    /// The invalid precision.
    int getPrecision() const pure nothrow @nogc
    {
        return precision;
    }
}

/// Java's `IllegalFormatWidthException`: a width that is out of range or disallowed.
class IllegalFormatWidthException : IllegalFormatException
{
    private int width;

    /// The invalid width.
    this(int width, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(decimal(width), file, line);
        this.width = width;
    }

    /// The invalid width.
    int getWidth() const pure nothrow @nogc
    {
        return width;
    }
}

/// Java's `MissingFormatWidthException`: a flag requires a width.
class MissingFormatWidthException : IllegalFormatException
{
    private string specifier;

    /// The incomplete specifier. A null slice counts as empty (R26).
    this(string specifier, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(specifier, file, line);
        this.specifier = specifier;
    }

    /// The incomplete specifier.
    string getFormatSpecifier() const pure nothrow @nogc
    {
        return specifier;
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

/// Java's `UnknownFormatFlagsException`: a flag the format specifier does not recognize.
class UnknownFormatFlagsException : IllegalFormatException
{
    private string flags;

    /// The unknown flags. A null slice counts as empty (R26).
    this(string flags, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super("Flags = " ~ flags, file, line);
        this.flags = flags;
    }

    /// The unknown flags.
    string getFlags() const pure nothrow @nogc
    {
        return flags;
    }
}

/// Java's `IllegalFormatConversionException`: a conversion that does not apply to the argument's type.
class IllegalFormatConversionException : IllegalFormatException
{
    private wchar conversion;

    /// `conversion` given an argument of type `argumentType` (its Java name).
    this(wchar conversion, string argumentType, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        const text = utf8(conversion);
        super((text is null ? "\uFFFD" : text) ~ " != " ~ argumentType, file, line);
        this.conversion = conversion;
    }

    /// The UTF-16 conversion unit.
    wchar getConversion() const pure nothrow @nogc
    {
        return conversion;
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

// Diagnostics list flags in this order. '^' is internal and cannot be written in a specifier.
private enum flagOrder = "-^#+ 0,(<";

private struct Spec
{
    string text; // the original specifier, including the conversion suffix
    size_t start;
    ptrdiff_t index = -1; // explicit 1-based index, 0 for `<`, -1 for ordinary
    FormatOptions options;
    alias options this;
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
    spec.flags = parseFlags(format[flagsStart .. widthStart]);
    if (spec.has(Flag.previous))
        spec.index = 0;
    if (widthEnd > widthStart)
        spec.width = formatWidth(format[widthStart .. widthEnd]);
    if (precisionStart != widthEnd)
        spec.precision = formatPrecision(format[precisionStart .. conversionStart]);

    spec.conversion = format[conversionStart];
    spec.start = start;
    spec.text = format[start .. end];
    validateSpec(spec, format[conversionStart .. end]);
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

private void validateSpec(ref Spec spec, string conversion)
{
    if (conversion.length == 2)
    {
        validateDate(spec, conversion);
        return;
    }
    if (!validConversion(spec.conversion))
        throw new UnknownFormatConversionException(conversion);
    const lower = asciiLower(spec.conversion);
    switch (lower)
    {
    case 'b', 'h', 's':
        validateGeneral(spec, lower);
        break;
    case 'c':
        requireNoPrecision(spec);
        rejectFlags(spec, characterFlags, lower);
        requireWidth(spec, Flag.left);
        break;
    case 'n', '%':
        validateText(spec);
        break;
    default:
        validateNumeric(spec, lower);
    }
}

private enum generalFlags = Flag.plus | Flag.space | Flag.zero | Flag.group | Flag.parentheses;
private enum characterFlags = generalFlags | Flag.alternate;

private void validateGeneral(const ref Spec spec, char lower)
{
    if (lower != 's')
        rejectFlags(spec, Flag.alternate, lower);
    requireWidth(spec, Flag.left);
    rejectFlags(spec, generalFlags, lower);
}

private void validateDate(ref Spec spec, string conversion)
{
    import flint.java.util.internal.formatter_date_time : datePatternIndex;

    requireNoPrecision(spec);
    const suffix = conversion[1];
    const pattern = datePatternIndex(suffix);
    if (pattern < 0)
        throw new UnknownFormatConversionException("t" ~ conversion[1 .. $]);
    spec.datePattern = cast(ubyte) pattern;
    rejectFlags(spec, characterFlags, suffix);
    requireWidth(spec, Flag.left);
}

private void validateText(const ref Spec spec)
{
    requireNoPrecision(spec);
    if (spec.conversion == 'n')
    {
        if (spec.width >= 0)
            throw new IllegalFormatWidthException(spec.width);
        if (spec.flags != 0)
            throw new IllegalFormatFlagsException(flagsText(spec.flags));
        return;
    }
    if ((spec.flags & ~Flag.left) != 0)
        throw new IllegalFormatFlagsException(flagsText(spec.flags));
    requireWidth(spec, Flag.left);
}

private void validateNumeric(const ref Spec spec, char lower)
{
    requireWidth(spec, Flag.left | Flag.zero);
    if (containsFlags(spec.flags, Flag.plus | Flag.space) || containsFlags(spec.flags, Flag.left | Flag.zero))
    {
        const diagnostic = spec.flags | (lower == spec.conversion ? 0u : Flag.uppercase);
        throw new IllegalFormatFlagsException(flagsText(diagnostic));
    }
    if (includes("dox", lower))
        requireNoPrecision(spec);
    switch (lower)
    {
    case 'd', 'g':
        rejectFlags(spec, Flag.alternate, lower);
        break;
    case 'o', 'x', 'e':
        rejectFlags(spec, Flag.group, lower);
        break;
    case 'a':
        rejectFlags(spec, Flag.parentheses | Flag.group, lower);
        break;
    default:
        break;
    }
}

private bool containsFlags(uint flags, uint required) pure nothrow @nogc
{
    return (flags & required) == required;
}

private void requireNoPrecision(const ref Spec spec)
{
    if (spec.precision >= 0)
        throw new IllegalFormatPrecisionException(spec.precision);
}

private void rejectFlags(const ref Spec spec, uint rejected, char conversion)
{
    const invalid = spec.flags & rejected;
    if (invalid != 0)
        throw new FormatFlagsConversionMismatchException(flagsText(invalid), conversion);
}

private void requireWidth(const ref Spec spec, uint flags)
{
    if (spec.width < 0 && (spec.flags & flags) != 0)
        throw new MissingFormatWidthException(diagnosticSpecifier(spec));
}

/// Reconstruct a specifier in Java's diagnostic order, only on the error path.
private string diagnosticSpecifier(const ref Spec spec) pure nothrow
{
    if (spec.text.length == 2)
        return spec.text;
    const prefix = "%" ~ flagsText(spec.flags);
    const index = spec.index > 0 ? decimal(cast(int) spec.index) ~ "$" : "";
    const width = spec.width >= 0 ? decimal(spec.width) : "";
    const precision = spec.precision >= 0 ? "." ~ decimal(spec.precision) : "";
    const suffixLength = spec.conversion == 't' || spec.conversion == 'T' ? 2 : 1;
    string conversion = spec.text[$ - suffixLength .. $];
    if (spec.conversion == 'T')
        conversion = "T" ~ [asciiUpper(conversion[1])];
    return prefix ~ index ~ width ~ precision ~ conversion;
}

private string flagsText(uint flags) pure nothrow
{
    char[flagOrder.length] buffer;
    size_t length;
    foreach (position, flag; flagOrder)
        if ((flags & (1u << position)) != 0)
            buffer[length++] = flag;
    return buffer[0 .. length].idup;
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
    const value = parseFormatInt(digits);
    if (value == int.min)
        throw new IllegalFormatArgumentIndexException("Format argument index: (not representable as int)");
    if (value == 0)
        throw new IllegalFormatArgumentIndexException("Illegal format argument index = 0");
    return value;
}

private int formatWidth(scope const(char)[] digits)
{
    const value = parseFormatInt(digits);
    if (value == int.min)
        throw new IllegalFormatWidthException(value);
    return value;
}

private int formatPrecision(scope const(char)[] digits)
{
    const value = parseFormatInt(digits);
    if (value == int.min)
        throw new IllegalFormatPrecisionException(value);
    return value;
}

private int parseFormatInt(scope const(char)[] digits) pure nothrow @nogc
{
    int value;
    foreach (c; digits)
    {
        const digit = c - '0';
        if (value > (int.max - digit) / 10)
            return int.min;
        value = value * 10 + digit;
    }
    return value;
}

private uint parseFlags(string flags)
{
    uint parsed;
    foreach (i, flag; flags)
    {
        const bit = flagBit(flag);
        if ((parsed & bit) != 0)
            throw new DuplicateFormatFlagsException(flags[i .. i + 1]);
        parsed |= bit;
    }
    return parsed;
}

private uint flagBit(char flag) pure nothrow @nogc
{
    foreach (position, candidate; flagOrder)
        if (flag == candidate)
            return 1u << position;
    assert(0, "parseFlags requires a validated flag");
}

/// The text of one specifier, taking its argument from `arguments`.
private string render(const ref Spec spec, scope Any[] arguments, ref size_t next, ref ptrdiff_t previous)
{
    switch (spec.conversion)
    {
    case 'n':
        return "\n";
    case '%':
        return pad(spec.options, "%");
    default:
        break;
    }
    size_t index;
    if (spec.index > 0)
        index = spec.index - 1;
    else if (spec.index == 0)
    {
        if (previous < 0)
            throw new MissingFormatArgumentException(diagnosticSpecifier(spec));
        index = previous;
    }
    else
        index = next++;
    if (index >= arguments.length)
        throw new MissingFormatArgumentException(diagnosticSpecifier(spec));
    previous = index;
    return pad(spec.options, convert(spec, arguments[index]));
}

private string convert(const ref Spec spec, Any argument)
{
    switch (spec.conversion)
    {
    case 'b', 'B':
        import flint.java.util.internal.formatter_boolean : formatBoolean;

        return formatBoolean(spec.options, booleanValue(argument));
    case 'h', 'H':
        return hashText(spec.options, argument);
    case 's', 'S':
        import flint.java.util.internal.formatter_string : formatString;

        return formatString(spec.options, argument);
    case 'c', 'C':
        return characterText(spec.options, argument);
    case 'd':
        return integralText(spec, argument);
    case 'o', 'x', 'X':
        return radixText(spec, argument);
    case 'f', 'e', 'E', 'g', 'G', 'a', 'A':
        return floatingText(spec, argument);
    case 't', 'T':
        return dateTimeText(spec, argument);
    default:
        throw new UnknownFormatConversionException([spec.conversion]);
    }
}

private string dateTimeText(const ref Spec spec, Any argument)
{
    import flint.java.util.internal.formatter_date_time : dateTimeValue;

    if (argument.isNull)
        return spec.conversion == 'T' ? "NULL" : "null";
    if (argument.typeName != "long")
        throw new IllegalFormatConversionException(spec.text[$ - 1], javaTypeName(argument));

    return dateTimeValue(argument.get!long, spec.datePattern, spec.conversion == 'T');
}

private bool booleanValue(Any argument)
{
    if (argument.isNull)
        return false;
    if (argument.typeName == "bool")
        return argument.get!bool;
    return true;
}

private string hashText(const ref FormatOptions options, Any argument)
{
    import flint.java.util.internal.formatter_hash : formatHash;

    if (!argument.isNull)
        return formatHash(options, boxedHashCode(argument));

    const text = truncate(options, "null");
    return options.conversion == 'H' ? asciiUppercase(text) : text;
}

private int boxedHashCode(Any argument)
{
    import flint.java.lang : javaHashCode;

    switch (argument.typeName)
    {
    case "string":
        return javaHashCode(argument.get!string);
    case "bool":
        return javaHashCode(argument.get!bool);
    case "char", "wchar", "dchar":
        return javaHashCode(argument.get!dchar);
    case "byte", "short", "int", "ubyte", "ushort", "uint":
        return javaHashCode(cast(int) argument.get!long);
    case "long":
        return javaHashCode(argument.get!long);
    case "ulong":
        return javaHashCode(argument.get!ulong);
    case "float":
        return javaHashCode(cast(float) argument.get!double);
    case "double", "real":
        return javaHashCode(argument.get!double);
    default:
        if (auto object = argument.asObject())
            return javaHashCode(object);
        throw new IllegalFormatConversionException('h', javaTypeName(argument));
    }
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
    case "byte":
        return "java.lang.Byte";
    case "short":
        return "java.lang.Short";
    case "int":
        return "java.lang.Integer";
    case "long":
        return "java.lang.Long";
    case "char", "wchar", "dchar":
        return "java.lang.Character";
    default:
        return argument.typeName;
    }
}

private string characterText(const ref FormatOptions options, Any argument)
{
    import flint.java.util.internal.formatter_character : formatCharacter;

    if (argument.isNull)
        return options.conversion == 'C' ? "NULL" : "null";

    const typeName = argument.typeName;
    const character = typeName == "char" || typeName == "wchar" || typeName == "dchar";
    if (!character && (!isIntegral(typeName) || typeName == "long"))
        throw new IllegalFormatConversionException('c', javaTypeName(argument));
    const code = character ? cast(long) argument.get!dchar : argument.get!long;
    const text = code < 0 || code > 0x10FFFF ? null : formatCharacter(options, cast(dchar) code);
    return text is null ? unencodableCharacter(typeName, character, code) : text;
}

private string unencodableCharacter(string typeName, bool character, long code)
{
    const signedCodePoint = typeName == "byte" || typeName == "short" || typeName == "int";
    // Java accepts lone UTF-16 surrogate code units. R14 projects them to U+FFFD.
    if ((character || signedCodePoint) && code >= 0xD800 && code <= 0xDFFF)
        return "\uFFFD";
    if (signedCodePoint)
        throw new IllegalFormatCodePointException(cast(int) code);
    throw new IllegalFormatException("Code point = 0x" ~ hex(cast(ulong) code));
}

private string integralText(const ref Spec spec, Any argument)
{
    import flint.java.util.internal.formatter_integer : formatIntegral;

    if (argument.isNull)
        return "null";
    if (!isIntegral(argument.typeName))
        throw new IllegalFormatConversionException('d', javaTypeName(argument));
    const unsigned = argument.typeName == "ulong";
    return formatIntegral(spec.options, argument.get!long, unsigned);
}

private string radixText(const ref Spec spec, Any argument)
{
    import flint.java.util.internal.formatter_integer : formatRadix;

    if (argument.isNull)
        return spec.conversion == 'X' ? "NULL" : "null";
    const conversion = asciiLower(spec.conversion);
    const typeName = argument.typeName;
    if (!isIntegral(typeName))
        throw new IllegalFormatConversionException(conversion, javaTypeName(argument));
    rejectFlags(spec, Flag.plus | Flag.space | Flag.parentheses, conversion);
    ulong bits = cast(ulong) argument.get!long;
    switch (typeName)
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
    return formatRadix(spec.options, bits);
}

private string floatingText(const ref Spec spec, Any argument)
{
    import flint.java.util.internal.formatter_decimal : formatDecimal;
    import flint.java.util.internal.formatter_hex_float : formatHexFloat;

    const conversion = asciiLower(spec.conversion);
    if (argument.isNull)
        return conversion != spec.conversion ? "NULL" : "null";
    if (argument.typeName != "double" && argument.typeName != "float")
        throw new IllegalFormatConversionException(conversion, javaTypeName(argument));
    const value = argument.get!double;
    return conversion == 'a' ? formatHexFloat(spec.options, value) : formatDecimal(spec.options, value);
}
