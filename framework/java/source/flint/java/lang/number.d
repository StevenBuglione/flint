/// The Java SE 21 numeric conversion contract (R1, R3).
module flint.java.lang.number;

@safe:

/// Base class for values that support conversion to Java's numeric primitives.
abstract class Number
{
    /// Construct the base portion of a concrete number.
    this() pure nothrow @nogc
    {
    }

    /// Convert to a signed 32-bit value.
    abstract int intValue();

    /// Convert to a signed 64-bit value.
    abstract long longValue();

    /// Convert to a binary32 floating-point value.
    abstract float floatValue();

    /// Convert to a binary64 floating-point value.
    abstract double doubleValue();

    /// Convert using the low eight bits of intValue.
    byte byteValue()
    {
        return cast(byte) intValue();
    }

    /// Convert using the low sixteen bits of intValue.
    short shortValue()
    {
        return cast(short) intValue();
    }
}
