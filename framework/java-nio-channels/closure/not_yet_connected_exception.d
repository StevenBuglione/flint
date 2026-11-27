// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module not_yet_connected_exception_probe;

import flint.java.nio.channels.notyetconnectedexception : NotYetConnectedException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new NotYetConnectedException;
        return 0;
    }
    catch (NotYetConnectedException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
