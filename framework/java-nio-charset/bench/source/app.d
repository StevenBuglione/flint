module app;

import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.charset : StandardCharsets;
import flint.java.nio.charset.codermalfunctionerror : CoderMalfunctionError;
import flint.java.nio.charset.coderresult : CoderResult;
import flint.java.nio.charset.codingerroraction : CodingErrorAction;
import flint.java.nio.charset.internal.decoders : standardDecoder;
import flint.java.nio.charset.internal.encoders : standardEncoder;

@safe:

private int runCoderResult(size_t mode, size_t argCount)
{
    if (mode == 0)
        return cast(int) CoderResult.UNDERFLOW.toString().length;
    if (mode == 1)
        return cast(int) CoderResult.OVERFLOW.toString().length;
    if (mode == 2)
    {
        auto malformed = CoderResult.malformedForLength(cast(int) argCount);
        return malformed.isMalformed() ? malformed.length() + cast(int) malformed.toString().length : 0;
    }
    if (mode == 3)
    {
        auto unmappable = CoderResult.unmappableForLength(cast(int) argCount);
        return unmappable.isUnmappable() ? unmappable.length() + cast(int) unmappable.toString().length : 0;
    }
    return CoderResult.UNDERFLOW.length();
}

private int runDecode()
{
    auto decoder = standardDecoder(StandardCharsets.UTF_8);
    decoder.onMalformedInput(CodingErrorAction.REPLACE);
    byte[] input = [
        cast(byte) 'f', cast(byte) 'l', cast(byte) 'i', cast(byte) 'n', cast(byte) 't', cast(byte) '!'
    ];
    auto src = ByteBuffer.wrap(input);
    auto dst = CharBuffer.allocate(8);
    const cr = decoder.decode(src, dst, true);
    const fl = decoder.flush(dst);
    return (cr.isUnderflow() && fl.isUnderflow()) ? dst.position() : 0;
}

private int runEncode()
{
    auto encoder = standardEncoder(StandardCharsets.UTF_8);
    encoder.onUnmappableCharacter(CodingErrorAction.REPLACE);
    wchar[] chars = ['f', 'l', 'i', 'n', 't'];
    auto src = CharBuffer.wrap(chars);
    auto dst = ByteBuffer.allocate(16);
    const cr = encoder.encode(src, dst, true);
    const fl = encoder.flush(dst);
    return (cr.isUnderflow() && fl.isUnderflow()) ? dst.position() : 0;
}

int main(string[] args)
{
    try
    {
        const mode = args.length % 8;
        if (mode < 5)
            return runCoderResult(mode, args.length);
        if (mode == 5)
            throw new CoderMalfunctionError(new Exception(args[0]));
        if (mode == 6)
            return runDecode();
        return runEncode();
    }
    catch (CoderMalfunctionError error)
    {
        return error.getCause() is null ? 3 : 4;
    }
    catch (Exception error)
    {
        return error.msg is null ? 1 : 2;
    }
}
