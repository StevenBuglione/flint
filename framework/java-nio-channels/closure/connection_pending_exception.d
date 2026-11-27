// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module connection_pending_exception_probe;

import flint.java.nio.channels.connectionpendingexception : ConnectionPendingException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new ConnectionPendingException;
        return 0;
    }
    catch (ConnectionPendingException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
