// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.unknownserviceexception : UnknownServiceException;

@safe:

int main(string[] args)
{
    try
    {
        throw new UnknownServiceException(args.length > 0 ? args[0] : "bad");
    }
    catch (UnknownServiceException failure)
    {
        return cast(int) failure.getMessage().length & 127;
    }
}
