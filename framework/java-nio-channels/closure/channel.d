// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module channel_probe;

import flint.java.nio.channels.channel : Channel;

@safe:

private final class DummyChannel : Channel
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
    Channel ch = new DummyChannel;
    if (args.length > 1)
        ch.close();
    return ch.isOpen() ? 1 : 0;
}
