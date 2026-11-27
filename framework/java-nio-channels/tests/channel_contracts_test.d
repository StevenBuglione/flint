// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for the Java SE 21 java.nio.channels core byte-channel contracts.
module channel_contracts_test;

import flint.java.io.closeable : Closeable;
import flint.java.lang : AutoCloseable;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.channels.bytechannel : ByteChannel;
import flint.java.nio.channels.channel : Channel;
import flint.java.nio.channels.gatheringbytechannel : GatheringByteChannel;
import flint.java.nio.channels.interruptiblechannel : InterruptibleChannel;
import flint.java.nio.channels.readablebytechannel : ReadableByteChannel;
import flint.java.nio.channels.scatteringbytechannel : ScatteringByteChannel;
import flint.java.nio.channels.seekablebytechannel : SeekableByteChannel;
import flint.java.nio.channels.writablebytechannel : WritableByteChannel;

@safe:

private final class InMemoryByteChannel : SeekableByteChannel, InterruptibleChannel,
    ScatteringByteChannel, GatheringByteChannel
{
    private byte[] storage;
    private long cursor;
    private bool open = true;
    private int closeCount;

    this(size_t initialCapacity) pure nothrow
    {
        storage = new byte[initialCapacity];
        storage.length = 0;
    }

    override bool isOpen()
    {
        return open;
    }

    override void close()
    {
        closeCount++;
        open = false;
    }

    override int read(ByteBuffer dst)
    {
        if (!open || dst is null)
            return -1;
        if (cursor >= cast(long) storage.length)
            return -1;
        int copied;
        while (dst.hasRemaining() && cursor < cast(long) storage.length)
        {
            dst.put(storage[cast(size_t) cursor]);
            cursor++;
            copied++;
        }
        return copied;
    }

    override long read(ByteBuffer[] dsts, int offset, int length)
    {
        long total;
        foreach (i; 0 .. length)
        {
            const n = read(dsts[cast(size_t)(offset + i)]);
            if (n < 0)
                return total == 0 ? -1 : total;
            total += n;
        }
        return total;
    }

    override long read(ByteBuffer[] dsts)
    {
        return read(dsts, 0, cast(int) dsts.length);
    }

    override int write(ByteBuffer src)
    {
        if (!open || src is null)
            return 0;
        int written;
        while (src.hasRemaining())
        {
            const b = src.get();
            const index = cast(size_t) cursor;
            if (index >= storage.length)
                storage.length = index + 1;
            storage[index] = b;
            cursor++;
            written++;
        }
        return written;
    }

    override long write(ByteBuffer[] srcs, int offset, int length)
    {
        long total;
        foreach (i; 0 .. length)
            total += write(srcs[cast(size_t)(offset + i)]);
        return total;
    }

    override long write(ByteBuffer[] srcs)
    {
        return write(srcs, 0, cast(int) srcs.length);
    }

    override long position()
    {
        return cursor;
    }

    override SeekableByteChannel position(long newPosition)
    {
        cursor = newPosition;
        return this;
    }

    override long size()
    {
        return cast(long) storage.length;
    }

    override SeekableByteChannel truncate(long newSize)
    {
        if (newSize < cast(long) storage.length)
            storage.length = cast(size_t) newSize;
        if (cursor > newSize)
            cursor = newSize;
        return this;
    }
}

@("Channel hierarchy upcasts to Closeable and AutoCloseable and dispatches close")
unittest
{
    auto impl = new InMemoryByteChannel(16);
    SeekableByteChannel seekable = impl;
    ByteChannel byteChannel = seekable;
    ReadableByteChannel readable = byteChannel;
    WritableByteChannel writable = byteChannel;
    InterruptibleChannel interruptible = impl;
    Channel channel = readable;
    Closeable closeable = channel;
    AutoCloseable autoCloseable = closeable;

    assert(channel.isOpen());
    assert(byteChannel.isOpen());
    assert(readable.isOpen());
    assert(writable.isOpen());
    assert(interruptible.isOpen());
    autoCloseable.close();
    assert(!channel.isOpen());
    assert(!seekable.isOpen());
    closeable.close();
    interruptible.close();
    assert(impl.closeCount == 3);
}

@("ScatteringByteChannel and GatheringByteChannel preserve single-buffer overloads alongside array overloads")
unittest
{
    auto impl = new InMemoryByteChannel(16);
    GatheringByteChannel gathering = impl;
    ScatteringByteChannel scattering = impl;

    auto first = ByteBuffer.wrap(cast(byte[])[1, 2]);
    auto second = ByteBuffer.wrap(cast(byte[])[3, 4, 5]);
    auto third = ByteBuffer.wrap(cast(byte[])[6]);
    ByteBuffer[] writeVec = [first, second, third];

    assert(gathering.write(writeVec, 0, 2) == 5);
    assert(gathering.write(third) == 1);
    assert(impl.size() == 6);
    assert(impl.position() == 6);

    impl.position(0);
    auto outA = ByteBuffer.allocate(2);
    auto outB = ByteBuffer.allocate(3);
    auto outC = ByteBuffer.allocate(2);
    ByteBuffer[] readVec = [outA, outB, outC];

    assert(scattering.read(readVec) == 6);
    outA.flip();
    outB.flip();
    outC.flip();
    assert(outA.get() == 1 && outA.get() == 2);
    assert(outB.get() == 3 && outB.get() == 4 && outB.get() == 5);
    assert(outC.get() == 6 && !outC.hasRemaining());

    impl.position(1);
    auto single = ByteBuffer.allocate(2);
    assert(scattering.read(single) == 2);
    single.flip();
    assert(single.get() == 2 && single.get() == 3);
}

@("SeekableByteChannel supports fluent position, size, truncate, read and write")
unittest
{
    auto impl = new InMemoryByteChannel(16);
    SeekableByteChannel ch = impl;

    auto src = ByteBuffer.wrap(cast(byte[])[10, 20, 30, 40]);
    assert(ch.write(src) == 4);
    assert(ch.position() == 4);
    assert(ch.size() == 4);

    assert(ch.position(2) is ch);
    assert(ch.position() == 2);

    auto dst = ByteBuffer.allocate(4);
    assert(ch.read(dst) == 2);
    dst.flip();
    assert(dst.get() == 30 && dst.get() == 40);

    assert(ch.truncate(3) is ch);
    assert(ch.size() == 3);
    assert(ch.position() == 3);

    dst.clear();
    assert(ch.read(dst) == -1);
}
