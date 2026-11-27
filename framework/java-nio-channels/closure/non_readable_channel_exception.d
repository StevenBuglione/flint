// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module non_readable_channel_exception_probe;

import flint.java.nio.channels.nonreadablechannelexception : NonReadableChannelException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new NonReadableChannelException;
        return 0;
    }
    catch (NonReadableChannelException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
