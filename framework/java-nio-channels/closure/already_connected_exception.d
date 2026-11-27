// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module already_connected_exception_probe;

import flint.java.nio.channels.alreadyconnectedexception : AlreadyConnectedException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new AlreadyConnectedException;
        return 0;
    }
    catch (AlreadyConnectedException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
