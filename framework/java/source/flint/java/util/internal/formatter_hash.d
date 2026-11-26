/// Hash rendering for Java Formatter.
module flint.java.util.internal.formatter_hash;

import flint.java.util.internal.formatter_support : FormatOptions, asciiUppercase, truncate;
import flint.java.util.internal.formatter_digits : hex;

@safe:

/// Render a precomputed Java hash as unsigned hexadecimal.
package(flint.java) string formatHash(const ref FormatOptions options, int hash) pure nothrow
{
    const text = truncate(options, hex(cast(uint) hash));
    return options.conversion == 'H' ? asciiUppercase(text) : text;
}
