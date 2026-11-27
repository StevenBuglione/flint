// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module gathering_byte_channel_probe;

import flint.java.nio.channels.gatheringbytechannel : GatheringByteChannel;

@safe:

static if (is(typeof(__traits(getOverloads, GatheringByteChannel, "write")[0]) Params == function))
    private alias Buf = Params[0];

private final class DummyGathering : GatheringByteChannel
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

    override int write(Buf src)
    {
        return src is null ? 0 : 1;
    }

    override long write(Buf[] srcs, int offset, int length)
    {
        return length > 0 && offset >= 0 && srcs.length > 0 ? 1 : 0;
    }

    override long write(Buf[] srcs)
    {
        return write(srcs, 0, cast(int) srcs.length);
    }
}

int main(string[] args)
{
    GatheringByteChannel ch = new DummyGathering;
    Buf buf = null;
    const total = ch.write(buf) + cast(int) ch.write(Buf[].init);
    if (args.length > 1)
        ch.close();
    return ch.isOpen() ? total + 1 : total;
}
