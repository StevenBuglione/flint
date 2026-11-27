// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module no_connection_pending_exception_probe;

import flint.java.nio.channels.noconnectionpendingexception : NoConnectionPendingException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new NoConnectionPendingException;
        return 0;
    }
    catch (NoConnectionPendingException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
