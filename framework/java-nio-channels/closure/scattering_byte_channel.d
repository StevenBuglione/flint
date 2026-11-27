// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module scattering_byte_channel_probe;

import flint.java.nio.channels.scatteringbytechannel : ScatteringByteChannel;

@safe:

static if (is(typeof(__traits(getOverloads, ScatteringByteChannel, "read")[0]) Params == function))
    private alias Buf = Params[0];

private final class DummyScattering : ScatteringByteChannel
{
    bool open = true;

    override bool isOpen()
    {
        return open;
    }

    override void close()
    {
        open = false;
    }

    override int read(Buf dst)
    {
        return dst is null ? 0 : 1;
    }

    override long read(Buf[] dsts, int offset, int length)
    {
        return length > 0 && offset >= 0 && dsts.length > 0 ? 1 : 0;
    }

    override long read(Buf[] dsts)
    {
        return read(dsts, 0, cast(int) dsts.length);
    }
}

int main(string[] args)
{
    ScatteringByteChannel ch = new DummyScattering;
    Buf buf = null;
    const total = ch.read(buf) + cast(int) ch.read(Buf[].init);
    if (args.length > 1)
        ch.close();
    return ch.isOpen() ? total + 1 : total;
}
