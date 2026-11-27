// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module writable_byte_channel_probe;

import flint.java.nio.channels.writablebytechannel : WritableByteChannel;

@safe:

static if (is(typeof(__traits(getOverloads, WritableByteChannel, "write")[0]) Params == function))
    private alias Buf = Params[0];

private final class DummyWritable : WritableByteChannel
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
}

int main(string[] args)
{
    WritableByteChannel ch = new DummyWritable;
    const n = ch.write(null);
    if (args.length > 1)
        ch.close();
    return ch.isOpen() ? n + 1 : n;
}
