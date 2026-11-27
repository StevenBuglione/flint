module app;

import flint.java.io.closeable : Closeable;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.channels.bytechannel : ByteChannel;
import flint.java.nio.channels.channel : Channel;
import flint.java.nio.channels.completionhandler : CompletionHandler;
import flint.java.nio.channels.gatheringbytechannel : GatheringByteChannel;
import flint.java.nio.channels.interruptiblechannel : InterruptibleChannel;
import flint.java.nio.channels.readablebytechannel : ReadableByteChannel;
import flint.java.nio.channels.scatteringbytechannel : ScatteringByteChannel;
import flint.java.nio.channels.seekablebytechannel : SeekableByteChannel;
import flint.java.nio.channels.writablebytechannel : WritableByteChannel;

@safe:

private final class MemoryChannel : SeekableByteChannel, InterruptibleChannel,
    ScatteringByteChannel, GatheringByteChannel, CompletionHandler!(int, int)
{
    bool open = true;
    long pos;
    long len = 8;
    int lastDone;

    override void completed(int result, int attachment)
    {
        lastDone = result + attachment;
    }

    override void failed(Throwable exc, int attachment)
    {
        lastDone = exc is null ? attachment : -attachment;
    }

    override bool isOpen()
    {
        return open;
    }

    override void close()
    {
        open = false;
    }

    override int read(ByteBuffer dst)
    {
        if (dst is null || !dst.hasRemaining())
            return 0;
        dst.put(cast(byte) pos);
        pos++;
        return 1;
    }

    override long read(ByteBuffer[] dsts, int offset, int length)
    {
        long total;
        foreach (i; 0 .. length)
            total += read(dsts[offset + i]);
        return total;
    }

    override long read(ByteBuffer[] dsts)
    {
        return read(dsts, 0, cast(int) dsts.length);
    }

    override int write(ByteBuffer src)
    {
        if (src is null || !src.hasRemaining())
            return 0;
        const value = src.get();
        pos += value >= 0 ? 1 : 1;
        if (pos > len)
            len = pos;
        return 1;
    }

    override long write(ByteBuffer[] srcs, int offset, int length)
    {
        long total;
        foreach (i; 0 .. length)
            total += write(srcs[offset + i]);
        return total;
    }

    override long write(ByteBuffer[] srcs)
    {
        return write(srcs, 0, cast(int) srcs.length);
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
        if (newSize < len)
            len = newSize;
        if (pos > len)
            pos = len;
        return this;
    }
}

int main(string[] args)
{
    auto mem = new MemoryChannel;
    Channel ch = mem;
    InterruptibleChannel ich = mem;
    ReadableByteChannel rch = mem;
    WritableByteChannel wch = mem;
    ByteChannel bch = mem;
    ScatteringByteChannel sch = mem;
    GatheringByteChannel gch = mem;
    SeekableByteChannel sbch = mem;
    CompletionHandler!(int, int) handler = mem;
    Closeable closeable = ch;

    auto buffer = ByteBuffer.allocate(8);
    buffer.put(cast(byte) args.length);
    buffer.flip();
    ByteBuffer[] list = [buffer];

    int total = wch.write(buffer);
    buffer.clear();
    total += rch.read(buffer);
    total += cast(int) gch.write(list);
    total += cast(int) sch.read(list);
    sbch.position(1).truncate(4);
    handler.completed(total, 1);
    total += cast(int)(sbch.position() + sbch.size() + bch.read(null)) + mem.lastDone;
    if (args.length > 1)
        ich.close();
    else
        closeable.close();
    return ch.isOpen() ? -1 : total;
}
