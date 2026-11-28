// SPDX-License-Identifier: GPL-2.0 WITH Classpath-exception-2.0
/// The public `java.text.DecimalFormat` over the private java-text decimal renderers.
module flint.java.text.decimalformat;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.text.decimalformatsymbols : DecimalFormatSymbols;
import flint.java.text.internal.decimaldigitlist : FixedRoundingMode, FixedRoundingStatus;
import flint.java.text.internal.decimalexponent : renderExponentLong;
import flint.java.text.internal.decimalfixed : DecimalFixedPattern, renderDecimalLong;
import flint.java.text.internal.decimalfixedbinary : tryRenderDecimalDouble;
import flint.java.text.internal.decimalformatsymbols : DecimalSymbolData, bodySymbolsEncodable;
import flint.java.text.internal.decimalpattern : DecimalCompileStatus, compileFixedDecimalPattern,
    synthesizeDecimalPattern;

@safe:

/// Java's `DecimalFormat`: a compiled fixed-point or exponent pattern plus its symbols and rounding mode.
class DecimalFormat
{
    private DecimalFixedPattern pattern;
    private DecimalSymbolData symbols;
    private bool groupingUsed = true;
    /// The default pattern `0` with the default locale's symbols.
    this()
    {
        this("0");
    }

    /// Compiles `pattern` with the default locale's symbols.
    this(string pattern)
    {
        this(pattern, DecimalFormatSymbols.getInstance());
    }

    /// Compiles `pattern` with `symbols`; throws IllegalArgumentException for a malformed pattern.
    this(string pattern, DecimalFormatSymbols symbols)
    {
        if (symbols is null)
            nullArgument();
        this.symbols = *symbols.raw();
        applyPattern(pattern);
    }

    /// Compiles and installs `pattern`; throws IllegalArgumentException for a malformed pattern or unencodable symbols.
    void applyPattern(string pattern)
    {
        if (!bodySymbolsEncodable(symbols))
            fail("DecimalFormat symbols are not encodable");
        DecimalFixedPattern compiled;
        if (compileFixedDecimalPattern(pattern, symbols, compiled) != DecimalCompileStatus.accepted)
            fail("Malformed DecimalFormat pattern");
        this.pattern = compiled;
        groupingUsed = compiled.groupingSize != 0;
    }

    /// The pattern text, as Java's toPattern renders it.
    string toPattern()
    {
        string text;
        if (!synthesizeDecimalPattern(pattern, symbols, false, text))
            fail("DecimalFormat pattern is too large to render");
        return text;
    }

    /// A copy of the symbols this format uses.
    DecimalFormatSymbols getDecimalFormatSymbols()
    {
        return DecimalFormatSymbols.from(symbols);
    }

    /// Replaces the symbols; the pattern is not recompiled.
    void setDecimalFormatSymbols(DecimalFormatSymbols symbols)
    {
        if (symbols is null)
            nullArgument();
        this.symbols = *symbols.raw();
    }

    /// Formats a long with the compiled pattern's affixes and symbols.
    string format(long value)
    {
        const multiplier = scaleMultiplier(pattern.scale);
        const activePattern = groupingUsed ? pattern : withoutGrouping(pattern);
        if (pattern.minimumExponentDigits == 0)
        {
            const required = renderDecimalLong(value, multiplier, activePattern, symbols, null);
            char[] buffer = allocate(required);
            renderDecimalLong(value, multiplier, activePattern, symbols, buffer);
            return seal(buffer);
        }
        FixedRoundingStatus status;
        const required = renderExponentLong(value, multiplier, activePattern, symbols, null,
                FixedRoundingMode.halfEven, status);
        if (status == FixedRoundingStatus.inexact)
            return "0";
        char[] buffer = allocate(required);
        renderExponentLong(value, multiplier, activePattern, symbols, buffer, FixedRoundingMode.halfEven, status);
        return seal(buffer);
    }

    /// Formats a binary64 with the compiled pattern's affixes and symbols.
    string format(double value)
    {
        const multiplier = scaleMultiplier(pattern.scale);
        const activePattern = groupingUsed ? pattern : withoutGrouping(pattern);
        ulong bits = *cast(ulong*)&value;
        size_t required;
        FixedRoundingStatus status;
        if (!tryRenderDecimalDouble(bits, multiplier, activePattern, symbols, null, required,
                FixedRoundingMode.halfEven, status))
            return "0";
        char[] buffer = allocate(required);
        tryRenderDecimalDouble(bits, multiplier, activePattern, symbols, buffer, required,
                FixedRoundingMode.halfEven, status);
        return seal(buffer);
    }

    /// The grouping interval, or 0 when grouping is off.
    uint getGroupingSize() const pure nothrow @nogc
    {
        return pattern.groupingSize;
    }

    /// Sets the grouping interval; 0 turns grouping off.
    void setGroupingSize(int size) pure nothrow @nogc
    {
        pattern.groupingSize = size < 0 ? 0 : cast(uint) size;
    }

    /// Whether grouping is in use, independent of the grouping interval.
    bool isGroupingUsed() const pure nothrow @nogc
    {
        return groupingUsed;
    }

    /// Turns grouping on or off; the interval is kept when grouping is restored.
    void setGroupingUsed(bool used) pure nothrow @nogc
    {
        groupingUsed = used;
    }

    private static DecimalFixedPattern withoutGrouping(DecimalFixedPattern source) pure nothrow @nogc
    {
        DecimalFixedPattern result = source;
        result.groupingSize = 0;
        return result;
    }

    /// The minimum number of integer digits.
    uint getMinimumIntegerDigits() const pure nothrow @nogc
    {
        return pattern.minimumIntegerDigits;
    }

    /// The maximum number of integer digits.
    uint getMaximumIntegerDigits() const pure nothrow @nogc
    {
        return pattern.maximumIntegerDigits;
    }

    /// The minimum number of fraction digits.
    uint getMinimumFractionDigits() const pure nothrow @nogc
    {
        return pattern.minimumFractionDigits;
    }

    /// The maximum number of fraction digits.
    uint getMaximumFractionDigits() const pure nothrow @nogc
    {
        return pattern.maximumFractionDigits;
    }

    /// Sets the minimum number of integer digits.
    void setMinimumIntegerDigits(int digits) pure nothrow @nogc
    {
        pattern.minimumIntegerDigits = digits < 0 ? 0 : cast(uint) digits;
    }

    /// Sets the maximum number of integer digits.
    void setMaximumIntegerDigits(int digits) pure nothrow @nogc
    {
        pattern.maximumIntegerDigits = digits < 0 ? 0 : cast(uint) digits;
    }

    /// Sets the minimum number of fraction digits.
    void setMinimumFractionDigits(int digits) pure nothrow @nogc
    {
        pattern.minimumFractionDigits = digits < 0 ? 0 : cast(uint) digits;
    }

    /// Sets the maximum number of fraction digits.
    void setMaximumFractionDigits(int digits) pure nothrow @nogc
    {
        pattern.maximumFractionDigits = digits < 0 ? 0 : cast(uint) digits;
    }

    /// The multiplier applied to the value, which is 1 when the pattern has no percent or per-mille sign.
    int getMultiplier() const pure nothrow @nogc
    {
        return scaleMultiplier(pattern.scale);
    }

    private static int scaleMultiplier(ubyte scale) pure nothrow @nogc
    {
        return scale == 0 ? 1 : (scale == 2 ? 100 : 1000);
    }

    /// The one IllegalArgumentException construction site for this class.
    private static void fail(string message) @safe
    {
        throw new IllegalArgumentException(message);
    }

    /// The one NullPointerException construction site for this class.
    private static void nullArgument() @safe
    {
        throw new NullPointerException("DecimalFormat argument is null");
    }

    /// The one output-allocation site: the renderers fill it, then `seal` publishes it.
    private static char[] allocate(size_t length) @safe
    {
        return new char[length];
    }

    private static string seal(char[] buffer) @safe
    {
        return buffer.idup;
    }
}
