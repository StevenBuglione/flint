// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.socketexception : SocketException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 0)
            throw new SocketException(args[0]);
    }
    catch (SocketException e)
    {
        return e.getMessage().length > 0 ? 0 : 1;
    }
    return 1;
}
