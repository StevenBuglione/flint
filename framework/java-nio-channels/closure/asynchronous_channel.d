// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module asynchronous_channel_probe;

import flint.java.nio.channels.asynchronouschannel : AsynchronousChannel;

@safe:

private final class DummyAsyncChannel : AsynchronousChannel
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
}

int main(string[] args)
{
    AsynchronousChannel ch = new DummyAsyncChannel;
    if (args.length > 1)
        ch.close();
    return ch.isOpen() ? 1 : 0;
}
