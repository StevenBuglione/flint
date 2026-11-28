/// Java SE 21 precision and rounding context (rules R5, R7, R8 and R11).
module flint.java.math.mathcontext;

import flint.engine.aot.text : decimal;
import flint.java.lang : IllegalArgumentException;
import flint.java.math.internal.mathcontextparse : modePrefix, precisionPrefix;
import flint.java.math.roundingmode : RoundingMode, modeName = name;

@safe:

/// Immutable settings for operations on decimal numbers.
final class MathContext
{
    static immutable MathContext UNLIMITED = new MathContext(0);
    static immutable MathContext DECIMAL32 = new MathContext(7, RoundingMode.HALF_EVEN);
    static immutable MathContext DECIMAL64 = new MathContext(16, RoundingMode.HALF_EVEN);
    static immutable MathContext DECIMAL128 = new MathContext(34, RoundingMode.HALF_EVEN);

    private immutable int precision;
    private immutable RoundingMode roundingMode;

    /// Construct with Java's default HALF_UP rounding mode.
    this(int precision) pure
    {
        this(precision, RoundingMode.HALF_UP);
    }

    /// Construct with explicit precision and rounding mode.
    this(int precision, RoundingMode mode) pure
    {
        this.precision = checkedPrecision(precision);
        if (cast(uint) mode > RoundingMode.max)
            throw new IllegalArgumentException("Invalid rounding mode");
        roundingMode = mode;
    }

    /// Read the fields written by toString. A null slice follows the empty-text path (R26).
    this(T)(scope T text) if (is(T : const(char)[]))
    {
        import flint.java.math.internal.mathcontextparse : parseMathContext;

        const settings = parseMathContext(text);
        this(settings.precision, settings.roundingMode);
    }

    /// Return the precision, with zero denoting unlimited digits.
    int getPrecision() const scope pure nothrow @nogc
    {
        return precision;
    }

    /// Return the rounding direction.
    RoundingMode getRoundingMode() const scope pure nothrow @nogc
    {
        return roundingMode;
    }

    /// Compare the two settings by value.
    bool equals(scope const Object other) const scope pure nothrow @nogc
    {
        const settings = cast(const MathContext) other;
        return settings !is null && sameSettings(settings);
    }

    override bool opEquals(Object other) pure nothrow @nogc
    {
        return equals(other);
    }

    bool opEquals(scope const MathContext other) const pure nothrow @nogc
    {
        return other !is null && sameSettings(other);
    }

    private bool sameSettings(scope const MathContext other) const scope pure nothrow @nogc
    {
        return precision == other.precision && roundingMode == other.roundingMode;
    }

    /// Combine the two settings into a value hash.
    int hashCode() const scope pure nothrow @nogc
    {
        return cast(int)(31U * cast(uint) precision + cast(uint) roundingMode);
    }

    override size_t toHash() const pure nothrow @nogc
    {
        return cast(uint) hashCode();
    }

    /// Render the Java precision and rounding fields.
    override string toString() const pure nothrow
    {
        return precisionPrefix ~ decimal(precision) ~ modePrefix ~ modeName(roundingMode);
    }
}

private int checkedPrecision(int value) pure
{
    if (value < 0)
        throw new IllegalArgumentException("Invalid math context precision");
    return value;
}
