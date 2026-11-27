// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module interruptible_channel_probe;

import flint.java.nio.channels.interruptiblechannel : InterruptibleChannel;

@safe:

private final class DummyInterruptible : InterruptibleChannel
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
    InterruptibleChannel ch = new DummyInterruptible;
    if (args.length > 1)
        ch.close();
    return ch.isOpen() ? 1 : 0;
}
