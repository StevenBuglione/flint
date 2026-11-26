/// Digit rendering for Java Formatter's integer and hash conversions.
module flint.java.util.internal.formatter_digits;

@safe:
package(flint.java):

/// `value` in `radix`, with `,` every three digits when `group` (decimal only).
string digits(ulong value, uint radix, bool group) pure nothrow
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

string hex(ulong value) pure nothrow
{
    return digits(value, 16, false);
}
