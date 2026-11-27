// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module charset_encoder_probe;

import flint.java.nio.charset.charsetencoder : CharsetEncoder;

@safe:

private alias Cs = typeof(CharsetEncoder.init.charset());
private alias Action = typeof(CharsetEncoder.init.malformedInputAction());
static if (is(typeof(__traits(getOverloads, CharsetEncoder, "encode")[0]) EncodeParams == function))
{
    private alias CharBuf = EncodeParams[0];
    private alias ByteBuf = EncodeParams[1];
}
static if (is(typeof(__traits(getOverloads, CharsetEncoder, "encode")[0]) Result == return))
    private alias ResultType = Result;

private final class AsciiProbeEncoder : CharsetEncoder
{
    this(Cs cs)
    {
        super(cs, 1.0f, 1.0f);
    }

    protected override ResultType encodeLoop(CharBuf src, ByteBuf dst)
    {
        while (src.hasRemaining())
        {
            const c = src.get();
            if (c > 0x7F)
            {
                src.position(src.position() - 1);
                return ResultType.unmappableForLength(1);
            }
            if (!dst.hasRemaining())
            {
                src.position(src.position() - 1);
                return ResultType.OVERFLOW;
            }
            dst.put(cast(byte) c);
        }
        return ResultType.UNDERFLOW;
    }
}

int main(string[] args)
{
    auto encoder = new AsciiProbeEncoder(Cs.forName("US-ASCII"));
    encoder.onUnmappableCharacter(Action.REPLACE);
    wchar[] chars = ['a', 'b', args.length > 1 ? cast(wchar) 0x00E9 : 'c', 'd'];
    auto src = CharBuf.wrap(chars);
    auto dst = ByteBuf.allocate(8);
    const cr = encoder.encode(src, dst, true);
    const fl = encoder.flush(dst);
    const ok = encoder.canEncode('z');
    encoder.reset();
    return (cr.isUnderflow() && fl.isUnderflow() && ok) ? dst.position() : 0;
}
