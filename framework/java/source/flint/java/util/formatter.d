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

private enum Flag : uint
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

// Diagnostics list flags in this order. '^' is internal and cannot be written in a specifier.
private enum flagOrder = "-^#+ 0,(<";

private struct Spec
{
    string text; // the original specifier, including the conversion suffix
    size_t start;
    ptrdiff_t index = -1; // explicit 1-based index, 0 for `<`, -1 for ordinary
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

private char asciiLower(char c) pure nothrow @nogc
{
    return c >= 'A' && c <= 'Z' ? cast(char)(c + 'a' - 'A') : c;
}

private char asciiUpper(char c) pure nothrow @nogc
{
    return c >= 'a' && c <= 'z' ? cast(char)(c + 'A' - 'a') : c;
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
            throw new MissingFormatArgumentException(diagnosticSpecifier(spec));
        index = previous;
    }
    else
        index = next++;
    if (index >= arguments.length)
        throw new MissingFormatArgumentException(diagnosticSpecifier(spec));
    previous = index;
    return pad(spec, convert(spec, arguments[index]));
}

private string convert(const ref Spec spec, Any argument)
{
    switch (spec.conversion)
    {
    case 'b', 'B':
        return cased(spec, truncate(spec, booleanText(argument)));
    case 'h', 'H':
        return cased(spec, truncate(spec, hashText(argument)));
    case 's', 'S':
        return cased(spec, truncate(spec, stringText(argument)));
    case 'c', 'C':
        return cased(spec, argument.isNull ? "null" : characterText(argument));
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
    if (spec.conversion == 'S' || spec.conversion == 'C')
    {
        foreach (c; text)
            if (c >= 0x80)
                return uppercaseUnicode(text);
    }
    else if (spec.conversion != 'B' && spec.conversion != 'H' && spec.conversion != 'X')
        return text;
    auto upper = text.dup;
    foreach (ref c; upper)
        c = asciiUpper(c);
    return upper.idup;
}

pragma(inline, false) private string uppercaseUnicode(string text) pure nothrow
{
    import flint.java.character : toUpperCase;

    Pieces result;
    char[1] ascii;
    size_t i;
    while (i < text.length)
    {
        if (text[i] < 0x80)
        {
            ascii[0] = asciiUpper(text[i++]);
            result.put(ascii[]);
            continue;
        }
        const start = i;
        const cp = decodeUtf8(text, i);
        const expansion = uppercaseExpansion(cp);
        if (expansion !is null)
            result.put(expansion);
        else
        {
            const upper = toUpperCase(cp);
            result.put(upper == cp ? text[start .. i] : utf8(upper));
        }
    }
    return result.text();
}

private string uppercaseExpansion(dchar cp) pure nothrow @nogc
{
    size_t first;
    size_t end = rootUppercaseIndex.length;
    while (first < end)
    {
        const mid = first + (end - first) / 2;
        const entry = rootUppercaseIndex[mid];
        const source = entry >> 16;
        if (cp < source)
            end = mid;
        else if (cp > source)
            first = mid + 1;
        else
        {
            const offset = (entry & 0xFFFF) >> 3;
            return rootUppercaseBytes[offset .. offset + (entry & 7)];
        }
    }
    return null;
}

// BEGIN GENERATED ROOT UPPERCASE EXPANSIONS
// Generated by GenFormatterUppercase.java on JDK 21.0.13+9-LTS.
// Index words store the code point, byte offset and byte length.
private immutable uint[102] rootUppercaseIndex = [
    0x00DF0002, 0x01490013, 0x01F0002B, 0x03900046, 0x03B00076, 0x058700A4, 0x1E9600C3, 0x1E9700DB,
    0x1E9800F3, 0x1E99010B, 0x1E9A0123, 0x1F50013C, 0x1F52015E, 0x1F54018E, 0x1F5601BE, 0x1F8001ED,
    0x1F810215, 0x1F82023D, 0x1F830265, 0x1F84028D, 0x1F8502B5, 0x1F8602DD, 0x1F870305, 0x1F88032D,
    0x1F890355, 0x1F8A037D, 0x1F8B03A5, 0x1F8C03CD, 0x1F8D03F5, 0x1F8E041D, 0x1F8F0445, 0x1F90046D,
    0x1F910495, 0x1F9204BD, 0x1F9304E5, 0x1F94050D, 0x1F950535, 0x1F96055D, 0x1F970585, 0x1F9805AD,
    0x1F9905D5, 0x1F9A05FD, 0x1F9B0625, 0x1F9C064D, 0x1F9D0675, 0x1F9E069D, 0x1F9F06C5, 0x1FA006ED,
    0x1FA10715, 0x1FA2073D, 0x1FA30765, 0x1FA4078D, 0x1FA507B5, 0x1FA607DD, 0x1FA70805, 0x1FA8082D,
    0x1FA90855, 0x1FAA087D, 0x1FAB08A5, 0x1FAC08CD, 0x1FAD08F5, 0x1FAE091D, 0x1FAF0945, 0x1FB2096D,
    0x1FB30994, 0x1FB409B4, 0x1FB609D4, 0x1FB709F6, 0x1FBC0A24, 0x1FC20A45, 0x1FC30A6C, 0x1FC40A8C,
    0x1FC60AAC, 0x1FC70ACE, 0x1FCC0AFC, 0x1FD20B1E, 0x1FD30B4E, 0x1FD60B7C, 0x1FD70B9E, 0x1FE20BCE,
    0x1FE30BFE, 0x1FE40C2C, 0x1FE60C4C, 0x1FE70C6E, 0x1FF20C9D, 0x1FF30CC4, 0x1FF40CE4, 0x1FF60D04,
    0x1FF70D26, 0x1FFC0D54, 0xFB000D72, 0xFB010D82, 0xFB020D92, 0xFB030DA3, 0xFB040DBB,
    0xFB050DD2, 0xFB060DE2, 0xFB130DF4, 0xFB140E14, 0xFB150E34, 0xFB160E54, 0xFB170E74,
];

private immutable char[466] rootUppercaseBytes = [
    0x53, 0x53, 0xCA, 0xBC, 0x4E, 0x4A, 0xCC, 0x8C, 0xCE, 0x99, 0xCC, 0x88, 0xCC, 0x81, 0xCE, 0xA5,
    0xCC, 0x88, 0xCC, 0x81, 0xD4, 0xB5, 0xD5, 0x92, 0x48, 0xCC, 0xB1, 0x54, 0xCC, 0x88, 0x57, 0xCC,
    0x8A, 0x59, 0xCC, 0x8A, 0x41, 0xCA, 0xBE, 0xCE, 0xA5, 0xCC, 0x93, 0xCE, 0xA5, 0xCC, 0x93, 0xCC,
    0x80, 0xCE, 0xA5, 0xCC, 0x93, 0xCC, 0x81, 0xCE, 0xA5, 0xCC, 0x93, 0xCD, 0x82, 0xE1, 0xBC, 0x88,
    0xCE, 0x99, 0xE1, 0xBC, 0x89, 0xCE, 0x99, 0xE1, 0xBC, 0x8A, 0xCE, 0x99, 0xE1, 0xBC, 0x8B, 0xCE,
    0x99, 0xE1, 0xBC, 0x8C, 0xCE, 0x99, 0xE1, 0xBC, 0x8D, 0xCE, 0x99, 0xE1, 0xBC, 0x8E, 0xCE, 0x99,
    0xE1, 0xBC, 0x8F, 0xCE, 0x99, 0xE1, 0xBC, 0x88, 0xCE, 0x99, 0xE1, 0xBC, 0x89, 0xCE, 0x99, 0xE1,
    0xBC, 0x8A, 0xCE, 0x99, 0xE1, 0xBC, 0x8B, 0xCE, 0x99, 0xE1, 0xBC, 0x8C, 0xCE, 0x99, 0xE1, 0xBC,
    0x8D, 0xCE, 0x99, 0xE1, 0xBC, 0x8E, 0xCE, 0x99, 0xE1, 0xBC, 0x8F, 0xCE, 0x99, 0xE1, 0xBC, 0xA8,
    0xCE, 0x99, 0xE1, 0xBC, 0xA9, 0xCE, 0x99, 0xE1, 0xBC, 0xAA, 0xCE, 0x99, 0xE1, 0xBC, 0xAB, 0xCE,
    0x99, 0xE1, 0xBC, 0xAC, 0xCE, 0x99, 0xE1, 0xBC, 0xAD, 0xCE, 0x99, 0xE1, 0xBC, 0xAE, 0xCE, 0x99,
    0xE1, 0xBC, 0xAF, 0xCE, 0x99, 0xE1, 0xBC, 0xA8, 0xCE, 0x99, 0xE1, 0xBC, 0xA9, 0xCE, 0x99, 0xE1,
    0xBC, 0xAA, 0xCE, 0x99, 0xE1, 0xBC, 0xAB, 0xCE, 0x99, 0xE1, 0xBC, 0xAC, 0xCE, 0x99, 0xE1, 0xBC,
    0xAD, 0xCE, 0x99, 0xE1, 0xBC, 0xAE, 0xCE, 0x99, 0xE1, 0xBC, 0xAF, 0xCE, 0x99, 0xE1, 0xBD, 0xA8,
    0xCE, 0x99, 0xE1, 0xBD, 0xA9, 0xCE, 0x99, 0xE1, 0xBD, 0xAA, 0xCE, 0x99, 0xE1, 0xBD, 0xAB, 0xCE,
    0x99, 0xE1, 0xBD, 0xAC, 0xCE, 0x99, 0xE1, 0xBD, 0xAD, 0xCE, 0x99, 0xE1, 0xBD, 0xAE, 0xCE, 0x99,
    0xE1, 0xBD, 0xAF, 0xCE, 0x99, 0xE1, 0xBD, 0xA8, 0xCE, 0x99, 0xE1, 0xBD, 0xA9, 0xCE, 0x99, 0xE1,
    0xBD, 0xAA, 0xCE, 0x99, 0xE1, 0xBD, 0xAB, 0xCE, 0x99, 0xE1, 0xBD, 0xAC, 0xCE, 0x99, 0xE1, 0xBD,
    0xAD, 0xCE, 0x99, 0xE1, 0xBD, 0xAE, 0xCE, 0x99, 0xE1, 0xBD, 0xAF, 0xCE, 0x99, 0xE1, 0xBE, 0xBA,
    0xCE, 0x99, 0xCE, 0x91, 0xCE, 0x99, 0xCE, 0x86, 0xCE, 0x99, 0xCE, 0x91, 0xCD, 0x82, 0xCE, 0x91,
    0xCD, 0x82, 0xCE, 0x99, 0xCE, 0x91, 0xCE, 0x99, 0xE1, 0xBF, 0x8A, 0xCE, 0x99, 0xCE, 0x97, 0xCE,
    0x99, 0xCE, 0x89, 0xCE, 0x99, 0xCE, 0x97, 0xCD, 0x82, 0xCE, 0x97, 0xCD, 0x82, 0xCE, 0x99, 0xCE,
    0x97, 0xCE, 0x99, 0xCE, 0x99, 0xCC, 0x88, 0xCC, 0x80, 0xCE, 0x99, 0xCC, 0x88, 0xCC, 0x81, 0xCE,
    0x99, 0xCD, 0x82, 0xCE, 0x99, 0xCC, 0x88, 0xCD, 0x82, 0xCE, 0xA5, 0xCC, 0x88, 0xCC, 0x80, 0xCE,
    0xA5, 0xCC, 0x88, 0xCC, 0x81, 0xCE, 0xA1, 0xCC, 0x93, 0xCE, 0xA5, 0xCD, 0x82, 0xCE, 0xA5, 0xCC,
    0x88, 0xCD, 0x82, 0xE1, 0xBF, 0xBA, 0xCE, 0x99, 0xCE, 0xA9, 0xCE, 0x99, 0xCE, 0x8F, 0xCE, 0x99,
    0xCE, 0xA9, 0xCD, 0x82, 0xCE, 0xA9, 0xCD, 0x82, 0xCE, 0x99, 0xCE, 0xA9, 0xCE, 0x99, 0x46, 0x46,
    0x46, 0x49, 0x46, 0x4C, 0x46, 0x46, 0x49, 0x46, 0x46, 0x4C, 0x53, 0x54, 0x53, 0x54, 0xD5, 0x84,
    0xD5, 0x86, 0xD5, 0x84, 0xD4, 0xB5, 0xD5, 0x84, 0xD4, 0xBB, 0xD5, 0x8E, 0xD5, 0x86, 0xD5, 0x84,
    0xD4, 0xBD,
];
// END GENERATED ROOT UPPERCASE EXPANSIONS

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

pragma(inline, false) private string hashText(Any argument)
{
    if (argument.isNull)
        return "null";
    return hex(cast(uint) boxedHashCode(argument));
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

private string characterText(Any argument)
{
    const typeName = argument.typeName;
    const character = typeName == "char" || typeName == "wchar" || typeName == "dchar";
    if (!character && (!isIntegral(typeName) || typeName == "long"))
        throw new IllegalFormatConversionException('c', javaTypeName(argument));
    const code = character ? cast(long) argument.get!dchar : argument.get!long;
    const text = code < 0 || code > 0x10FFFF ? null : utf8(cast(dchar) code);
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
    if (argument.isNull)
        return "null";
    if (!isIntegral(argument.typeName))
        throw new IllegalFormatConversionException('d', javaTypeName(argument));
    const unsigned = argument.typeName == "ulong";
    const value = argument.get!long;
    const negative = !unsigned && value < 0;
    const magnitude = negative ? -cast(ulong) value : cast(ulong) value;
    return signed(spec, digits(magnitude, 10, spec.has(Flag.group)), negative);
}

/// Apply the sign flags and zero padding to `body`, the magnitude's digits.
private string signed(const ref Spec spec, string body, bool negative) pure nothrow
{
    const suffix = negative && spec.has(Flag.parentheses) ? ")" : "";
    return paddedNumber(spec, numberSign(spec, negative), body, suffix);
}

private string numberSign(const ref Spec spec, bool negative) pure nothrow @nogc
{
    return negative ? (spec.has(Flag.parentheses) ? "(" : "-") : spec.has(Flag.plus)
        ? "+" : spec.has(Flag.space) ? " " : "";
}

private string numberZeros(size_t count) pure nothrow
{
    if (count == 0)
        return "";
    auto zeros = new char[count];
    zeros[] = '0';
    return zeros.idup;
}

/// Zero padding follows a sign or radix indicator and precedes the digits.
private string paddedNumber(const ref Spec spec, string prefix, string body, string suffix) pure nothrow
{
    if (spec.has(Flag.zero) && spec.width > 0)
    {
        const used = prefix.length + body.length + suffix.length;
        if (used < spec.width)
            body = numberZeros(spec.width - used) ~ body;
    }
    return prefix ~ body ~ suffix;
}

private string radixText(const ref Spec spec, Any argument)
{
    if (argument.isNull)
        return cased(spec, "null");
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
    const octal = conversion == 'o';
    const magnitude = digits(bits, octal ? 8 : 16, false);
    const prefix = spec.has(Flag.alternate) ? (octal ? "0" : "0x") : "";
    return cased(spec, paddedNumber(spec, prefix, magnitude, ""));
}

private string floatingText(const ref Spec spec, Any argument)
{
    const uppercase = asciiLower(spec.conversion) != spec.conversion;
    if (argument.isNull)
        return uppercase ? "NULL" : "null";
    if (argument.typeName != "double" && argument.typeName != "float")
        throw new IllegalFormatConversionException(asciiLower(spec.conversion), javaTypeName(argument));
    const value = argument.get!double;
    const negative = value < 0 || (value == 0 && 1 / value < 0);
    if (value != value || value == double.infinity || value == -double.infinity)
        return nonFinite(spec, value, negative, uppercase);
    const magnitude = negative ? -value : value;
    if (asciiLower(spec.conversion) == 'a')
        return hexadecimalFloatingText(spec, magnitude, negative, uppercase);
    const precision = spec.precision < 0 ? 6 : spec.precision;
    const text = spec.conversion == 'f' ? fixedMagnitude(spec, magnitude,
            precision) : significantMagnitude(spec, magnitude, precision);
    return signed(spec, text, negative);
}

private union HexDoubleBits
{
    double value;
    ulong bits;
}

private enum doubleHiddenBit = 1UL << 52;
private enum hexFractionDigits = 13;

private string hexadecimalFloatingText(const ref Spec spec, double magnitude, bool negative, bool uppercase)
{
    const precision = spec.precision == 0 ? 1 : spec.precision;
    int exponent;
    const mantissa = hexFloatMantissa(magnitude, precision, uppercase, exponent);
    const ending = (uppercase ? "P" : "p") ~ decimal(exponent);
    const sign = numberSign(spec, negative);
    const prefix = uppercase ? "0X" : "0x";

    // Java measures width padding before adding any fractional zeros requested by precision.
    const used = sign.length + prefix.length + mantissa.length + ending.length;
    const widthZeros = spec.has(Flag.zero) && spec.width > 0 && cast(size_t) spec.width > used
        ? numberZeros(spec.width - used) : "";
    const present = cast(int) mantissa.length - 2;
    const precisionZeros = precision > present ? numberZeros(precision - present) : "";
    return sign ~ prefix ~ widthZeros ~ mantissa ~ precisionZeros ~ ending;
}

private string hexFloatMantissa(double magnitude, int precision, bool uppercase, out int exponent)
{
    HexDoubleBits data;
    data.value = magnitude;
    const encodedExponent = cast(int)((data.bits >> 52) & 0x7ff);
    ulong significand = data.bits & (doubleHiddenBit - 1);
    if (encodedExponent != 0)
    {
        significand |= doubleHiddenBit;
        exponent = encodedExponent - 1023;
    }
    else if (significand != 0)
        exponent = -1022;

    if (significand != 0 && precision > 0 && precision < hexFractionDigits)
        significand = roundHexSignificand(significand, precision, exponent);

    char[2 + hexFractionDigits] buffer;
    buffer[0] = (significand & doubleHiddenBit) != 0 ? '1' : '0';
    buffer[1] = '.';
    const alphabet = uppercase ? "0123456789ABCDEF" : "0123456789abcdef";
    foreach (i; 0 .. hexFractionDigits)
    {
        const shift = 4 * (hexFractionDigits - 1 - i);
        buffer[i + 2] = alphabet[(significand >> shift) & 0xF];
    }
    size_t end = buffer.length;
    while (end > 3 && buffer[end - 1] == '0')
        --end;
    return buffer[0 .. end].idup;
}

private ulong roundHexSignificand(ulong significand, int precision, ref int exponent) pure nothrow @nogc
{
    while ((significand & doubleHiddenBit) == 0)
    {
        significand <<= 1;
        --exponent;
    }
    const discard = 4 * (hexFractionDigits - precision);
    const halfway = 1UL << (discard - 1);
    const remainder = significand & ((1UL << discard) - 1);
    auto retained = significand >> discard;
    if (remainder > halfway || (remainder == halfway && (retained & 1) != 0))
        ++retained;
    auto rounded = retained << discard;
    if ((rounded & (doubleHiddenBit << 1)) != 0)
    {
        rounded >>= 1;
        ++exponent;
    }
    return rounded;
}

private string fixedMagnitude(const ref Spec spec, double magnitude, int precision)
{
    string whole, fraction;
    decimalDigits(magnitude, whole, fraction);
    roundHalfUp(whole, fraction, precision);
    return plainText(spec, whole, fraction);
}

private string plainText(const ref Spec spec, string whole, string fraction)
{
    const integer = spec.has(Flag.group) ? grouped(whole) : whole;
    return fraction.length != 0 || spec.has(Flag.alternate) ? integer ~ "." ~ fraction : integer;
}

/// `NaN` and the infinities, with Java's sign flags.
private string nonFinite(const ref Spec spec, double value, bool negative, bool uppercase) pure nothrow @nogc
{
    if (value != value)
        return uppercase ? "NAN" : "NaN";
    if (negative)
    {
        if (spec.has(Flag.parentheses))
            return uppercase ? "(INFINITY)" : "(Infinity)";
        return uppercase ? "-INFINITY" : "-Infinity";
    }
    if (spec.has(Flag.plus))
        return uppercase ? "+INFINITY" : "+Infinity";
    if (spec.has(Flag.space))
        return uppercase ? " INFINITY" : " Infinity";
    return uppercase ? "INFINITY" : "Infinity";
}

private string significantMagnitude(const ref Spec spec, double magnitude, int precision)
{
    const general = asciiLower(spec.conversion) == 'g';
    const significantDigits = precision == 0 ? 1 : precision;
    string whole, fraction;
    const exponent = roundedMantissa(magnitude, general ? significantDigits - 1 : precision, whole, fraction);
    // General notation is selected using the exponent after rounding.
    if (general && exponent >= -4 && exponent < significantDigits)
        return generalPlainText(spec, whole, fraction, exponent);
    return scientificText(spec, whole, fraction, exponent);
}

private string generalPlainText(const ref Spec spec, string whole, string fraction, int exponent)
{
    if (exponent < 0)
        return "0." ~ "000"[0 .. -exponent - 1] ~ whole ~ fraction;
    const significand = whole ~ fraction;
    const point = exponent + 1;
    return plainText(spec, significand[0 .. point], significand[point .. $]);
}

/// Round a single leading digit and its fractional digits and return the adjusted exponent.
private int roundedMantissa(double magnitude, int precision, out string whole, out string fraction)
{
    ptrdiff_t point;
    auto significand = decimalSignificand(magnitude, point);
    while (significand.length > 1 && significand[0] == '0')
    {
        significand = significand[1 .. $];
        --point;
    }
    int exponent = magnitude == 0 ? 0 : cast(int) point - 1;
    whole = significand[0 .. 1];
    fraction = significand[1 .. $];
    roundHalfUp(whole, fraction, precision);
    if (whole.length > 1)
    {
        ++exponent;
        whole = whole[0 .. 1]; // A mantissa of 10 becomes 1 with the next exponent.
    }
    return exponent;
}

private string scientificText(const ref Spec spec, string whole, string fraction, int exponent)
{
    const separator = fraction.length != 0 || spec.has(Flag.alternate) ? "." : "";
    const marker = asciiLower(spec.conversion) == spec.conversion ? "e" : "E";
    const sign = exponent < 0 ? "-" : "+";
    const exponentDigits = decimal(exponent < 0 ? -exponent : exponent);
    const leadingZero = exponentDigits.length == 1 ? "0" : "";
    return whole ~ separator ~ fraction ~ marker ~ sign ~ leadingZero ~ exponentDigits;
}

/// The whole and fraction digits of `magnitude` from Java's shortest representation (`Double.toString`), which
/// Java's `Formatter` rounds from (a `float` is widened to `double` first, as Java does).
private void decimalDigits(double magnitude, out string whole, out string fraction)
{
    ptrdiff_t position;
    auto digitText = decimalSignificand(magnitude, position);
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

/// The shortest decimal digits and the point position after applying any exponent.
private string decimalSignificand(double magnitude, out ptrdiff_t position)
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
    foreach (c; text[0 .. e])
    {
        if (c == '.')
            point = cast(ptrdiff_t) digitText.length;
        else
            digitText ~= c;
    }
    position = (point < 0 ? cast(ptrdiff_t) digitText.length : point) + exponent;
    return digitText;
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
