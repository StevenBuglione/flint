// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module byte_channel_probe;

import flint.java.nio.channels.bytechannel : ByteChannel;

@safe:

static if (is(typeof(__traits(getVirtualMethods, ByteChannel, "read")[0]) Params == function))
    private alias Buf = Params[0];

private final class DummyByteChannel : ByteChannel
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

    override int write(Buf src)
    {
        return src is null ? 0 : 1;
    }
}

int main(string[] args)
{
    ByteChannel ch = new DummyByteChannel;
    const total = ch.read(null) + ch.write(null);
    if (args.length > 1)
        ch.close();
    return ch.isOpen() ? total + 1 : total;
}
