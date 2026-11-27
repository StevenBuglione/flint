// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module readable_byte_channel_probe;

import flint.java.nio.channels.readablebytechannel : ReadableByteChannel;

@safe:

static if (is(typeof(__traits(getOverloads, ReadableByteChannel, "read")[0]) Params == function))
    private alias Buf = Params[0];

private final class DummyReadable : ReadableByteChannel
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
}

int main(string[] args)
{
    ReadableByteChannel ch = new DummyReadable;
    const n = ch.read(null);
    if (args.length > 1)
        ch.close();
    return ch.isOpen() ? n + 1 : n;
}
