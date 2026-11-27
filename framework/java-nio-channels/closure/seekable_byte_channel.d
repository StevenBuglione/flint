// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module seekable_byte_channel_probe;

import flint.java.nio.channels.seekablebytechannel : SeekableByteChannel;

@safe:

static if (is(typeof(__traits(getOverloads, SeekableByteChannel, "read")[0]) Params == function))
    private alias Buf = Params[0];

private final class DummySeekable : SeekableByteChannel
{
    bool open = true;
    long pos;
    long len = 4;

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

    override long position()
    {
        return pos;
    }

    override SeekableByteChannel position(long newPosition)
    {
        pos = newPosition;
        return this;
    }

    override long size()
    {
        return len;
    }

    override SeekableByteChannel truncate(long newSize)
    {
        len = newSize;
        return this;
    }
}

int main(string[] args)
{
    SeekableByteChannel ch = new DummySeekable;
    ch.position(1).truncate(2);
    const total = ch.read(null) + ch.write(null) + cast(int)(ch.position() + ch.size());
    if (args.length > 1)
        ch.close();
    return ch.isOpen() ? total + 1 : total;
}
