// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module non_writable_channel_exception_probe;

import flint.java.nio.channels.nonwritablechannelexception : NonWritableChannelException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new NonWritableChannelException;
        return 0;
    }
    catch (NonWritableChannelException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
