/// Clean-room Java SE 21 temporal field bounds (R1, R8 and R11).
module flint.java.time.temporal.valuerange;

import flint.java.lang : IllegalArgumentException;

@safe:

/// The outer bounds of a field and the limits its minimum and maximum can vary between.
struct ValueRange
{
    private long minimum;
    private long largestMinimum;
    private long smallestMaximum;
    private long maximum;

    private this(long minimum, long largestMinimum, long smallestMaximum, long maximum) pure nothrow @nogc
    {
        this.minimum = minimum;
        this.largestMinimum = largestMinimum;
        this.smallestMaximum = smallestMaximum;
        this.maximum = maximum;
    }

    /// A range with a fixed minimum and maximum.
    static ValueRange of(long min, long max) pure
    {
        if (min > max)
            throw new IllegalArgumentException("Minimum value must be less than maximum value");
        return ValueRange(min, min, max, max);
    }

    /// A range with a fixed minimum and a varying maximum.
    static ValueRange of(long min, long maxSmallest, long maxLargest) pure
    {
        if (min > maxSmallest)
            throw new IllegalArgumentException("Minimum value must be less than smallest maximum value");
        return of(min, min, maxSmallest, maxLargest);
    }

    /// A range whose minimum and maximum can both vary.
    static ValueRange of(long minSmallest, long minLargest, long maxSmallest, long maxLargest) pure
    {
        if (minSmallest > minLargest)
            throw new IllegalArgumentException("Smallest minimum value must be less than largest minimum value");
        if (maxSmallest > maxLargest)
            throw new IllegalArgumentException("Smallest maximum value must be less than largest maximum value");
        if (minLargest > maxLargest)
            throw new IllegalArgumentException("Largest minimum value must be less than largest maximum value");
        if (minSmallest > maxSmallest)
            throw new IllegalArgumentException("Smallest minimum value must be less than smallest maximum value");
        return ValueRange(minSmallest, minLargest, maxSmallest, maxLargest);
    }

    bool isFixed() const pure nothrow @nogc
    {
        return minimum == largestMinimum && smallestMaximum == maximum;
    }

    long getMinimum() const pure nothrow @nogc
    {
        return minimum;
    }

    long getLargestMinimum() const pure nothrow @nogc
    {
        return largestMinimum;
    }

    long getSmallestMaximum() const pure nothrow @nogc
    {
        return smallestMaximum;
    }

    long getMaximum() const pure nothrow @nogc
    {
        return maximum;
    }

    bool isIntValue() const pure nothrow @nogc
    {
        return minimum >= int.min && maximum <= int.max;
    }

    bool isValidValue(long value) const pure nothrow @nogc
    {
        return value >= minimum && value <= maximum;
    }

    bool isValidIntValue(long value) const pure nothrow @nogc
    {
        return isIntValue() && isValidValue(value);
    }

    bool equals(ValueRange other) const pure nothrow @nogc
    {
        return minimum == other.minimum && largestMinimum == other.largestMinimum
            && smallestMaximum == other.smallestMaximum && maximum == other.maximum;
    }

    /// Combine the four bounds with the signed shifts and wrapping sum observed in Java SE 21.
    int hashCode() const pure nothrow @nogc
    {
        ulong hash = cast(ulong) minimum;
        hash += (cast(ulong) largestMinimum << 16) + cast(ulong)(largestMinimum >> 48);
        hash += (cast(ulong) smallestMaximum << 32) + cast(ulong)(smallestMaximum >> 32);
        hash += (cast(ulong) maximum << 48) + cast(ulong)(maximum >> 16);
        return cast(int)(hash ^ (hash >> 32));
    }

    /// Display each varying endpoint as its two bounds separated by a slash.
    string toString() const pure nothrow
    {
        // Four signed longs of up to 20 characters, two slashes and " - ".
        char[85] buffer = void;
        size_t start = buffer.length;
        prependDecimal(buffer, start, maximum);
        if (smallestMaximum != maximum)
        {
            buffer[--start] = '/';
            prependDecimal(buffer, start, smallestMaximum);
        }
        buffer[--start] = ' ';
        buffer[--start] = '-';
        buffer[--start] = ' ';
        if (minimum != largestMinimum)
        {
            prependDecimal(buffer, start, largestMinimum);
            buffer[--start] = '/';
        }
        prependDecimal(buffer, start, minimum);
        return copyText(buffer[start .. $]);
    }
}

// Keep the copy non-templated so the archive can link it with this leaf alone.
private char[] copyText(scope const(char)[] source) pure nothrow
{
    auto text = new char[source.length];
    text[] = source;
    return text;
}

private void prependDecimal(ref scope char[85] buffer, ref size_t start, long value) pure nothrow @nogc
{
    ulong magnitude = cast(ulong) value;
    if (value < 0)
        magnitude = 0UL - magnitude;
    do
    {
        buffer[--start] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    while (magnitude != 0);
    if (value < 0)
        buffer[--start] = '-';
}
