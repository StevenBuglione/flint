// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for java.nio.channels.spi.AbstractInterruptibleChannel (Java SE 21).
module abstract_interruptible_channel_test;

import flint.java.io : IOException;
import flint.java.nio.channels.asynchronouscloseexception : AsynchronousCloseException;
import flint.java.nio.channels.channel : Channel;
import flint.java.nio.channels.interruptiblechannel : InterruptibleChannel;
import flint.java.nio.channels.spi.abstractinterruptiblechannel : AbstractInterruptibleChannel;

@safe:

private final class RecordingChannel : AbstractInterruptibleChannel
{
    int closedCount;
    bool throwOnClose;

    override protected void implCloseChannel()
    {
        closedCount++;
        if (throwOnClose)
            throw new IOException("close failed");
    }

    void probeEnd(bool completed)
    {
        begin();
        end(completed);
    }
}

@("close marks the channel closed once and runs implCloseChannel exactly once")
unittest
{
    auto channel = new RecordingChannel;
    assert(channel.isOpen());
    assert(channel.closedCount == 0);

    channel.close();
    assert(!channel.isOpen());
    assert(channel.closedCount == 1);

    // Repeated close is a no-op and does not call implCloseChannel again.
    channel.close();
    channel.close();
    assert(!channel.isOpen());
    assert(channel.closedCount == 1);
}

@("an exception from implCloseChannel propagates but leaves the channel closed")
unittest
{
    auto channel = new RecordingChannel;
    channel.throwOnClose = true;

    bool thrown;
    try
        channel.close();
    catch (IOException failure)
    {
        assert(failure.getMessage() == "close failed");
        thrown = true;
    }
    assert(thrown);
    assert(!channel.isOpen());
    assert(channel.closedCount == 1);

    // The channel is still closed; a second close does not retry implCloseChannel.
    channel.close();
    assert(channel.closedCount == 1);
}

@("end throws AsynchronousCloseException only for an incomplete operation on a closed channel")
unittest
{
    auto open = new RecordingChannel;
    open.probeEnd(true);
    open.probeEnd(false);
    assert(open.isOpen());

    auto closed = new RecordingChannel;
    closed.close();

    // A completed operation is fine even after close.
    closed.probeEnd(true);

    bool thrown;
    try
        closed.probeEnd(false);
    catch (AsynchronousCloseException failure)
        thrown = true;
    assert(thrown);
}

@("an AbstractInterruptibleChannel is both a Channel and an InterruptibleChannel")
unittest
{
    auto channel = new RecordingChannel;
    Channel asChannel = channel;
    InterruptibleChannel asInterruptible = channel;
    assert(asChannel.isOpen());
    assert(asInterruptible is channel);

    asInterruptible.close();
    assert(!asChannel.isOpen());
}
