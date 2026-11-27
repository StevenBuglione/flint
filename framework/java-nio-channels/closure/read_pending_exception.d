// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module read_pending_exception_probe;

import flint.java.nio.channels.readpendingexception : ReadPendingException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new ReadPendingException;
        return 0;
    }
    catch (ReadPendingException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
