// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module closed_channel_exception_probe;

import flint.java.nio.channels.closedchannelexception : ClosedChannelException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new ClosedChannelException;
        return 0;
    }
    catch (ClosedChannelException exception)
    {
        return exception.getCause() is null ? 1 : 2;
    }
}
