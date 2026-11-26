/// Character rendering for Java Formatter.
module flint.java.util.internal.formatter_character;

import flint.engine.aot.text : utf8;
import flint.java.util.internal.formatter_support : FormatOptions;
import flint.java.util.internal.formatter_unicode : rootUppercase;

@safe:

/// Render a Unicode scalar, or return null for an unencodable code point.
package(flint.java) string formatCharacter(const ref FormatOptions spec, dchar code) pure nothrow
{
    const text = utf8(code);
    return spec.conversion == 'C' && text !is null ? rootUppercase(text) : text;
}
