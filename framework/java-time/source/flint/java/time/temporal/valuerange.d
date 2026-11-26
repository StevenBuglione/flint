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
}
