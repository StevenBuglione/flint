// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module accept_pending_exception_probe;

import flint.java.nio.channels.acceptpendingexception : AcceptPendingException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new AcceptPendingException;
        return 0;
    }
    catch (AcceptPendingException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
