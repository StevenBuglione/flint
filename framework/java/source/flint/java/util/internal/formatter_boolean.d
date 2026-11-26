/// Boolean rendering for Java Formatter.
module flint.java.util.internal.formatter_boolean;

import flint.java.util.internal.formatter_support : FormatOptions, asciiUppercase, truncate;

@safe:

/// Render the boolean value of a validated argument.
package(flint.java) string formatBoolean(const ref FormatOptions options, bool value) pure nothrow
{
    const text = truncate(options, value ? "true" : "false");
    return options.conversion == 'B' ? asciiUppercase(text) : text;
}
