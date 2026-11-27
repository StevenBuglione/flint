// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module illegal_channel_group_exception_probe;

import flint.java.nio.channels.illegalchannelgroupexception : IllegalChannelGroupException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new IllegalChannelGroupException;
        return 0;
    }
    catch (IllegalChannelGroupException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
