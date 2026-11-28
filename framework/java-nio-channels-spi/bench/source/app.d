// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.nio.channels.spi.abstractinterruptiblechannel : AbstractInterruptibleChannel;

@safe:

private final class ProbeChannel : AbstractInterruptibleChannel
{
    int closedCount;

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
    fputc(result == 0 ? '0' : '1', stdout);
    fputc('\n', stdout);
    return result;
}
