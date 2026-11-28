/// Text parser for the Java MathContext constructor.
module flint.java.math.internal.mathcontextparse;

import flint.java.lang : IllegalArgumentException;
import flint.java.math.internal.radixparse : digitAt;
import flint.java.math.roundingmode : RoundingMode, valueOf;

@safe:

package(flint.java.math) enum precisionPrefix = "precision=";
package(flint.java.math) enum modePrefix = " roundingMode=";

package(flint.java.math) struct MathContextSettings
{
    int precision;
    RoundingMode roundingMode;
}

package(flint.java.math) MathContextSettings parseMathContext(scope const(char)[] text)
{
    if (text.length < precisionPrefix.length || text[0 .. precisionPrefix.length] != precisionPrefix)
        throw new IllegalArgumentException("Invalid math context");

    const fields = text[precisionPrefix.length .. $];
    size_t split;
    while (split < fields.length && fields[split] != ' ')
        ++split;

    const mode = fields[split .. $];
    if (mode.length < modePrefix.length || mode[0 .. modePrefix.length] != modePrefix)
        throw new IllegalArgumentException("Invalid math context");

    const precision = parsePrecision(fields[0 .. split]);
    if (precision < 0)
        throw new IllegalArgumentException("Invalid math context precision");
    return MathContextSettings(precision, valueOf(mode[modePrefix.length .. $]));
}

private int parsePrecision(scope const(char)[] text) pure nothrow @nogc
{
    if (!text.length)
        return -1;
    const negative = text[0] == '-';
    size_t index = negative || text[0] == '+' ? 1 : 0;
    if (index == text.length)
        return -1;

    int value;
    while (index < text.length)
    {
        const digit = digitAt(text, index, 10);
        if (digit < 0 || value > (int.max - digit) / 10)
            return -1;
        value = value * 10 + digit;
    }
    return negative && value != 0 ? -1 : value;
}
