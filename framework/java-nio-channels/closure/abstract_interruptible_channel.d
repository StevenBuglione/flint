// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module abstract_interruptible_channel_probe;

import flint.java.nio.channels.spi.abstractinterruptiblechannel : AbstractInterruptibleChannel;

@safe:

private final class ProbeChannel : AbstractInterruptibleChannel
{
    private int closedCount;

    override protected void implCloseChannel()
    {
        closedCount++;
    }

    int probe(bool completed)
    {
        begin();
        end(true);
        int result = isOpen() ? 1 : 0;
        close();
        result += closedCount;
        try
        {
            begin();
            end(completed);
        }
        catch (Exception)
        {
            result += 4;
        }
        return result;
    }
}

int main(string[] args)
{
    auto channel = new ProbeChannel;
    const result = channel.probe(args.length > 1);
    return result + (channel.isOpen() ? 2 : 0);
}
