// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module shutdown_channel_group_exception_probe;

import flint.java.nio.channels.shutdownchannelgroupexception : ShutdownChannelGroupException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new ShutdownChannelGroupException;
        return 0;
    }
    catch (ShutdownChannelGroupException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
