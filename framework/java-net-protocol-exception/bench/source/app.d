// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.protocolexception : ProtocolException;

@safe:

int main(string[] args)
{
    try
    {
        throw new ProtocolException(args.length > 0 ? args[0] : "bad");
    }
    catch (ProtocolException failure)
    {
        return cast(int) failure.getMessage().length & 127;
    }
}
