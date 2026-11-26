/// Spelling for non-finite numbers in Java Formatter.
module flint.java.util.internal.formatter_float_special;

import flint.java.util.internal.formatter_support : Flag, FormatOptions;

@safe:
package(flint.java):

/// `NaN` and the infinities, with Java's sign flags.
string nonFinite(const ref FormatOptions spec, double value, bool negative, bool uppercase) pure nothrow @nogc
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
