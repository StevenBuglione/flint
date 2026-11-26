/// Date and time rendering for Java Formatter's boxed millisecond value.
module flint.java.util.internal.formatter_date_time;

import flint.engine.aot.text : decimal;
import flint.java.util.internal.gregorian : GregorianFields, fieldsOf;

@safe:

// Each row starts with its suffix, followed by the fields and punctuation to emit.
private immutable string[31] datePatterns = [
    "HH", "II", "kk", "ll", "MM", "SS", "LL", "NL000000", "pp", "zz", "ZZ", "s", "Q", "BB", "bB",
    "hB", "AA", "aA", "CC", "YY", "yy", "jj", "mm", "dd", "ee", "RH:M", "TH:M:S", "rI:M:S P",
    "Dm/d/y", "FY-m-d", "cA B d H:M:S Z Y"
];

/// Find the shared date suffix rule, or return -1 for an invalid suffix.
package(flint.java) int datePatternIndex(char suffix) pure nothrow @nogc
{
    foreach (index, pattern; datePatterns)
        if (pattern[0] == suffix)
            return cast(int) index;
    return -1;
}

/// Render a validated date suffix in Flint's default UTC zone.
pragma(inline, false) package(flint.java) string dateTimeValue(long millis, ubyte rule, bool uppercase) pure nothrow
{
    const pattern = datePatterns[rule];
    if (pattern.length == 1)
        return decimal(pattern[0] == 's' ? millis / 1000 : millis);

    const fields = fieldsOf(millis, 0);
    DateText result;
    foreach (token; pattern[1 .. $])
        putDatePart(result, token, fields);
    return result.text(uppercase);
}

// The longest composite includes a nine-digit year for the signed millisecond extremes.
private struct DateText
{
    private char[48] buffer = void;
    private size_t used;

    void put(scope const(char)[] piece) pure nothrow @nogc
    {
        buffer[used .. used + piece.length] = piece;
        used += piece.length;
    }

    void put(char c) pure nothrow @nogc
    {
        buffer[used++] = c;
    }

    string text(bool uppercase) pure nothrow
    {
        if (uppercase)
            foreach (ref char c; buffer[0 .. used])
                if (c >= 'a' && c <= 'z')
                    c = cast(char)(c - 'a' + 'A');
        return buffer[0 .. used].idup;
    }
}

private void putDatePart(ref DateText result, char token, const ref GregorianFields fields) pure nothrow @nogc
{
    // Locale.ROOT uses abbreviated month and day names, including for %tB and %tA.
    enum months = "JanFebMarAprMayJunJulAugSepOctNovDec";
    enum weekdays = "SunMonTueWedThuFriSat";
    switch (token)
    {
    case 'B':
        const start = 3 * (fields.month - 1);
        result.put(months[start .. start + 3]);
        break;
    case 'A':
        const start = 3 * (fields.weekday() - 1);
        result.put(weekdays[start .. start + 3]);
        break;
    case 'p':
        result.put(fields.hour < 12 ? "am" : "pm");
        break;
    case 'P':
        result.put(fields.hour < 12 ? "AM" : "PM");
        break;
    case 'z':
        result.put("+0000");
        break;
    case 'Z':
        result.put("UTC");
        break;
    case '/', '-', ':', ' ', '0':
        result.put(token);
        break;
    default:
        putDateNumber(result, token, fields);
    }
}

private void putDateNumber(ref DateText result, char token, const ref GregorianFields fields) pure nothrow @nogc
{
    uint value;
    uint width = 2;
    switch (token)
    {
    case 'k', 'H':
        value = fields.hour;
        width = token == 'k' ? 1 : 2;
        break;
    case 'l', 'I':
        value = fields.hour % 12;
        if (value == 0)
            value = 12;
        width = token == 'l' ? 1 : 2;
        break;
    case 'M':
        value = fields.minute;
        break;
    case 'S':
        value = fields.second;
        break;
    case 'L':
        value = fields.millis;
        width = 3;
        break;
    case 'C':
        value = fields.yearOfEra() / 100;
        break;
    case 'Y':
        value = fields.yearOfEra();
        width = 4;
        break;
    case 'y':
        value = fields.yearOfEra() % 100;
        break;
    case 'j':
        value = fields.dayOfYear();
        width = 3;
        break;
    case 'm':
        value = fields.month;
        break;
    case 'e', 'd':
        value = fields.day;
        width = token == 'e' ? 1 : 2;
        break;
    default:
        assert(0, "invalid internal date field");
    }

    char[10] buffer = void;
    size_t start = buffer.length;
    do
    {
        buffer[--start] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value || buffer.length - start < width);
    result.put(buffer[start .. $]);
}
