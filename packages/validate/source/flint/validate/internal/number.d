module flint.validate.internal.number;

import std.traits : Unqual, isIntegral, isUnsigned;

@safe:

package(flint.validate) enum IsReal(T) = is(Unqual!T == float) || is(Unqual!T == double) || is(Unqual!T == real);
package(flint.validate) enum IsNumber(T) = isIntegral!T || IsReal!T;

package(flint.validate) bool meetsBound(bool minimum, T)(T value, long bound) pure nothrow @nogc
        if (IsNumber!T)
{
    static if (IsReal!T)
    {
        alias Float = Unqual!T;
        // Reject all nonfinite values, including NaN where both comparisons fail.
        if (!(value > -Float.infinity && value < Float.infinity))
            return false;
        immutable comparison = compareFloat(value, bound);
        return minimum ? comparison >= 0 : comparison <= 0;
    }
    else static if (isUnsigned!T)
    {
        if (bound < 0)
            return minimum;
        return minimum ? value >= cast(ulong) bound : value <= cast(ulong) bound;
    }
    else
    {
        return minimum ? value >= bound : value <= bound;
    }
}

private int compareFloat(T)(T value, long bound) pure nothrow @nogc
{
    // Powers of two are exact on all supported float/real ABIs. Check the
    // conversion domain before truncation rather than rounding the long bound.
    if (value >= 0x1p63)
        return 1;
    if (value < -0x1p63)
        return -1;
    immutable integral = cast(long) value;
    if (integral < bound)
        return -1;
    if (integral > bound)
        return 1;
    immutable exact = cast(T) integral;
    return value < exact ? -1 : value > exact ? 1 : 0;
}
