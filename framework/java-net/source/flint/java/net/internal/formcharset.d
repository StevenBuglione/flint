/** Shared charset classification for Java form codecs. */
module flint.java.net.internal.formcharset;

import flint.java.lang : NullPointerException;
import flint.java.nio.charset : Charset, StandardCharsets;

@safe:

package(flint.java.net):

enum Mode
{
    ascii,
    latin1,
    utf16,
    bigEndian,
    littleEndian
}

Mode representation(Charset charset) pure
{
    if (charset == StandardCharsets.US_ASCII)
        return Mode.ascii;
    if (charset == StandardCharsets.ISO_8859_1)
        return Mode.latin1;
    if (charset == StandardCharsets.UTF_16)
        return Mode.utf16;
    if (charset == StandardCharsets.UTF_16BE)
        return Mode.bigEndian;
    if (charset == StandardCharsets.UTF_16LE)
        return Mode.littleEndian;
    throwNullArgument("Charset is required");
}

bool isSingleByte(Mode mode) pure nothrow @nogc
{
    return mode == Mode.ascii || mode == Mode.latin1;
}

pragma(inline, false) noreturn throwNullArgument(string message, string file = __FILE__, size_t line = __LINE__) pure
{
    throw new NullPointerException(message, null, file, line);
}
