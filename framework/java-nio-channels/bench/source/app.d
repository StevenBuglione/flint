module app;

import flint.java.io : IOException;
import flint.java.io.closeable : Closeable;
import flint.java.lang : RuntimeException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.channels.acceptpendingexception : AcceptPendingException;
import flint.java.nio.channels.alreadyboundexception : AlreadyBoundException;
import flint.java.nio.channels.alreadyconnectedexception : AlreadyConnectedException;
import flint.java.nio.channels.asynchronouschannel : AsynchronousChannel;
import flint.java.nio.channels.asynchronouscloseexception : AsynchronousCloseException;
import flint.java.nio.channels.bytechannel : ByteChannel;
import flint.java.nio.channels.cancelledkeyexception : CancelledKeyException;
import flint.java.nio.channels.channel : Channel;
import flint.java.nio.channels.closedbyinterruptexception : ClosedByInterruptException;
import flint.java.nio.channels.closedchannelexception : ClosedChannelException;
import flint.java.nio.channels.closedselectorexception : ClosedSelectorException;
import flint.java.nio.channels.completionhandler : CompletionHandler;
import flint.java.nio.channels.connectionpendingexception : ConnectionPendingException;
import flint.java.nio.channels.filelockinterruptionexception : FileLockInterruptionException;
import flint.java.nio.channels.gatheringbytechannel : GatheringByteChannel;
import flint.java.nio.channels.illegalblockingmodeexception : IllegalBlockingModeException;
import flint.java.nio.channels.illegalchannelgroupexception : IllegalChannelGroupException;
import flint.java.nio.channels.illegalselectorexception : IllegalSelectorException;
import flint.java.nio.channels.interruptedbytimeoutexception : InterruptedByTimeoutException;
import flint.java.nio.channels.interruptiblechannel : InterruptibleChannel;
import flint.java.nio.channels.noconnectionpendingexception : NoConnectionPendingException;
import flint.java.nio.channels.nonreadablechannelexception : NonReadableChannelException;
import flint.java.nio.channels.nonwritablechannelexception : NonWritableChannelException;
import flint.java.nio.channels.notyetboundexception : NotYetBoundException;
import flint.java.nio.channels.notyetconnectedexception : NotYetConnectedException;
import flint.java.nio.channels.overlappingfilelockexception : OverlappingFileLockException;
import flint.java.nio.channels.readablebytechannel : ReadableByteChannel;
import flint.java.nio.channels.readpendingexception : ReadPendingException;
import flint.java.nio.channels.scatteringbytechannel : ScatteringByteChannel;
import flint.java.nio.channels.seekablebytechannel : SeekableByteChannel;
import flint.java.nio.channels.shutdownchannelgroupexception : ShutdownChannelGroupException;
import flint.java.nio.channels.unresolvedaddressexception : UnresolvedAddressException;
import flint.java.nio.channels.unsupportedaddresstypeexception : UnsupportedAddressTypeException;
import flint.java.nio.channels.writablebytechannel : WritableByteChannel;
import flint.java.nio.channels.writependingexception : WritePendingException;
import flint.java.nio.channels.spi.abstractinterruptiblechannel : AbstractInterruptibleChannel;

@safe:

private final class InterruptibleProbeChannel : AbstractInterruptibleChannel
{
    int closeCount;

    override protected void implCloseChannel()
    {
        closeCount++;
    }

    int probeEnd(bool completed)
    {
        begin();
        end(completed);
        return closeCount;
    }
}

private final class MemoryChannel : SeekableByteChannel, InterruptibleChannel, AsynchronousChannel,
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

private RuntimeException makeChannelExceptionLow(size_t selector)
{
    if (selector == 0)
        return new AcceptPendingException;
    if (selector == 1)
        return new AlreadyBoundException;
    if (selector == 2)
        return new AlreadyConnectedException;
    if (selector == 3)
        return new CancelledKeyException;
    if (selector == 4)
        return new ClosedSelectorException;
    if (selector == 5)
        return new ConnectionPendingException;
    if (selector == 6)
        return new IllegalBlockingModeException;
    if (selector == 7)
        return new IllegalChannelGroupException;
    if (selector == 8)
        return new IllegalSelectorException;
    return new NoConnectionPendingException;
}

private RuntimeException makeChannelExceptionHigh(size_t selector)
{
    if (selector == 10)
        return new NonReadableChannelException;
    if (selector == 11)
        return new NonWritableChannelException;
    if (selector == 12)
        return new NotYetBoundException;
    if (selector == 13)
        return new NotYetConnectedException;
    if (selector == 14)
        return new OverlappingFileLockException;
    if (selector == 15)
        return new ReadPendingException;
    if (selector == 16)
        return new ShutdownChannelGroupException;
    if (selector == 17)
        return new UnresolvedAddressException;
    if (selector == 18)
        return new UnsupportedAddressTypeException;
    return new WritePendingException;
}

private int throwChannelException(size_t selector)
{
    try
    {
        const index = selector % 20;
        throw index < 10 ? makeChannelExceptionLow(index) : makeChannelExceptionHigh(index);
    }
    catch (RuntimeException ex)
        return ex.getMessage() is null ? 1 : 2;
}

private IOException makeChannelIOException(size_t selector)
{
    if (selector == 0)
        return new ClosedChannelException;
    if (selector == 1)
        return new AsynchronousCloseException;
    if (selector == 2)
        return new ClosedByInterruptException;
    if (selector == 3)
        return new FileLockInterruptionException;
    return new InterruptedByTimeoutException;
}

private int throwChannelIOException(size_t selector)
{
    try
        throw makeChannelIOException(selector % 5);
    catch (IOException ex)
        return ex.getCause() is null ? 3 : 4;
}

int main(string[] args)
{
    const count = args.length;
    if (count >= 24)
        return throwChannelIOException(count - 24);
    if (count >= 4)
        return throwChannelException(count - 4);

    auto mem = new MemoryChannel;
    Channel ch = mem;
    InterruptibleChannel ich = mem;
    AsynchronousChannel ach = mem;
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
    if (args.length == 2)
        ich.close();
    else if (args.length == 3)
        ach.close();
    else
        closeable.close();

    auto interruptible = new InterruptibleProbeChannel;
    total += interruptible.probeEnd(true);
    if (args.length == 6)
        interruptible.close();
    total += interruptible.isOpen() ? 1 : 0;
    try
        interruptible.probeEnd(false);
    catch (AsynchronousCloseException)
        total += 2;

    return ch.isOpen() ? -1 : total;
}
