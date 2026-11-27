// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for the Java SE 21 java.nio.channels.AsynchronousChannel interface.
module asynchronous_channel_test;

import flint.java.io.closeable : Closeable;
import flint.java.lang : AutoCloseable;
import flint.java.nio.channels.asynchronouschannel : AsynchronousChannel;
import flint.java.nio.channels.channel : Channel;

@safe:

private final class DummyAsynchronousChannel : AsynchronousChannel
{
    private bool open = true;
    private int closeCount;

    override bool isOpen()
    {
        return open;
    }

    override void close()
    {
        closeCount++;
        open = false;
    }
}

@("AsynchronousChannel extends Channel, Closeable and AutoCloseable and dispatches close")
unittest
{
    auto impl = new DummyAsynchronousChannel;
    AsynchronousChannel asyncChannel = impl;
    Channel channel = asyncChannel;
    Closeable closeable = channel;
    AutoCloseable autoCloseable = closeable;

    assert(asyncChannel.isOpen());
    assert(channel.isOpen());
    asyncChannel.close();
    assert(!asyncChannel.isOpen());
    assert(!channel.isOpen());
    closeable.close();
    autoCloseable.close();
    assert(impl.closeCount == 3);
}
