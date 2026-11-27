// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module charset_decoder_probe;

import flint.java.nio.charset.charsetdecoder : CharsetDecoder;

@safe:

private alias Cs = typeof(CharsetDecoder.init.charset());
private alias Action = typeof(CharsetDecoder.init.malformedInputAction());
static if (is(typeof(__traits(getOverloads, CharsetDecoder, "decode")[0]) DecodeParams == function))
{
    private alias ByteBuf = DecodeParams[0];
    private alias CharBuf = DecodeParams[1];
}
static if (is(typeof(__traits(getOverloads, CharsetDecoder, "decode")[0]) Result == return))
    private alias ResultType = Result;

private final class AsciiProbeDecoder : CharsetDecoder
{
    this(Cs cs)
    {
        super(cs, 1.0f, 1.0f);
    }

    protected override ResultType decodeLoop(ByteBuf src, CharBuf dst)
    {
        while (src.hasRemaining())
        {
            const b = src.get();
            if (b < 0)
            {
                src.position(src.position() - 1);
                return ResultType.malformedForLength(1);
            }
            if (!dst.hasRemaining())
            {
                src.position(src.position() - 1);
                return ResultType.OVERFLOW;
            }
            dst.put(cast(wchar) b);
        }
        return ResultType.UNDERFLOW;
    }
}

int main(string[] args)
{
    auto decoder = new AsciiProbeDecoder(Cs.forName("US-ASCII"));
    decoder.onMalformedInput(Action.REPLACE).replaceWith("?");
    byte[] bytes = [
        cast(byte) 'a', cast(byte) 'b', cast(byte)(args.length > 1 ? 0x80 : 'c'), cast(byte) 'd'
    ];
    auto src = ByteBuf.wrap(bytes);
    auto dst = CharBuf.allocate(8);
    const cr = decoder.decode(src, dst, true);
    const fl = decoder.flush(dst);
    decoder.reset();
    return (cr.isUnderflow() && fl.isUnderflow()) ? dst.position() : 0;
}
