// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.noroutetohostexception : NoRouteToHostException;

@safe:

int main(string[] args)
{
    try
    {
        throw new NoRouteToHostException(args.length > 0 ? args[0] : "bad");
    }
    catch (NoRouteToHostException failure)
    {
        return cast(int) failure.getMessage().length & 127;
    }
}
