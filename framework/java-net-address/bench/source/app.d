// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.inetaddress : InetAddress;
import flint.java.net.unknownhostexception : UnknownHostException;

@safe:

int main(string[] args)
{
    try
    {
        auto address = InetAddress.getByName(args.length > 1 ? args[1] : "10.0.0.1");
        return cast(int) address.getHostAddress().length & 127;
    }
    catch (UnknownHostException failure)
    {
        return cast(int) failure.getMessage().length & 127;
    }
}
